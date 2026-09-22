-- 鱼载体的伤害接口（M18 / issue #32 方向 A）：让技能包 melee_hit 的 _applyDamage 真扣到血。
--
-- 为什么需要这一层：包内 `server/packages/ability_system/anchors/melee_hit.lua:107` 的
-- _applyDamage 只认两条路——`target:TakeDamage(...)`，退到 `target.Controller:TakeDamage(...)`。
-- 本图自建单位两条都没有，M15 实测「伤害恒 0 只击退」。M18 把可行接缝逐条查实（见
-- docs/verification/m0-playtest-ledger.md §1），结论是引擎里只有 BaseController 有 TakeDamage，
-- 而 Controller 只能由单位类型自己在创建时带出来：
--   * WorldUnit 加 `EnableController = true` 也拿不到 Controller（本体读 `.Controller` 恒 nil，
--     且赋 `.Controller` / `.TakeDamage` 一律 `cannot access an internal table/userdata`）。
--   * 沙盒没有 `debug` 库 → `debug.setmetatable` 这条路不存在；`setmetatable` 只吃 table，
--     对单位 userdata 用不了。
--   * 单位类型 × Controller 的实测矩阵：EggyUnit / HumanUnit 加 `EnableController = true` 有
--     Controller（Health/TakeDamage/HealthChanged/Died 齐全）；WorldUnit 没有；`EggyController`
--     不能由脚本建；`PetUnit` 建不出来。
--   * 举鱼（M2/F-1）要求鱼本体是带 `Liftable` 的 WorldUnit；EggyUnit / HumanUnit 都没有
--     `Liftable`。所以鱼本体与「能挨打」这两件事在引擎里落在两个不同单位上。
--
-- 于是本模块的形态是：**一条 WorldUnit 鱼本体 + 一个带 Controller 的受击体（EggyUnit）**。
-- 受击体跟着鱼本体走，挥砍命中盒打到的是受击体，扣的是这条鱼的血。这条接缝由 issue #8 的
-- 探针先证（`EnableController = true` → Controller 就绪、TakeDamage 生效），M18 复证并确认
-- 包内命中盒真能打中它、且一层 WorldUnit 鱼本体不会被重复计伤（台账 §1）。
--
-- 边界：本模块只做「载体实例化 + 伤害接口 + 死亡接缝」。抓举/顶鱼、逃脱运动、数量上限、
-- 鱼获生成都是 M2（路线图 §4，F-8 的 MgrFishUnit 一并归它）——那时把 Spawn 的参数摊开即可，
-- 死亡那一刻要生成的鱼获挂在 `Mgr:SubscribeDied` 上（路线图 I-13：血量归零那刻在鱼的位置生成鱼获）。

local GameCfg = require("common.GameCfg")

local Mgr = {}

-- 受击体的名字固定：探针与调试按名字反查
Mgr.RECEIVER_NAME = "FishHitReceiver"
-- 鱼本体默认名前缀
Mgr.BODY_NAME_PREFIX = "FishCarrier"

-- 血量口径：本图 GameCfg 与策划案都还没有鱼的血量（M0-V3 只定了模型号，挥砍伤害 25 在
-- GameCfg.Ability 里），缺口径 → 取引擎自己的默认：EggyUnit 的 Controller 默认
-- `MaxHealth = 100`（M0-V6 / D-1 实测值）。M2 定策划数值后写进 GameCfg.FishCarrier.MaxHealth 覆盖。
Mgr.DEFAULT_MAX_HEALTH = 100

-- [bodyUnitId] = carrier
Mgr.Carriers = {}
-- 死亡订阅者：fn(carrier) → 是否已处理（M2 在这里生成鱼获，I-13）
Mgr.Subscribers = {}

-- ===== 纯函数：配置解析（单测覆盖 tests/fish_carrier_test.lua）=====

local function isPositiveNumber(v)
	if type(v) ~= "number" then
		return false
	end
	-- nan / inf 与任何值比较都恒为 false，先显式挡掉（同 MgrReelIn 的判定口径）
	if v ~= v or v == math.huge or v == -math.huge then
		return false
	end
	return v > 0
end

-- cfg 缺省取本图配置：`{MaxHealth=..., RenderMeshId=..., PhysicsMeshId=..., ModelId=...}`
-- （形状取自 common/GameCfg.lua 的 TODO(M0-V3) 注释；单测显式传 cfg 以免依赖它落盘与否）
local function resolveMaxHealth(opts, cfg)
	cfg = cfg or GameCfg.FishCarrier or {}
	local v = opts and opts.MaxHealth
	if v == nil then
		v = cfg.MaxHealth
	end
	if not isPositiveNumber(v) then
		return Mgr.DEFAULT_MAX_HEALTH
	end
	return v
end

-- 模型资源写法：`RenderMeshId = "official://mesh/<模型号>"`（M0-V3 实测结论，见台账 §2.1）。
-- 优先显式入参（试玩探针、M2 自定义都走这条），其次 GameCfg.FishCarrier，最后 ModelId 拼写法。
local function resolveMesh(opts, cfg)
	cfg = cfg or GameCfg.FishCarrier or {}
	if opts and opts.RenderMeshId and opts.RenderMeshId ~= "" then
		return opts.RenderMeshId
	end
	if cfg.RenderMeshId and cfg.RenderMeshId ~= "" then
		return cfg.RenderMeshId
	end
	local id = (opts and opts.ModelId) or cfg.ModelId
	if id ~= nil and id ~= "" then
		return "official://mesh/" .. tostring(id)
	end
	return nil
end

Mgr.ResolveMaxHealth = resolveMaxHealth
Mgr.ResolveMesh = resolveMesh

-- ===== 引擎侧 =====

local function readPosition(unit)
	if not unit then
		return nil
	end
	if unit.GetPosition then
		return unit:GetPosition()
	end
	local ok, pos = pcall(function()
		return unit.Position
	end)
	if ok then
		return pos
	end
	return nil
end

-- 把受击体挪到鱼本体上。举着 / 逃脱 / 落地都靠这一句跟住：受击体与鱼本体之间没有约束，
-- 引擎也没有「子节点跟随父节点」的开关给 EggyUnit 用（实测 ModelBindParent 在 EggyUnit 上不存在）。
local function syncReceiver(carrier)
	local body = carrier.Body
	local receiver = carrier.Receiver
	if not body or not receiver then
		return
	end
	local ok, pos = pcall(readPosition, body)
	if not ok or not pos then
		return
	end
	pcall(function()
		if receiver.SetPosition then
			receiver:SetPosition(pos + carrier.ReceiverOffset)
		else
			receiver.Position = pos + carrier.ReceiverOffset
		end
	end)
end

function Mgr:SubscribeDied(fn)
	if type(fn) ~= "function" then
		return false
	end
	self.Subscribers[#self.Subscribers + 1] = fn
	return true
end

-- 死亡单点：`Died` 与 `HealthChanged(<=0)` 两条路都可能来，只往外通知一次（同 D-11 的兜底口径）。
-- 实测（M18 台账 §11.3）：致命那一下引擎**只发 `Died`、不发 `HealthChanged`**，所以两条都要接。
-- 通知前把 Controller 的真血量同步回记录：致命一击时 Died 早于 HealthChanged，
-- 订阅者若读 carrier.Health 会看到上一档的值（实测读到 25 而不是 0）。
function Mgr:NotifyDied(carrier)
	if not carrier or carrier.Dead then
		return
	end
	carrier.Dead = true
	if carrier.Controller then
		local ok, health = pcall(function()
			return carrier.Controller.Health
		end)
		if ok and type(health) == "number" then
			carrier.Health = health
		end
	end
	for _, fn in ipairs(self.Subscribers) do
		pcall(fn, carrier)
	end
end

-- 公开接口一律冒号调用（`Mgr:XXX(...)`），与本图其它 Mgr 一致；只有上面两个纯函数是点号
-- （它们不碰 self，给单测直接调）。
---给一条鱼本体补伤害接口：建受击体、接血量与死亡信号
---@param body Unit 鱼本体（WorldUnit，举鱼要求 Liftable + Dynamic）
---@param opts? Table { MaxHealth, ReceiverOffset }
---@return Table carrier
function Mgr:Attach(body, opts)
	opts = opts or {}
	local World = game:GetService("World")
	if not body or not World then
		return nil
	end

	local pos = readPosition(body) or Vector3.New(0, 0, 0)
	local maxHealth = resolveMaxHealth(opts)

	-- 受击体：与鱼本体同名的受击点。EggyUnit + EnableController 是引擎里唯一「脚本能建、
	-- 又带 Controller」的单位类型（WorldUnit 挂不上 Controller，#32 的根因）。
	local receiver = World:CreateUnit("EggyUnit", {
		Name = Mgr.RECEIVER_NAME .. "_" .. tostring(body.UnitId),
		Parent = body,
		Position = pos + (opts.ReceiverOffset or Vector3.New(0, 0, 0)),
		EnableController = true,
		Visible = false,
	})
	if not receiver then
		print("[MgrFishCarrier] 受击体创建失败，这条鱼不会被挥砍扣血: " .. tostring(body.UnitId))
		return nil
	end

	local controller = receiver.Controller
	if not controller then
		-- 到了这里说明 EnableController 这条接缝变了：伤害会静默归零，不能静默吞掉（#32 就是这么来的）
		print("[MgrFishCarrier] 受击体没有 Controller，伤害接口不成立: " .. tostring(body.UnitId))
		return nil
	end

	controller.MaxHealth = maxHealth
	controller.Health = maxHealth

	local carrier = {
		Body = body,
		Receiver = receiver,
		Controller = controller,
		MaxHealth = maxHealth,
		Health = maxHealth,
		FishId = opts.FishId,
		Player = opts.Player,
		ReceiverOffset = opts.ReceiverOffset or Vector3.New(0, 0, 0),
		Dead = false,
	}

	carrier.HealthConn = controller.HealthChanged:Connect(function(health)
		carrier.Health = health
		if health <= 0 then
			Mgr:NotifyDied(carrier)
		end
	end)
	carrier.DiedConn = controller.Died:Connect(function()
		Mgr:NotifyDied(carrier)
	end)

	-- 受击体与鱼本体不参与彼此碰撞：两者同位置，交给物理互推会把鱼顶走
	-- （实测同位的动态 WorldUnit 会被推开，见台账 §1）。这条是保险，失败不影响伤害。
	if body.AddNoCollisionPairWithUnit then
		pcall(body.AddNoCollisionPairWithUnit, body, receiver)
	end

	self.Carriers[body.UnitId] = carrier
	return carrier
end

---建一条鱼载体：鱼本体（WorldUnit + 官方鱼模型）+ 伤害接口
---@param opts Table { Position, Rotation, FishId, MaxHealth, RenderMeshId, ModelId, Mass, BodyType, GravityEnabled, LinearDamping, AngularDamping, ReceiverOffset, Player }
---@return Table? carrier, string? 失败原因
function Mgr:Spawn(opts)
	opts = opts or {}
	local World = game:GetService("World")
	if not World then
		return nil, "no-world"
	end
	local mesh = resolveMesh(opts)
	if not mesh then
		-- 建不出几何的空壳鱼没有意义（RenderMeshId 缺失时引擎只给你一个 1×1×1 方块）
		return nil, "no-mesh"
	end

	local cfg = GameCfg.FishCarrier or {}
	local values = {
		Name = Mgr.BODY_NAME_PREFIX .. "_" .. tostring(opts.FishId or "unknown"),
		Position = opts.Position or Vector3.New(0, 0, 0),
		Rotation = opts.Rotation or Quaternion.FromEulerAngles(0, 0, 0),
		RenderMeshId = mesh,
		-- 缺省时引擎取 RenderMeshId 作物理资源（M0-V3），这里只在显式给了才写
		-- Enums.BodyType.Dynamic(4)：抓举只对动态物体生效；逃脱阶段用 Kinematic(2) 由脚本驱动
		BodyType = opts.BodyType or 4,
		PhysicsActive = true,
		Liftable = true,
		Mass = opts.Mass or 10,
		GravityEnabled = opts.GravityEnabled,
	}
	if opts.PhysicsMeshId then
		values.PhysicsMeshId = opts.PhysicsMeshId
	elseif cfg.PhysicsMeshId and cfg.PhysicsMeshId ~= "" then
		values.PhysicsMeshId = cfg.PhysicsMeshId
	end
	if values.GravityEnabled == nil then
		values.GravityEnabled = true
	end
	-- 阻尼：受击体与鱼本体同位置，物理层难免偶尔互推；给动态鱼一点阻尼，
	-- 被推一下不会一漂到底（M18 试玩实测：无阻尼 + 无重力时会一直漂）。
	if opts.LinearDamping then
		values.LinearDamping = opts.LinearDamping
	end
	if opts.AngularDamping then
		values.AngularDamping = opts.AngularDamping
	end

	local body = World:CreateUnit("WorldUnit", values)
	if not body then
		return nil, "body-create-failed"
	end

	local carrier = self:Attach(body, opts)
	if not carrier then
		pcall(function()
			body:Destroy()
		end)
		return nil, "receiver-create-failed"
	end
	return carrier
end

---单点造成的伤害（业务侧要主动扣血时用；技能来源的扣血走包内 _applyDamage，不经这里）
function Mgr:Damage(carrier, damage)
	if not carrier or carrier.Dead or not carrier.Controller then
		return false
	end
	if not isPositiveNumber(damage) then
		return false
	end
	carrier.Controller:TakeDamage(damage)
	return true
end

function Mgr:Despawn(carrier)
	if not carrier then
		return
	end
	if carrier.HealthConn then
		carrier.HealthConn:Disconnect()
	end
	if carrier.DiedConn then
		carrier.DiedConn:Disconnect()
	end
	if carrier.Body and carrier.Body.UnitId then
		self.Carriers[carrier.Body.UnitId] = nil
	end
	-- 受击体是鱼本体的子节点，跟着一起回收
	pcall(function()
		if carrier.Body then
			carrier.Body:Destroy()
		end
	end)
	carrier.Body = nil
	carrier.Receiver = nil
	carrier.Controller = nil
end

function Mgr:Start()
end

function Mgr:OnPlayerAdded(player)
end

function Mgr:OnPlayerRemoving(player)
end

-- 每帧把受击体跟到鱼本体上（举着 / 逃脱 / 落地都跟得住）。
-- 6 条鱼 × 30Hz 的量级与 M0-V4 实测的 12 条 0.074 ms/帧 同量级，不构成开销问题。
function Mgr:Update(deltaTime)
	for _, carrier in pairs(self.Carriers) do
		syncReceiver(carrier)
	end
end

return Mgr

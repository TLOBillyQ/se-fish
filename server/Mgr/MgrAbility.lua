-- 技能管理器：把官方技能包装进本图。只做装配，不含任何玩法逻辑。
-- 装到角色下的技能管理器单位（官方叫「技能背包」，与 CONTEXT.md 的物品「背包」不同物）
-- 由包内管理器脚本负责解析归属、按 InitAbilities 装备技能；
-- 本模块只负责「建管理器 → 装技能 → 挂锚点」三件事，全程经根 AbilityAPI 触达技能包。

local World = game:GetService("World")
local Task = game:GetService("Task")

local GameCfg = require("common.GameCfg")
-- 体型计划由 MgrAttr 通过属性模型投影。
-- 属性计算与引擎投影由注入的 MgrAttr 统一持有。
local AbilityAPI = require("server.AbilityAPI")

local Mgr = { PendingFishCleanup = {} }

-- [userId] = 该玩家的技能管理器 ScriptUnit
Mgr.Managers = {}
-- [userId] = 该玩家的 CharacterAdded 连接
Mgr.CharacterSignals = {}
-- #139 持续效果状态机：[targetKey] = { kind='player'|'fish', ref=目标, carrier=鱼载体,
--   poison/burn={stacks,expiresAt,nextTickAt,source}, frost/paralyze={expiresAt,source} }
-- 玩家键 'p:<userId>'；鱼键带载体（查询走载体比对，不依赖键形状）。
Mgr.Effects = {}
-- [userId] = 角色入图时捕获的基础移速（成长/虚弱/霜冻/麻痹的乘算基准，只捕一次）
Mgr.SpeedBase = {}

-- 装备尝试的等待上限（0.1 秒一次）：管理器脚本是延迟执行的，AbilityManager 标签要等它 Attach 完才查得到。
local EQUIP_RETRY_INTERVAL = 0.1
local EQUIP_RETRY_COUNT = 50

-- 建一个技能管理器挂到角色下
local function createManager(character, presetKey)
	local assets = World:CreateAsset(presetKey)
	local manager = assets and assets[1]
	if not manager then
		print("[MgrAbility] 技能管理器预设创建失败: " .. tostring(presetKey))
		return nil
	end
	manager.Parent = character
	return manager
end

-- 锚点实例属性覆盖：预设里「已声明的属性」改不动默认值（issue #7 坑 2），
-- 关键值在挂接前直接 SetAttribute 到实例；{x,y,z} 表转成 Vector3（GameCfg 要保持纯数据可单测）。
local function applyAnchorAttributes(anchor, attrs, presetKey)
	if not attrs then
		return
	end
	for key, value in pairs(attrs) do
		if type(value) == "table" then
			value = Vector3.New(value.x or 0, value.y or 0, value.z or 0)
		end
		local ok, err = pcall(anchor.SetAttribute, anchor, key, value)
		if not ok then
			print("[MgrAbility] 锚点属性覆盖失败: " .. tostring(presetKey) .. " " .. tostring(key) .. " " .. tostring(err))
            return false
		end
	end
    return true
end

-- 锚点：运行时装配（本图的锚点预设壳不挂接，只声明属性）。
-- 顺序要紧：预设实例化时壳脚本会在 Parent 还是 World 的那一刻执行，此时 anchor_logic 认错宿主；
-- 所以必须先把锚点 parent 到技能单位、覆盖实例属性，再由根 AbilityAPI 补挂框架与行为。
local function createAnchor(abilityScript, entry)
	local assets = World:CreateAsset(entry.Anchor)
	local anchor = assets and assets[1]
	if not anchor then
		print("[MgrAbility] 锚点预设创建失败: " .. tostring(entry.Anchor))
		return nil
	end
	anchor.Parent = abilityScript
	if applyAnchorAttributes(anchor, entry.AnchorAttributes, entry.Anchor) == false then
        anchor:Destroy()
        return nil
    end
	local ok, err = pcall(AbilityAPI.AttachAnchor, anchor, entry.AnchorBehavior)
	if not ok or err ~= true then
		print("[MgrAbility] 锚点挂接失败: " .. tostring(err))
        local removed, removeError = pcall(function() anchor:Destroy() end)
        if not removed then print('[MgrAbility] 回收失败锚点', tostring(removeError)) end
        return nil
	end
	return anchor
end

-- 角色可能正处在重生的空档里被销毁：读子节点抛错就当成角色没了。
-- 不静默：这一路只会走到一次（随后 return），把原因打出来省得事后猜。
local function characterReadable(character)
	local ok, err = pcall(function()
		return character:GetChildren()
	end)
	if not ok then
		print("[MgrAbility] 角色已不可读，放弃装备: " .. tostring(err))
	end
	return ok
end

-- 管理器就绪需要等：管理器脚本 Attach 之后才会打上 AbilityManager 标签，
-- 而 AddAbility 靠这个标签反查管理器，早于此会拿不到。
local function equip(character, entry)
	Task:Spawn(function()
		for _ = 1, EQUIP_RETRY_COUNT do
			if not characterReadable(character) then
				return
			end
			local abilityScript = AbilityAPI.AddAbility(character, entry.AssetId, entry.Index)
			if abilityScript then
				-- 技能模板默认 CdTime=3 / CastTime=0.5；有配置时覆盖，出手节奏交给 MgrWeapon 的 IntervalSec
				if entry.CdSec then abilityScript:SetAttribute("CdTime", entry.CdSec) end
				if entry.CastSec then abilityScript:SetAttribute("CastTime", entry.CastSec) end
				if entry.Anchor then
					createAnchor(abilityScript, entry)
				end
				return
			end
			Task:Wait(EQUIP_RETRY_INTERVAL)
		end
		print("[MgrAbility] 装备技能超时: " .. tostring(entry.AssetId))
	end)
end

local function setUpPlayer(mgr, player, character)
	if not character then
		return
	end
	local manager = createManager(character, GameCfg.Ability.ManagerPreset)
	if not manager then
		return
	end
	mgr.Managers[player.UserId] = manager

	local initialAbilities = GameCfg.Ability.InitialAbilities or {}
	for _, entry in ipairs(initialAbilities) do
		if entry.AssetId and entry.AssetId ~= "" then
			equip(character, entry)
		end
	end
end

-- 鱼技能的记录跟随鱼持有，取消标记使尚未就绪的异步装配失效。
-- #139：同时清理挂在该鱼载体上的持续效果（目标离场清理）。
function Mgr:RemoveFish(fish)
    if self.Modifier then self.Modifier:ClearTarget(fish) end
    local record = fish.AbilityRecord
    if not record then return end
    record.Cancelled = true
    if record.Ready then
        local ok, err = pcall(AbilityAPI.StopAbility, record.Receiver, record.Entry.Index)
        if not ok then print('[MgrAbility] 停止鱼技能失败', fish.Id, tostring(err)) end
    end
    local ok, err = pcall(function() record.Manager:Destroy() end)
    if not ok then
        if not self.PendingFishCleanup[fish] then
            print('[MgrAbility] 回收鱼技能管理器失败，将重试', fish.Id, tostring(err))
        end
        self.PendingFishCleanup[fish] = true
        return
    end
    self.PendingFishCleanup[fish] = nil
    fish.AbilityRecord = nil
end

function Mgr:EquipFish(fish)
    if fish.AbilityRecord then return true end
    local species = GameCfg.Fish[fish.FishId]
    local entry = GameCfg.Ability.FishAbilities[species.Combat]
    local receiver = fish.Carrier.Receiver
    if not entry or not receiver then return false end
    local manager = createManager(receiver, GameCfg.Ability.ManagerPreset)
    if not manager then return false end
    local record = { Manager = manager, Receiver = receiver, Entry = entry }
    fish.AbilityRecord = record
    Task:Spawn(function()
        local ok, err = pcall(function()
        for _ = 1, EQUIP_RETRY_COUNT do
            if record.Cancelled then return end
            if fish.Carrier.Dead then self:RemoveFish(fish) return end
            local ability = AbilityAPI.AddAbility(receiver, entry.AssetId, entry.Index)
            if ability then
                ability:SetAttribute('CastTime', entry.CastSec)
                ability:SetAttribute('CdTime', 0)
                local anchor = createAnchor(ability, {
                    Anchor = entry.Anchor,
                    AnchorBehavior = entry.AnchorBehavior,
                    AnchorAttributes = { Duration = 0, StartTime = 0, DischargeRadius = entry.Radius,
                        DischargeDamage = entry.Damage or species.Attack },
                })
                if not anchor then self:RemoveFish(fish) return end
                record.Ready = true
                print('[MgrAbility] 电鳗技能就绪', fish.Id)
                return
            end
            Task:Wait(EQUIP_RETRY_INTERVAL)
        end
        if not record.Cancelled then
            print('[MgrAbility] 电鳗技能装配超时', fish.Id)
            self:RemoveFish(fish)
        end
        end)
        if not ok then
            print('[MgrAbility] 电鳗技能装配失败', fish.Id, tostring(err))
            self:RemoveFish(fish)
        end
    end)
    return true
end

function Mgr:CastFish(fish)
    local record = fish.AbilityRecord
    if not record or not record.Ready or record.Cancelled or fish.Carrier.Dead then return false end
    return AbilityAPI.CastAbility(record.Receiver, record.Entry.Index)
end

function Mgr:CanCast(unit)
	local player = unit and unit.UserId and unit or nil
	if not player and unit then
		local players = game:GetService("Players")
		if players and players.GetPlayerFromCharacter then
			local ok, found = pcall(players.GetPlayerFromCharacter, players, unit)
			if ok then player = found
			else print('[MgrAbility] 玩家解析失败', tostring(found)) end
		end
	end
	if not player then return true end -- 鱼等服务端单位的技能不受玩家动作互斥影响
	if not self.Vitals then return true end
	return self.Vitals:CanAct(player)
end

-- #132 T11 原型：三倍体型的装配口。数值与派生量在 common/BodyScale.lua，落地在 AbilityAPI.SetBodyScale，
-- 这里只负责「从玩家存档读药水数 → 应用到角色」。
-- 边界（本单未做，见 issue #132 待办清单）：
--   * 交互距离/相机距离先用角色属性发布，客户端是否读取、三倍碰撞体是否真的能拾取/钓鱼/摆渡要真机试玩。
-- #139 起血量上限随药水成长（MgrVitals:RefreshMaxHealth 单点落地，见 ApplyGrowth）。
---玩家已吃某药水的个数：走注入的 MgrPlayerData（存档 PlayerData），读不到按 0 个处理。
---#132 原型误读引擎玩家的 player.Data（永远不存在），本单修复为 PlayerData:PotionCount。
function Mgr:PotionCount(player, itemId)
	if not self.PlayerData or not self.PlayerData.GetDataInst then return 0 end
	local ok, count = pcall(function()
		local data = self.PlayerData:GetDataInst(player)
		return data and data:PotionCount(itemId) or 0
	end)
	if ok and type(count) == 'number' then return count end
	return 0
end

---按玩家已吃的变大药水算体型计划（读不到存档时按 0 个处理）
---@return table { Scale, Health, Potions, Capped, MaxScale, MaxHealth }
function Mgr:BodyPlan(player)
	return self.Attr:BodyPlan(player)
end

---把体型计划落到角色上：SetScale + 派生量属性。倍率非法由 BodyScale 净化，不会写入 NaN。
---@return table { Ok, Scale?, Health?, Capped?, Derived?, Error? }
function Mgr:ApplyBodyScale(player)
	return self.Attr:ApplyBodyScale(player)
end

-- ===== #139 属性成长应用（唯一计算处）=====

local function controllerOf(player)
	local character = player and player.Character
	return character and character.Controller
end

---角色入图（或重生）时捕获基础移速：整段会话只捕一次，此时角色必为引擎默认速度，
---之后所有修饰（成长/虚弱/霜冻/麻痹）都以它为基准乘算，不重复捕获被改过的值。
function Mgr:CaptureBaseSpeed(player)
	return self.Attr:CaptureBaseSpeed(player)
end

---玩家血量上限：基础 300 + 变大药水成长（AttrGrowth 委托 BodyScale 钉表）
function Mgr:MaxHealth(player)
	return self.Attr:MaxHealth(player)
end

---移速刷新委托：MgrAttr读取成长计数与统一效果倍率，单点投影。
---任何一侧变化（喝药/虚弱进出/霜冻麻痹起止/重生）都调本函数整体重写，不做增量叠加。
-- 所有调用路径共用速度重试队列；每名玩家只登记一次，连续失败只记录首个错误，避免心跳刷屏。
local function queueSpeed(self, player, err)
	self.PendingSpeed = self.PendingSpeed or {}
	if not self.PendingSpeed[player.UserId] then
		print('[MgrAbility] 移速写入失败', player.UserId, tostring(err))
	end
	self.PendingSpeed[player.UserId] = player
	return false, tostring(err)
end

function Mgr:RefreshMoveSpeed(player)
	local ok, err = self.Attr:RefreshMoveSpeed(player)
	if not ok then
		return queueSpeed(self, player, err)
	end
	if self.PendingSpeed then self.PendingSpeed[player.UserId] = nil end
	return true
end

---喝属性药水后的一站应用：体型 + 血量上限 + 移速。存档计数已落账，这里全部重算。
function Mgr:ApplyGrowth(player)
	local applied = self.Attr:ApplyGrowth(player)
	local retryGrowth = not applied.Ok
	if retryGrowth then
		self.PendingGrowth = self.PendingGrowth or {}
		self.PendingGrowth[player.UserId] = player
	elseif self.PendingGrowth then self.PendingGrowth[player.UserId] = nil end
	return applied
end

-- ===== #139 持续效果状态机（毒/灼烧叠层，霜冻/麻痹不叠加）=====

function Mgr:Now()
	local ok, now = pcall(function() return World:GetServerTime() end)
	return ok and now or 0
end

---把命中目标解析为效果宿主：玩家（UserId 或角色反查）或鱼（FishCarrier 载体）。
---@return string? key, any? ref, string? kind, table? carrier
function Mgr:ResolveEffectTarget(target)
	if not target then return nil end
	if target.UserId then return 'p:' .. tostring(target.UserId), target, 'player' end
	local players = game:GetService("Players")
	if players and players.GetPlayerFromCharacter then
		local ok, found = pcall(players.GetPlayerFromCharacter, players, target)
		if ok and found then return 'p:' .. tostring(found.UserId), found, 'player' end
	end
	if self.Vitals and self.Vitals.FishCarrier and self.Vitals.FishCarrier.ResolveCarrier then
		local ok, carrier = pcall(self.Vitals.FishCarrier.ResolveCarrier, self.Vitals.FishCarrier, target)
		if ok and carrier then
			local key = carrier.Body and carrier.Body.UnitId and ('c:' .. tostring(carrier.Body.UnitId))
				or tostring(carrier)
			return key, target, 'fish', carrier
		end
	end
	return nil
end

---武器命中挂持续效果（统一规格 §6.3）：毒/灼烧叠层（上限 5）并刷新持续、tick 相位不变；
---霜冻/麻痹不叠加只刷新。同一目标同一效果只有一条状态（唯一状态管理）。
---@param source any 攻击来源玩家（DOT 的 NewHit 来源）
---@param target any 命中目标（玩家/角色/鱼记录/载体/鱼本体）
---@param effect table { Kind = 'poison'|'burn'|'frost'|'paralyze' }
function Mgr:ApplyWeaponEffect(source, target, effect)
	return self.Modifier:ApplyWeaponEffect(source, target, effect)
end

-- 兼容既有离线探针公开入口；运行时仅 MgrModifier.Update 调度 DOT。
function Mgr:UpdateEffects()
	return self.Modifier:Update()
end

---玩家是否麻痹（无法行动）：MgrVitals.CanAct 的 ActGuard 钩子用
function Mgr:IsParalyzed(player)
	return self.Modifier:IsControlled(player)
end

-- 鱼的效果条目按载体比对（鱼记录/本体/接收器都可能当过命中目标，键形状不可靠）
function Mgr:FishEffects(fish)
	local carrier = fish and fish.Carrier
	if not carrier then return nil end
	for _, entry in pairs(self.Effects) do
		if entry.kind == 'fish' and entry.carrier == carrier then return entry end
	end
	return nil
end

---鱼移速乘区（MgrFishUnit:Speed 唯一读取点挂这里）：麻痹 0、霜冻 0.7、都无 1
function Mgr:FishSpeedFactor(fish)
	return self.Modifier:GetMoveMultiplier(fish)
end

---鱼是否麻痹（追咬/攻击闸用）
function Mgr:FishParalyzed(fish)
	return self.Modifier:IsControlled(fish)
end

function Mgr:Start()
	AbilityAPI.SetCastGuard(function(unit, index) return self:CanCast(unit) end)
end

function Mgr:OnPlayerAdded(player)
	if self.CharacterSignals[player.UserId] then
		return
	end

	self.CharacterSignals[player.UserId] = player.CharacterAdded:Connect(function(character)
		setUpPlayer(self, player, character)
		-- #139：CaptureBaseSpeed 只捕首次（重生时跳过，不会把修饰中的速度当基准）；
		-- 重生后引擎重置体型/速度，按存档成长重套。
		self:CaptureBaseSpeed(player)
		self:ApplyGrowth(player)
	end)

	-- 事件注册前就进图的玩家，Character 可能已经就绪
	if player.Character then
		setUpPlayer(self, player, player.Character)
		self:CaptureBaseSpeed(player)
		self:ApplyGrowth(player)
	end
end

function Mgr:OnPlayerRemoving(player)
	local signal = self.CharacterSignals[player.UserId]
	if signal then
		signal:Disconnect()
		self.CharacterSignals[player.UserId] = nil
	end

	-- 管理器挂在角色下，角色销毁时一起消失；这里只清引用，不主动 Destroy，
	-- 避免离开流程里再动一次正被销毁的单位。
	self.Managers[player.UserId] = nil
	-- 效果目标与来源清理由 MgrModifier 的独立生命周期负责。
	if self.PendingGrowth then self.PendingGrowth[player.UserId] = nil end
	if self.PendingSpeed then self.PendingSpeed[player.UserId] = nil end
	self.SpeedBase[player.UserId] = nil
end

function Mgr:Update(deltaTime)
    for fish in pairs(self.PendingFishCleanup) do self:RemoveFish(fish) end
    -- 只重试本帧开始已有的请求；本帧到期事件失败留到下一帧。刷新始终读取当前存档/权威状态。
    local retrySpeed = {}
    for uid, player in pairs(self.PendingSpeed or {}) do retrySpeed[uid] = player end
    for uid, player in pairs(retrySpeed) do
        if self.PendingSpeed and self.PendingSpeed[uid] == player then self:RefreshMoveSpeed(player) end
    end
    for _, player in pairs(self.PendingGrowth or {}) do self:ApplyGrowth(player) end
end

return Mgr

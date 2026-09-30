-- 技能管理器：把官方技能包装进本图。只做装配，不含任何玩法逻辑。
-- 装到角色下的技能管理器单位（官方叫「技能背包」，与 CONTEXT.md 的物品「背包」不同物）
-- 由包内管理器脚本负责解析归属、按 InitAbilities 装备技能；
-- 本模块只负责「建管理器 → 装技能 → 挂锚点」三件事，全程经根 AbilityAPI 触达技能包。

local World = game:GetService("World")
local Task = game:GetService("Task")

local GameCfg = require("common.GameCfg")
local BodyScale = require("common.BodyScale")
local AttrGrowth = require("common.AttrGrowth")
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
    for key, entry in pairs(self.Effects) do
        if entry.kind == 'fish' and entry.carrier and fish and entry.carrier == fish.Carrier then
            self.Effects[key] = nil
        end
    end
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
	return BodyScale.Plan(self:PotionCount(player, GameCfg.Ability.BodyScale.PotionItem))
end

---把体型计划落到角色上：SetScale + 派生量属性。倍率非法由 BodyScale 净化，不会写入 NaN。
---@return table { Ok, Scale?, Health?, Capped?, Derived?, Error? }
function Mgr:ApplyBodyScale(player)
	local character = player and player.Character
	if not character then return { Ok = false, Error = 'no-character' } end
	local plan = self:BodyPlan(player)
	local applied = AbilityAPI.SetBodyScale(character, plan.Scale)
	if not applied.Ok then return { Ok = false, Error = applied.Error, Plan = plan } end
	local derived = applied.Derived or {}
	pcall(function()
		character:SetAttribute('CameraDistance', derived.CameraDistance)
		character:SetAttribute('InteractRange', derived.InteractRange)
		character:SetAttribute('BodyScaleCapped', plan.Capped)
	end)
	print('[MgrAbility] 体型', player.UserId, plan.Potions, applied.Scale, 'health=' .. tostring(plan.Health))
	return { Ok = true, Scale = applied.Scale, Health = plan.Health, Capped = plan.Capped, Derived = derived }
end

-- ===== #139 属性成长应用（唯一计算处）=====

local function controllerOf(player)
	local character = player and player.Character
	return character and character.Controller
end

---角色入图（或重生）时捕获基础移速：整段会话只捕一次，此时角色必为引擎默认速度，
---之后所有修饰（成长/虚弱/霜冻/麻痹）都以它为基准乘算，不重复捕获被改过的值。
function Mgr:CaptureBaseSpeed(player)
	local uid = player and player.UserId
	if not uid or self.SpeedBase[uid] then return end
	local controller = controllerOf(player)
	if not controller then return end
	local ok, speed = pcall(function() return controller.WalkSpeed end)
	if ok and type(speed) == 'number' and speed > 0 then
		self.SpeedBase[uid] = speed
	end
end

---玩家血量上限：基础 300 + 变大药水成长（AttrGrowth 委托 BodyScale 钉表）
function Mgr:MaxHealth(player)
	return AttrGrowth.MaxHealth(self:PotionCount(player, GameCfg.Ability.BodyScale.PotionItem))
end

---移速唯一写口：基础 × 加速成长 × 虚弱 × 霜冻（麻痹为 0），数值在 common/AttrGrowth.lua 算一次。
---任何一侧变化（喝药/虚弱进出/霜冻麻痹起止/重生）都调本函数整体重写，不做增量叠加。
function Mgr:RefreshMoveSpeed(player)
	local controller = controllerOf(player)
	if not controller then return false, "no-controller" end
	self:CaptureBaseSpeed(player)
	local base = self.SpeedBase[player.UserId] or GameCfg.Ability.MoveSpeed.Base
	local weak = false
	if self.Survival and self.Survival.GetState then
		local ok, state = pcall(self.Survival.GetState, self.Survival, player)
		weak = ok and state ~= nil and state.weakUntil ~= nil
	end
	local entry = self.Effects['p:' .. tostring(player.UserId)]
	local now = self:Now()
	local frost = entry ~= nil and entry.frost ~= nil and now < entry.frost.expiresAt
	local paralyzed = entry ~= nil and entry.paralyze ~= nil and now < entry.paralyze.expiresAt
	local speed = AttrGrowth.EffectiveSpeed(base,
		self:PotionCount(player, GameCfg.Ability.SpeedPotion.Item),
		{ weak = weak, frost = frost, paralyzed = paralyzed })
	local ok, err = pcall(function() controller.WalkSpeed = speed end)
	if not ok then
		print("[MgrAbility] 移速写入失败", player.UserId, tostring(err))
		return false, tostring(err)
	end
	return true
end

---喝属性药水后的一站应用：体型 + 血量上限 + 移速。存档计数已落账，这里全部重算。
function Mgr:ApplyGrowth(player)
	local applied = self:ApplyBodyScale(player)
	local errors = {}
	if not applied.Ok then errors[#errors + 1] = tostring(applied.Error) end
	if self.Vitals and self.Vitals.RefreshMaxHealth then
		local called, ok, err = pcall(self.Vitals.RefreshMaxHealth, self.Vitals, player)
		if not called or ok ~= true then
			local reason = called and err or ok
			print('[MgrAbility] 血量上限刷新失败', player.UserId, tostring(reason))
			errors[#errors + 1] = 'MaxHealth:' .. tostring(reason)
		end
	end
	local ok, err = self:RefreshMoveSpeed(player)
	if not ok then errors[#errors + 1] = 'WalkSpeed:' .. tostring(err) end
	if #errors > 0 then
		applied.Ok, applied.Error = false, table.concat(errors, '; ')
		-- 存档已落账；后续 Update 按当前存档重算，角色重建后也会再次尝试。
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
	local fxcfg = effect and GameCfg.Ability.StatusEffects[effect.Kind]
	if not fxcfg then return false end
	local kind = effect.Kind
	local key, ref, targetKind, carrier = self:ResolveEffectTarget(target)
	if not key then return false end
	local now = self:Now()
	local entry = self.Effects[key]
	if not entry then
		entry = { kind = targetKind, ref = ref, carrier = carrier }
		self.Effects[key] = entry
	end
	if fxcfg.MaxStacks then -- 毒/灼烧：叠层 + 刷新；已过期的残留按全新计
		local st = entry[kind]
		if st and st.expiresAt and now >= st.expiresAt then st = nil end
		if not st then
			st = { stacks = 0, nextTickAt = now + fxcfg.TickSec }
			entry[kind] = st
		end
		st.stacks = math.min(st.stacks + 1, fxcfg.MaxStacks)
		st.expiresAt = now + fxcfg.DurationSec
		st.source = source
	else -- 霜冻/麻痹：不叠加，只刷新持续
		entry[kind] = { expiresAt = now + fxcfg.DurationSec, source = source }
		if targetKind == 'player' then self:RefreshMoveSpeed(ref) end
	end
	return true
end

-- DOT 每跳都重新走 T07/#128 统一伤害入口（NewHit('dot') + ApplyHit），不直扣血。
local function updateDot(self, entry, kind, fxcfg, now)
	local st = entry[kind]
	if not st then return end
	while st and now >= st.nextTickAt and st.nextTickAt <= st.expiresAt do
		if self.Vitals and self.Vitals.NewHit and self.Vitals.ApplyHit then
			local hit = self.Vitals:NewHit(st.source, 'dot')
			self.Vitals:ApplyHit(hit, entry.ref, st.stacks * fxcfg.DamagePerStack)
		end
		st.nextTickAt = st.nextTickAt + fxcfg.TickSec
	end
	if now >= st.expiresAt then entry[kind] = nil end
end

function Mgr:UpdateEffects()
	local now = self:Now()
	local fxcfgAll = GameCfg.Ability.StatusEffects
	for key, entry in pairs(self.Effects) do
		if entry.kind == 'fish' and entry.carrier and entry.carrier.Dead then
			self.Effects[key] = nil -- 死鱼立即清理，不再吃 DOT
		else
			for _, kind in ipairs({ 'poison', 'burn' }) do
				updateDot(self, entry, kind, fxcfgAll[kind], now)
			end
			for _, kind in ipairs({ 'frost', 'paralyze' }) do
				local st = entry[kind]
				if st and now >= st.expiresAt then
					entry[kind] = nil
					if entry.kind == 'player' then self:RefreshMoveSpeed(entry.ref) end
				end
			end
			if not entry.poison and not entry.burn and not entry.frost and not entry.paralyze then
				self.Effects[key] = nil
			end
		end
	end
end

---玩家是否麻痹（无法行动）：MgrVitals.CanAct 的 ActGuard 钩子用
function Mgr:IsParalyzed(player)
	local entry = player and self.Effects['p:' .. tostring(player.UserId)]
	local st = entry and entry.paralyze
	return st ~= nil and self:Now() < st.expiresAt
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
	local entry = self:FishEffects(fish)
	if not entry then return 1 end
	local now = self:Now()
	if entry.paralyze and now < entry.paralyze.expiresAt then return 0 end
	if entry.frost and now < entry.frost.expiresAt then
		return 1 - GameCfg.Ability.StatusEffects.frost.SlowPercent / 100
	end
	return 1
end

---鱼是否麻痹（追咬/攻击闸用）
function Mgr:FishParalyzed(fish)
	local entry = self:FishEffects(fish)
	return entry ~= nil and entry.paralyze ~= nil and self:Now() < entry.paralyze.expiresAt
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
	-- #139 目标离场清理：持续效果与移速基准随玩家移除
	self.Effects['p:' .. tostring(player.UserId)] = nil
	-- 来源退出策略：取消该来源在所有目标上的效果，避免下一跳丢失权威来源身份。
	for _, entry in pairs(self.Effects) do
		for _, kind in ipairs({ 'poison', 'burn', 'frost', 'paralyze' }) do
			local st = entry[kind]
			if st and st.source == player then entry[kind] = nil end
		end
		if entry.kind == 'player' then self:RefreshMoveSpeed(entry.ref) end
	end
	if self.PendingGrowth then self.PendingGrowth[player.UserId] = nil end
	self.SpeedBase[player.UserId] = nil
end

function Mgr:Update(deltaTime)
    for fish in pairs(self.PendingFishCleanup) do self:RemoveFish(fish) end
    self:UpdateEffects()
    for _, player in pairs(self.PendingGrowth or {}) do self:ApplyGrowth(player) end
end

return Mgr

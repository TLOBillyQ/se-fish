-- 技能管理器：把官方技能包装进本图。只做装配，不含任何玩法逻辑。
-- 装到角色下的技能管理器单位（官方叫「技能背包」，与 CONTEXT.md 的物品「背包」不同物）
-- 由包内管理器脚本负责解析归属、按 InitAbilities 装备技能；
-- 本模块只负责「建管理器 → 装技能 → 挂锚点」三件事，全程经根 AbilityAPI 触达技能包。

local World = game:GetService("World")
local Task = game:GetService("Task")

local GameCfg = require("common.GameCfg")
local AbilityAPI = require("server.AbilityAPI")

local Mgr = { PendingFishCleanup = {} }

-- [userId] = 该玩家的技能管理器 ScriptUnit
Mgr.Managers = {}
-- [userId] = 该玩家的 CharacterAdded 连接
Mgr.CharacterSignals = {}

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
function Mgr:RemoveFish(fish)
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
                    AnchorAttributes = { Duration = 0, DischargeRadius = entry.Radius,
                        DischargeDamage = species.Attack },
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

function Mgr:Start()
end

function Mgr:OnPlayerAdded(player)
	if self.CharacterSignals[player.UserId] then
		return
	end

	self.CharacterSignals[player.UserId] = player.CharacterAdded:Connect(function(character)
		setUpPlayer(self, player, character)
	end)

	-- 事件注册前就进图的玩家，Character 可能已经就绪
	if player.Character then
		setUpPlayer(self, player, player.Character)
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
end

function Mgr:Update(deltaTime)
    for fish in pairs(self.PendingFishCleanup) do self:RemoveFish(fish) end
end

return Mgr

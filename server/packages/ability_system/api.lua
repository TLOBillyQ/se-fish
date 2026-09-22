--技能系统 - server端api
--服务端权威技能 API 实现；仅由根 AbilityAPI.lua 在服务端加载。

local AbilityConstants = require("common.packages.ability_system.constants")
local AbilityRegistry = require("common.packages.ability_system.registry")
local SubAbilityPlugin = require("server.packages.ability_system.sub_ability_plugin")

local AbilityServerAPI = {}

local function addExistingAbility(config)
	local managerHandler = AbilityRegistry.getManagerHandler(config.manager)
	if not managerHandler or not config.existingScript then
		return false
	end
	local abilityScript = config.existingScript
	local def = AbilityRegistry.getDefinition(config.name)
	if def then
		abilityScript:SetAttribute("AbilityName", config.name)
		abilityScript:SetAttribute("CdTime", def.cdTime)
		abilityScript:SetAttribute("CastTime", def.castTime)
		if def.maxLevel then
			abilityScript:SetAttribute("MaxLevel", def.maxLevel)
		end
		if def.maxChargeCount then
			abilityScript:SetAttribute("MaxChargeCount", def.maxChargeCount)
		end
		if def.pointerType then
			abilityScript:SetAttribute("PointerType", def.pointerType)
		end
		if def.releaseType then
			abilityScript:SetAttribute("ReleaseType", def.releaseType)
		end
	end
	abilityScript:SetAttribute("Index", config.slotIndex)
	AbilityRegistry.addTag(abilityScript, AbilityConstants.Tag.AbilityUnit)
	abilityScript.Parent = config.manager
	local added = managerHandler.addAbility(abilityScript, config.slotIndex)
	if added then
		-- 装好后按配置自动建子技能组（无子技能则内部跳过）
		SubAbilityPlugin.OnAbilityReady(abilityScript)
	end
	return added
end

local function getManagerForUnit(unit)
	if not unit then
		return nil
	end
	if AbilityRegistry.getManagerHandler(unit) then
		return unit
	end
	for _, child in ipairs(unit:GetChildren()) do
		if AbilityRegistry.hasTag(child, AbilityConstants.Tag.AbilityManager) then
			return child
		end
	end
	return nil
end

---给单位装备技能到指定槽位（不传槽位自动找空槽；同槽同预设复用现有实例）
---@param unit Unit 目标单位
---@param abilityKey string 技能预设 Key
---@param slotIndex integer? 槽位索引（0 基），不传自动找空槽
---@return Script? 技能脚本单位
---@return string? err 失败原因（带 [ability_system] 前缀）
function AbilityServerAPI.AddAbility(unit, abilityKey, slotIndex)
	local manager = getManagerForUnit(unit)
	if not manager or not abilityKey or abilityKey == "" then
		return nil, "[ability_system] AddAbility: manager or abilityKey is invalid"
	end
	local managerHandler = AbilityRegistry.getManagerHandler(manager)
	slotIndex = slotIndex or managerHandler.getFirstAvailableSlot()
	if not slotIndex then
		return nil, "[ability_system] AddAbility: no available slot"
	end

	local existingHandler = managerHandler.getAbility(slotIndex)
	if existingHandler then
		local existingScript = existingHandler.getScript()
		if existingScript:GetAttribute("AbilityPresetKey") == abilityKey then
			return existingScript
		end
		return nil, "[ability_system] AddAbility: slot is occupied by another ability"
	end

	local World = game:GetService("World")
	local assets = World:CreateAsset(abilityKey)
	local abilityScript = assets and assets[1]
	if not abilityScript then
		return nil, "[ability_system] AddAbility: failed to create ability asset"
	end

	local abilityName = abilityScript:GetAttribute("AbilityName")
	if not abilityName or abilityName == "" then
		abilityName = abilityKey
	end
	abilityScript:SetAttribute("AbilityPresetKey", abilityKey)
	local added = addExistingAbility({
		name = abilityName,
		slotIndex = slotIndex,
		manager = manager,
		existingScript = abilityScript,
	})
	if not added then
		abilityScript:Destroy()
		return nil, "[ability_system] AddAbility: failed to register ability"
	end
	return abilityScript
end

---获取指定槽位的技能脚本单位
---@param unit Unit 目标单位
---@param abilityIndex integer 槽位索引（0 基）
---@return Script? 技能脚本单位，未找到返回 nil
function AbilityServerAPI.GetAbility(unit, abilityIndex)
	local manager = getManagerForUnit(unit)
	if not manager then
		return nil
	end
	local abilityHandler = AbilityRegistry.getManagerHandler(manager).getAbility(abilityIndex)
	if not abilityHandler then
		return nil
	end
	return abilityHandler.getScript()
end

---按技能脚本单位反查其 handler
---@param abilityScript Script 技能脚本单位
---@return table? handler，未注册返回 nil
function AbilityServerAPI.GetAbilityByScript(abilityScript)
	return AbilityRegistry.getAbilityHandler(abilityScript)
end

---施放指定槽位的技能
---@param unit Unit 目标单位
---@param abilityIndex integer 槽位索引（0 基）
---@param releasePoint Vector3? 释放点
---@param releaseDir Vector3? 释放方向
---@param releaseTarget integer? 释放目标
---@return boolean 是否成功开始施法
function AbilityServerAPI.CastAbility(unit, abilityIndex, releasePoint, releaseDir, releaseTarget)
	local manager = getManagerForUnit(unit)
	if not manager then
		return false, "[ability_system] CastAbility: manager not found"
	end
	local abilityHandler = AbilityRegistry.getManagerHandler(manager).getAbility(abilityIndex)
	if not abilityHandler then
		return false, "[ability_system] CastAbility: ability not found in slot"
	end
	return abilityHandler.startCast(releasePoint, releaseDir, releaseTarget)
end

---打断指定槽位技能的施法
---@param unit Unit 目标单位
---@param abilityIndex integer 槽位索引（0 基）
---@return boolean 是否成功打断
function AbilityServerAPI.StopAbility(unit, abilityIndex)
	local manager = getManagerForUnit(unit)
	if not manager then
		return false, "[ability_system] StopAbility: manager not found"
	end
	local abilityHandler = AbilityRegistry.getManagerHandler(manager).getAbility(abilityIndex)
	if not abilityHandler then
		return false, "[ability_system] StopAbility: ability not found in slot"
	end
	abilityHandler.breakCast()
	return true
end

---让指定槽位的技能进入蓄力
---@param unit Unit 目标单位
---@param abilityIndex integer 槽位索引（0 基）
---@return boolean 是否成功进入蓄力
function AbilityServerAPI.AccumulateAbility(unit, abilityIndex)
	local manager = getManagerForUnit(unit)
	if not manager then
		return false, "[ability_system] AccumulateAbility: manager not found"
	end
	local abilityHandler = AbilityRegistry.getManagerHandler(manager).getAbility(abilityIndex)
	if not abilityHandler then
		return false, "[ability_system] AccumulateAbility: ability not found in slot"
	end
	return abilityHandler.startAccumulate()
end

-- 切换子技能组下一个成员（客户端 SwitchNext 请求的服务端入口；
-- 对任意 SwitchMode 的组均可显式调用，Manual 模式依赖此入口触发轮转）
---切换子技能组到下一个成员（任意 SwitchMode 均可显式调用）
---@param unit Unit 目标单位
---@param parentSlotIndex integer 父技能槽位索引（0 基）
---@return boolean 是否成功切换
function AbilityServerAPI.SwitchNextAbility(unit, parentSlotIndex)
	local manager = getManagerForUnit(unit)
	if not manager or not parentSlotIndex then
		return false, "[ability_system] SwitchNextAbility: manager or parentSlotIndex is invalid"
	end
	local managerHandler = AbilityRegistry.getManagerHandler(manager)
	local abilityHandler = managerHandler and managerHandler.getAbility(parentSlotIndex)
	local abilityScript = abilityHandler and abilityHandler.getScript()
	-- 组以父脚本为键注册；切换后槽位可能已是子技能，故需再按子成员反查
	local group = abilityScript
		and (
			AbilityRegistry.findGroup(abilityScript)
			or AbilityRegistry.findGroupByChild(abilityScript)
		)
	if not group or not group.activateNext then
		return false, "[ability_system] SwitchNextAbility: no switchable group at slot"
	end
	return group.activateNext() or false
end

---把已装备技能移动到指定槽位
---@param unit Unit 目标单位
---@param ability Script 技能脚本单位
---@param slotIndex integer 目标槽位索引（0 基）
---@return Script? 技能脚本单位，失败返回 nil
function AbilityServerAPI.SetAbilityToSlot(unit, ability, slotIndex)
	local manager = getManagerForUnit(unit)
	if not manager or not ability or not slotIndex then
		return nil
	end
	local managerHandler = AbilityRegistry.getManagerHandler(manager)
	local abilityHandler = AbilityRegistry.getAbilityHandler(ability)
	if not abilityHandler then
		return nil
	end
	local abilityScript = abilityHandler.getScript()
	local fromIndex = abilityScript:GetAttribute("Index")
	if not fromIndex then
		return nil
	end
	if fromIndex == slotIndex then
		return abilityScript
	end
	if not managerHandler.moveAbility(fromIndex, slotIndex) then
		return nil
	end
	return abilityScript
end

---按技能预设 Key 移除该单位所有对应技能
---@param unit Unit 目标单位
---@param abilityKey string 技能预设 Key
function AbilityServerAPI.RemoveAbilityByKey(unit, abilityKey)
	local manager = getManagerForUnit(unit)
	if not manager or not abilityKey then
		return
	end
	local managerHandler = AbilityRegistry.getManagerHandler(manager)
	-- 先快照再逐个移除（getAbilities 返回新数组，遍历中改槽位是安全的）
	for _, abilityScript in ipairs(managerHandler.getAbilities()) do
		if abilityScript:GetAttribute("AbilityPresetKey") == abilityKey then
			local slotIndex = abilityScript:GetAttribute("Index")
			if slotIndex ~= nil then
				managerHandler.removeAbility(slotIndex)
			end
			AbilityRegistry.unregisterAbility(abilityScript)
			abilityScript:Destroy()
		end
	end
end

-- 移除指定槽位的技能
---移除指定槽位的技能
---@param unit Unit 目标单位
---@param slotIndex integer 槽位索引（0 基）
---@return Script? 被移除的技能脚本单位
function AbilityServerAPI.RemoveAbility(unit, slotIndex)
	local manager = getManagerForUnit(unit)
	if not manager or not slotIndex then
		return nil
	end
	local managerHandler = AbilityRegistry.getManagerHandler(manager)
	local abilityScript = managerHandler.removeAbility(slotIndex)
	if abilityScript then
		AbilityRegistry.unregisterAbility(abilityScript)
		abilityScript:Destroy()
	end
	return abilityScript
end

-- 获取单位所有已装备的技能列表
---获取单位所有已装备的技能脚本单位列表
---@param unit Unit 目标单位
---@return Script[] 技能脚本单位列表
function AbilityServerAPI.GetAbilities(unit)
	local manager = getManagerForUnit(unit)
	if not manager then
		return {}
	end
	local managerHandler = AbilityRegistry.getManagerHandler(manager)
	return managerHandler.getAbilities()
end

-- 获取指定槽位范围内的技能列表
---获取指定槽位范围内的技能脚本单位列表
---@param unit Unit 目标单位
---@param startIndex integer 起始槽位（0 基）
---@param endIndex integer 结束槽位（0 基）
---@return Script[] 技能脚本单位列表
function AbilityServerAPI.GetAbilitiesFromIndexRange(unit, startIndex, endIndex)
	local manager = getManagerForUnit(unit)
	if not manager or not startIndex or not endIndex then
		return {}
	end
	local managerHandler = AbilityRegistry.getManagerHandler(manager)
	return managerHandler.getAbilitiesInSlotRange(startIndex, endIndex)
end

-- 客户端施法请求监听（事件分发入口）
--
-- RemoteEvent 契约：OnServerEvent(player, payload)，
-- 客户端载荷为单参数 table：{ action, ownerId, index, args = {...} }。
-- 模块加载时自动注册（幂等）。

local _eventsRegistered = false

---注册客户端施法请求监听（模块加载时自动调用，幂等）
function AbilityServerAPI.RegisterEvents()
	if _eventsRegistered then
		return
	end
	_eventsRegistered = true

	local AbilityEventDefs = require("common.packages.ability_system.event_defs")
	local remoteEvent = AbilityEventDefs.getRemote()

	remoteEvent.OnServerEvent:Connect(function(player, payload)
		-- 单参数解包
		local action, index, releasePoint, releaseDir, releaseTarget
		if type(payload) == "table" and payload.action then
			action = payload.action
			index = payload.index
			local args = payload.args or {}
			releasePoint, releaseDir, releaseTarget = args[1], args[2], args[3]
		else
			action = payload
		end

		if not action then
			return
		end

		local character = player and player.Character
		if not character then
			return
		end

		if action == AbilityEventDefs.ClientAction.Cast then
			AbilityServerAPI.CastAbility(character, index, releasePoint, releaseDir, releaseTarget)
		elseif action == AbilityEventDefs.ClientAction.BreakCast then
			AbilityServerAPI.StopAbility(character, index)
		elseif action == AbilityEventDefs.ClientAction.Accumulate then
			AbilityServerAPI.AccumulateAbility(character, index)
		elseif action == AbilityEventDefs.ClientAction.SwitchNext then
			-- 切换子技能组下一个成员（组反查失败=该槽位无子技能组，安全忽略）
			AbilityServerAPI.SwitchNextAbility(character, index)
		end
	end)
end

-- 模块加载即注册（服务端上下文；幂等防重复）

local RunService = game:GetService("RunService")
if RunService:IsServer() then
	AbilityServerAPI.RegisterEvents()
end

return AbilityServerAPI

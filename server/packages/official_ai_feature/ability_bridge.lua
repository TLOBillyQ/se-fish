--生物AI包 - server端技能交互桥接（包内模块）
--AbilityBridge：技能槽位反查、带蓄力的技能释放与反应行为分发；
--依赖技能包服务端门面 server.packages.ability_system.api。

local Task = game:GetService("Task")

local abilitySystem = require("server.packages.ability_system.api")

local Configs = require("common.packages.official_ai_feature.configs")
local utils = require("common.packages.official_ai_feature.utils")

local AbilityBridge = {}

---按技能预设 Key 反查单位身上已有技能的槽位号。
---技能包未提供按预设查技能的接口，这里遍历全部技能、比对 AbilityPresetKey 自行反查；
---GetAbilities 只返回有效槽位区间内的技能，已天然过滤回收槽位。
---@param unit Unit 目标单位
---@param abilityKey String 技能预设 Key
---@return Int? 命中的槽位号；未命中返回 nil
function AbilityBridge.findSlotByPrefab(unit, abilityKey)
	if abilityKey == nil or abilityKey == "" then
		return nil
	end
	if abilitySystem.GetAbilities == nil then
		return nil
	end
	local abilities = abilitySystem.GetAbilities(unit)
	if type(abilities) ~= "table" then
		return nil
	end
	for _, abilityScript in ipairs(abilities) do
		if
			abilityScript ~= nil
			and abilityScript.GetAttribute ~= nil
			and abilityScript:GetAttribute("AbilityPresetKey") == abilityKey
		then
			return abilityScript:GetAttribute("Index")
		end
	end
	return nil
end

---按槽位释放技能：可带目标或方向；蓄力时间大于 0 时先等待再释放
---@param unit Unit 目标单位
---@param slot Int? 技能槽位
---@param target Unit? 释放目标
---@param direction Vector3? 释放方向
---@param chargeTime Float? 蓄力时间（秒）
function AbilityBridge.castAtSlot(unit, slot, target, direction, chargeTime)
	if abilitySystem.CastAbility == nil or slot == nil then
		return
	end
	local releasePoint = nil
	local releaseDirection = nil
	local releaseTarget = nil
	if target ~= nil and utils.isValidUnit(target) then
		releasePoint = target:GetPosition()
		releaseTarget = target.UnitId
		releaseDirection = utils.normalized(releasePoint - unit:GetPosition())
	elseif direction ~= nil then
		releasePoint = unit:GetPosition() + direction
		releaseDirection = utils.normalized(direction)
	end
	if chargeTime ~= nil and chargeTime > 0 then
		Task:Spawn(function()
			Task:Wait(chargeTime)
			if not utils.isValidUnit(unit) then
				return
			end
			abilitySystem.CastAbility(unit, slot, releasePoint, releaseDirection, releaseTarget)
		end)
	else
		abilitySystem.CastAbility(unit, slot, releasePoint, releaseDirection, releaseTarget)
	end
end

---按技能预设释放技能：没有该技能时先添加再释放
---@param unit Unit 目标单位
---@param abilityKey String 技能预设 Key
---@param chargeTime Float? 蓄力时间（秒）
---@param target Unit? 释放目标
function AbilityBridge.castByKey(unit, abilityKey, chargeTime, target)
	if abilityKey == nil or abilityKey == "" then
		return
	end
	local slot = AbilityBridge.findSlotByPrefab(unit, abilityKey)
	if slot == nil then
		if abilitySystem.AddAbility == nil then
			return
		end
		local abilityScript = abilitySystem.AddAbility(unit, abilityKey)
		if abilityScript == nil then
			return
		end
		slot = abilityScript:GetAttribute("Index")
	end
	if slot ~= nil then
		AbilityBridge.castAtSlot(unit, slot, target, nil, chargeTime)
	end
end

---给单位添加技能并放到指定槽位（目标槽位被其他预设占用时不覆盖）
---@param unit Unit 目标单位
---@param abilityIndex Int 槽位号
---@param abilityId String 技能预设 Key
function AbilityBridge.addAbilityToSlot(unit, abilityIndex, abilityId)
	if abilitySystem.AddAbility == nil then
		return
	end
	abilitySystem.AddAbility(unit, abilityId, abilityIndex)
end

---执行反应行为：跳跃/滚动/飞扑/抓举/施放技能
---@param unit Unit 目标单位
---@param reactBehavior Int 反应行为编号（Configs.CMD_*）
---@param reactArg Int? 反应参数（施放技能时为技能槽位）
function AbilityBridge.doReact(unit, reactBehavior, reactArg)
	if not utils.isValidUnit(unit) then
		return
	end
	if reactBehavior == Configs.CMD_JUMP then
		unit.Controller:Jump()
	elseif reactBehavior == Configs.CMD_FLING then
		-- 预期错误：单位处于不能滚动的状态时无效
		pcall(function()
			unit.Controller:Fling()
		end)
	elseif reactBehavior == Configs.CMD_RUSH then
		-- 预期错误：单位处于不能飞扑的状态时无效
		pcall(function()
			unit.Controller:Rush()
		end)
	elseif reactBehavior == Configs.CMD_LIFT then
		-- 预期错误：单位处于不能抓举的状态时无效
		pcall(function()
			unit.Controller:Lift()
		end)
	elseif reactBehavior == Configs.CMD_ABILITY then
		-- reactArg 为技能槽位
		if abilitySystem.CastAbility ~= nil then
			abilitySystem.CastAbility(unit, reactArg)
		end
	end
end

return AbilityBridge

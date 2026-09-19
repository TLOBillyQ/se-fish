--技能系统 - server子技能插件
-- 技能装好后（AddAbility 完成）按预设配置自动建立子技能组：
--   读 SubAbilities（List<SubAbilityInfo>）与 SwitchMode/SwitchOrder/SwitchInterval/SwitchCooldown/RevertTime/SwitchRefresh，
--   用 World:CreateAsset 逐个创建子技能并休眠（Index=-1、不进管理器槽位），再交给 sub_ability.lua 的
--   SubAbilityHandler.create 建组（槽位共享 / 切换策略 / 回归计时 / 整组清理都在其中）。
-- 由 server/packages/ability_system/api.lua 的 AddAbility 完成后调用 OnAbilityReady。

local AbilityConstants = require("common.packages.ability_system.constants")
local AbilityRegistry = require("common.packages.ability_system.registry")
local SubAbilityHandler = require("server.packages.ability_system.sub_ability")

local SubAbilityPlugin = {}

-- 配置数值 → 作者版字符串枚举（constants.SwitchMode / constants.SwitchOrder）
local SWITCH_MODE = {
	[1] = AbilityConstants.SwitchMode.AfterCast,
	[2] = AbilityConstants.SwitchMode.Timer,
	[3] = AbilityConstants.SwitchMode.Manual,
}

local SWITCH_ORDER = {
	[0] = AbilityConstants.SwitchOrder.Sequential,
	[1] = AbilityConstants.SwitchOrder.Shuffle,
	[2] = AbilityConstants.SwitchOrder.Random,
}

-- 读子技能列表（元素形状 { AssetId = "..." }；兼容纯字符串）
local function _readSubAbilityIds(script)
	local list = script:GetAttribute("SubAbilities")
	local ids = {}
	if type(list) ~= "table" then
		return ids
	end
	for _, entry in ipairs(list) do
		local asset_id = type(entry) == "table" and entry.AssetId or entry
		if type(asset_id) == "string" and asset_id ~= "" then
			ids[#ids + 1] = asset_id
		end
	end
	return ids
end

-- 创建单个子技能脚本单位：休眠（Index=-1）、归属同步、禁止嵌套建组
local function _createChildScript(manager, asset_id, owner_id)
	local assets = game:GetService("World"):CreateAsset(asset_id)
	local child = assets and assets[1]
	if not child then
		print("[SubAbilityPlugin] 子技能创建失败: " .. tostring(asset_id))
		return nil
	end
	child:SetAttribute("AbilityPresetKey", asset_id)
	child:SetAttribute("Index", AbilityConstants.SLOT_INDEX_UNASSIGNED)
	child:SetAttribute("OwnerId", owner_id or "")
	-- 防御：子技能不再建组（避免递归）
	child:SetAttribute("SubAbilities", {})
	child:SetAttribute("SwitchMode", 0)
	AbilityRegistry.addTag(child, AbilityConstants.Tag.AbilityUnit)
	child.Parent = manager
	return child
end

-- 等父/子技能脚本 Attach 完成（handler 注册）再建组；有界重试
local function _waitHandlers(abilityScript, child_scripts)
	local Task = game:GetService("Task")
	local function allReady()
		if not AbilityRegistry.getAbilityHandler(abilityScript) then
			return false
		end
		for _, child in ipairs(child_scripts) do
			if not AbilityRegistry.getAbilityHandler(child) then
				return false
			end
		end
		return true
	end
	local retries = 0
	while not allReady() and retries < 100 do
		Task:Wait(0.05)
		retries = retries + 1
	end
	return allReady()
end

-- 技能装好后调用：配置了子技能则自动建组（幂等）
---@param abilityScript Script 已加入管理器的技能脚本单位
function SubAbilityPlugin.OnAbilityReady(abilityScript)
	if not abilityScript then
		return
	end
	local ids = _readSubAbilityIds(abilityScript)
	if #ids == 0 then
		return
	end
	local switch_mode = SWITCH_MODE[abilityScript:GetAttribute("SwitchMode") or 0]
	if not switch_mode then
		return
	end
	if AbilityRegistry.findGroup(abilityScript) then
		return
	end
	local manager = abilityScript.Parent
	if not manager then
		return
	end

	local owner_id = abilityScript:GetAttribute("OwnerId")
	game:GetService("Task"):Spawn(function()
		local child_scripts = {}
		for _, asset_id in ipairs(ids) do
			local child = _createChildScript(manager, asset_id, owner_id)
			if child then
				child_scripts[#child_scripts + 1] = child
			end
		end
		if #child_scripts == 0 then
			return
		end
		if not _waitHandlers(abilityScript, child_scripts) then
			print("[SubAbilityPlugin] 子技能组未就绪，跳过: " .. tostring(abilityScript))
			return
		end

		local parent_handler = AbilityRegistry.getAbilityHandler(abilityScript)
		local child_handlers = {}
		for _, child in ipairs(child_scripts) do
			local child_handler = AbilityRegistry.getAbilityHandler(child)
			if child_handler then
				child_handlers[#child_handlers + 1] = child_handler
			end
		end
		if not parent_handler or #child_handlers == 0 then
			return
		end

		local switch_order = SWITCH_ORDER[abilityScript:GetAttribute("SwitchOrder") or 0]
			or AbilityConstants.SwitchOrder.Sequential
		local switch_interval = abilityScript:GetAttribute("SwitchInterval") or 3.0
		local options = {
			slotIndex = abilityScript:GetAttribute("Index"),
			switchCooldown = abilityScript:GetAttribute("SwitchCooldown") or 0,
			revertTime = abilityScript:GetAttribute("RevertTime") or 0,
			switchRefresh = abilityScript:GetAttribute("SwitchRefresh") ~= false,
		}
		SubAbilityHandler.create(
			parent_handler,
			abilityScript,
			child_handlers,
			switch_mode,
			switch_order,
			switch_interval,
			options
		)
	end)
end

return SubAbilityPlugin

--技能系统 - client技能实例绑定
-- 监听关键 @type 属性变化，通过 AbilityUIHooks 把 reactive 事件暴露给 UI。
-- 由 manager_local_script.bindAbility() 对每个技能 ScriptUnit 调用 attach()。

local AbilityConstants = require("common.packages.ability_system.constants")
local AbilityRegistry = require("common.packages.ability_system.registry")
local AbilityUIHooks = require("common.packages.ability_system.ui_hooks")

local M = {}

-- 幂等：同一 abilityScript 只绑定一次
local _attachedSet = {}

-- attach：把 7 个 reactive 属性绑定挂到技能 ScriptUnit 上
---@param abilityScript ScriptUnit 技能实例（manager 的子节点）
function M.attach(abilityScript)
	if not abilityScript then
		return false
	end
	local key = tostring(abilityScript)
	if _attachedSet[key] then
		return true
	end

	local RunService = game:GetService("RunService")
	if not RunService:IsClient() then
		return false
	end

	AbilityRegistry.addTag(abilityScript, AbilityConstants.Tag.AbilityUnit)

	local function bindReactiveSignals()
		_attachedSet[key] = true

		-- 1. InCD 变化 → CD 进度条 + Icon 灰显
		abilityScript:GetAttributeChangedSignal("InCD"):Connect(function(newVal)
			local cdFinishTime = abilityScript:GetAttribute("CdFinishTime")
			AbilityUIHooks.onInCDChange(abilityScript, newVal, cdFinishTime)
		end)

		-- 2. InCast 变化 → 施法指示器
		abilityScript:GetAttributeChangedSignal("InCast"):Connect(function(newVal)
			local castStartTime = abilityScript:GetAttribute("CastStartTime")
			AbilityUIHooks.onInCastChange(abilityScript, newVal, castStartTime)
		end)

		-- 3. ChargeCount 变化 → 充能 icon
		abilityScript:GetAttributeChangedSignal("ChargeCount"):Connect(function(newVal)
			local maxChargeCount = abilityScript:GetAttribute("MaxChargeCount")
			AbilityUIHooks.onChargeCountChange(abilityScript, newVal, maxChargeCount)
		end)

		-- 4. PointerType 变化 → 重建 Pointer 实例
		abilityScript:GetAttributeChangedSignal("PointerType"):Connect(function(newVal)
			AbilityUIHooks.onPointerTypeChange(abilityScript, newVal)
		end)

		-- 5. ReleaseType 变化 → 释放策略 UI 提示
		abilityScript:GetAttributeChangedSignal("ReleaseType"):Connect(function(newVal)
			AbilityUIHooks.onReleaseTypeChange(abilityScript, newVal)
		end)

		-- 6. Index 变化 → EUI Slot 节点位置
		abilityScript:GetAttributeChangedSignal("Index"):Connect(function(newVal)
			AbilityUIHooks.onIndexChange(abilityScript, newVal)
		end)

		-- 7. OwnerId 变化 → 是否激活本地 UI
		abilityScript:GetAttributeChangedSignal("OwnerId"):Connect(function(newVal)
			AbilityUIHooks.onOwnerIdChange(abilityScript, newVal)
		end)

		-- 8. AccumulateStartTime 变化 → 蓄力进度条
		-- 服务端进蓄力写服务器时间戳、结束蓄力清零；0/nil 即蓄力结束
		abilityScript:GetAttributeChangedSignal("AccumulateStartTime"):Connect(function(newVal)
			AbilityUIHooks.onAccumulateChange(abilityScript, newVal)
		end)
	end

	-- BindParented / Posted 双保险：父节点赋值后触发一次
	local bound = false
	local function bindOnce()
		if bound then
			return
		end
		bound = true
		bindReactiveSignals()
	end

	if abilityScript.BindParented then
		abilityScript.BindParented:Connect(function()
			bindOnce()
		end)
	end

	if abilityScript.Posted then
		abilityScript.Posted:Connect(function()
			bindOnce()
		end)
	end

	-- 已 Posted / 无 Posted 信号时立即绑定
	bindOnce()

	-- 销毁清理
	abilityScript.Destroying:Connect(function()
		AbilityRegistry.unregisterAbility(abilityScript)
		AbilityRegistry.clearTags(abilityScript)
		_attachedSet[key] = nil
	end)

	return true
end

-- 兼容路径：若脚本被作为 LocalScript 挂载（挂在技能下），自动 attach
if script and script.Parent then
	M.attach(script.Parent)
end

return M

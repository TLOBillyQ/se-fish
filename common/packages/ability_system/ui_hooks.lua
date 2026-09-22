--技能系统 - commonUI钩子
-- UIController 后续注入实际实现替换下方 no-op 函数即可

local AbilityUIHooks = {}

-- 属性变化 hook 入口（AbilityItem LocalScript 在 GetAttributeChangedSignal callback 中调用）

-- 技能进入 / 退出 CD
function AbilityUIHooks.onInCDChange(abilityScript, isInCD, cdFinishTime)
	-- UIController 注入：刷新技能 Icon 灰显 + 显示/隐藏 CD 进度条
	-- 默认 no-op
end

-- 技能施法开始 / 结束
function AbilityUIHooks.onInCastChange(abilityScript, isInCast, castStartTime)
	-- UIController 注入：显示施法进度条 + 角色施法指示器
end

-- 充能数变化
function AbilityUIHooks.onChargeCountChange(abilityScript, chargeCount, maxChargeCount)
	-- UIController 注入：刷新充能 icon 数量
end

-- 蓄力开始 / 结束：startTime 为服务端 AccumulateStartTime（0/nil = 蓄力结束）
function AbilityUIHooks.onAccumulateChange(abilityScript, startTime)
	-- UIController 注入：驱动蓄力进度节点（AccumulateNode）
end

-- Pointer 类型变化
function AbilityUIHooks.onPointerTypeChange(abilityScript, pointerType)
	-- UIController 注入：重建对应 Pointer 实例并显示
end

-- Release Strategy 类型变化
function AbilityUIHooks.onReleaseTypeChange(abilityScript, releaseType)
	-- UIController 注入：切换释放策略 UI 提示
end

-- 槽位索引变化
function AbilityUIHooks.onIndexChange(abilityScript, newIndex)
	-- UIController 注入：把 AbilitySlot 节点重新挂载到对应格子
end

-- 拥有者 ID 变化
function AbilityUIHooks.onOwnerIdChange(abilityScript, ownerId)
	-- UIController 注入：判断是否激活本地 UI（ownerId == LocalPlayer name）
end

-- 管理器级 hook

-- 一个新技能加入管理器
function AbilityUIHooks.onAbilityAdded(managerScript, abilityScript, slotIndex)
	-- UIManager 注入：绑定新技能的槽位 UI 节点
end

-- 管理器移除一个技能
function AbilityUIHooks.onAbilityRemoved(managerScript, slotIndex)
	-- UIController 注入：释放对应 EUI Slot 节点
end

-- 子技能组激活切换
function AbilityUIHooks.onSwitchNext(managerScript, parentSlotIndex, newActiveIndex)
	-- UIController 注入：UI 上突出新激活的子能力
end

-- 显式注入接口
-- Controller.lua 加载时调用一次替换 hook 实现
-- 用法：AbilityUIHooks.setUIHooks({ onInCDChange = function() ... end, ... })

function AbilityUIHooks.setUIHooks(hooksTable)
	if type(hooksTable) ~= "table" then
		error("SetUIHooks: hooksTable must be a table")
	end
	for k, v in pairs(hooksTable) do
		if
			type(v) == "function"
			and AbilityUIHooks[k]
			and type(AbilityUIHooks[k]) == "function"
		then
			AbilityUIHooks[k] = v
		end
	end
end

return AbilityUIHooks

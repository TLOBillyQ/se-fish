--技能系统 - client技能栏UI管理器
--按节点 custom_kv 定位编辑器摆好的 EUI 节点并驱动 Controller：
--   AbilitySlot / AbilityAccumulateNode 带 Index=<槽位号>，取消区 AbilityCancelArea 为单例。
--   节点暂时缺失时有界重试（最多 2 秒，每 0.1 秒一次）。

local Controller = require("client.packages.ability_system.ui.Controller")
local AbilitySlot = require("client.packages.ability_system.ui.nodes.AbilitySlot")
local AccumulateNode = require("client.packages.ability_system.ui.nodes.AccumulateNode")
local CancelArea = require("client.packages.ability_system.ui.nodes.CancelArea")
local EuiAdapter = require("client.packages.ability_system.ui.eui_adapter")
local AbilityUIHooks = require("common.packages.ability_system.ui_hooks")
local AbilityConstants = require("common.packages.ability_system.constants")

---技能栏 UI 管理器：按节点 custom_kv 定位编辑器摆放的 EUI 节点并驱动 Controller。
---@class UIManager
---@field unit Unit? 本地玩家角色（或其下的 AbilityManager）
---@field manager Script? 技能管理器脚本单位
---@field controllers table<integer, Controller> 槽位索引 → 控制器
local UIManager = {}
UIManager.__index = UIManager

local _instance = nil
local _cancelNodes = {}
local _accumulateNode = nil -- 蓄力进度共享节点缓存（单例，不与槽位绑定）
local _hooksInjected = false
local _pendingRetries = {} -- {[abilityIndex] = { ability=abilityScript, remaining=N }}

-- 单例 / 生命周期

---@param unit Unit 本地玩家角色（或其下的 AbilityManager）
function UIManager.new(unit)
	local self = setmetatable({}, UIManager)
	self.unit = unit
	self.manager = nil
	self.controllers = {} -- {[abilityIndex] = controller}
	_instance = self
	-- 让 Controller 能反向访问 UIManager（取消区/拖拽施法需要）
	Controller.SetUIManager(self)
	UIManager.InjectHooks()
	return self
end

function UIManager.GetInstance()
	return _instance
end

-- 注入 UI hooks：把技能属性/事件变化桥接到本 UI 管理器

function UIManager.InjectHooks()
	if _hooksInjected then
		return
	end
	_hooksInjected = true

	AbilityUIHooks.setUIHooks({
		-- 技能进入/退出 CD
		onInCDChange = function(abilityScript, isInCD, cdFinishTime)
			local um = UIManager.GetInstance()
			if not um then
				return
			end
			local controller = um:_FindControllerByAbility(abilityScript)
			if controller then
				controller:OnInCDChange(isInCD, cdFinishTime)
			end
		end,

		-- 充能数变化
		onChargeCountChange = function(abilityScript, chargeCount, maxChargeCount)
			local um = UIManager.GetInstance()
			if not um then
				return
			end
			local controller = um:_FindControllerByAbility(abilityScript)
			if controller then
				controller:OnChargeCountChange(chargeCount, maxChargeCount)
			end
		end,

		-- 蓄力开始/结束 → 蓄力进度节点（全局共享单例，谁蓄力谁驱动；0/nil 为结束）
		onAccumulateChange = function(abilityScript, startTime)
			local um = UIManager.GetInstance()
			if not um then
				return
			end
			if startTime and startTime > 0 then
				um:ShowAccumulate(abilityScript, startTime)
			else
				um:HideAccumulate(abilityScript)
			end
		end,

		-- 指示器类型变化
		onPointerTypeChange = function(abilityScript, pointerType)
			local um = UIManager.GetInstance()
			if not um then
				return
			end
			local controller = um:_FindControllerByAbility(abilityScript)
			if controller then
				controller:OnPointerTypeChange(pointerType)
			end
		end,

		-- 释放策略变化
		onReleaseTypeChange = function(abilityScript, releaseType)
			local um = UIManager.GetInstance()
			if not um then
				return
			end
			local controller = um:_FindControllerByAbility(abilityScript)
			if controller then
				controller:OnReleaseTypeChange(releaseType)
			end
		end,

		-- 槽位变化：解绑旧槽位 + 绑定新槽位
		onIndexChange = function(abilityScript, newIndex)
			local um = UIManager.GetInstance()
			if not um then
				return
			end
			-- 先找旧槽位解绑
			for index, controller in pairs(um.controllers) do
				if controller._ability == abilityScript and index ~= newIndex then
					um:UnBindAbility(index)
				end
			end
			if newIndex then
				um:BindAbility(abilityScript)
			end
		end,

		-- 拥有者变化：判定是否本地玩家（manager 的 OwnerId 是玩家名/空串）
		onOwnerIdChange = function(abilityScript, ownerId)
			-- 本地判定走 onAbilityAdded 的归属检查
		end,

		-- 新技能加入 → 绑定 UI
		onAbilityAdded = function(managerScript, abilityScript, slotIndex)
			local um = UIManager.GetInstance()
			if not um then
				um = UIManager.new(managerScript)
			end
			-- 归属检查（双保险）：仅本地玩家的 manager 参与绑定。
			-- OwnerId 为空串 = 服务端归属尚未解析，放行；非本地玩家名 → 拒绑。
			local ownerId = managerScript.GetAttribute and managerScript:GetAttribute("OwnerId")
				or ""
			if ownerId ~= "" then
				local player = game:GetService("Players").LocalPlayer
				local okName, localName = pcall(function()
					return player and player:GetName()
				end)
				if okName and localName and ownerId ~= localName then
					return
				end
			end
			um:SetManager(managerScript)
			um:BindAbility(abilityScript)
		end,

		-- 技能移除 → 解绑 UI
		onAbilityRemoved = function(managerScript, slotIndex)
			local um = UIManager.GetInstance()
			if um then
				um:UnBindAbility(slotIndex)
			end
		end,

		-- 子技能组切换
		onSwitchNext = function(managerScript, parentSlotIndex, newActiveIndex) end,

		-- 施法开始/结束（可用于施法条）
		onInCastChange = function(abilityScript, isInCast, castStartTime) end,
	})
end

-- 节点查找

-- 按自定义属性定位槽位节点：UIType=AbilityConstants.UIType.AbilitySlot 且 Index==abilityIndex
function UIManager:_FindSlotNode(abilityIndex)
	local root = EuiAdapter.GetRootNode()
	if not root then
		return nil
	end
	local descendants = EuiAdapter.GetDescendants(root)
	for _, node in ipairs(descendants) do
		if
			node.GetAttribute
			and node:GetAttribute("UIType") == AbilityConstants.UIType.AbilitySlot
			and node:GetAttribute("Index") == abilityIndex
		then
			return node
		end
	end
	return nil
end

-- 蓄力进度共享节点（全局单例，不与槽位绑定）：首次调用时查找并 Attach
-- 按 UIType=AbilityConstants.UIType.AccumulateNode 定位，无需 Index
function UIManager:_EnsureAccumulateNode()
	if _accumulateNode then
		return _accumulateNode
	end
	local root = EuiAdapter.GetRootNode()
	if not root then
		return nil
	end
	local descendants = EuiAdapter.GetDescendants(root)
	for _, node in ipairs(descendants) do
		if
			node.GetAttribute
			and node:GetAttribute("UIType") == AbilityConstants.UIType.AccumulateNode
		then
			_accumulateNode = AccumulateNode.Attach(node)
			return _accumulateNode
		end
	end
	return nil
end

-- 取消区节点集合（首次调用时查找）
-- 按 UIType=AbilityConstants.UIType.CancelArea 定位（单例节点无 Index；支持多节点摆放）
function UIManager:_EnsureCancelNodes()
	if #_cancelNodes > 0 then
		return
	end
	local root = EuiAdapter.GetRootNode()
	if not root then
		return
	end
	local descendants = EuiAdapter.GetDescendants(root)
	for _, node in ipairs(descendants) do
		if
			node.GetAttribute
			and node:GetAttribute("UIType") == AbilityConstants.UIType.CancelArea
		then
			CancelArea.Attach(node)
			table.insert(_cancelNodes, node)
		end
	end
end

-- 绑定 / 解绑

function UIManager:SetManager(managerScript)
	self.manager = managerScript
	Controller.SetUIManager(self)
end

function UIManager:BindAbility(abilityScript)
	if not abilityScript then
		return
	end
	local index = abilityScript:GetAttribute("Index")
	-- 未入槽哨兵（< SLOT_BASE）不参与绑定，也不进入重试循环
	if not index or index < AbilityConstants.SLOT_BASE then
		return
	end
	if self.controllers[index] ~= nil then
		local old = self.controllers[index]
		-- 仅复用"同技能且 manager 已就绪并一致"的旧 controller；绑定可能先于
		-- onAbilityAdded 的 SetManager 触发（Index 变化钩子），此时须解绑重建。
		if old._ability == abilityScript and self.manager ~= nil and old._manager == self.manager then
			return
		end
		self:UnBindAbility(index)
	end

	local node = self:_FindSlotNode(index)
	if not node then
		-- 启动有界延迟重试（仅当尚未为该槽位排队时）
		self:_ScheduleRetry(abilityScript, index)
		return
	end

	-- 绑定成功，取消任何待处理的重试
	self:_CancelRetry(index)

	AbilitySlot.Attach(node)

local delayTimer = nil
    delayTimer = game:GetService("Task"):Delay(0.033, function()
        local presetLink = abilityScript:FindFirstChildWhichIsA("PresetLink")
        local icon = (presetLink and presetLink:GetAttribute("PrefabIcon")) or abilityScript:GetAttribute("Icon")
        EuiAdapter.SetImage(node, icon or nil)
        game:GetService("Task"):Cancel(delayTimer)
    end)

	-- 显示主节点并开启触摸
	EuiAdapter.SetVisible(node, true)
	EuiAdapter.SetTouchEnabled(node, true)

	-- 隐藏功能性子节点（CD/充能相关，CD 中/充能中由事件驱动再显示）
	local nodeState = AbilitySlot.GetState(node)
	if nodeState.ProgressTimer then
		EuiAdapter.SetVisible(nodeState.ProgressTimer, false)
	end
	if nodeState.CdText then
		EuiAdapter.SetVisible(nodeState.CdText, false)
	end
	if nodeState.CdMask then
		EuiAdapter.SetVisible(nodeState.CdMask, false)
	end
	if nodeState.ChargeBackground then
		EuiAdapter.SetVisible(nodeState.ChargeBackground, false)
	end
	if nodeState.ChargeProgressTimer then
		EuiAdapter.SetVisible(nodeState.ChargeProgressTimer, false)
	end
	if nodeState.ChargeCount then
		EuiAdapter.SetVisible(nodeState.ChargeCount, false)
	end

	-- 初始化充能数据
	AbilitySlot.InitChargeData(node, {
		IsChargeConsuming = abilityScript:GetAttribute("IsChargeConsuming"),
		ChargeCount = abilityScript:GetAttribute("ChargeCount"),
		MaxChargeCount = abilityScript:GetAttribute("MaxChargeCount"),
		ChargeInterval = abilityScript:GetAttribute("ChargeInterval"),
		ChargeAmount = abilityScript:GetAttribute("ChargeAmount"),
		ChargeType = abilityScript:GetAttribute("ChargeType"),
	})

	-- manager 兜底：技能 ScriptUnit 的 Parent 即 AbilityManager；
	-- self.manager 未就绪时用它建 Controller（不写回 self.manager）。
	local mgr = self.manager or abilityScript.Parent
	local controller = Controller.new(abilityScript, node, mgr)
	self.controllers[index] = controller

	-- 初始 CD 状态（子技能切换后恢复 CD UI 的关键）
	if abilityScript:GetAttribute("InCD") then
		local cdFinishTime = abilityScript:GetAttribute("CdFinishTime") or 0
		local leftCD = cdFinishTime - game:GetService("World"):GetServerTime()
		if leftCD > 0 then
			controller:OnInCDChange(true, cdFinishTime)
		end
	end

	-- 蓄力兜底：绑定晚于蓄力开始时，按当前 AccumulateStartTime 直接显示进度
	local accStart = abilityScript:GetAttribute("AccumulateStartTime")
	if accStart and accStart > 0 then
		self:ShowAccumulate(abilityScript, accStart)
	end
end

function UIManager:UnBindAbility(abilityIndex)
	self:_CancelRetry(abilityIndex)
	local controller = self.controllers[abilityIndex]
	if not controller then
		return
	end
	controller:Destroy()
	self.controllers[abilityIndex] = nil
end

-- 重置全部绑定（角色重生/切换场景）：旧 controller 指向已销毁的单位，不调 controller:Destroy，
-- 仅清掉节点侧的本地状态（Lua 定时器等），防止残留空转。
function UIManager:ResetBindings()
	for index, controller in pairs(self.controllers) do
		self:_CancelRetry(index)
		if controller and controller._node then
			AbilitySlot.Cleanup(controller._node)
		end
		self.controllers[index] = nil
	end
	-- 共享蓄力节点复位（旧技能已销毁，驱动者作废）
	self._accumulateOwner = nil
	if _accumulateNode then
		AccumulateNode.Cleanup(_accumulateNode)
		_accumulateNode = nil
	end
end

-- 蓄力进度（全局共享单例节点，当前蓄力技能驱动）

-- 显示蓄力进度：记录驱动者 + 起表（后触发的蓄力直接覆盖显示）
function UIManager:ShowAccumulate(abilityScript, startTime)
	local node = self:_EnsureAccumulateNode()
	if not node then
		return
	end
	self._accumulateOwner = abilityScript
	local maxTime = 1.0
	if abilityScript and abilityScript.GetAttribute then
		maxTime = abilityScript:GetAttribute("MaxAccumulateTime") or 1.0
	end
	AccumulateNode.StartAccumulate(node, startTime, maxTime)
end

-- 隐藏蓄力进度：仅当前驱动者的结束事件生效，
-- 防止前一技能的"结束"事件误关掉后一技能已开始的蓄力显示
function UIManager:HideAccumulate(abilityScript)
	if self._accumulateOwner and self._accumulateOwner ~= abilityScript then
		return
	end
	self._accumulateOwner = nil
	if _accumulateNode then
		AccumulateNode.StopAccumulate(_accumulateNode)
	end
end

-- 按 abilityScript 反查 controller
function UIManager:_FindControllerByAbility(abilityScript)
	for _, controller in pairs(self.controllers) do
		if controller._ability == abilityScript then
			return controller
		end
	end
	return nil
end

-- 延迟重试（有界）

local _RETRY_INTERVAL = 0.1 -- 秒
local _RETRY_MAX_ATTEMPTS = 20 -- 最多 2 秒

function UIManager:_ScheduleRetry(abilityScript, index)
	if _pendingRetries[index] then
		return
	end
	_pendingRetries[index] = { ability = abilityScript, remaining = _RETRY_MAX_ATTEMPTS }
	self:_RunRetryLoop(index)
end

function UIManager:_CancelRetry(index)
	_pendingRetries[index] = nil
end

function UIManager:_RunRetryLoop(index)
	local Task = game:GetService("Task")
	Task:Delay(_RETRY_INTERVAL, function()
		local entry = _pendingRetries[index]
		if not entry then
			return
		end -- 已取消（解绑/已绑定）

		-- 技能已不存在或已被替换
		local ability = entry.ability
		local currentIndex = ability and ability.GetAttribute and ability:GetAttribute("Index")
		if currentIndex ~= index then
			_pendingRetries[index] = nil
			return
		end

		-- 已被其他路径绑定
		if self.controllers[index] ~= nil then
			_pendingRetries[index] = nil
			return
		end

		entry.remaining = entry.remaining - 1
		if entry.remaining <= 0 then
			_pendingRetries[index] = nil
			return
		end

		-- 尝试绑定（BindAbility 内部会 _CancelRetry 如果成功）
		self:BindAbility(ability)

		-- 如果仍在待处理中，继续下一轮
		if _pendingRetries[index] then
			self:_RunRetryLoop(index)
		end
	end)
end

-- 取消区

function UIManager:SetCancelAreaVisible(visible)
	self:_EnsureCancelNodes()
	for _, node in ipairs(_cancelNodes) do
		EuiAdapter.SetVisible(node, visible)
	end
end

function UIManager:IsInCancelArea(position)
	if #_cancelNodes == 0 then
		return false
	end
	local result = false
	for _, node in ipairs(_cancelNodes) do
		if EuiAdapter.HitTest(node, position) then
			result = true
			CancelArea.SetCancelState(node, true)
		else
			CancelArea.SetCancelState(node, false)
		end
	end
	return result
end

return UIManager

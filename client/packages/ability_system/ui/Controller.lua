--技能系统 - client技能槽位UI控制器
--一个技能对应一个 Controller，管理：
--   * 节点触摸信号 → 释放策略
--   * 技能属性变化 → CD/充能 UI；施法请求 → AbilityClientAPI.RequestCast/RequestStop

local AbilityConstants = require("common.packages.ability_system.constants")
local AbilityClientAPI = require("client.packages.ability_system.api")
local EuiAdapter = require("client.packages.ability_system.ui.eui_adapter")

-- 指示器类
local AbilityPointer = require("client.packages.ability_system.pointer.AbilityPointer")
local CirclePointer = require("client.packages.ability_system.pointer.CirclePointer")
local RectanglePointer = require("client.packages.ability_system.pointer.RectanglePointer")
local SectorPointer = require("client.packages.ability_system.pointer.SectorPointer")
local ParabolaPointer = require("client.packages.ability_system.pointer.ParabolaPointer")

-- 释放策略类
local ReleaseStrategy = require("client.packages.ability_system.strategy.ReleaseStrategy")
local HoldStrategy = require("client.packages.ability_system.strategy.HoldStrategy")
local PressStrategy = require("client.packages.ability_system.strategy.PressStrategy")
local TwoStageStrategy = require("client.packages.ability_system.strategy.TwoStageStrategy")

---技能槽位 UI 控制器：一个技能对应一个 Controller，管理触摸→策略、属性→UI、施法请求。
---@class Controller
---@field _ability Script? 技能脚本单位
---@field _node any? AbilitySlot EUI 节点
---@field _manager Script? 技能管理器脚本单位
---@field abilityPointer any? 当前施法指示器实例
---@field releaseParam table 释放参数（strategy 间共享）
---@field _listenerList Connection[]? 节点信号连接句柄
---@field strategy any? 当前释放策略实例
local Controller = {}
Controller.__index = Controller

-- UIManager 单例引用（供 Controller 与 UIManager 互相访问）
local _uiManagerRef = nil
local _setUIManager
local _getUIManager

-- 注册默认指示器类型（数值对齐官方 enums.lua）
local Registry = require("common.packages.ability_system.registry")
Registry.register("PointerType", AbilityConstants.PointerType.None, AbilityPointer)
Registry.register("PointerType", AbilityConstants.PointerType.Circle, CirclePointer)
Registry.register("PointerType", AbilityConstants.PointerType.Sector, SectorPointer)
Registry.register("PointerType", AbilityConstants.PointerType.Rectangle, RectanglePointer)
Registry.register("PointerType", AbilityConstants.PointerType.Parabola, ParabolaPointer)

-- 注册默认释放策略（数值/名称对齐官方 enums.lua，0 即默认松开施放）
Registry.register("ReleaseStrategy", AbilityConstants.ReleaseType.Release, ReleaseStrategy)
Registry.register("ReleaseStrategy", AbilityConstants.ReleaseType.Hold, HoldStrategy)
Registry.register("ReleaseStrategy", AbilityConstants.ReleaseType.TwoStage, TwoStageStrategy)
Registry.register("ReleaseStrategy", AbilityConstants.ReleaseType.Press, PressStrategy)

-- 构造 / 销毁

---@param abilityScript ScriptUnit 技能实例（manager 的子节点）
---@param node EUI AbilitySlot 节点（已 Attach 行为）
---@param manager ScriptUnit AbilityManager（施法请求需要）
function Controller.new(abilityScript, node, manager)
	local obj = {}
	setmetatable(obj, Controller)

	obj._ability = abilityScript
	obj._node = node
	obj._manager = manager
	obj.abilityPointer = nil
	obj.releaseParam = {}
	obj._listenerList = {}

	-- 按技能 ReleaseType 创建释放策略
	local releaseType = abilityScript and abilityScript:GetAttribute("ReleaseType")
	obj.strategy = obj:_createStrategy(releaseType)

	if node then
		local function bind(signal, func)
			if signal and type(signal.Connect) == "function" then
				table.insert(obj._listenerList, signal:Connect(func))
			end
		end

		-- 节点触摸信号 → 策略
		bind(node.OnTouchBegan, function(...)
			obj:_onTouchBegan(...)
		end)
		bind(node.OnTouchMoved, function(...)
			obj:_onTouchMoved(...)
		end)
		bind(node.OnTouchEnded, function(...)
			obj:_onTouchEnded(...)
		end)
		-- 兜底：OnClicked（EUI 点击信号）→ 直接施法
		bind(node.OnClicked, function(...)
			obj:_onClicked(...)
		end)
	end

	return obj
end

function Controller:Destroy()
	if self.strategy and self.strategy.Destroy then
		self.strategy:Destroy()
	end
	self.strategy = nil

	if self.abilityPointer and self.abilityPointer.Destroy then
		self.abilityPointer:Destroy()
	end
	self.abilityPointer = nil

	if self._node then
		local AbilitySlot = require("client.packages.ability_system.ui.nodes.AbilitySlot")
		AbilitySlot.Cleanup(self._node)
		EuiAdapter.SetVisible(self._node, false)
	end

	if self._listenerList then
		for _, l in ipairs(self._listenerList) do
			if l and l.Disconnect then
				l:Disconnect()
			end
		end
		self._listenerList = nil
	end

	self._ability = nil
end

-- 触摸 → 释放交互（strategy 存在时由 strategy 接管）

-- 点击兜底：EUI OnClicked 信号 → 直接施法
function Controller:_onClicked(...)
	-- 触摸序列已处理本次点击，忽略 OnClicked
	if self._touchHandled then
		self._touchHandled = false
		return
	end
	if self.strategy and self.strategy.OnTouchEnd then
		-- 走策略的 OnTouchEnd（无触摸信息，用零向量）
		local eventData = {
			BeganPosition = Vector2.New(0, 0),
			MovedPosition = Vector2.New(0, 0),
			EndedPosition = Vector2.New(0, 0),
		}
		self.strategy:OnTouchEnd(eventData)
		return
	end
	self:_requestCast(nil, nil, nil)
end

function Controller:_onTouchBegan(eventData)
	self._touchHandled = false
	if self.strategy then
		self.strategy:OnTouchBegin(eventData)
		return
	end
	local AbilitySlot = require("client.packages.ability_system.ui.nodes.AbilitySlot")
	if self._node then
		AbilitySlot.ShowDragIndicator(self._node, eventData.BeganPosition)
	end
	self:SetReleaseParam("cancel", false)
	-- 创建指示器
	self:_createPointer()
	if self.abilityPointer then
		self.abilityPointer:Create(Vector2.New(0, 0))
	end
	local uiManager = _getUIManager()
	if uiManager then
		uiManager:SetCancelAreaVisible(true)
	end
end

function Controller:_onTouchMoved(eventData)
	if self.strategy then
		self.strategy:OnTouchMove(eventData)
		return
	end
	local AbilitySlot = require("client.packages.ability_system.ui.nodes.AbilitySlot")
	if self._node then
		AbilitySlot.UpdateDragIndicator(
			self._node,
			eventData.BeganPosition,
			eventData.MovedPosition
		)
	end
	if self.abilityPointer then
		local delta = eventData.MovedPosition - eventData.BeganPosition
		self.abilityPointer:Refresh(delta)
	end
	local uiManager = _getUIManager()
	if uiManager then
		if uiManager:IsInCancelArea(eventData.MovedPosition) then
			if self._node then
				AbilitySlot.SetCancelState(self._node, true)
			end
			self:SetReleaseParam("cancel", true)
		else
			if self._node then
				AbilitySlot.SetCancelState(self._node, false)
			end
			self:SetReleaseParam("cancel", false)
		end
	end
end

function Controller:_onTouchEnded(eventData)
	self._touchHandled = true
	if self.strategy then
		self.strategy:OnTouchEnd(eventData)
		return
	end
	local AbilitySlot = require("client.packages.ability_system.ui.nodes.AbilitySlot")
	if self._node then
		AbilitySlot.HideDragIndicator(self._node)
		AbilitySlot.SetCancelState(self._node, false)
	end
	if self.abilityPointer then
		self.abilityPointer:Clear()
		self.abilityPointer:Destroy()
		self.abilityPointer = nil
	end
	local uiManager = _getUIManager()
	local canceled = self:GetReleaseParam("cancel")
	if uiManager then
		uiManager:SetCancelAreaVisible(false)
	end
	if not canceled then
		self:_requestCast(nil, nil, nil)
	end
end

-- 施法请求

-- manager 兜底：技能 ScriptUnit 的 Parent 即 AbilityManager（绑定可能先于 manager 就绪）。
function Controller:_ensureManager()
	if not self._manager and self._ability then
		self._manager = self._ability.Parent
	end
	return self._manager
end

function Controller:_requestCast(point, dir, target)
	self:_ensureManager()
	if not self._manager or not self._ability then
		return
	end
	local index = self._ability:GetAttribute("Index")
	if not index then
		return
	end
	AbilityClientAPI.RequestCast(self._manager, index, point, dir, target)
end

function Controller:_requestStop()
	self:_ensureManager()
	if not self._manager or not self._ability then
		return
	end
	local index = self._ability:GetAttribute("Index")
	if not index then
		return
	end
	AbilityClientAPI.RequestStop(self._manager, index)
end

function Controller:_requestAccumulate()
	self:_ensureManager()
	if not self._manager or not self._ability then
		return
	end
	local index = self._ability:GetAttribute("Index")
	if not index then
		return
	end
	local api = require("client.packages.ability_system.api")
	if api.RequestAccumulate then
		api.RequestAccumulate(self._manager, index)
	end
end

-- 结束蓄力：映射到 RequestStop
function Controller:_requestStopAccumulate()
	self:_requestStop()
end

-- 获取 owner（角色 Unit）：manager 挂在角色下，manager.Parent 即角色
function Controller:GetOwner()
	if self._manager then
		return self._manager.Parent
	end
	if self._ability and self._ability.Parent then
		return self._ability.Parent.Parent
	end
	return nil
end

-- 释放参数（strategy 间共享）

function Controller:SetReleaseParam(key, value)
	if self.releaseParam[key] == value then
		return
	end
	self.releaseParam[key] = value
end

function Controller:GetReleaseParam(key)
	return self.releaseParam[key]
end

-- 属性 hook 入口（由 UIManager 调用）

-- 技能进入/退出 CD → 刷新 CD UI
function Controller:OnInCDChange(isInCD, cdFinishTime)
	if not self._node then
		return
	end
	local AbilitySlot = require("client.packages.ability_system.ui.nodes.AbilitySlot")
	if isInCD then
		local leftCD = 0
		if cdFinishTime and cdFinishTime > 0 then
			leftCD = cdFinishTime - game:GetService("World"):GetServerTime()
		end
		if leftCD <= 0 then
			leftCD = self._ability:GetAttribute("CdTime") or 1
		end
		AbilitySlot.StartCD(self._node, leftCD)
	else
		AbilitySlot.StopCD(self._node)
	end
end

-- 充能数变化 → 刷新充能 UI
function Controller:OnChargeCountChange(chargeCount, maxChargeCount)
	if not self._node then
		return
	end
	local AbilitySlot = require("client.packages.ability_system.ui.nodes.AbilitySlot")
	AbilitySlot.UpdateChargeUI(self._node, chargeCount, {
		MaxChargeCount = self._ability:GetAttribute("MaxChargeCount"),
		ChargeInterval = self._ability:GetAttribute("ChargeInterval"),
		ChargeType = self._ability:GetAttribute("ChargeType"),
		ChargeAmount = self._ability:GetAttribute("ChargeAmount"),
		IsChargeConsuming = self._ability:GetAttribute("IsChargeConsuming"),
	})
end

-- 指示器类型变化 → 重建 Pointer
function Controller:OnPointerTypeChange(pointerType)
	self:_rebuildPointer()
end

-- 释放类型变化 → 重建 Strategy
function Controller:OnReleaseTypeChange(releaseType)
	self:_rebuildStrategy(releaseType)
end

-- 释放策略创建 / 重建

-- 按 ReleaseType 从 Registry 取策略类并构造实例
function Controller:_createStrategy(releaseType)
	local Registry = require("common.packages.ability_system.registry")
	local cls = Registry.get("ReleaseStrategy", releaseType) or ReleaseStrategy
	return setmetatable({ ctrl = self }, cls)
end

-- 销毁旧 Strategy，按新 releaseType 重建（触摸进行中先清理旧状态）
function Controller:_rebuildStrategy(releaseType)
	if self.strategy then
		if self.abilityPointer then
			self.abilityPointer:Clear()
		end
		if self.strategy.Destroy then
			self.strategy:Destroy()
		end
	end
	self.strategy = self:_createStrategy(releaseType)
end

-- 指示器创建 / 重建

-- 创建指示器（按技能 PointerType 从 Registry 取类）
function Controller:_createPointer()
	if self.abilityPointer then
		return
	end
	local Registry = require("common.packages.ability_system.registry")
	local pointerType = self._ability:GetAttribute("PointerType")
	local cls = Registry.get("PointerType", pointerType) or AbilityPointer
	self.abilityPointer = cls.new(self._ability, self)
end

-- 销毁旧 Pointer（下次触摸时 _createPointer 按新 PointerType 重建）
function Controller:_rebuildPointer()
	if self.abilityPointer then
		self.abilityPointer:Clear()
		self.abilityPointer:Destroy()
		self.abilityPointer = nil
	end
end

-- 内部辅助

function _setUIManager(um)
	_uiManagerRef = um
end
function _getUIManager()
	return _uiManagerRef
end

function Controller.SetUIManager(um)
	_setUIManager(um)
end
function Controller.GetUIManager()
	return _getUIManager()
end

return Controller

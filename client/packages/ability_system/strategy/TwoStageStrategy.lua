--技能系统 - client两段式施法策略
--首次松开进入瞄准，点场景落点施法。
-- 进入瞄准时通过 scene_input.lua（SceneInput.Connect）接线 InputBegan，
-- 将下一次未消费的场景点击路由到 OnSceneClick（第二阶段落点），
-- 连接存于 self.mouseListener，由 CancelAiming 统一释放。

local AbilityConstants = require("common.packages.ability_system.constants")
local BaseStrategy = require("client.packages.ability_system.strategy.BaseStrategy")

-- 安全释放监听：兼容两种形态 —— 纯函数（SceneInput.Connect 返回的 disconnect）
-- 与带 Disconnect 方法的连接对象（引擎信号连接），nil 直接跳过。
local function safeDisconnect(listener)
	if not listener then
		return
	end
	if type(listener) == "function" then
		listener()
	elseif listener.Disconnect then
		listener:Disconnect()
	end
end

local TwoStageStrategy = setmetatable({}, BaseStrategy)
TwoStageStrategy.__index = TwoStageStrategy

function TwoStageStrategy:OnTouchBegin(eventData)
	local ctrl = self.ctrl
	if self.isAiming then
		-- 如果已经在瞄准状态，再次点击按钮 = 取消瞄准
		self:CancelAiming()
	else
		-- 正常按下图标，准备进入 Stage 1
	end
end

function TwoStageStrategy:OnTouchEnd(eventData)
	if self.isAiming then
		return
	end

	-- 第一次松手，进入瞄准状态
	self.isAiming = true
	local ctrl = self.ctrl
	if ctrl._node then
		require("client.packages.ability_system.ui.nodes.AbilitySlot").ShowDragIndicator(
			ctrl._node,
			eventData.BeganPosition
		)
	end
	ctrl:_createPointer()
	if ctrl.abilityPointer then
		ctrl.abilityPointer:Create(Vector2.New(0, 0))
	end
	local um = ctrl.GetUIManager()
	if um then
		um:SetCancelAreaVisible(true)
	end

	-- 进入瞄准后接线场景输入：下一次未消费的 InputBegan（新手势）路由到 OnSceneClick，
	-- 连接（disconnect 函数）存入 self.mouseListener，由 CancelAiming 统一释放。
	local SceneInput = require("client.packages.ability_system.ui.scene_input")
	local uis = game:GetService("UserInputService")
	self.mouseListener = SceneInput.Connect(self, uis)
end

-- 场景点击（第二阶段落点）。由 SceneInput 在瞄准期间将未消费的场景 InputBegan
-- 转换为 Vector2 屏幕坐标后调用本方法。
function TwoStageStrategy:OnSceneClick(screenPos)
	if not self.isAiming then
		return
	end

	local ctrl = self.ctrl

	-- 检查是否点到了取消区域
	local um = ctrl.GetUIManager()
	if um and um:IsInCancelArea(screenPos) then
		self:CancelAiming()
		return
	end

	-- 执行施法：将屏幕坐标转换为施法方向或点
	local beginPos = ctrl._node and ctrl._node.Position or Vector2.New(0, 0)
	local delta = screenPos - beginPos

	if ctrl.abilityPointer then
		local releasePoint = ctrl.abilityPointer:GetReleasePoint(delta)

		local releaseDirection, releaseTarget = nil, -1
		if ctrl._ability:GetAttribute("TargetType") == AbilityConstants.TargetType.Direction then
			local owner = ctrl:GetOwner()
			releaseDirection = owner and (releasePoint - owner.Position) or nil
			if releaseDirection then
				releaseDirection:Normalize()
				releasePoint = nil
			end
		end

		ctrl:_requestCast(releasePoint, releaseDirection, releaseTarget)
	end

	self:CancelAiming()
end

function TwoStageStrategy:CancelAiming()
	self.isAiming = false
	local ctrl = self.ctrl
	if ctrl._node then
		require("client.packages.ability_system.ui.nodes.AbilitySlot").HideDragIndicator(ctrl._node)
	end
	if ctrl.abilityPointer then
		ctrl.abilityPointer:Clear()
	end
	local um = ctrl.GetUIManager()
	if um then
		um:SetCancelAreaVisible(false)
	end

	safeDisconnect(self.touchListener)
	self.touchListener = nil
	safeDisconnect(self.mouseListener)
	self.mouseListener = nil
end

function TwoStageStrategy:Destroy()
	self:CancelAiming()
end

return TwoStageStrategy

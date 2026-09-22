--技能系统 - client拖拽瞄准施法策略
-- 按下创建指示器并显示取消区；拖拽刷新指示器与取消态；松开时未取消则施法，
-- 蓄力技能（EnableAccumulate）按下进蓄力、松开或取消时结束蓄力。

local AbilityConstants = require("common.packages.ability_system.constants")
local BaseStrategy = require("client.packages.ability_system.strategy.BaseStrategy")

local ReleaseStrategy = setmetatable({}, BaseStrategy)
ReleaseStrategy.__index = ReleaseStrategy

function ReleaseStrategy:OnTouchBegin(eventData)
	local ctrl = self.ctrl
	if ctrl._node then
		require("client.packages.ability_system.ui.nodes.AbilitySlot").ShowDragIndicator(
			ctrl._node,
			eventData.BeganPosition
		)
	end
	ctrl:_createPointer()
	if ctrl._ability:GetAttribute("EnableAccumulate") then
		ctrl:_requestAccumulate()
	end
	if ctrl.abilityPointer then
		ctrl.abilityPointer:Create(Vector2.New(0, 0))
	end
	ctrl:SetReleaseParam("cancel", false)
	-- 本次拖拽位移（未拖拽时为零向量）
	ctrl:SetReleaseParam("dragDelta", Vector2.New(0, 0))
	local um = ctrl.GetUIManager()
	if um then
		um:SetCancelAreaVisible(true)
	end
end

function ReleaseStrategy:OnTouchMove(eventData)
	local ctrl = self.ctrl
	if ctrl._node then
		require("client.packages.ability_system.ui.nodes.AbilitySlot").UpdateDragIndicator(
			ctrl._node,
			eventData.BeganPosition,
			eventData.MovedPosition
		)
	end
	if not ctrl.abilityPointer then
		return
	end

	local delta = eventData.MovedPosition - eventData.BeganPosition
	ctrl:SetReleaseParam("dragDelta", delta)
	ctrl.abilityPointer:Refresh(delta)

	local um = ctrl.GetUIManager()
	if um and um:IsInCancelArea(eventData.MovedPosition) then
		if ctrl._node then
			require("client.packages.ability_system.ui.nodes.AbilitySlot").SetCancelState(
				ctrl._node,
				true
			)
		end
		ctrl:SetReleaseParam("cancel", true)
	else
		if ctrl._node then
			require("client.packages.ability_system.ui.nodes.AbilitySlot").SetCancelState(
				ctrl._node,
				false
			)
		end
		ctrl:SetReleaseParam("cancel", false)
	end
end

function ReleaseStrategy:OnTouchEnd(eventData)
	local ctrl = self.ctrl
	if ctrl._node then
		require("client.packages.ability_system.ui.nodes.AbilitySlot").HideDragIndicator(ctrl._node)
	end
	if not ctrl.abilityPointer then
		return
	end

	ctrl.abilityPointer:Clear()

	if not ctrl:GetReleaseParam("cancel") then
		local ability = ctrl._ability
		if ability:GetAttribute("EnableAccumulate") then
			-- 蓄力技能：判断是否可释放
			local canCast = not ability:GetAttribute("InCD")
				and (
					not ability:GetAttribute("IsChargeConsuming")
					or (ability:GetAttribute("ChargeCount") or 0) > 0
				)
			if canCast then
				local delta = ctrl:GetReleaseParam("dragDelta") or Vector2.New(0, 0)
				local releasePoint = ctrl.abilityPointer:GetReleasePoint(delta)
				local releaseDirection, releaseTarget = nil, -1
				if ability:GetAttribute("TargetType") == AbilityConstants.TargetType.Direction then
					local owner = ctrl:GetOwner()
					releaseDirection = owner and (releasePoint - owner.Position) or nil
					if releaseDirection then
						releaseDirection:Normalize()
						releasePoint = nil
					end
				end
				ctrl:_requestCast(releasePoint, releaseDirection, releaseTarget)
			else
				ctrl:_requestStopAccumulate()
			end
		else
			-- 非蓄力技能：直接施法
			local delta = ctrl:GetReleaseParam("dragDelta") or Vector2.New(0, 0)
			local releasePoint = ctrl.abilityPointer:GetReleasePoint(delta)
			local releaseDirection, releaseTarget = nil, -1
			if ability:GetAttribute("TargetType") == AbilityConstants.TargetType.Direction then
				local owner = ctrl:GetOwner()
				releaseDirection = owner and (releasePoint - owner.Position) or nil
				if releaseDirection then
					releaseDirection:Normalize()
					releasePoint = nil
				end
			end
			ctrl:_requestCast(releasePoint, releaseDirection, releaseTarget)
		end
	else
		-- 取消区域：蓄力中也要通知服务端结束蓄力
		if ctrl._ability:GetAttribute("EnableAccumulate") then
			ctrl:_requestStopAccumulate()
		end
	end

	local um = ctrl.GetUIManager()
	if um then
		um:SetCancelAreaVisible(false)
	end
end

return ReleaseStrategy

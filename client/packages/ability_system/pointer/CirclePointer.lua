--技能系统 - client圆形施法指示器
--在落点位置显示圆形范围特效，支持方向拖拽瞄准。

local AbilityPointer = require("client.packages.ability_system.pointer.AbilityPointer")

local CirclePointer = {}
setmetatable(CirclePointer, AbilityPointer)
CirclePointer.__index = CirclePointer
CirclePointer.super = AbilityPointer

function CirclePointer.new(ability, uiController)
	local obj = AbilityPointer.new(ability, uiController)
	setmetatable(obj, CirclePointer)
	-- {特效， 取消特效， 特效半径}
	obj.effectInfo = { "official://preset/7191", "official://preset/7192", 10.0 }
	obj.beginRotation = nil
	obj.relPositions = nil
	return obj
end

function CirclePointer:Create(dirInfo)
	self.super.Create(self, dirInfo)
	if self.effects then
		local releaseRadius = self._ability:GetAttribute("ReleaseRadius")
		local scale = releaseRadius / self.effectInfo[3]
		local rotation = self:GetCameraRotation()
		self.beginRotation = Quaternion.FromAxisAngle(Vector3.New(0, 1, 0), rotation.yaw)
		self.relPositions = {}

		for _, effect in ipairs(self.effects) do
			effect.Scale = Vector3.New(scale, 0, scale)
		end

		if dirInfo then
			self:Refresh(dirInfo)
		end
	end
end

function CirclePointer:UpdateEffect()
	local owner = self:_GetOwner()
	if not owner then
		return
	end
	local ownerPosition = owner.Position
	ownerPosition = ownerPosition + Vector3.New(0, 0.1, 0)

	if self.effects then
		for i, effect in ipairs(self.effects) do
			local effPosition = ownerPosition
			if self.relPositions and self.relPositions[i] then
				effPosition = ownerPosition + self.relPositions[i]
			end
			effect.Position = effPosition
		end
	end

	if self.distanceEffect ~= nil then
		self.distanceEffect.Position = ownerPosition
	end
end

function CirclePointer:Refresh(dirInfo)
	if self.effects == nil then
		return
	end

	local owner = self:_GetOwner()
	if not owner then
		return
	end

	-- Vector2 无 Length 声明，用欧氏距离
	local pixelLength = math.sqrt(dirInfo.x * dirInfo.x + dirInfo.y * dirInfo.y)
	if pixelLength < 1.0 then
		return
	end
	dirInfo:Normalize()

	local baseRad = math.atan(dirInfo.x, dirInfo.y)
	if baseRad ~= baseRad then
		return
	end

	local releaseDistance = self:GetAbilityProperty("ReleaseDistance")
	local offsetAngle = math.rad(self:GetAbilityProperty("PointerOffsetAngle") or 0)
	local intervalAngle = math.rad(self:GetAbilityProperty("PointerIntervalAngle") or 0)

	-- touchRange 存在 AbilitySlot 的 Lua 侧状态表（EUI userdata 不能挂字段）
	local touchRange = 0
	if self._uiController and self._uiController._node then
		local SlotNode = require("client.packages.ability_system.ui.nodes.AbilitySlot")
		local nodeState = SlotNode.GetState(self._uiController._node)
		if nodeState then
			touchRange = nodeState.touchRange or 0
		end
	end
	local ratio = 1.0
	if touchRange and touchRange > 0 then
		ratio = pixelLength / touchRange
		if ratio > 1.0 then
			ratio = 1.0
		end
	end

	local count = #self.effects
	local startAngle = baseRad + offsetAngle - (count - 1) * intervalAngle * 0.5
	if not self.relPositions then
		self.relPositions = {}
	end

	for i, effect in ipairs(self.effects) do
		local currentAngle = startAngle + (i - 1) * intervalAngle

		local dirX = math.sin(currentAngle)
		local dirY = math.cos(currentAngle)

		local distance = releaseDistance * ratio
		local pos = Vector3.New(distance * dirX, 0, distance * dirY)

		if self.beginRotation then
			pos = self.beginRotation:Apply(pos)
		end

		self.relPositions[i] = pos
		effect.Position = pos + owner.Position
	end
end

return CirclePointer

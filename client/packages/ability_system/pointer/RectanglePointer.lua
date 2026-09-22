--技能系统 - client矩形施法指示器
--沿角色朝向显示矩形范围特效。

local AbilityPointer = require("client.packages.ability_system.pointer.AbilityPointer")

local RectanglePointer = {}
setmetatable(RectanglePointer, AbilityPointer)
RectanglePointer.__index = RectanglePointer
RectanglePointer.super = AbilityPointer

function RectanglePointer.new(ability, uiController)
	local obj = AbilityPointer.new(ability, uiController)
	setmetatable(obj, RectanglePointer)
	-- {特效， 取消特效， 特效长度}
	obj.effectInfo = { "official://preset/7185", "official://preset/7186", 20.0 }
	return obj
end

function RectanglePointer:Create(dirInfo)
	self.super.Create(self, dirInfo)
	if self.effects then
		local releaseDistance = self._ability:GetAttribute("ReleaseDistance")
		local scale = releaseDistance / self.effectInfo[3]
		local rotation = self:GetCameraRotation()
		self.beginRotation = Quaternion.FromAxisAngle(Vector3.New(0, 1, 0), rotation.yaw)

		for _, effect in ipairs(self.effects) do
			effect.Scale = Vector3.New(scale, 1, scale)
		end
		-- 重新应用一次更新，确保使用了正确的 beginRotation
		self:UpdateEffect()
	end
end

return RectanglePointer

--技能系统 - client扇形施法指示器
--沿角色朝向显示扇形范围特效。

local AbilityPointer = require("client.packages.ability_system.pointer.AbilityPointer")

local SectorPointer = {}
setmetatable(SectorPointer, AbilityPointer)
SectorPointer.__index = SectorPointer
SectorPointer.super = AbilityPointer

function SectorPointer.new(ability, uiController)
	local obj = AbilityPointer.new(ability, uiController)
	setmetatable(obj, SectorPointer)
	-- {特效， 取消特效， 特效长度}
	obj.effectInfo = { "official://preset/7189", "official://preset/7190", 10.0 }
	return obj
end

function SectorPointer:Create(dirInfo)
	self.super.Create(self, dirInfo)
	if self.effects then
		local releaseDistance = self._ability:GetAttribute("ReleaseDistance")
		local scale = releaseDistance / self.effectInfo[3]
		local rotation = self:GetCameraRotation()
		self.beginRotation = Quaternion.FromAxisAngle(Vector3.New(0, 1, 0), rotation.yaw)

		for _, effect in ipairs(self.effects) do
			effect.Scale = Vector3.New(scale, 0, scale)
		end
		-- 重新应用一次更新，确保使用了正确的 beginRotation
		self:UpdateEffect()
	end
end

return SectorPointer

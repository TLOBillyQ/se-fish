--技能系统 - client抛物线施法指示器
--PrimitiveService 渲染抛物线轨迹，支持方向拖拽瞄准。
-- 初速度由 ParabolaHorizontalSpeed / ParabolaVerticalSpeed 控制，重力固定 (0, -9.8, 0)。
-- 松开时 GetReleasePoint 返回落地点世界坐标。

local AbilityPointer = require("client.packages.ability_system.pointer.AbilityPointer")

local ParabolaPointer = {}
setmetatable(ParabolaPointer, AbilityPointer)
ParabolaPointer.__index = ParabolaPointer
ParabolaPointer.super = AbilityPointer

local GRAVITY = Vector3.New(0, -9.8, 0)

function ParabolaPointer.new(ability, uiController)
	local obj = AbilityPointer.new(ability, uiController)
	setmetatable(obj, ParabolaPointer)
	obj._primitiveHandle = nil
	obj._lastEndPos = nil
	obj._currentVelocity = nil
	return obj
end

function ParabolaPointer:Create(dirInfo)
	local owner = self:_GetOwner()
	if not owner then
		return
	end

	self.currentDirInfo = dirInfo

	local ps = game:GetService("PrimitiveService")
	self._primitiveHandle = ps:CreatePrimitive()
	ps:SetMaterial(self._primitiveHandle, "shader/splendor/vertex_color.mtg")
	ps:CullNone(self._primitiveHandle)

	-- 更新循环用 Task:Delay 自调度，取消统一走 Task:Cancel
	local Task = game:GetService("Task")
	if self.updateTimer ~= nil then
		Task:Cancel(self.updateTimer)
	end
	local function tick()
		if self.updateTimer == nil then
			return
		end
		self:UpdateEffect()
		self.updateTimer = Task:Delay(0.033, tick)
	end
	self.updateTimer = Task:Delay(0.033, tick)

	self:Refresh(dirInfo or Vector2.New(0, 0))
end

function ParabolaPointer:UpdateEffect()
	if not self._primitiveHandle then
		return
	end
	if not self._currentVelocity then
		return
	end

	local owner = self:_GetOwner()
	if not owner then
		return
	end

	local startPos = owner.Position + Vector3.New(0, 0.1, 0)

	local ps = game:GetService("PrimitiveService")
	local hit, endPos = ps:DrawParabola(self._primitiveHandle, {
		startPos = startPos,
		velocity = self._currentVelocity,
		gravity = GRAVITY,
	})

	self._lastEndPos = endPos
end

function ParabolaPointer:Refresh(dirInfo)
	if not self._primitiveHandle then
		return
	end

	local owner = self:_GetOwner()
	if not owner then
		return
	end

	self.currentDirInfo = dirInfo

	local velocity = self:_calcVelocity(dirInfo)
	if not velocity then
		return
	end

	self._currentVelocity = velocity

	local startPos = owner.Position + Vector3.New(0, 0.1, 0)

	local ps = game:GetService("PrimitiveService")
	local hit, endPos = ps:DrawParabola(self._primitiveHandle, {
		startPos = startPos,
		velocity = velocity,
		gravity = GRAVITY,
	})

	self._lastEndPos = endPos
end

-- 返回落地点世界坐标（Controller 传给 CastAbility）
function ParabolaPointer:GetReleasePoint(dirInfo)
	return self._lastEndPos or Vector3.New(0, 0, 0)
end

function ParabolaPointer:Clear(dirInfo)
	self.currentDirInfo = nil
	self._currentVelocity = nil

	if self.updateTimer then
		game:GetService("Task"):Cancel(self.updateTimer)
		self.updateTimer = nil
	end

	if self._primitiveHandle then
		game:GetService("PrimitiveService"):DestroyPrimitive(self._primitiveHandle)
		self._primitiveHandle = nil
	end
end

function ParabolaPointer:Destroy()
	self:Clear()
end

function ParabolaPointer:_calcVelocity(dirInfo)
	local horzSpeed = self:GetAbilityProperty("ParabolaHorizontalSpeed") or 10
	local vertSpeed = self:GetAbilityProperty("ParabolaVerticalSpeed") or 8
	local dir = Vector2.New(dirInfo.x, dirInfo.y)
	-- Vector2 无 Length 声明，用欧氏距离
	if math.sqrt(dir.x * dir.x + dir.y * dir.y) < 0.01 then
		dir = Vector2.New(0, 1)
	else
		dir:Normalize()
	end

	local baseRad = math.atan(dir.x, dir.y)
	if baseRad ~= baseRad then
		baseRad = 0
	end

	local cameraRot = self:GetCameraRotation()
	local quat = Quaternion.FromAxisAngle(Vector3.New(0, 1, 0), baseRad)
		* Quaternion.FromAxisAngle(Vector3.New(0, 1, 0), cameraRot.yaw)
	local worldDir = quat:Apply(Vector3.New(0, 0, 1))

	return Vector3.New(worldDir.x * horzSpeed, vertSpeed, worldDir.z * horzSpeed)
end

return ParabolaPointer

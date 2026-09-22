--技能系统 - client施法指示器基类
-- 职责：创建/刷新/销毁指示器特效，按输入方向更新位置与旋转，
-- 并在释放时由 GetReleasePoint 计算落点世界坐标。

---施法指示器基类：创建 / 刷新 / 销毁指示器特效，计算释放落点。
---@class AbilityPointer
---@field _ability Script? 技能脚本单位
---@field _uiController Controller? 技能槽位 UI 控制器
---@field effects table? 所有指示器特效实例
---@field effectInfo table? {特效, 取消特效, 特效长度/半径}
---@field distanceEffectInfo table 施法范围圈配置
---@field updateTimer any 刷新计时句柄
---@field currentDirInfo any? 当前输入方向信息
local AbilityPointer = {}
AbilityPointer.__index = AbilityPointer

function AbilityPointer.new(ability, uiController)
	local obj = {}
	setmetatable(obj, AbilityPointer)

	obj._ability = ability
	obj._uiController = uiController
	obj.effects = nil -- 所有指示器特效实例
	obj.effectInfo = nil -- {特效, 取消特效, 特效长度/半径}
	-- 施法范围圈
	obj.distanceEffectInfo = { "official://preset/7187", "official://preset/7188", 10.0 }
	obj.updateTimer = nil
	return obj
end

-- 获取 owner（角色 Unit）
function AbilityPointer:_GetOwner()
	if self._uiController and self._uiController.GetOwner then
		return self._uiController:GetOwner()
	end
	return nil
end

function AbilityPointer:GetAbilityProperty(key)
	if self._ability == nil then
		return nil
	end
	return self._ability:GetAttribute(key)
end

function AbilityPointer:Create(dirInfo)
	self.currentDirInfo = dirInfo
	local owner = self:_GetOwner()
	if owner == nil then
		return
	end
	if self.effects == nil and self.effectInfo ~= nil then
		self.effects = {}
		local effectId = self.effectInfo[1]
		local count = self:GetAbilityProperty("PointerCount") or 1
		if count < 1 then
			count = 1
		end

		for i = 1, count do
			local units = game:GetService("World"):CreateAsset(effectId)
			local effect = units and units[1]
			if effect then
				effect.Position = owner.Position
				table.insert(self.effects, effect)
			end
		end
	end
	if self.distanceEffect == nil then
		local effectId = self.distanceEffectInfo[1]
		local units = game:GetService("World"):CreateAsset(effectId)
		local effect = units and units[1]
		local releaseDistance = self:GetAbilityProperty("ReleaseDistance")
		local scale = releaseDistance / self.distanceEffectInfo[3]
		if effect then
			effect.Position = owner.Position
			effect.Scale = Vector3.New(scale, 0, scale)
			self.distanceEffect = effect
		end
	end
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

	self:UpdateEffect()
end

function AbilityPointer:UpdateEffect()
	if self._ability == nil then
		return
	end
	local owner = self:_GetOwner()
	if owner == nil then
		return
	end
	local ownerPosition = owner.Position
	ownerPosition = ownerPosition + Vector3.New(0, 0.1, 0)

	if self.currentDirInfo then
		self:UpdateTransforms(ownerPosition, self.currentDirInfo)
	elseif self.effects then
		for _, effect in ipairs(self.effects) do
			effect.Position = ownerPosition
		end
	end

	if self.distanceEffect ~= nil then
		self.distanceEffect.Position = ownerPosition
	end
end

-- 根据当前输入方向计算并更新所有指示器的位置和旋转
function AbilityPointer:UpdateTransforms(ownerPosition, dirInfo)
	local effects = self.effects
	if not effects then
		return
	end

	local count = #effects
	if count == 0 then
		return
	end

	local baseRad = math.atan(dirInfo.x, dirInfo.y)
	if baseRad ~= baseRad then
		return
	end -- NaN 检查

	local releaseDistance = self:GetAbilityProperty("ReleaseDistance")
	local offsetAngle = math.rad(self:GetAbilityProperty("PointerOffsetAngle") or 0)
	local intervalAngle = math.rad(self:GetAbilityProperty("PointerIntervalAngle") or 0)

	local pointerOffset = self:GetAbilityProperty("PointerOffset") or Vector3.New(0, 0, 0)
	if type(pointerOffset) == "table" then
		pointerOffset =
			Vector3.New(pointerOffset[1] or 0, pointerOffset[2] or 0, pointerOffset[3] or 0)
	end

	local startAngle = baseRad + offsetAngle - (count - 1) * intervalAngle * 0.5

	for i, effect in ipairs(effects) do
		local currentRad = startAngle + (i - 1) * intervalAngle
		local quat = Quaternion.FromAxisAngle(Vector3.New(0, 1, 0), currentRad)

		if self.beginRotation then
			quat = quat * self.beginRotation
		end
		effect.Rotation = quat

		local worldOffset = quat:Apply(pointerOffset)
		effect.Position = ownerPosition + worldOffset
	end
end

function AbilityPointer:Refresh(dirInfo)
	if self.effects == nil then
		return
	end
	dirInfo:Normalize()
	-- Vector2 无 Length 声明，用欧氏距离
	if math.sqrt(dirInfo.x * dirInfo.x + dirInfo.y * dirInfo.y) <= 0.01 then
		return
	end

	self.currentDirInfo = dirInfo
	self:UpdateEffect()
end

function AbilityPointer:Clear(dirInfo)
	local World = game:GetService("World")
	self.currentDirInfo = nil

	if self.effects then
		for _, effect in ipairs(self.effects) do
			if effect and effect.Destroy then
				effect:Destroy()
			end
		end
		self.effects = nil
	end
	if self.distanceEffect ~= nil then
		if self.distanceEffect.Destroy then
			self.distanceEffect:Destroy()
		end
		self.distanceEffect = nil
	end
	if self.updateTimer ~= nil then
		game:GetService("Task"):Cancel(self.updateTimer)
		self.updateTimer = nil
	end
end

function AbilityPointer:GetReleasePoint(dirInfo)
	local owner = self:_GetOwner()
	if not owner then
		return Vector3.New(0, 0, 0)
	end
	local releaseDistance = self:GetAbilityProperty("ReleaseDistance")

	-- touchRange 存在 AbilitySlot 的 Lua 侧状态表（EUI userdata 不能挂字段）
	local touchRange = 0
	if self._uiController and self._uiController._node then
		local SlotNode = require("client.packages.ability_system.ui.nodes.AbilitySlot")
		local nodeState = SlotNode.GetState(self._uiController._node)
		if nodeState then
			touchRange = nodeState.touchRange or 0
		end
	end
	if touchRange and touchRange > 0 then
		dirInfo = dirInfo * (1 / touchRange)
	end
	-- Vector2 无 Length 声明，用欧氏距离
	if math.sqrt(dirInfo.x * dirInfo.x + dirInfo.y * dirInfo.y) > 0 then
		if math.sqrt(dirInfo.x * dirInfo.x + dirInfo.y * dirInfo.y) > 1.0 then
			dirInfo:Normalize()
		end
		local quat = self.beginRotation or Quaternion.Identity()
		local relPos = Vector3.New(releaseDistance * dirInfo.x, 0, releaseDistance * dirInfo.y)
		return owner.Position + quat:Apply(relPos)
	end
	-- 无方向输入（按下即抬起）：用 beginRotation 朝向（有指示器时）
	if self.beginRotation then
		return owner.Position + self.beginRotation:Apply(Vector3.New(0, 0, releaseDistance))
	end
	-- PointerType=None fallback：用角色朝向
	local forward = owner.Rotation:Apply(Vector3.New(0, 0, 1))
	return owner.Position + forward * releaseDistance
end

function AbilityPointer:GetCameraRotation()
	local camera = game:GetService("CameraService").LiveCamera
	if not camera then
		local owner = self:_GetOwner()
		return owner and owner.Rotation or Quaternion.Identity()
	end
	return camera.Rotation
end

function AbilityPointer:Destroy()
	self:Clear()
end

return AbilityPointer

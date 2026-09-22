--技能系统 - server组件创建脚本
-- 服务器创建组件（垫脚石/弹板等"施放时在脚下生成组件"技能专用）
-- 挂载：作为 Ability ScriptUnit 的直接子节点 Script；script.Parent = 技能壳。
-- 流程：收到宿主 CastStart →（可选 Delay 延迟）→ 在施法者位置+朝向生成 Prefab 组件 →
--       隐藏 → 移交 NetworkOwner → FireClient 通知拥有端 → 客户端本地修正位置后显示。
-- 生命周期：LifeDur 由服务端 TimerService 兜底销毁（替代老版内嵌子脚本字节码方案）。
-- 依赖：宿主已挂 server.packages.ability_system.ability_logic（生成 CastStart 事件）。

-- 公开字段（编辑器可配置，逐个技能覆盖）

---@type WorldUnitPrefab 创建的组件
local Prefab = nil
---创建的组件

---@type Vector3 偏移位置
local Offset = { 0.0, 0.0, 0.0 }
---偏移位置

---@type Vector3 旋转
local Rotation = { 0.0, 0.0, 0.0 }
---旋转

---@type Vector3 缩放
local Scale = { 1.0, 1.0, 1.0 }
---缩放

---@type number 生命周期
local LifeDur = 50.0
---生命周期

---@type boolean 是否绑定
local Bind = false
---是否绑定

---@type number 生效时间
local Delay = 0.0
---生效时间

local RunService = game:GetService("RunService")
if not RunService:IsServer() then
	return
end

local World = game:GetService("World")
local TimerService = game:GetService("TimerService")

local compScript = script
local abilityScript = script.Parent

-- 远程事件，通知拥有端客户端: (unitId, worldOffset, worldRot)
local _createdEvent =
	game:CreateRemoteEvent("BoxComponentCreated_" .. tostring(abilityScript.UnitId))

-- 反射默认值可能是表（引擎 Vector3 反射默认值按表解析），统一转 Vector3.New
local function _vec(v, dx, dy, dz)
	if v == nil then
		return Vector3.New(dx, dy, dz)
	end
	if type(v) == "table" then
		local x, y, z = v.x or v[1] or 0, v.y or v[2] or 0, v.z or v[3] or 0
		return Vector3.New(x, y, z)
	end
	return v
end

local function _rot(ownerRot, offset)
	if ownerRot and ownerRot.Apply then
		local ok, applied = pcall(function()
			return ownerRot:Apply(offset)
		end)
		if ok and applied then
			return applied
		end
	elseif ownerRot then
		local ok, applied = pcall(function()
			return ownerRot * offset
		end)
		if ok and applied then
			return applied
		end
	end
	return offset
end

local function _setDynamic(units)
	for _, u in ipairs(units or {}) do
		local ok = pcall(function()
			if u.BodyType then
				u.BodyType = 4
			end -- 4 = Dynamic
		end)
		if not ok then
			print(
				"[box component server] WARN BodyType=Dynamic rejected, unit id =",
				tostring(u.UnitId)
			)
		end
	end
end

local function _create()
	local owner = abilityScript.Parent and abilityScript.Parent.Parent
	if not owner then
		print("[box component server] ERROR: owner nil")
		return
	end

	local prefab = compScript:GetAttribute("Prefab") or Prefab
	if not prefab then
		print("[box component server] ERROR: Prefab is nil, abort")
		return
	end

	local offset = _vec(compScript:GetAttribute("Offset") or Offset, 0, 0, 0)
	local rotation = _vec(compScript:GetAttribute("Rotation") or Rotation, 0, 0, 0)
	local scale = _vec(compScript:GetAttribute("Scale") or Scale, 1, 1, 1)
	local bind = compScript:GetAttribute("Bind")
	if bind == nil then
		bind = Bind
	end
	local lifeDur = compScript:GetAttribute("LifeDur")
	if lifeDur == nil then
		lifeDur = LifeDur
	end

	-- owner 世界朝向（cast 时刻可能未就绪，兜底单位四元数）
	local ownerRot
	local rotOk = pcall(function()
		ownerRot = owner:GetRotation()
	end)
	if not rotOk or ownerRot == nil then
		rotOk = pcall(function()
			ownerRot = owner.Rotation
		end)
	end
	if not rotOk or ownerRot == nil then
		ownerRot = Quaternion.New(0, 0, 0, 1)
	end

	local worldOffset = _rot(ownerRot, offset)
	local pos = owner:GetPosition() + worldOffset

	local rx = (rotation and (rotation.x or rotation[1])) or 0
	local ry = (rotation and (rotation.y or rotation[2])) or 0
	local rz = (rotation and (rotation.z or rotation[3])) or 0
	local localRot = Quaternion.FromEulerAngles(math.rad(rx), math.rad(ry), math.rad(rz))
	local rot = ownerRot * localRot

	local units =
		World:LoadUnitAssetByRPS(prefab, pos, rot, scale, { resolveSkinFrom = abilityScript })
	local unit = units and units[1]
	if not unit then
		print(
			"[box component server] ERROR: LoadUnitAssetByRPS no unit, prefab =",
			tostring(prefab)
		)
		return
	end

	_setDynamic(units)

	unit.ModelVisible = false

	if bind then
		unit.Parent = owner
	end

	local ownerPlayer = owner:GetNetworkOwner()
	if ownerPlayer then
		if unit.SetNetworkOwner then
			unit:SetNetworkOwner(ownerPlayer)
		end
		_createdEvent:FireClient(ownerPlayer, unit.UnitId, worldOffset, rot)
	else
		print("[box component server] WARNING ownerPlayer nil, show without fix")
		unit.ModelVisible = true
	end

	if lifeDur and lifeDur > 0 then
		TimerService:CreateTimer(1, lifeDur, false, function()
			pcall(function()
				unit:Destroy()
			end)
		end)
	end
end

-- 订阅宿主 CastStart
-- 宿主 (父节点) 优先执行；个别顺序颠倒时轮询等 handler 就绪（最多 ~2s）
local AbilityRegistry = require("common.packages.ability_system.registry")

local tries = 0
local function tryConnect()
	local handler = AbilityRegistry.getAbilityHandler(abilityScript)
	if not handler or not handler.getSignals then
		tries = tries + 1
		if tries < 200 then
			TimerService:CreateTimer(1, 0.01, false, tryConnect)
		else
			print(
				"[box component server] ERROR: ability handler not ready, id =",
				tostring(abilityScript.UnitId)
			)
		end
		return
	end
	local signals = handler.getSignals()
	if not signals or not signals.CastStart then
		print("[box component server] ERROR: CastStart signal missing")
		return
	end

	signals.CastStart:Connect(function()
		local delay = compScript:GetAttribute("Delay")
		if delay == nil then
			delay = Delay
		end
		if delay and delay > 0 then
			TimerService:CreateTimer(1, delay, false, _create)
		else
			_create()
		end
	end)
	print("[box component server] hooked CastStart, ability id =", tostring(abilityScript.UnitId))
end
tryConnect()

-- 本图挥砍行为，基于官方 ability_system/anchors/melee_hit.lua（导入版本 9382ad8）。
-- 官方代码向 TakeDamage 多传 owner；本图受击体的 BaseController 只接受 damage，
-- 多传实参会报 framecore1::Instance 类型告警。保留官方命中、动画及回收行为。
--技能系统 - server锚点逻辑：melee_hit（Constant：命中盒/武器随锚点生命周期回收）
-- 点火时（可选）在施法者武器插槽挂武器模型 + 播上半身动画，并生成命中盒（TriggerUnit）
-- 捕获目标，命中造成伤害/击退/命中特效。
-- 命中盒与武器随锚点生命周期回收：Duration 到时 / 施法结束 / 施法打断 / 锚点销毁
-- → 锚点 Duration 必须 > 0。

local MgrVitals = require("server.Mgr.MgrVitals")
local MgrFishCarrier = require("server.Mgr.MgrFishCarrier")

local M = {}

-- 硬编码常量
local TRIGGER_BOX_PREFAB_ID = 57450
local HIT_SFX_LIFETIME = 1.0
local HITTABLE_UNIT_TYPES = {
	EggyUnit = true,
	HumanUnit = true,
	PetUnit = true,
	PhysicsUnit = true,
}

local function _getPosition(unit)
	if not unit then
		return nil
	end
	if unit.GetPosition then
		return unit:GetPosition()
	end
	return unit.Position
end

local function _getYaw(unit)
	if not unit then
		return 0.0
	end
	if unit.GetYaw then
		return unit:GetYaw() or 0.0
	end
	return 0.0
end

-- 本地空间偏移（+Z=朝向, +X=右侧, +Y=上）旋转到世界空间
local function _rotateYaw(vec, yaw)
	local c = math.cos(yaw)
	local s = math.sin(yaw)
	return Vector3.New(vec.x * c + vec.z * s, vec.y, -vec.x * s + vec.z * c)
end

-- sync_facing=true：命中盒朝向跟随 owner yaw；false：世界绝对方向
local function _getAreaTransform(owner, offset, sync_facing)
	local owner_pos = _getPosition(owner)
	if not owner_pos then
		return nil, 0.0
	end
	local yaw = 0.0
	if sync_facing then
		yaw = _getYaw(owner)
	end
	return owner_pos + _rotateYaw(offset, yaw), yaw
end

local function _safeScale(scale, fallback)
	if not scale then
		return fallback
	end
	if scale.x <= 0.0 or scale.y <= 0.0 or scale.z <= 0.0 then
		return fallback
	end
	return scale
end

-- 欧拉角（度）→ 四元数（ZXY）
local function _eulerDegToQuat(v)
	if not v then
		return Quaternion.FromEulerAngles(0, 0, 0)
	end
	return Quaternion.FromEulerAngles(math.rad(v.x), math.rad(v.y), math.rad(v.z))
end

local function _isHittable(unit)
	if not unit then
		return false
	end
	local ut = unit.UnitType
	if ut ~= nil then
		if HITTABLE_UNIT_TYPES[ut] == true then
			return true
		end
		if ut == "WorldUnit" then
			return unit.PhysicsActive == true
		end
		return false
	end
	return unit.Controller ~= nil
end

local function _isSelf(unit, owner)
	if unit == owner then
		return true
	end
	if not owner then
		return false
	end
	if owner.UnitId and unit.UnitId and owner.UnitId == unit.UnitId then
		return true
	end
	return false
end

local function _applyDamage(target, damage, owner, hit)
	if not damage or damage == 0.0 or not hit then
		return false
	end
	-- #128：本图业务伤害不直接碰 Controller。鱼受击体与玩家角色都经根 Vitals 的命中身份结算；
	-- 同一判定段对同一目标的重放由入口拒绝，未解析到业务目标时不做旧式直扣。
	if MgrFishCarrier:ResolveCarrier(target) then
		return (MgrVitals:ApplyHit(hit, target, damage))
	end
	local players = game:GetService("Players")
	local targetPlayer = players and players.GetPlayerFromCharacter and players:GetPlayerFromCharacter(target)
	if targetPlayer then
		return (MgrVitals:ApplyHit(hit, targetPlayer, damage))
	end
	return false
end

local function _applyHitPower(target, power, owner)
	if not power or power == 0.0 then
		return
	end
	local owner_pos = _getPosition(owner)
	local target_pos = _getPosition(target)
	if not owner_pos or not target_pos then
		return
	end
	local dx = target_pos.x - owner_pos.x
	local dz = target_pos.z - owner_pos.z
	local len = math.sqrt(dx * dx + dz * dz)
	local dir
	if len < 0.0001 then
		local yaw = _getYaw(owner)
		dir = Vector3.New(math.sin(yaw), 0.0, math.cos(yaw))
	else
		dir = Vector3.New(dx / len, 0.0, dz / len)
	end
	local force = Vector3.New(dir.x * power, power, dir.z * power)

	local ctrl = target.Controller
	if ctrl and ctrl.ApplyForce then
		ctrl:ApplyForce(force)
		return
	end
	if target.ApplyImpulse then
		target:ApplyImpulse(force)
		return
	end
	if target.ApplyForceToCenterOfMass then
		target:ApplyForceToCenterOfMass(force)
	end
end

local function _createHitSfx(anchor_script, target)
	local prefab = anchor_script:GetAttribute("ABILITY_ANOSTATE_HIT_SFX")
	if not prefab or prefab == "" then
		return
	end
	local pos = _getPosition(target)
	if not pos then
		return
	end
	local scale =
		_safeScale(anchor_script:GetAttribute("ABILITY_ANOSTATE_HIT_SFX_SCALE"), Vector3.New(1, 1, 1))
	local rotation = _eulerDegToQuat(anchor_script:GetAttribute("ABILITY_ANOSTATE_HIT_SFX_ROTATION"))
	local offset =
		anchor_script:GetAttribute("ABILITY_ANOSTATE_BULLET_HITSFXOFFSET") or Vector3.New(0, 0, 0)
	local units = game:GetService("World"):LoadUnitAssetByRPS(prefab, pos + offset, rotation, scale)
	if units and units[1] then
		local sfx = units[1]
		game:GetService("TimerService"):CreateTimer(1, HIT_SFX_LIFETIME, false, function()
			pcall(function()
				sfx:Destroy()
			end)
		end)
	end
end

function M.Attach(anchor_script)
	local RunService = game:GetService("RunService")
	if not RunService:IsServer() then
		return
	end
	-- 命中盒/武器随锚点生命周期回收，Duration=0（Instant）将无法回收
	if (anchor_script:GetAttribute("Duration") or 0) <= 0 then
		print("[melee_hit] WARNING: Duration 必须 > 0（命中盒随锚点生命周期回收）")
		return
	end
	local start_sig = anchor_script:FindFirstChild("AnchorStart")
	if not start_sig then
		return
	end

	-- 本次点火私有状态（AnchorStart 重建）
	local state = nil

	local function _cleanup()
		if not state then
			return
		end
		if state.enter_conn then
			pcall(function()
				state.enter_conn:Disconnect()
			end)
			state.enter_conn = nil
		end
		if state.tu and state.tu.UnitId then
			pcall(function()
				state.tu:Destroy()
			end)
		end
		state.tu = nil
		-- 武器实际存在 state.weapon_unit / state.weapon_mount（见下方创建处），
		-- 之前写成 mount_ref / unit_ref，字段名不匹配 → 永远销毁不到。
		if state.weapon_mount and state.weapon_mount.UnitId then
			pcall(function()
				state.weapon_mount:Destroy()
			end)
		end
		state.weapon_mount = nil
		if state.weapon_unit and state.weapon_unit.UnitId then
			pcall(function()
				state.weapon_unit:Destroy()
			end)
		end
		state.weapon_unit = nil
		state = nil
	end

	start_sig:Connect(function()
		_cleanup() -- 防御：上一轮未正常终结时先回收
		state = {}
		local ability_script = anchor_script.Parent
		local manager = ability_script and ability_script.Parent
		local owner = manager and manager.Parent
		if not owner or not owner.UnitId then
			return
		end

		-- #129：玩家挥砍只认服务端登记（MgrWeapon 按 GameCfg 表登记伤害/射程）；
		-- 未登记（伪造 RequestCast）不建命中盒、不结算伤害，只播表现。非玩家单位（鱼类施法）
		-- 没有登记概念，沿用预设属性。
		local player = game:GetService("Players"):GetPlayerFromCharacter(owner)
		local swing = nil
		if player then
			swing = require("server.AbilityAPI").TakeSwing(player.UserId)
			if not swing then
				print("[melee_hit] 玩家挥砍缺少服务端登记，只播表现不结算伤害 uid=" .. tostring(player.UserId))
			end
		end

		local hit_box_offset = anchor_script:GetAttribute("ABILITY_ANOSTATE_HITBOX_OFFSET")
			or Vector3.New(0, 1, 0)
		local hit_box_scale =
			_safeScale(anchor_script:GetAttribute("ABILITY_ANOSTATE_HITBOX_SCALE"), Vector3.New(2, 2, 2))
		local hit_damage = anchor_script:GetAttribute("ABILITY_ANOSTATE_BULLET_DAMAGE") or 0.0
		if player then
			if not swing then
				return
			end
			-- 命中盒随登记射程：offset z=range/2（盒中心在面前半程），scale z=range，宽/高 2 米
			hit_box_offset = Vector3.New(0, 1, swing.range / 2)
			hit_box_scale = Vector3.New(2, 2, swing.range)
			hit_damage = swing.damage
		end
		if player then
			hit_damage = require("server.Mgr.MgrGM"):GetMeleeDamage(player, hit_damage)
		end
		state.hit = MgrVitals:NewHit(player or owner, "weapon")
		local hit_power = anchor_script:GetAttribute("ABILITY_ANOSTATE_HITPOWER") or 0.0
		local weapon_prefab = anchor_script:GetAttribute("ABILITY_ANOSTATE_USE_PERFAB") or ""
		local anim_id = anchor_script:GetAttribute("ABILITY_ANOSTATE_ANIMKEY") or ""
		local bind_socket = anchor_script:GetAttribute("ABILITY_ANOSTATE_BINDSOCKET") or "origin"
		local bind_offset = anchor_script:GetAttribute("ABILITY_ANOSTATE_OFFSET") or Vector3.New(0, 0, 0)
		local bind_rotation = _eulerDegToQuat(anchor_script:GetAttribute("ABILITY_ANOSTATE_QUD"))
		local bind_scale =
			_safeScale(anchor_script:GetAttribute("ABILITY_ANOSTATE_SCALE"), Vector3.New(1, 1, 1))
		local sync_facing = anchor_script:GetAttribute("ABILITY_ANOSTATE_FACE_SYNC")
		if sync_facing == nil then
			sync_facing = true
		end

		local World = game:GetService("World")

		-- 武器模型：SkeletalSocketMount 挂插槽 + CreateAsset 生成
		if weapon_prefab ~= "" then
			local weapon_mount = World:CreateUnit("SkeletalSocketMount", {
				Name = "ToolMount_" .. tostring(owner.UnitId),
				Parent = owner,
				SocketName = bind_socket,
				SocketOffset = bind_offset,
				SocketRotation = bind_rotation,
			})
			if weapon_mount then
				local assets = World:CreateAsset(weapon_prefab)
				if assets and assets[1] then
					local weapon_unit = assets[1]
					weapon_unit.Parent = weapon_mount
					weapon_unit.Scale = bind_scale
					if weapon_unit.ModelVisible ~= nil then
						weapon_unit.ModelVisible = true
					end
					if weapon_unit.PhysicsActive ~= nil then
						weapon_unit.PhysicsActive = false
					end
					if weapon_unit.CanCollide ~= nil then
						weapon_unit.CanCollide = false
					end
					if weapon_unit.CanTouch ~= nil then
						weapon_unit.CanTouch = false
					end
					if weapon_unit.CanTrigger ~= nil then
						weapon_unit.CanTrigger = false
					end
					if weapon_unit.CanQuery ~= nil then
						weapon_unit.CanQuery = false
					end
					state.weapon_unit = weapon_unit
					state.weapon_mount = weapon_mount
				else
					pcall(function()
						weapon_mount:Destroy()
					end)
					print("[melee_hit] WARNING: CreateAsset failed:", weapon_prefab)
				end
			else
				print("[melee_hit] WARNING: CreateUnit SkeletalSocketMount failed")
			end
		end

		-- 上半身挥击动画（播完自停，无需回收）
		if anim_id ~= "" and owner.Animator then
			pcall(function()
					local track = owner.Animator:LoadAnimation(anim_id)
					if track then
						-- 引擎没有 AnimationFilterType.UpperBody（只有 Head/Trunk/LeftArm/RightArm/LeftLeg/RightLeg 位），
						-- 取 nil 会让引擎赋值报错并被 pcall 吞掉 → track:Play 不执行 → 没动作。上半身用位掩码 30。
						track.FilterType = 30
						track.Looped = false
						track:Play(0.05, 1, 1)
				end
			end)
		end

		-- 命中盒（随锚点生命周期回收）
		local hit_map = {}
		local center, yaw = _getAreaTransform(owner, hit_box_offset, sync_facing)
		if not center then
			return
		end
		local tu = World:CreateUnit("TriggerUnit", {
			PhysicsMeshId = TRIGGER_BOX_PREFAB_ID,
			Scale = hit_box_scale,
			Position = center,
			Rotation = Quaternion.FromEulerAngles(0, yaw, 0),
			Name = "MeleeHitBox_TU",
		})
		if not tu then
			print("[melee_hit] WARNING: failed to create trigger unit")
			return
		end
		state.tu = tu

		local function process_hit(target)
			if not target or not target.UnitId then
				return
			end
			if not _isHittable(target) then
				return
			end
			if _isSelf(target, owner) then
				return
			end
			if state and state.weapon_unit and target == state.weapon_unit then
				return
			end
			local tid = target.UnitId
			if tid and hit_map[tid] then
				return
			end
			if tid then
				hit_map[tid] = true
			end
			-- 命中：先经统一入口结算；被安全区 / 状态规则拦下时不击退也不播命中特效
			if _applyDamage(target, hit_damage, owner, state and state.hit) then
				print("[melee_hit] 命中 uid=" .. tostring(player and player.UserId or owner.UnitId),
					"target=" .. tostring(tid), "damage=" .. tostring(hit_damage))
				_applyHitPower(target, hit_power, owner)
				_createHitSfx(anchor_script, target)
			end
		end

		state.enter_conn = tu.OnTriggerEnter:Connect(function(other_unit)
			process_hit(other_unit)
		end)

		-- 捕获创建时已在区域内的单位
		local Physics = game:GetService("PhysicsService")
		if Physics and Physics.GetPartsInPart then
			local init_units = Physics:GetPartsInPart(tu)
			if init_units and type(init_units) == "table" then
				for _, u in ipairs(init_units) do
					process_hit(u)
				end
			end
		end
	end)

	-- 随锚点生命周期回收：Duration 到时 / 施法结束 / 施法打断 / 锚点销毁
	for _, name in ipairs({ "AnchorEnd", "AnchorBreak", "AnchorStop" }) do
		local sig = anchor_script:FindFirstChild(name)
		if sig then
			sig:Connect(_cleanup)
		end
	end
	if anchor_script.Destroying then
		anchor_script.Destroying:Connect(_cleanup)
	end
end

return M

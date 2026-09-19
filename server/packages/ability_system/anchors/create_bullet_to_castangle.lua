--技能系统 - server锚点逻辑：create_bullet_to_castangle（Instant）
-- 点火时按目标类型解算方向发射子弹，碰撞（OnlyHitEggy 时校验目标）或寿命到期后爆炸：
-- 爆效 + 球形范围击退（排除施法者），随后销毁子弹。
-- HorizontalSpeed 沿释放方向、VerticalSpeed 竖直上抛。

local M = {}

local function _boom(anchor_script, cast_point, caster)
	-- 爆效
	local sfx_id = anchor_script:GetAttribute("ABILITY_ANOSTATE_NEW_SFX")
	if sfx_id then
		local units = game:GetService("World"):LoadUnitAssetByRPS(
			sfx_id,
			cast_point,
			Quaternion.New(0, 0, 0, 1),
			Vector3.New(1, 1, 1)
		)
		if units and units[1] then
			units[1].Duration = 1.0
		end
	end

	local area = anchor_script:GetAttribute("ABILITY_ANOSTATE_AREA")
	local hit_power = anchor_script:GetAttribute("ABILITY_ANOSTATE_HITPOWER")
	local caster_id = caster and caster.UnitId

	-- Eggy 击退：沿 (目标 - 爆点) 方向，排除 owner
	local eggy_units = game:GetService("World"):GetUnitsInSphere(cast_point, area)
	for _, v in ipairs(eggy_units or {}) do
		if
			v ~= nil
			and v.UnitId ~= caster_id
			and (v:IsA("EggyUnit") == true or v.UnitType == "EggyUnit")
		then
			if v.Controller then
				v.Controller:ApplyForce((v.Position - cast_point):Normalize() * hit_power)
			end
		end
	end

	-- WorldUnit 推力
	local world_units = game:GetService("World"):GetUnitsInSphere(cast_point, area)
	for _, v in ipairs(world_units or {}) do
		if v ~= nil and v.UnitId ~= caster_id and v:IsA("WorldUnit") == true then
			v:ApplyForceAtLocalPosition(
				(v.Position - cast_point):Normalize() * hit_power,
				Vector3.New(0.0, 0.0, 0.0)
			)
		end
	end
end

function M.Attach(anchor_script)
	local RunService = game:GetService("RunService")
	if not RunService:IsServer() then
		return
	end
	local start_sig = anchor_script:FindFirstChild("AnchorStart")
	if not start_sig then
		return
	end
	start_sig:Connect(function()
		local ability_script = anchor_script.Parent
		local manager = ability_script and ability_script.Parent
		local caster = manager and manager.Parent
		if not caster then
			return
		end

		local AbilityRegistry = require("common.packages.ability_system.registry")
		local handler = AbilityRegistry.getAbilityHandler(ability_script)

		-- 方向解算：TargetType==1 走朝向×施法距离，否则用释放点反推方向
		local cast_offset = anchor_script:GetAttribute("Offset") or Vector3.New(0.0, 1.0, 0.0)
		local cast_point = nil
		local cast_angle = nil
		if ability_script:GetAttribute("TargetType") == 1 then
			local euler = caster.Rotation.euler
			local facing = Vector3.New(math.deg(euler.x), math.deg(euler.y), math.deg(euler.z))
			cast_point = caster.Position
				+ facing
					* (handler and handler.getReleaseDistance and handler.getReleaseDistance() or 0)
			cast_angle = handler and handler.getReleaseDirection and handler.getReleaseDirection()
		else
			cast_point = handler and handler.getReleasePoint and handler.getReleasePoint()
			if cast_point then
				cast_angle = (cast_point - (caster.Position + cast_offset)):Normalize()
			end
		end
		if not cast_angle then
			return
		end

		-- 生成子弹（朝向按方向向量取 yaw）
		local yaw = math.atan(cast_angle.x, cast_angle.z)
		local units = game:GetService("World"):LoadUnitAssetByRPS(
			anchor_script:GetAttribute("ABILITY_ANOSTATE_BULLET_OBJ"),
			caster.Position + cast_offset,
			Quaternion.FromEulerAngles(0, yaw, 0),
			anchor_script:GetAttribute("Scale")
		)
		local bullet = units and units[1] or nil
		if not bullet then
			return
		end

		-- 速度：方向×水平 + (0,垂直,0)
		local velocity = cast_angle
				* (anchor_script:GetAttribute("ABILITY_ANOSTATE_BULLET_HSPEED") or 0)
			+ Vector3.New(
				0.0,
				anchor_script:GetAttribute("ABILITY_ANOSTATE_BULLET_VSPEED") or 0,
				0.0
			)
		local bullet_dur = anchor_script:GetAttribute("ABILITY_ANOSTATE_BULLET_DUR")

		-- 按刚体类型施加运动（Kinematic 用直线马达 / Dynamic 用冲量 / Static 空操作）
		local raw_body = bullet.BodyType
		if raw_body == Enums.BodyType.Kinematic then
			game:GetService("World"):CreateUnit("LinearMotorUnit", {
				LinearVelocity = velocity,
				Duration = bullet_dur,
				Parent = bullet,
			})
		elseif raw_body ~= Enums.BodyType.Static then
			bullet:ApplyForceToCenterOfMass(velocity * 1000.0)
		end

		-- 寿命到期的回收统一在 boom_on_destroy 定义之后注册（见下方）。
		-- 不要在这里直接 bullet:Destroy()：Destroy 会同步触发 World.UnitRemoving → boom_on_destroy
		-- 再销毁一次，同一单位被销毁两遍 → 引擎 physicsReplicationSend 对它调 dtor 报 nil。

		-- 20ms 后非 Static 转 Dynamic
		game:GetService("TimerService"):CreateTimer(1, 0.02, false, function()
			if bullet and bullet.BodyType ~= Enums.BodyType.Static then
				pcall(function()
					bullet.BodyType = Enums.BodyType.Dynamic
				end)
			end
		end)

		-- 施法者免碰撞对（宽限期可配）
		local grace = anchor_script:GetAttribute("ABILITY_ANOSTATE_COLLISION_CASTER_TIME")
		if grace and grace > 0.0 then
			bullet:AddNoCollisionPairWithUnit(caster)
			game:GetService("TimerService"):CreateTimer(1, grace, false, function()
				if bullet then
					pcall(function()
						bullet:RemoveNoCollisionPairWithUnit(caster)
					end)
				end
			end)
		end

		-- 无重力窗口
		local ignore_grav = anchor_script:GetAttribute("ABILITY_ANOSTATE_IGNORE_GRAVITATION_TIME")
		if ignore_grav and ignore_grav > 0.0 then
			bullet.GravityEnabled = false
			game:GetService("TimerService"):CreateTimer(1, ignore_grav, false, function()
				if bullet then
					pcall(function()
						bullet.GravityEnabled = true
					end)
				end
			end)
		end

		local boomed = false
		local unit_removing_conn = nil

		-- 爆炸入口：先发标记防重，再走 UnitRemoving 主路径触发
		-- from_destroy=true 表示「非命中销毁」（寿命到期 / 被外力销毁）：
		-- 这种销毁只有 ABILITY_ANOSTATE_ONLYDESTROYBOOM=true 才爆，否则静默消失。
		-- 命中触发时调用不带参数（from_destroy=nil），照旧必爆。
		local function boom_on_destroy(from_destroy)
			if boomed then
				return
			end
			boomed = true
			if unit_removing_conn then
				pcall(function()
					unit_removing_conn:Disconnect()
				end)
				unit_removing_conn = nil
			end
			if bullet then
				local pos = bullet.Position
				local explode = (not from_destroy)
					or anchor_script:GetAttribute("ABILITY_ANOSTATE_ONLYDESTROYBOOM") == true
				pcall(function()
					bullet:Destroy()
				end)
				if pos and explode then
					_boom(anchor_script, pos, caster)
				end
			end
		end

		-- 碰撞（0.2s 后注册）：OnlyHitEggy 时仅 EggyUnit 触发爆炸
		game:GetService("TimerService"):CreateTimer(1, 0.2, false, function()
			if not (bullet and bullet.OnCollisionEnter) then
				return
			end
			pcall(function()
				bullet.OnCollisionEnter:Connect(function(other_unit)
					if boomed then
						return
					end
					-- 命中是否销毁投射物：false 时命中不销毁、不爆炸，交给寿命到期回收
					if anchor_script:GetAttribute("ABILITY_ANOSTATE_BULLET_HITDESTROY") == false then
						return
					end
					local only_hit_eggy = anchor_script:GetAttribute("ABILITY_ANOSTATE_ONLYHITEGGY")
					local valid = other_unit ~= nil
						and (
							other_unit:IsA("EggyUnit") == true
							or other_unit.UnitType == "EggyUnit"
						)
					if only_hit_eggy == true and not valid then
						return
					end
					boom_on_destroy()
				end)
			end)
		end)

		-- 寿命耗尽/被外力销毁 → UnitRemoving 触发爆炸（0.15s 后注册）
		game:GetService("TimerService"):CreateTimer(1, 0.15, false, function()
			if boomed then
				return
			end
			unit_removing_conn = game:GetService("World").UnitRemoving:Connect(function(unit)
				if unit == bullet then
					boom_on_destroy(true)
				end
			end)
		end)

		-- 寿命到期：走 boom_on_destroy 统一回收（只销毁一次），是否爆炸由
		-- ABILITY_ANOSTATE_ONLYDESTROYBOOM 决定（false = 静默消失）
		game:GetService("TimerService"):CreateTimer(1, bullet_dur, false, function()
			boom_on_destroy(true)
		end)
	end)
end

return M

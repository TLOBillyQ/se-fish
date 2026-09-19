--技能系统 - server锚点逻辑：create_landmine（Instant）
-- 点火时按施法者朝向旋转偏移生成地雷 → 免碰撞对（0.8s 解除）→ 1s 后注册碰撞
-- → 碰撞/寿命到期爆炸：爆效 + 球形范围击退（Eggy 施力 / WorldUnit 推力）→ 销毁地雷。

local M = {}

function M.Attach(anchor_script)
	local RunService = game:GetService("RunService")
	if not RunService:IsServer() then
		return
	end
	local start_sig = anchor_script:FindFirstChild("AnchorStart")
	if not start_sig then
		print("[Landmine] Attach FAILED: 锚点下没有 AnchorStart 事件单位（anchor_logic 可能没跑）:", tostring(anchor_script))
		return
	end
	print("[Landmine] Attach ok: " .. tostring(anchor_script))
	start_sig:Connect(function()
		local ability_script = anchor_script.Parent
		local manager = ability_script and ability_script.Parent
		local caster = manager and manager.Parent
		if not caster then
			print("[Landmine] ABORT: caster 取不到（anchor.Parent.Parent.Parent）")
			return
		end

		-- 生成位置：caster.Position + Offset 按 caster yaw 旋转
		local offset = anchor_script:GetAttribute("Offset") or Vector3.New(0, 0, 0)
		local yaw = caster:GetRotation():GetYaw()
		local cy = math.cos(yaw)
		local sy = math.sin(yaw)
		local caster_pos = caster.Position
		local landmine_pos = caster_pos
			+ Vector3.New(offset.x * cy + offset.z * sy, offset.y, -offset.x * sy + offset.z * cy)

		local prefab = anchor_script:GetAttribute("ABILITY_ANOSTATE_NEW_OBJ")
		print("[Landmine] AnchorStart -> prefab=" .. tostring(prefab) .. " pos=" .. tostring(landmine_pos))

		local units = game:GetService("World"):LoadUnitAssetByRPS(
			prefab,
			landmine_pos,
			Quaternion.New(0, 0, 0, 1),
			anchor_script:GetAttribute("Scale"),
			{ resolveSkinFrom = ability_script }
		)
		local landmine = units and units[1] or nil
		if not landmine then
			print("[Landmine] ABORT: LoadUnitAssetByRPS 没返回 unit（units=" .. tostring(units) .. "）")
			return
		end
		print("[Landmine] created: " .. tostring(landmine) .. "  BodyType=" .. tostring(landmine.BodyType) .. "  ModelVisible=" .. tostring(landmine.ModelVisible))

		-- 显式可见（LoadUnitAssetByRPS 出来的 unit 不保证默认可见）
		if landmine.ModelVisible ~= nil then
			landmine.ModelVisible = true
		end

		-- 寿命到期自毁
		local life_dur = anchor_script:GetAttribute("ABILITY_ANOSTATE_LIFE_DUR")
		if life_dur then
			game:GetService("TimerService"):CreateTimer(1, life_dur, false, function()
				pcall(function()
					landmine:Destroy()
				end)
			end)
		end

		-- 非 Static 转 Dynamic（Static 忽略速度/重力，永远不碰撞）
		if landmine.BodyType ~= Enums.BodyType.Static then
			landmine.BodyType = Enums.BodyType.Dynamic
		end

		-- 施法者免碰撞对，0.8s 后解除
		landmine:AddNoCollisionPairWithUnit(caster)
		game:GetService("TimerService"):CreateTimer(1, 0.8, false, function()
			if landmine then
				pcall(function()
					landmine:RemoveNoCollisionPairWithUnit(caster)
				end)
			end
		end)

		-- 爆炸：爆效 + 范围击退 + 销毁地雷（碰撞/寿命共用，保证只炸一次）
		local boomed = false
		local function explode()
			if boomed then
				return
			end
			boomed = true
			local cast_point = landmine.Position

			-- 爆效（Duration=1.0）
			local sfx_id = anchor_script:GetAttribute("ABILITY_ANOSTATE_NEW_SFX")
			if sfx_id then
				-- sfx 旋转固定为单位四元数
				local sfx_rot = Quaternion.Identity()
				local sfx_units = game:GetService("World"):LoadUnitAssetByRPS(
					sfx_id,
					cast_point,
					sfx_rot,
					anchor_script:GetAttribute("Scale")
				)
				if sfx_units and sfx_units[1] then
					sfx_units[1].Duration = 1.0
				end
			end

			local area = anchor_script:GetAttribute("ABILITY_ANOSTATE_AREA")
			local hit_power = anchor_script:GetAttribute("ABILITY_ANOSTATE_HITPOWER")
			local caster_id = caster.UnitId
			local landmine_id = landmine.UnitId

			-- Eggy 击退：沿 (目标位置 - 爆点) 施力，排除施法者
			local eggy_units = game:GetService("World"):GetUnitsInSphere(cast_point, area)
			for _, v in ipairs(eggy_units or {}) do
				if
					v ~= nil
					and v.UnitId ~= caster_id
					and (v:IsA("EggyUnit") == true or v.UnitType == "EggyUnit")
				then
					if v.Controller then
						v.Controller:ApplyForce((v.Position - cast_point) * hit_power)
					end
				end
			end

			-- WorldUnit 推力：沿现有速度方向，静止则延迟 0.1s 取位移方向，再兜底取离爆点方向
			local world_units = game:GetService("World"):GetUnitsInSphere(cast_point, area)
			for _, v in ipairs(world_units or {}) do
				if
					v ~= nil
					and v.UnitId ~= caster_id
					and v.UnitId ~= landmine_id
					and v:IsA("WorldUnit") == true
				then
					local vel = v.Velocity
					local speed = 0
					if vel then
						speed = math.sqrt(vel.x * vel.x + vel.y * vel.y + vel.z * vel.z)
					end
					if speed > 0.1 then
						v:ApplyForceToCenterOfMass(
							Vector3.New(vel.x / speed, vel.y / speed, vel.z / speed) * hit_power
						)
					else
						local pos1 = v.Position
						game:GetService("TimerService"):CreateTimer(1, 0.1, false, function()
							local pos2 = v.Position
							local delta = pos2 - pos1
							if delta:Length() > 0.01 then
								v:ApplyForceToCenterOfMass(delta:Normalize() * hit_power)
							else
								local dir = pos2 - cast_point
								if dir:Length() > 0 then
									v:ApplyForceToCenterOfMass(dir:Normalize() * hit_power)
								end
							end
						end)
					end
				end
			end

			pcall(function()
				landmine:Destroy()
			end)
		end

		-- 1s 后才注册碰撞（落地稳定期）
		game:GetService("TimerService"):CreateTimer(1, 1.0, false, function()
			if landmine and landmine.OnCollisionEnter then
				pcall(function()
					landmine.OnCollisionEnter:Connect(function()
						explode()
					end)
				end)
			end
		end)
	end)
end

return M

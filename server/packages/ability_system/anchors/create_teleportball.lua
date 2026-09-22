--技能系统 - server锚点逻辑：create_teleportball（Instant）
-- 点火时沿释放方向发射传送球，命中后建传送门（入口特效 + 触发区域），把施法者传送到落点后销毁球。
-- HorizontalSpeed 沿释放方向、VerticalSpeed 竖直上抛（配表时旧 VSPEED 值填 HorizontalSpeed）。

local M = {}

-- 硬编码常量
local HIT_EFFECT_ASSET_ID = "official://preset/286"
local ENTRY_EFFECT_ASSET_ID = "official://preset/285"
local TRIGGER_AREA_ASSET_ID = "official://preset/3101340"
local TRIGGER_AREA_SCALE = Vector3.New(2.5, 4.0, 2.5)
local COLLISION_DELAY = 0.14

local function _createEffect(asset_id, pos, duration)
	local units = game:GetService("World"):LoadUnitAssetByRPS(
		asset_id,
		pos,
		Quaternion.New(0, 0, 0, 1),
		Vector3.New(1.2, 1.2, 1.2)
	)
	if units and units[1] then
		units[1].Duration = duration
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

		-- 释放方向（handler 读取）
		local AbilityRegistry = require("common.packages.ability_system.registry")
		local handler = AbilityRegistry.getAbilityHandler(ability_script)
		local cast_angle = handler and handler.getReleaseDirection and handler.getReleaseDirection()
			or Vector3.New(0, 0, 1)
		local dur = anchor_script:GetAttribute("BallDuration")

		-- 生成传送球（朝向按方向向量取 yaw）
		local yaw = math.atan(cast_angle.x, cast_angle.z)
		local units = game:GetService("World"):LoadUnitAssetByRPS(
			anchor_script:GetAttribute("ABILITY_ANOSTATE_BULLET_OBJ"),
			caster.Position + (anchor_script:GetAttribute("Offset") or Vector3.New(0, 0, 0)),
			Quaternion.FromEulerAngles(0, yaw, 0),
			anchor_script:GetAttribute("Scale"),
			{ resolveSkinFrom = ability_script }
		)
		local bullet = units and units[1] or nil
		if not bullet then
			return
		end

		bullet:AddNoCollisionPairWithUnit(caster)

		-- 速度：水平沿方向 + 垂直上抛
		local velocity = cast_angle
				* (anchor_script:GetAttribute("ABILITY_ANOSTATE_BULLET_HSPEED") or 0)
			+ Vector3.New(
				0.0,
				anchor_script:GetAttribute("ABILITY_ANOSTATE_BULLET_VSPEED") or 0,
				0.0
			)
		game:GetService("World"):CreateUnit("LinearMotorUnit", {
			LinearVelocity = velocity,
			Duration = dur,
			Parent = bullet,
		})
		if bullet.BodyType ~= Enums.BodyType.Static then
			bullet.BodyType = Enums.BodyType.Dynamic
		end

		-- 碰撞 → 建传送门
		local function on_bullet_hit()
			if not bullet then
				return
			end

			-- 命中特效（bullet 位置 + 高度偏移 2.1）
			_createEffect(HIT_EFFECT_ASSET_ID, bullet.Position + Vector3.New(0.0, 2.1, 0.0), dur)

			-- 传送目标点
			local teleport_pos = bullet.Position + Vector3.New(0.0, 1.0, 0.0)

			-- 入口特效（caster + 方向*3 + (0,2.6,0)）
			_createEffect(
				ENTRY_EFFECT_ASSET_ID,
				caster.Position + cast_angle * 3.0 + Vector3.New(0.0, 2.6, 0.0),
				dur
			)

			-- 触发区域（caster + 方向*3 + (0,1,0)）
			local trig_units = game:GetService("World"):LoadUnitAssetByRPS(
				TRIGGER_AREA_ASSET_ID,
				caster.Position + cast_angle * 3.0 + Vector3.New(0.0, 1.0, 0.0),
				Quaternion.New(0, 0, 0, 1),
				TRIGGER_AREA_SCALE
			)
			local trig_area = trig_units and trig_units[1] or nil

			if trig_area then
				-- DUR 到期销毁触发区域
				game:GetService("TimerService"):CreateTimer(1, dur, false, function()
					pcall(function()
						trig_area:Destroy()
					end)
				end)
				-- 进入触发区 → 传送施法者
				if trig_area.OnTriggerEnter then
					pcall(function()
						trig_area.OnTriggerEnter:Connect(function()
							if caster then
								caster.Position = teleport_pos
							end
						end)
					end)
				end
			end

			-- 销毁球
			pcall(function()
				bullet:Destroy()
			end)
		end

		-- 0.14s 后注册碰撞（离手稳定期）
		game:GetService("TimerService"):CreateTimer(1, COLLISION_DELAY, false, function()
			if bullet and bullet.OnCollisionEnter then
				pcall(function()
					bullet.OnCollisionEnter:Connect(function()
						on_bullet_hit()
					end)
				end)
			end
		end)
	end)
end

return M

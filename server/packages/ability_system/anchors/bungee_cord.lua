--技能系统 - server锚点逻辑：bungee_cord（Instant 起步 + 内部 flying/pulling/done 状态机）
-- 点火时沿抛物线弹出弹簧绳 → flying 阶段心跳做命中检测（碰撞回调 + 球形查询兜底）
-- → 命中转 pulling：弹簧 + 阻尼 + 渐入 + 上限钳制拉拽施法者 → 到达/超时收尾。
-- 抛物线初速：读能力 ParabolaHorizontalSpeed/ParabolaVerticalSpeed 属性，取不到用兜底常量。
-- Static 绳必须转 Dynamic 否则永不碰撞。

local M = {}

-- 硬编码常量
local SPRING_ROPE_ASSET_ID = "official://preset/102255"
local LINE_EFFECT_ASSET_ID = "official://preset/5929"
local PARABOLA_HORZ_SPEED_FALLBACK = 10.0
local PARABOLA_VERT_SPEED_FALLBACK = 8.0
local HEARTBEAT_DT = 0.033
local HIT_DETECT_RADIUS = 1.5

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
		local owner = manager and manager.Parent
		if not owner then
			print("[spring_rope] ERROR: owner is nil")
			return
		end

		-- 状态机（闭包私有，每个能力实例各自一套）
		local state = "flying"
		local rope = nil
		local line_effect = nil
		local heartbeat = nil
		local lifetime = nil
		local hit_pos = nil
		local pull_elapsed = 0

		local function _attr(name)
			return anchor_script:GetAttribute(name)
		end

		-- 清理：取消 timer / 销毁绳 / 销毁连线特效 / 标记 done
		local function cleanup()
			if state == "done" then
				return
			end
			state = "done"
			if heartbeat then
				heartbeat:Cancel()
				heartbeat = nil
			end
			if lifetime then
				lifetime:Cancel()
				lifetime = nil
			end
			if rope then
				pcall(function()
					rope:Destroy()
				end)
				rope = nil
			end
			if line_effect then
				pcall(function()
					line_effect:Destroy()
				end)
				line_effect = nil
			end
			hit_pos = nil
			pull_elapsed = 0
		end

		-- 拉拽：弹簧 + 阻尼 + 渐入 + 上限钳制
		local function apply_spring_force()
			local controller = owner and owner.Controller
			if not controller or not controller.ApplyForce then
				return
			end
			local owner_pos = owner and owner.Position
			if not owner_pos or not hit_pos then
				return
			end
			local diff = hit_pos - owner_pos
			local dist = diff:Length()
			if dist < 0.001 then
				return
			end
			local dir = diff.Unit

			-- 弹簧拉力 F = k * stretch（小于静止长度则不拉）
			local stretch = math.max(dist - (_attr("SPRING_ROPE_REST_LENGTH") or 0), 0)
			local mag = (_attr("SPRING_ROPE_STIFFNESS") or 0) * stretch

			-- 沿绳向阻尼，抑制振荡；绳只能拉不能推
			local vel = Vector3.New(0, 0, 0)
			if controller.GetLinearVelocity then
				vel = controller:GetLinearVelocity()
			end
			mag = mag - (_attr("SPRING_ROPE_DAMPING_COEFFICIENT") or 0) * vel:Dot(dir)
			if mag < 0 then
				mag = 0
			end

			-- 渐入：起拉 0→1 线性放大
			local ramp = pull_elapsed / (_attr("SPRING_ROPE_TENSION_FADE_IN_DURATION") or 1)
			if ramp > 1 then
				ramp = 1
			end
			mag = mag * ramp

			-- 上限钳制
			local max_force = _attr("SPRING_ROPE_MAX_PER_TENSION")
			if mag > max_force then
				mag = max_force
			end

			controller:ApplyForce(dir * mag)
		end

		-- pulling 主循环单帧
		local function pull_tick()
			pull_elapsed = pull_elapsed + HEARTBEAT_DT
			if not rope then
				cleanup()
				return
			end
			local owner_pos = owner and owner.Position
			if not owner_pos or not hit_pos then
				print("[spring_rope] pull tick: owner_pos or hit_pos is nil, cleanup")
				cleanup()
				return
			end
			rope.Position = hit_pos
			local dist = (hit_pos - owner_pos):Length()
			-- 终止 1：到达目标附近（小于静止长度）
			if dist <= (_attr("SPRING_ROPE_REST_LENGTH") or 0) then
				cleanup()
				return
			end
			apply_spring_force()
			-- 终止 2：拉拽超时
			if pull_elapsed > (_attr("SPRING_ROPE_DRAG_MAX_DURATION") or 0) then
				cleanup()
			end
		end

		-- flying 命中检测：球形查询兜底（排除绳与 owner 自身）
		local function hit_check()
			if not rope then
				return
			end
			local rope_id = rope.UnitId
			local owner_id = owner and owner.UnitId
			local rope_pos = rope.Position
			if not rope_pos then
				return
			end
			local hits = game:GetService("World"):GetUnitsInSphere(rope_pos, HIT_DETECT_RADIUS)
			for _, unit in ipairs(hits) do
				if unit and unit.UnitId ~= rope_id and unit.UnitId ~= owner_id then
					-- 命中切换 flying → pulling
					if state ~= "flying" then
						return
					end
					local pos = rope.Position
					if not pos then
						return
					end
					state = "pulling"
					hit_pos = pos
					pull_elapsed = 0
					rope.LinearVelocity = Vector3.New(0, 0, 0)
					rope.AngularVelocity = Vector3.New(0, 0, 0)
					return
				end
			end
		end

		-- 心跳：flying 检测命中 / pulling 驱动拉拽；pcall 防异常炸掉 timer
		heartbeat = game:GetService("TimerService"):CreateTimer(-1, HEARTBEAT_DT, false, function()
			if state == "done" then
				return
			end
			local ok, err = pcall(function()
				if state == "flying" then
					hit_check()
				elseif state == "pulling" then
					pull_tick()
				end
			end)
			if not ok then
				print("[spring_rope] Heartbeat ERROR:", err)
			end
		end)

		-- 整体生命兜底超时（含无限心跳 timer 的最终回收路径）
		lifetime = game:GetService("TimerService")
			:CreateTimer(1, _attr("SPRING_ROPE_TOTAL_MAX_LIFETIME") or 0, false, function()
				cleanup()
			end)

		-- 抛物线初速：能力属性优先，兜底常量
		local horz_speed = ability_script:GetAttribute("ParabolaHorizontalSpeed")
			or PARABOLA_HORZ_SPEED_FALLBACK
		local vert_speed = ability_script:GetAttribute("ParabolaVerticalSpeed")
			or PARABOLA_VERT_SPEED_FALLBACK
		local AbilityRegistry = require("common.packages.ability_system.registry")
		local handler = AbilityRegistry.getAbilityHandler(ability_script)
		local release_dir = handler
				and handler.getReleaseDirection
				and handler.getReleaseDirection()
			or Vector3.New(0, 0, 1)
		if release_dir:Length() < 0.001 then
			release_dir = Vector3.New(0, 0, 1)
		else
			release_dir = release_dir.Unit
		end
		local initial_velocity =
			Vector3.New(release_dir.x * horz_speed, vert_speed, release_dir.z * horz_speed)

		-- 生成位置：owner + 前向/上向偏移
		local owner_pos = owner.Position
		if not owner_pos then
			print("[spring_rope] ERROR: owner.Position is nil")
			cleanup()
			return
		end
		local spawn_pos = owner_pos
			+ release_dir * (_attr("SPRING_ROPE_SPAWN_FORWARD_OFFSET") or 0)
			+ Vector3.New(0, (_attr("SPRING_ROPE_SPAWN_UP_OFFSET") or 0), 0)

		-- 创建绳（必须用 LoadUnitAssetByRPS）
		local release_yaw = math.atan(release_dir.x, release_dir.z)
		local rot = Quaternion.FromEulerAngles(
			0,
			release_yaw + math.rad(_attr("SPRING_ROPE_MODEL_ROTATION_CORRECTION") or 0),
			0
		)
		local units =
			game:GetService("World")
				:LoadUnitAssetByRPS(SPRING_ROPE_ASSET_ID, spawn_pos, rot, Vector3.New(1, 1, 1))
		if not units or not units[1] then
			print("[spring_rope] ERROR: failed to create rope unit")
			cleanup()
			return
		end
		rope = units[1]

		-- 物理：Static 绳不会飞出 → 必须 Dynamic + 独立重力
		rope.BodyType = Enums.BodyType.Dynamic
		rope.GravityEnabled = true
		rope.UseIndividualGravity = true
		rope.IndividualGravityValue =
			Vector3.New(0, -(_attr("SPRING_ROPE_PARABOLA_GRAVITY_ACC") or 0), 0)
		rope.LinearVelocity = initial_velocity
		if rope.AddNoCollisionPairWithUnit then
			rope:AddNoCollisionPairWithUnit(owner)
		end
		if rope.SetNetworkOwner then
			rope:SetNetworkOwner(nil)
		end

		-- 碰撞回调（球形查询为主，碰撞事件为辅）
		if rope.OnCollisionEnter then
			pcall(function()
				rope.OnCollisionEnter:Connect(function(other_unit)
					if state ~= "flying" then
						return
					end
					if other_unit and other_unit.UnitId == (owner and owner.UnitId) then
						return
					end
					local pos = rope and rope.Position
					if not pos then
						return
					end
					state = "pulling"
					hit_pos = pos
					pull_elapsed = 0
					rope.LinearVelocity = Vector3.New(0, 0, 0)
					rope.AngularVelocity = Vector3.New(0, 0, 0)
				end)
			end)
		end

		-- 连线特效（起点挂 owner origin，终点绑绳 Socket_1）
		game:GetService("TimerService"):RegisterNextFrame(function()
			if state == "done" then
				return
			end
			if not rope or not rope.UnitId then
				return
			end
			line_effect = game:GetService("World"):CreateUnit("EffectUnit", {
				EffectId = LINE_EFFECT_ASSET_ID,
				Duration = -1,
				EffectEndBindData = {
					BindUnitId = rope.UnitId,
					BindSocket = "Socket_1",
				},
			})
			if not line_effect then
				print("[spring_rope] WARNING: failed to create line effect")
				return
			end
			line_effect:StartposAttach(owner, "origin", Vector3.New(0, 0, 0))
			line_effect.EffectEndBindData = {
				BindUnitId = rope.UnitId,
				BindSocket = "Socket_1",
			}
		end)
	end)
end

return M

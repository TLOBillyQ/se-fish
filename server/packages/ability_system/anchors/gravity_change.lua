--技能系统 - server锚点逻辑：gravity_change（Constant-only：可逆状态，Duration 必须 >0）
-- 语义：点火期间以固定频率施加补偿力使净 Y 加速度 ≈ 配置值，终结时停止施力。
-- 角色重力用 humanoid 自身默认 9.8（非 world.Gravity）；质量优先 controller:GetMass()，取不到用 10。

local M = {}

local CHARACTER_GRAVITY = 9.8

function M.Attach(anchor_script)
	local RunService = game:GetService("RunService")
	if not RunService:IsServer() then
		return
	end

	local state = nil -- 本次点火私有：{ force_timer = 补偿力 timer }

	local function _stopForce()
		local timer = state and state.force_timer
		if timer then
			state.force_timer = nil
			local ok, err = pcall(function()
				timer:Cancel()
			end)
			if not ok then
				print("[gravity_modifier] cancel force timer err: " .. tostring(err))
			end
		end
	end

	local start_sig = anchor_script:FindFirstChild("AnchorStart")
	if start_sig then
		start_sig:Connect(function()
			state = {}
			local ability_script = anchor_script.Parent
			local manager = ability_script and ability_script.Parent
			local owner = manager and manager.Parent
			if owner == nil then
				print("[gravity_modifier] BEGIN: owner is nil, skip")
				return
			end
			local target = anchor_script:GetAttribute("ABILITY_ANOSTATE_UP_ACCELERATION")
			if target == nil then
				print("[gravity_modifier] BEGIN: TargetGravityAcceleration nil, skip")
				return
			end
			local controller = owner.Controller
			if controller == nil or controller.ApplyForce == nil then
				print("[gravity_modifier] owner.Controller or ApplyForce nil, skip")
				return
			end
			local mass = 10
			if controller.GetMass then
				local ok, m = pcall(function()
					return controller:GetMass()
				end)
				if ok and m and m > 0 then
					mass = m
				end
			end
			local force_y = mass * (target + CHARACTER_GRAVITY)
			local err_printed = false
			local timer = game:GetService("TimerService"):CreateTimer(-1, 0.033, false, function()
				local ok, err = pcall(function()
					controller:ApplyForce(Vector3.New(0, force_y, 0))
				end)
				if not ok and not err_printed then
					err_printed = true
					print("[gravity_modifier] apply force err: " .. tostring(err))
				end
			end)
			state.force_timer = timer
		end)
	end
	for _, name in ipairs({ "AnchorEnd", "AnchorBreak", "AnchorStop" }) do
		local sig = anchor_script:FindFirstChild(name)
		if sig then
			sig:Connect(_stopForce)
		end
	end
	if anchor_script.Destroying then
		anchor_script.Destroying:Connect(_stopForce)
	end
end

return M

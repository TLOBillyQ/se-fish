--技能系统 - server锚点逻辑：speed_add（Constant-only：可逆状态，Duration 必须 >0）
-- 语义：点火期间修改施法者移速（WalkSpeedDelta 可为负），终结时恢复原速。
-- 自监听锚点级四事件驱动。

local M = {}

function M.Attach(anchor_script)
	local RunService = game:GetService("RunService")
	if not RunService:IsServer() then
		return
	end

	local state = nil -- 本次点火私有：{ orig_speed = 原移速 }

	local function _getOwner()
		local ability_script = anchor_script.Parent
		local manager = ability_script and ability_script.Parent
		return manager and manager.Parent
	end

	-- 控制器：EggyAPI 里明确是「通过 Unit.Controller 获取」（EggyController 是类名，不是属性），
	-- 写 owner.EggyController 恒为 nil，会静默失效。
	local function _controller(owner)
		if not owner then
			return nil
		end
		return owner.Controller or owner.EggyController
	end

	local function _restore()
		local orig_speed = state and state.orig_speed
		if orig_speed then
			state.orig_speed = nil
			local ctrl = _controller(_getOwner())
			if ctrl and ctrl.WalkSpeed ~= nil then
				ctrl.WalkSpeed = orig_speed
			end
		end
	end

	local start_sig = anchor_script:FindFirstChild("AnchorStart")
	if start_sig then
		start_sig:Connect(function()
			state = {}
			local delta = anchor_script:GetAttribute("ABILITY_ANOSTATE_WALK_SPEED")
			local ctrl = _controller(_getOwner())
			if ctrl and ctrl.WalkSpeed ~= nil and delta then
				state.orig_speed = ctrl.WalkSpeed
				ctrl.WalkSpeed = state.orig_speed + delta
			end
		end)
	end
	for _, name in ipairs({ "AnchorEnd", "AnchorBreak", "AnchorStop" }) do
		local sig = anchor_script:FindFirstChild(name)
		if sig then
			sig:Connect(_restore)
		end
	end
	if anchor_script.Destroying then
		anchor_script.Destroying:Connect(_restore)
	end
end

return M

--技能系统 - server锚点逻辑：play_body_animation（Constant）
-- 语义：点火时在施法者身上播放动画（半身/循环/起始点/速率），终结时停止。
-- 播放时长由锚点 Duration 控制，到时自动停止。
-- 自监听锚点级四事件驱动。

local M = {}

function M.Attach(anchor_script)
	local RunService = game:GetService("RunService")
	if not RunService:IsServer() then
		return
	end

	local state = nil -- 本次点火私有：{ track = 动画 Track }

	local function _stopTrack()
		local track = state and state.track
		if track then
			state.track = nil
			local ok, err = pcall(function()
				track:Stop()
			end)
			if not ok then
				print("[play_body_animation] stop track err: " .. tostring(err))
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
			local name = anchor_script:GetAttribute("ABILITY_ANOSTATE_ANIMKEY")
			if not owner or not owner.Animator or not name then
				return
			end
			local track = owner.Animator:LoadAnimation(name)
			if track == nil then
				return
			end
			if anchor_script:GetAttribute("ABILITY_ANOSTATE_ANIM_HALF") == true then
				-- Enums.AnimationFilterType 没有 UpperBody 成员，写它会得到 nil 并在赋值时报错，
				-- 被 pcall 吞掉后 track:Play 不执行 → 没动作。上半身用位掩码 30（Head|Trunk|LeftArm|RightArm）。
				track.FilterType = 30
			end
			local loop = anchor_script:GetAttribute("ABILITY_ANOSTATE_LOOP")
			if loop ~= nil then
				track.Looped = loop
			end
			local start_point = anchor_script:GetAttribute("ABILITY_ANOSTATE_ANIM_STARTPOINT")
			if start_point ~= nil and start_point > 0 then
				track.TimePosition = start_point
			end
			local speed = anchor_script:GetAttribute("ABILITY_ANOSTATE_ANIM_SPEED") or 1
			track:Play(0.1, 1, speed)
			state.track = track
		end)
	end
	for _, name in ipairs({ "AnchorEnd", "AnchorBreak", "AnchorStop" }) do
		local sig = anchor_script:FindFirstChild(name)
		if sig then
			sig:Connect(_stopTrack)
		end
	end
	if anchor_script.Destroying then
		anchor_script.Destroying:Connect(_stopTrack)
	end
end

return M

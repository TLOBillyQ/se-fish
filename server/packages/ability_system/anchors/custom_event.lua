--技能系统 - server锚点逻辑：custom_event（Instant）
-- 语义：点火时触发一次世界自定义事件（World.CustomEvent[EventName]:Fire()）。
-- 自监听锚点级 AnchorStart 驱动；Instant 无终结语义。

local M = {}

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
		local event_name = anchor_script:GetAttribute("ABILITY_ANOSTATE_EVENT_NAME")
		if event_name then
			game:GetService("World").CustomEvent[event_name]:Fire()
		end
	end)
end

return M

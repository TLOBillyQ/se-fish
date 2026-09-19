--技能系统 - server锚点逻辑：cast_face_target（Instant）
-- 语义：点火时把施法者朝向旋转到释放方向（仅水平 yaw，忽略俯仰）。
-- 自监听锚点级 AnchorStart 驱动；Instant 无终结语义。

local AbilityRegistry = require("common.packages.ability_system.registry")

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
		local ability_script = anchor_script.Parent
		local manager = ability_script and ability_script.Parent
		local owner = manager and manager.Parent
		local handler = ability_script and AbilityRegistry.getAbilityHandler(ability_script)
		local dir = handler and handler.getReleaseDirection and handler.getReleaseDirection()
		if owner and dir then
			local yaw = math.atan(dir.x, dir.z)
			owner.Rotation = Quaternion.FromEulerAngles(0, yaw, 0)
		end
	end)
end

return M

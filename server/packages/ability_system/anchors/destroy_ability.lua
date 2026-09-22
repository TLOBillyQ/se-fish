--技能系统 - server锚点逻辑：destroy_ability（Instant）
-- 语义：点火时把宿主能力从管理器移除。
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
		if not manager then
			return
		end
		local slot_index = ability_script:GetAttribute("Index")
		local manager_handler = AbilityRegistry.getAbilityHandler(manager)
		if manager_handler and manager_handler.removeAbility then
			manager_handler.removeAbility(slot_index)
		end
	end)
end

return M

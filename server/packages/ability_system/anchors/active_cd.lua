--技能系统 - server锚点逻辑：active_cd（Instant）
-- 语义：点火时让宿主能力进入 CD（cdTime 缺省读能力自身 CdTime 属性）。
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
		local handler = ability_script and AbilityRegistry.getAbilityHandler(ability_script)
		if handler then
			handler.enterCD()
		end
	end)
end

return M

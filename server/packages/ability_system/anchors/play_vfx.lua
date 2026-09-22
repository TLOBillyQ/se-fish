--技能系统 - server锚点逻辑：play_vfx（Instant）
-- 语义：点火时在施法者位置创建一次性 3D 音效（SoundUnit 自带 Duration，到点自灭）。
-- CampRoleId 固定传 0：所有玩家可听。

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
		local caster = manager and manager.Parent
		local sound_key = anchor_script:GetAttribute("ABILITY_ANOSTATE_NEW_SOUND")
		if not caster or not sound_key then
			return
		end
		local values = {
			SoundId = sound_key,
			Position = caster.Position,
			Volume = anchor_script:GetAttribute("Volume") or 50.0,
			Speed = 1.0,
			Duration = anchor_script:GetAttribute("SoundDuration") or 1.0,
			CampRoleId = 0,
			SoundType = "3D",
			UnitType = "SoundUnit",
			needInit = true,
		}
		game:GetService("World"):CreateUnit("SoundUnit", values)
	end)
end

return M

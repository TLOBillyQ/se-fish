--技能系统 - server锚点逻辑：play_sfx（Constant：Bind=true 时必须 Duration>0）
-- 语义：点火时在施法者位置（+偏移）创建特效；Bind=true 时附着跟随；终结时销毁。
-- 自监听锚点级四事件驱动。

local M = {}

function M.Attach(anchor_script)
	local RunService = game:GetService("RunService")
	if not RunService:IsServer() then
		return
	end

	local state = nil -- 本次点火私有：{ sfx = 特效 Unit }

	local function _destroySfx()
		local sfx = state and state.sfx
		if sfx then
			state.sfx = nil
			local ok, err = pcall(function()
				sfx:Destroy()
			end)
			if not ok then
				print("[play_sfx] destroy sfx err: " .. tostring(err))
			end
		end
	end

	local start_sig = anchor_script:FindFirstChild("AnchorStart")
	if start_sig then
		start_sig:Connect(function()
			state = {}
			local ability_script = anchor_script.Parent
			local manager = ability_script and ability_script.Parent
			local caster = manager and manager.Parent
			local sfx_id = anchor_script:GetAttribute("ABILITY_ANOSTATE_NEW_SFX")
			if not caster or not sfx_id then
				return
			end
			local offset = anchor_script:GetAttribute("Offset") or Vector3.New(0, 0, 0)
			local scale_val = anchor_script:GetAttribute("ABILITY_ANOSTATE_SCALE") or 1.0
			local scale = Vector3.New(scale_val, scale_val, scale_val)
			local rot = Quaternion.New(0, 0, 0, 1)
			local pos = caster.Position + offset
			local units = game:GetService("World"):LoadUnitAssetByRPS(sfx_id, pos, rot, scale)
			if units and units[1] then
				local sfx = units[1]
				sfx.Duration = -1
				if anchor_script:GetAttribute("ABILITY_ANOSTATE_BIND") == true then
					sfx:StartposAttach(caster, "origin", offset)
				end
				state.sfx = sfx
			end
		end)
	end
	for _, name in ipairs({ "AnchorEnd", "AnchorBreak", "AnchorStop" }) do
		local sig = anchor_script:FindFirstChild(name)
		if sig then
			sig:Connect(_destroySfx)
		end
	end
	if anchor_script.Destroying then
		anchor_script.Destroying:Connect(_destroySfx)
	end
end

return M

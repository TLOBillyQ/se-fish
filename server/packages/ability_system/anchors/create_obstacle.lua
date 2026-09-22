--技能系统 - server锚点逻辑：create_obstacle（Instant）
-- 点火时在施法者位置（+偏移）生成障碍物；Bind=true 时挂为 owner 子节点；
-- LifeDuration 到时销毁。实体自管生命周期（Instant 无终结语义）。

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
		if not owner then
			return
		end
		local prefab = anchor_script:GetAttribute("ABILITY_ANOSTATE_NEW_OBJ")
		local obj_pos = owner.Position
			+ (anchor_script:GetAttribute("Offset") or Vector3.New(0, 0, 0))
		-- 朝向取单位四元数（不旋转）
		local obj_rot = Quaternion.New(0, 0, 0, 1)
		local obj_scale = anchor_script:GetAttribute("Scale")
		local units = game:GetService("World"):LoadUnitAssetByRPS(
			prefab,
			obj_pos,
			obj_rot,
			obj_scale,
			{ resolveSkinFrom = ability_script }
		)
		local obj = units and units[1] or nil
		if not obj then
			return
		end
		if anchor_script:GetAttribute("ABILITY_ANOSTATE_BIND") == true then
			obj.Parent = owner
		end
		-- LifeDuration 到时自毁（实体自管生命周期）
		local life_dur = anchor_script:GetAttribute("ABILITY_ANOSTATE_LIFE_DUR")
		if life_dur then
			game:GetService("TimerService"):CreateTimer(1, life_dur, false, function()
				pcall(function()
					obj:Destroy()
				end)
			end)
		end
	end)
end

return M

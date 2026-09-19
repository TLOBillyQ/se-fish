--技能系统 - server锚点逻辑：add_bind_diy_model（Constant）
-- 语义：点火时创建模型挂到施法者骨骼插槽，终结时销毁。
-- 插槽/偏移由 Socket/Offset 属性配置，默认 origin/(0,3,0)。
-- 自监听锚点级四事件驱动。

local M = {}

function M.Attach(anchor_script)
	local RunService = game:GetService("RunService")
	if not RunService:IsServer() then
		return
	end

	local state = nil -- 本次点火私有：{ model = 模型 Unit }

	local function _destroyModel()
		local model = state and state.model
		if model then
			state.model = nil
			local ok, err = pcall(function()
				model:Destroy()
			end)
			if not ok then
				print("[bind_custom_model] destroy model err: " .. tostring(err))
			end
		end
	end

	local start_sig = anchor_script:FindFirstChild("AnchorStart")
	if start_sig then
		start_sig:Connect(function()
			state = {}
			local ability_script = anchor_script.Parent
			local manager = ability_script and ability_script.Parent
			local eggy_unit = manager and manager.Parent
			local unit_prefab = anchor_script:GetAttribute("ABILITY_ANOSTATE_USE_PERFAB")
			if not eggy_unit or not unit_prefab then
				return
			end
			local socket = anchor_script:GetAttribute("Socket") or "origin"
			local offset = anchor_script:GetAttribute("Offset") or Vector3.New(0.0, 3.0, 0.0)
			local spawn_pos = eggy_unit:GetPosition() or Vector3.New(0, 0, 0)
			local spawn_rot = eggy_unit:GetRotation() or Quaternion.New(0, 0, 0, 1)
			local rst_units = game:GetService("World"):LoadUnitAssetByRPS(
				unit_prefab,
				spawn_pos,
				spawn_rot,
				Vector3.New(1, 1, 1),
				{ resolveSkinFrom = ability_script }
			)
			if rst_units and #rst_units > 0 then
				local model = rst_units[1]
				eggy_unit:MountOnSkeletalSocket(model, socket, offset, Quaternion.New(0, 0, 0, 1))
				state.model = model
			end
		end)
	end
	for _, name in ipairs({ "AnchorEnd", "AnchorBreak", "AnchorStop" }) do
		local sig = anchor_script:FindFirstChild(name)
		if sig then
			sig:Connect(_destroyModel)
		end
	end
	if anchor_script.Destroying then
		anchor_script.Destroying:Connect(_destroyModel)
	end
end

return M

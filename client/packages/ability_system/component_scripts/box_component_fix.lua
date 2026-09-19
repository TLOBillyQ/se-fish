--技能系统 - client组件位置修正脚本
--垫脚石/弹板等"施放时在脚下生成组件"技能专用。
-- 挂载：作为 Ability ScriptUnit 的直接子节点 LocalScript；script.Parent = 技能壳（客户端镜像）。
-- 流程：收到服务器 FireClient → 等待 unit 同步 + NetworkOwner → 用本地瞬时位置修正坐标 →
--       设为可见（拥有端写入会回同步到服务器，其余客户端随后可见）。
-- 注意：仅拥有端执行（FireClient 定向本机 + 技能树按网络所有权只在拥有端跑）。

if not game:GetService("RunService"):IsClient() then
	print("[box component local] ERROR: this script must be a LocalScript, abort")
	return
end

local World = game:GetService("World")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local abilityScript = script.Parent
if not abilityScript then
	print("[box component local] ERROR: parent nil")
	return
end

local _createdEvent =
	game:CreateRemoteEvent("BoxComponentCreated_" .. tostring(abilityScript.UnitId))

-- 每帧轮询条件，最多 maxRetries 帧 (~0.83s)
local function _waitFor(predicate, maxRetries)
	for _ = 1, maxRetries do
		if predicate() then
			return true
		end
		RunService.Heartbeat:Wait()
	end
	return false
end

_createdEvent.OnClientEvent:Connect(function(unitId, serverOffset, serverRot)
	local localPlayer = Players.LocalPlayer
	if not localPlayer or not localPlayer.Character then
		return
	end

	-- 校验是本地施法者的技能树：ability → manager → caster
	local caster = abilityScript.Parent and abilityScript.Parent.Parent
	if not caster then
		return
	end

	local okId, casterId = pcall(function()
		return caster.UnitId
	end)
	local okChar, charId = pcall(function()
		return localPlayer.Character.UnitId
	end)
	if caster ~= localPlayer.Character and not (okId and okChar and casterId == charId) then
		return
	end

	local unit
	if
		not _waitFor(function()
			unit = World:GetUnitByID(unitId)
			return unit ~= nil
		end, 50)
	then
		print("[box component local] ERROR: unit not found after retries, id =", unitId)
		return
	end

	-- 等 NetworkOwner 同步到本机，确保 SetPosition 具有权威性
	if
		not _waitFor(function()
			return unit.IsNetworkOwnerSide and unit:IsNetworkOwnerSide()
		end, 50)
	then
		print("[box component local] ERROR: NetworkOwner NOT synced, id =", unitId)
		return
	end

	local owner = caster
	local pos = owner:GetPosition() + serverOffset
	unit:SetPosition(pos)
	if serverRot and unit.SetRotation then
		unit:SetRotation(serverRot)
	end
	unit.ModelVisible = true
	print("[box component local] unit visible, id =", unitId)
end)

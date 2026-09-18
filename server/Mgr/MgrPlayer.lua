local Task = game:GetService("Task")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local World = game:GetService("World")
local Mgr = {}
Mgr.PlayerSignal = {}

function Mgr:Start()
end

function Mgr:GetPlayerUnit(player)
	if not player then 
		print("[MgrPlayer]MgrPlayer:GetPlayerUnit() no player")
		return
	end

	local playerUnit = player.Character
	if not playerUnit then
		print("[MgrPlayer] MgrPlayer:GetPlayerUnit() not character")
	end
	return playerUnit
end

local function GetPlayerControl(player)
	local character = player.Character
	if character and character.EggyController then
		local ctrl = character.EggyController
		return ctrl
	end
end

function Mgr:OnPlayerAdded(player)
	GetPlayerControl(player)
	local checkCharAddLinkMap = self.PlayerSignal[player.UserId]
	if checkCharAddLinkMap then
		return
	end

	checkCharAddLinkMap = {}
	checkCharAddLinkMap["CharacterAdded"] = player.CharacterAdded:Connect(function(character)
		local eggy = self:GetPlayerUnit(player)
		GetPlayerControl(player)

		if not eggy:HasTag("Player") then
			eggy:AddTag("Player")
		end
	end)

	checkCharAddLinkMap["CharacterRemoving"] = player.CharacterRemoving:Connect(function(character)
		print("[MgrPlayer] CharacterRemoving")
	end)
	self.PlayerSignal[player.UserId] = checkCharAddLinkMap
end

function Mgr:OnPlayerRemoving(player)
    print("[MgrPlayer]玩家正在离开:", player.Name)
	local checkCharAddLinkMap = self.PlayerSignal[player.UserId]
	if checkCharAddLinkMap then
		self.PlayerSignal[player.UserId] = nil
		for k, v in checkCharAddLinkMap do
			v:Disconnect()
		end	
	end
	-- 在此处执行清理逻辑，例如移除玩家相关的 UI、数据或资源
end

function Mgr:Update(deltaTime)
    
end

return Mgr
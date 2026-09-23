local PlayerData = require('server.Data.PlayerData')
local Mgr = {}
local DataMap = {}

function Mgr:GetDataInst(player)
    local data = player and DataMap[player.UserId]
    if data and data.Player == player and data.Inited then return data end
end

function Mgr:SendItemBar(player)
    local data = self:GetDataInst(player)
    if not data then return end
    _G.REUtil:GetRE('ItemBarState'):FireClient(player, data:GetItemBarSnapshot())
end

function Mgr:OnPlayerAdded(player)
    local current = DataMap[player.UserId]
    if current and current.Player == player then return end
    if current then current:Destroy() end
    local data = PlayerData.New(player)
    DataMap[player.UserId] = data
    data:Init()
    self:SendItemBar(player)
end

function Mgr:OnPlayerRemoving(player)
    local data = DataMap[player.UserId]
    if data and data.Player == player then
        DataMap[player.UserId] = nil
        data:Destroy()
    end
end

function Mgr:Start()
    _G.REUtil:GetRE('RequestItemBar').OnServerEvent:Connect(function(player)
        self:SendItemBar(player)
    end)
end

_G.MgrPlayerData = Mgr
return Mgr

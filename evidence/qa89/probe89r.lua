-- #89 复验探针（server 端）：评审修复后主流程回归
local GameCfg = require('common.GameCfg')
local MgrFerry = require('server.Mgr.MgrFerry')
local MgrPlayerData = _G.MgrPlayerData
local Task = game:GetService('Task')

local player = game:GetService('Players'):GetPlayers()[1]
local data = MgrPlayerData:GetDataInst(player)
local ferry = GameCfg.Ferry

data:GrantItem('shrimpTicket', 1)
player.Character.Position = Vector3.New(-6, 2.5, 25)
local ok1 = MgrFerry:Handle(player, { action = 'Board', seq = 1 })
print('PROBE89R board ok=' .. tostring(ok1) .. ' ticket=' .. data:ItemCount('shrimpTicket'))

Task:Delay(ferry.Outbound.CountdownSec + 1.5, function()
    local pos = player.Character.Position
    local dest = ferry.Outbound.Destination
    print('PROBE89R outbound hit=' .. tostring(math.abs(pos.x - dest.x) < 1 and math.abs(pos.z - dest.z) < 1)
        .. ' zone=' .. tostring(data.Data.Zone))
    data:AddCoin(ferry.Return.Price, nil, 'probe')
    player.Character.Position = Vector3.New(101, 6, 102)
    local ok2 = MgrFerry:Handle(player, { action = 'Return', seq = 2 })
    local home = ferry.Return.Destination
    local back = player.Character.Position
    print('PROBE89R return ok=' .. tostring(ok2) .. ' coin=' .. data.Data.FishCoin
        .. ' hit=' .. tostring(math.abs(back.x - home.x) < 1 and math.abs(back.z - home.z) < 1)
        .. ' zone=' .. tostring(data.Data.Zone))
    print('PROBE89R DONE')
end)

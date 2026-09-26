-- #89 试玩验收探针（server 端）：交票倒计时去程（含搭便船范围判定）、按人付费返程、船票消耗
local GameCfg = require('common.GameCfg')
local MgrFerry = require('server.Mgr.MgrFerry')
local MgrPlayerData = _G.MgrPlayerData
local Task = game:GetService('Task')

local player = game:GetService('Players'):GetPlayers()[1]
local data = MgrPlayerData:GetDataInst(player)
local world = game:GetService('World')
local ferry = GameCfg.Ferry

-- 场景核对：两个锚点与平台
for _, name in ipairs({ 'FerryBoat', 'FerryReturn', '星光地板' }) do
    local ok, unit = pcall(world.FindFirstChild, world, name)
    print('PROBE89 scene ' .. name .. ' @ ' .. tostring(ok and unit and unit.Position))
end

-- ① 去程：交 1 张船票
data:GrantItem('shrimpTicket', 1)
player.Character.Position = Vector3.New(-6, 2.5, 25)
local ok1 = MgrFerry:Handle(player, { action = 'Board', seq = 1 })
print('PROBE89 board ok=' .. tostring(ok1) .. ' ticket=' .. data:ItemCount('shrimpTicket')
    .. ' departAt=' .. tostring(MgrFerry.DepartAt))

Task:Delay(ferry.Outbound.CountdownSec + 1.5, function()
    local pos = player.Character.Position
    local dest = ferry.Outbound.Destination
    print('PROBE89 outbound pos=' .. tostring(pos) .. ' zone=' .. tostring(data.Data.Zone)
        .. ' hit=' .. tostring(math.abs(pos.x - dest.x) < 1 and math.abs(pos.z - dest.z) < 1))

    -- ② 返程：金币刚好够价
    data:AddCoin(ferry.Return.Price, nil, 'probe')
    player.Character.Position = Vector3.New(101, 6, 102)
    local ok2 = MgrFerry:Handle(player, { action = 'Return', seq = 2 })
    local back = player.Character.Position
    local home = ferry.Return.Destination
    print('PROBE89 return ok=' .. tostring(ok2) .. ' coin=' .. data.Data.FishCoin
        .. ' pos=' .. tostring(back) .. ' zone=' .. tostring(data.Data.Zone)
        .. ' hit=' .. tostring(math.abs(back.x - home.x) < 1 and math.abs(back.z - home.z) < 1))

    -- ③ 返程金币不足被拒
    player.Character.Position = Vector3.New(101, 6, 102)
    data:SetZone('shrimpPond')
    local ok3 = MgrFerry:Handle(player, { action = 'Return', seq = 3 })
    print('PROBE89 poorReturn ok=' .. tostring(ok3) .. ' zone=' .. tostring(data.Data.Zone))
    print('PROBE89 DONE')
end)

-- #89 摆渡（GameSpec §8.3 已确认细则）：去程一人交 1 张船票、倒计时后带走船上所有玩家
-- （搭便船合法）；返程按人付金币、立即出发；区域写入 PlayerData.Data.Zone（#92 存档用）。
-- 失败方式（先列后写）：
--   1. 没船票也能开船，或船票扣了却不开船、一次乘船扣两张票；
--   2. 倒计时没结束就传送，或到点不传送；倒计时中再交票被吞（应拒绝且不扣）；
--   3. 到点只带走交票人（搭便船失败），或把船范围外的玩家也带走；
--   4. 返程不验金币 / 金币不足也传送 / 一人付费两人回家 / 传送失败不退款；
--   5. 落点不是配置的目的地，或 Zone 不更新（去程 shrimpPond、返程 fishPond1）；
--   6. seq 重放 / 旧序号重复结算（重复扣票扣金币）；
--   7. 船范围内有角色缺失的玩家时整个传送崩掉，其余玩家也走不了。
local lu = require('luaunit')

TestFerry = {}

local function vec(x, y, z) return { x = x, y = y, z = z } end

local function signal()
    local slots = {}
    return {
        Connect = function(_, fn)
            slots[#slots + 1] = fn
            return { Disconnect = function() end }
        end,
        Fire = function(_, ...) for _, fn in ipairs(slots) do fn(...) end end,
    }
end

-- 假角色：SetPosition 搬动 Position；记录传送次数
local function newPlayer(userId, x, y, z)
    local player = { UserId = userId, teleports = 0 }
    player.Character = {
        Position = vec(x, y, z),
        SetPosition = function(self, pos)
            self.Position = pos
            player.teleports = player.teleports + 1
        end,
    }
    player.SetAttribute = function() end
    return player
end

function TestFerry:setUp()
    local env = self
    self.saved = {
        game = rawget(_G, 'game'), Vector3 = rawget(_G, 'Vector3'), REUtilG = rawget(_G, 'REUtil'),
        GameCfg = package.loaded['common.GameCfg'],
        REUtil = package.loaded['common.REUtil'],
        PlayerData = package.loaded['server.Mgr.MgrPlayerData'],
    }
    package.loaded['common.GameCfg'] = nil
    self.cfg = require('common.GameCfg')
    self.cfg.Debug = { Enabled = false }
    _G.Vector3 = { New = vec }

    local PlayerData = assert(loadfile('server/Data/PlayerData.lua'))()
    self.players = {
        newPlayer(1, -8, 2.2, 24),   -- 船边（去程锚点 (-8, 1.2, 24.5) 附近）
        newPlayer(2, -9, 2.2, 26),   -- 船边搭便船
        newPlayer(3, 6.26, 5, 39.29), -- 远处出生点，不上船
    }
    self.data = {}
    for _, player in ipairs(self.players) do
        self.data[player.UserId] = PlayerData.New(player, function() end)
        self.data[player.UserId]:Init()
    end

    self.now = 100
    self.sent = {}
    self.broadcasts = {}
    local reStub = {
        GetRE = function(_, name)
            env.sent[name] = env.sent[name] or {}
            return {
                OnServerEvent = signal(),
                FireClient = function(_, player, payload)
                    env.sent[name][#env.sent[name] + 1] = { userId = player.UserId, payload = payload }
                end,
                FireAllClients = function(_, payload)
                    env.broadcasts[#env.broadcasts + 1] = payload
                end,
            }
        end,
        CheckRECD = function() return false end,
    }
    package.loaded['common.REUtil'] = reStub
    _G.REUtil = reStub
    package.loaded['server.Mgr.MgrPlayerData'] = {
        GetDataInst = function(_, player) return env.data[player.UserId] end,
        SendItemBar = function() end,
    }

    self.mgr = assert(loadfile('server/Mgr/MgrFerry.lua'))()
    self.mgr.World = { GetServerTime = function() return env.now end }
    -- 锚点用配置里的名字注册假位置；InRange 复刻「Radius+Slack 内（只看 x/z）」契约
    self.anchors = {
        FerryBoat = { Position = vec(-8, 1.2, 24.5) },
        FerryReturn = { Position = vec(100, 6, 103) },
    }
    self.mgr.Interact = {
        FindAnchor = function(_, name) return env.anchors[name] end,
        InRange = function(_, player, point)
            local anchor = env.anchors[point.AnchorName]
            local pos = player.Character and player.Character.Position
            if not anchor or not pos then return nil end
            local dx, dz = pos.x - anchor.Position.x, pos.z - anchor.Position.z
            if math.sqrt(dx * dx + dz * dz) > point.Radius + point.Slack then return nil end
            return anchor
        end,
    }
    self.mgr.PlayerData = package.loaded['server.Mgr.MgrPlayerData']
    self.mgr.OnlinePlayers = function() return env.players end
end

function TestFerry:tearDown()
    package.loaded['common.GameCfg'] = self.saved.GameCfg
    package.loaded['common.REUtil'] = self.saved.REUtil
    package.loaded['server.Mgr.MgrPlayerData'] = self.saved.PlayerData
    _G.game = self.saved.game
    _G.Vector3 = self.saved.Vector3
    _G.REUtil = self.saved.REUtilG
end

function TestFerry:lastReply(userId)
    local list = self.sent.FerryResult or {}
    for index = #list, 1, -1 do
        if list[index].userId == userId then return list[index].payload end
    end
end

function TestFerry:board(userId, seq)
    return self.mgr:Handle(self.players[userId], { action = 'Board', seq = seq })
end

function TestFerry:sail()
    self.now = self.now + self.cfg.Ferry.Outbound.CountdownSec
    self.mgr:Update()
end

-- 配置钉住：船票、倒计时、票价、区域名与落点
function TestFerry:test_config_pins()
    local ferry = self.cfg.Ferry
    lu.assertEquals(ferry.Outbound.Ticket, 'shrimpTicket')
    lu.assertEquals(ferry.Outbound.Zone, 'shrimpPond')
    lu.assertEquals(ferry.Return.Zone, 'fishPond1')
    lu.assertEquals(ferry.HomeZone, 'fishPond1')
    lu.assertNotNil(ferry.Outbound.CountdownSec)
    lu.assertNotNil(ferry.Outbound.BoatRange)
    lu.assertNotNil(ferry.Return.Price)
    lu.assertNotNil(self.cfg.Items.Definitions[ferry.Outbound.Ticket])
end

function TestFerry:test_zone_defaults_to_home()
    lu.assertEquals(self.data[1].Data.Zone, 'fishPond1')
end

function TestFerry:test_board_requires_ticket_and_consumes_exactly_one()
    lu.assertFalse(self:board(1, 1))
    lu.assertEquals(self:lastReply(1).reason, 'ticket')
    lu.assertNil(self.mgr.DepartAt)
    lu.assertTrue(self.data[1]:AddItem('shrimpTicket'))
    lu.assertTrue(self.data[1]:AddItem('shrimpTicket'))
    lu.assertTrue(self:board(1, 2))
    lu.assertEquals(self.data[1]:ItemCount('shrimpTicket'), 1)
    lu.assertNotNil(self.mgr.DepartAt)
    lu.assertTrue(self:lastReply(1).ok)
    lu.assertEquals((self.broadcasts[#self.broadcasts]).phase, 'countdown')
end

function TestFerry:test_board_replay_and_stale_seq_rejected()
    lu.assertTrue(self.data[1]:AddItem('shrimpTicket'))
    lu.assertTrue(self.data[1]:AddItem('shrimpTicket'))
    lu.assertTrue(self:board(1, 5))
    lu.assertFalse(self:board(1, 5))
    lu.assertFalse(self:board(1, 4))
    lu.assertEquals(self.data[1]:ItemCount('shrimpTicket'), 1)
end

function TestFerry:test_second_ticket_during_countdown_rejected_not_consumed()
    lu.assertTrue(self.data[1]:AddItem('shrimpTicket'))
    lu.assertTrue(self.data[2]:AddItem('shrimpTicket'))
    lu.assertTrue(self:board(1, 1))
    lu.assertFalse(self:board(2, 1))
    lu.assertEquals(self:lastReply(2).reason, 'sailing')
    lu.assertEquals(self.data[2]:ItemCount('shrimpTicket'), 1)
end

function TestFerry:test_no_departure_before_countdown_ends()
    lu.assertTrue(self.data[1]:AddItem('shrimpTicket'))
    lu.assertTrue(self:board(1, 1))
    self.now = self.now + self.cfg.Ferry.Outbound.CountdownSec - 0.5
    self.mgr:Update()
    lu.assertEquals(self.players[1].teleports, 0)
    lu.assertNotNil(self.mgr.DepartAt)
end

function TestFerry:test_departure_takes_everyone_in_boat_range_only()
    lu.assertTrue(self.data[1]:AddItem('shrimpTicket'))
    lu.assertTrue(self:board(1, 1))
    self:sail()
    local dest = self.cfg.Ferry.Outbound.Destination
    for _, userId in ipairs({ 1, 2 }) do
        lu.assertEquals(self.players[userId].teleports, 1)
        lu.assertEquals(self.players[userId].Character.Position, vec(dest.x, dest.y, dest.z))
        lu.assertEquals(self.data[userId].Data.Zone, 'shrimpPond')
    end
    -- 范围外的不动
    lu.assertEquals(self.players[3].teleports, 0)
    lu.assertEquals(self.data[3].Data.Zone, 'fishPond1')
    lu.assertNil(self.mgr.DepartAt)
    lu.assertEquals((self.broadcasts[#self.broadcasts]).phase, 'departed')
end

function TestFerry:test_departure_skips_player_without_character()
    lu.assertTrue(self.data[1]:AddItem('shrimpTicket'))
    lu.assertTrue(self:board(1, 1))
    self.players[2].Character = nil
    self:sail()
    lu.assertEquals(self.players[1].teleports, 1)
    lu.assertEquals(self.players[3].teleports, 0)
end

local function moveTo(player, anchor)
    player.Character.Position = vec(anchor.Position.x + 1, anchor.Position.y, anchor.Position.z)
end

function TestFerry:test_return_charges_each_player_and_teleports_immediately()
    local point = self.cfg.Ferry.Return
    moveTo(self.players[1], self.anchors.FerryReturn)
    moveTo(self.players[2], self.anchors.FerryReturn)
    lu.assertTrue(self.data[1]:AddCoin(point.Price, nil, 'test'))
    self.data[1].Data.Zone = 'shrimpPond'
    self.data[2].Data.Zone = 'shrimpPond'
    lu.assertTrue(self.mgr:Handle(self.players[1], { action = 'Return', seq = 1 }))
    lu.assertEquals(self.data[1].Data.FishCoin, 0)
    lu.assertEquals(self.players[1].Character.Position,
        vec(point.Destination.x, point.Destination.y, point.Destination.z))
    lu.assertEquals(self.data[1].Data.Zone, 'fishPond1')
    -- 没付费的搭不了返程
    lu.assertFalse(self.mgr:Handle(self.players[2], { action = 'Return', seq = 1 }))
    lu.assertEquals(self:lastReply(2).reason, 'coin')
    lu.assertEquals(self.players[2].teleports, 0)
    lu.assertEquals(self.data[2].Data.Zone, 'shrimpPond')
end

function TestFerry:test_return_refunds_when_teleport_fails()
    local point = self.cfg.Ferry.Return
    moveTo(self.players[1], self.anchors.FerryReturn)
    lu.assertTrue(self.data[1]:AddCoin(point.Price, nil, 'test'))
    self.players[1].Character = nil
    lu.assertFalse(self.mgr:Handle(self.players[1], { action = 'Return', seq = 1 }))
    lu.assertEquals(self.data[1].Data.FishCoin, point.Price)
end

function TestFerry:test_actions_require_range()
    lu.assertTrue(self.data[3]:AddItem('shrimpTicket'))
    lu.assertFalse(self:board(3, 1)) -- 出生点离船太远
    lu.assertEquals(self:lastReply(3).reason, 'range')
    lu.assertEquals(self.data[3]:ItemCount('shrimpTicket'), 1)
    lu.assertTrue(self.data[3]:AddCoin(self.cfg.Ferry.Return.Price, nil, 'test'))
    lu.assertFalse(self.mgr:Handle(self.players[3], { action = 'Return', seq = 2 }))
    lu.assertEquals(self.data[3].Data.FishCoin, self.cfg.Ferry.Return.Price)
end

-- 锚点缺失是场景配置事故：航班取消、退票给交票人、广播 cancelled 让客户端收倒计时条
function TestFerry:test_missing_anchor_cancels_and_refunds_ticket()
    lu.assertTrue(self.data[1]:AddItem('shrimpTicket'))
    lu.assertTrue(self:board(1, 1))
    self.anchors.FerryBoat = nil
    self:sail()
    lu.assertEquals(self.data[1]:ItemCount('shrimpTicket'), 1)
    lu.assertEquals(self.players[1].teleports, 0)
    lu.assertEquals((self.broadcasts[#self.broadcasts]).phase, 'cancelled')
end

function TestFerry:test_return_teleport_failure_reports_teleport_reason()
    local point = self.cfg.Ferry.Return
    moveTo(self.players[1], self.anchors.FerryReturn)
    lu.assertTrue(self.data[1]:AddCoin(point.Price, nil, 'test'))
    -- 人在范围内但引擎拒绝传送（SetPosition 抛错），命中退款 + 'teleport' 分支
    self.players[1].Character.SetPosition = function() error('boom') end
    lu.assertFalse(self.mgr:Handle(self.players[1], { action = 'Return', seq = 1 }))
    lu.assertEquals(self:lastReply(1).reason, 'teleport')
    lu.assertEquals(self.data[1].Data.FishCoin, point.Price)
end

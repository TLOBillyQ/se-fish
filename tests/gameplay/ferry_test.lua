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
-- #123 失败方式：持久化前扣费/倒计时/传送/成功回包；并发交票；存储失败重试双扣；
-- 传送异常裸退款；取消航班退款无身份；断线后的恢复记录丢失；requestId 跨会话重放。
-- seam：Handle + Update 生命周期，真实 MgrSave/PlayerData，仅替换引擎和 DataStore 边界。
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
        FerryCfg = self.cfg and self.cfg.Ferry,
        REUtil = package.loaded['common.REUtil'],
        PlayerData = package.loaded['server.Mgr.MgrPlayerData'],
        DataClass = package.loaded['server.Data.PlayerData'],
    }
    package.loaded['common.GameCfg'] = nil
    self.cfg = require('common.GameCfg')
    self.cfg.Debug = { Enabled = false }
    self.ferryCfg = self.saved.FerryCfg
        and { HomeZone = self.saved.FerryCfg.HomeZone, Outbound = self.saved.FerryCfg.Outbound,
            Return = self.saved.FerryCfg.Return }
        or { HomeZone = self.cfg.Ferry.HomeZone, Outbound = self.cfg.Ferry.Outbound,
            Return = self.cfg.Ferry.Return }
    self.cfg.Ferry = {
        HomeZone = self.ferryCfg.HomeZone,
        Outbound = self.ferryCfg.Outbound,
        Return = self.ferryCfg.Return,
    }
    _G.Vector3 = { New = vec }

    local PlayerDataClass = require('server.Data.PlayerData')
    self.PlayerDataClass = PlayerDataClass
    self.players = {
        newPlayer(1, -8, 2.2, 24),   -- 船边（去程锚点 (-8, 1.2, 24.5) 附近）
        newPlayer(2, -9, 2.2, 26),   -- 船边搭便船
        newPlayer(3, 6.26, 5, 39.29), -- 远处出生点，不上船
    }
    self.data = {}
    for _, player in ipairs(self.players) do
        self.data[player.UserId] = PlayerDataClass.New(player, function() end)
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
    self.values, self.queue = {}, {}
    self.defer, self.writeFailure, self.loseReply = false, false, false
    self.store = {
        GetAsync = function(_, key) return env.values[key] end,
        UpdateAsync = function(_, key, transform)
            if env.writeFailure then error('写档失败') end
            local value = transform(env.values[key])
            if value then env.values[key] = value end
            if env.loseReply then env.loseReply = false error('写成功但回包丢失') end
            return value
        end,
    }
    _G.game = { GetService = function(_, name)
        if name == 'Task' then return {
            Spawn = function(_, fn)
                if env.defer then table.insert(env.queue, fn) else fn() end
            end,
            Wait = function() end,
        } end
        if name == 'World' then return env.mgr.World end
        if name == 'Players' then return { GetPlayers = function() return env.players end } end
        if name == 'DataStoreService' then return { GetDataStore = function() return env.store end } end
    end }
    self.save = assert(loadfile('server/Mgr/MgrSave.lua'))()
    self.mgr.Save = self.save
    for _, player in ipairs(self.players) do self.save:LoadInto(player, self.data[player.UserId]) end
end

function TestFerry:drain()
    while #self.queue > 0 do table.remove(self.queue, 1)() end
end

function TestFerry:test_board_waits_for_durable_ticket_before_publishing_countdown()
    self.data[1]:AddItem('shrimpTicket')
    local before = self.data[1].Data.Containers
    self.defer = true
    lu.assertTrue(self:board(1, 1))
    lu.assertNotNil(before.itemBar[1], '落账前不能删除真实船票')
    lu.assertNil(self.mgr.DepartAt)
    lu.assertNil(self.mgr.Payer)
    lu.assertNil(self:lastReply(1))
    lu.assertEquals(#self.broadcasts, 0)
    self:drain()
    lu.assertEquals(self.data[1]:ItemCount('shrimpTicket'), 0)
    lu.assertNotNil(self.mgr.DepartAt)
    lu.assertTrue(self:lastReply(1).ok)
end

function TestFerry:test_return_waits_for_payment_and_recovery_before_teleport()
    local player, data = self.players[1], self.data[1]
    player.Character.Position = vec(101, 6, 103)
    data:AddCoin(40)
    self.defer = true
    lu.assertTrue(self.mgr:Handle(player, { action = 'Return', seq = 1 }))
    lu.assertEquals(data.Data.FishCoin, 40)
    lu.assertEquals(player.teleports, 0)
    lu.assertNil(self:lastReply(1))
    self:drain()
    lu.assertEquals(data.Data.FishCoin, 20)
    lu.assertEquals(player.teleports, 1)
    lu.assertTrue(self:lastReply(1).ok)
end

function TestFerry:test_cancelled_flight_refund_is_durable_and_retries_once()
    self.data[1]:AddItem('shrimpTicket')
    lu.assertTrue(self:board(1, 1))
    self.anchors.FerryBoat = nil
    self.writeFailure = true
    self:sail()
    lu.assertEquals(self.data[1]:ItemCount('shrimpTicket'), 0)
    lu.assertEquals(self.data[1].Data.Containers.itemBar[1].itemId, 'starterRod',
        '写入失败不能塞回船票；开发赠礼也替代不了恢复记账')
    lu.assertEquals(self.players[1].teleports, 0)
    self.writeFailure = false
    self.loseReply = true
    self.save:Update()
    self.mgr:Update()
    self.mgr:Update()
    lu.assertEquals(self.data[1]:ItemCount('shrimpTicket'), 1)
    self.save:LoadInto(self.players[1], self.data[1])
    lu.assertEquals(self.data[1]:ItemCount('shrimpTicket'), 1)
end

function TestFerry:test_rejoin_recovers_unfinished_board_once_without_starting_a_flight()
    self.data[1]:AddItem('shrimpTicket')
    self:board(1, 1)
    self.mgr:OnPlayerRemoving(self.players[1])
    local player = newPlayer(1, -8, 2.2, 24)
    local data = self.PlayerDataClass.New(player)
    self.players[1], self.data[1] = player, data
    self.save:LoadInto(player, data)
    self.mgr.DepartAt, self.mgr.Payer, self.mgr.Flight = nil, nil, nil
    self.mgr:Update()
    lu.assertEquals(data:ItemCount('shrimpTicket'), 1)
    lu.assertEquals(player.teleports, 0)
    self.mgr:Update()
    lu.assertEquals(data:ItemCount('shrimpTicket'), 1)
    lu.assertNil(self.mgr.DepartAt)
end

function TestFerry:test_departed_board_stays_consumed_after_rejoin()
    self.data[1]:AddItem('shrimpTicket')
    self:board(1, 1)
    self:sail()
    local player = newPlayer(1, 100, 6, 103)
    local data = self.PlayerDataClass.New(player)
    self.players[1], self.data[1] = player, data
    self.save:LoadInto(player, data)
    self.mgr:Update()
    lu.assertEquals(data:ItemCount('shrimpTicket'), 0)
    lu.assertEquals(data.Data.Zone, 'shrimpPond')
end

function TestFerry:test_return_operation_replay_after_rejoin_never_charges_or_teleports()
    local player, data = self.players[1], self.data[1]
    player.Character.Position = vec(101, 6, 103)
    data:AddCoin(40)
    self.mgr:Handle(player, { action = 'Return', seq = 1 })
    local operation = self:lastReply(1).operation
    lu.assertNotNil(operation, '返回服务端操作身份供跨会话补发')
    self.mgr:OnPlayerRemoving(player)
    player = newPlayer(1, 101, 6, 103)
    data = assert(loadfile('server/Data/PlayerData.lua'))().New(player)
    self.players[1], self.data[1] = player, data
    self.save:LoadInto(player, data)
    lu.assertTrue(self.mgr:Handle(player, { action = 'Return', seq = 1, requestId = operation }))
    lu.assertEquals(data.Data.FishCoin, 20)
    lu.assertEquals(player.teleports, 0)
    lu.assertTrue(self:lastReply(1).ok)
end

function TestFerry:test_leaving_during_payment_does_not_reserve_the_boat_forever()
    self.data[1]:AddItem('shrimpTicket')
    self.data[2]:AddItem('shrimpTicket')
    self.defer = true
    self:board(1, 1)
    self.mgr:OnPlayerRemoving(self.players[1])
    lu.assertTrue(self:board(2, 1))
    self:drain()
    lu.assertEquals(self.mgr.Payer, 2)
    lu.assertEquals(self.data[2]:ItemCount('shrimpTicket'), 0)
    lu.assertFalse(self:lastReply(1) and self:lastReply(1).ok or false)
end

function TestFerry:test_return_failure_keeps_durable_refund_until_storage_recovers()
    local player, data = self.players[1], self.data[1]
    player.Character.Position = vec(101, 6, 103)
    data:AddCoin(40)
    player.Character.SetPosition = function()
        self.writeFailure = true
        error('引擎拒绝传送')
    end
    self.mgr:Handle(player, { action = 'Return', seq = 1 })
    lu.assertEquals(data.Data.FishCoin, 20, '退款未落账不能裸加金币')
    lu.assertNil(self:lastReply(1), '退款未落账不能声称已处理')
    self.writeFailure = false
    self.loseReply = true
    self.save:Update()
    lu.assertEquals(data.Data.FishCoin, 40)
    lu.assertFalse(self:lastReply(1).ok)
    local operation = self:lastReply(1).operation
    lu.assertTrue(self.mgr:Handle(player, { action = 'Return', seq = 2, requestId = operation }))
    lu.assertEquals(self:lastReply(1).reason, 'teleport')
    lu.assertEquals(data.Data.FishCoin, 40)
    self.save:LoadInto(player, data)
    self.mgr:Update()
    lu.assertEquals(data.Data.FishCoin, 40)
end

function TestFerry:test_pending_board_excludes_second_payer_and_failed_write_grants_nothing()
    self.data[1]:AddItem('shrimpTicket')
    self.data[2]:AddItem('shrimpTicket')
    self.writeFailure = true
    self:board(1, 1)
    lu.assertFalse(self:board(2, 1))
    lu.assertEquals(self.data[2]:ItemCount('shrimpTicket'), 1)
    lu.assertNil(self.mgr.DepartAt)
    lu.assertNil(self.mgr.Payer)
    lu.assertEquals(#self.broadcasts, 0)
    lu.assertNil(self:lastReply(1))
    self.writeFailure = false
    self.save:Update()
    lu.assertEquals(self.mgr.Payer, 1)
    lu.assertEquals(self.data[1]:ItemCount('shrimpTicket'), 0)
end

function TestFerry:test_missing_save_and_forged_request_never_grant_travel()
    self.data[1]:AddItem('shrimpTicket')
    self.mgr.Save = nil
    lu.assertFalse(self:board(1, 1))
    self.mgr.Save = self.save
    lu.assertFalse(self.mgr:Handle(self.players[1], { action = 'Board', seq = 2,
        requestId = { id = '1:99', sequence = 99, kind = 'ferry:board', requestKey = 'forged' } }))
    lu.assertFalse(self:board(1, math.huge))
    lu.assertEquals(self.data[1]:ItemCount('shrimpTicket'), 1)
    lu.assertNil(self.mgr.DepartAt)
end

function TestFerry:test_return_callback_after_leaving_never_teleports()
    local player, data = self.players[1], self.data[1]
    player.Character.Position = vec(101, 6, 103)
    data:AddCoin(40)
    self.defer = true
    self.mgr:Handle(player, { action = 'Return', seq = 1 })
    self.mgr:OnPlayerRemoving(player)
    self:drain()
    lu.assertEquals(player.teleports, 0)
    lu.assertNil(self:lastReply(1))
end

function TestFerry:test_board_request_replay_only_returns_receipt_during_countdown()
    self.data[1]:AddItem('shrimpTicket')
    self:board(1, 1)
    local operation = self:lastReply(1).operation
    local broadcasts = #self.broadcasts
    lu.assertTrue(self.mgr:Handle(self.players[1], { action = 'Board', seq = 2, requestId = operation }))
    lu.assertTrue(self:lastReply(1).ok)
    lu.assertEquals(#self.broadcasts, broadcasts)
    lu.assertEquals(self.data[1]:ItemCount('shrimpTicket'), 0)
end

function TestFerry:tearDown()
    package.loaded['common.GameCfg'] = self.saved.GameCfg
    self.cfg.Ferry = self.ferryCfg
    package.loaded['common.REUtil'] = self.saved.REUtil
    package.loaded['server.Mgr.MgrPlayerData'] = self.saved.PlayerData
    package.loaded['server.Data.PlayerData'] = self.saved.DataClass
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

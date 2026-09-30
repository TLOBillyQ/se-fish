-- #89 摆渡（GameSpec §8.3 已确认细则）+ #127 T06 七区六航线：请求带航线 id，锚点、目的地、
-- 船票与票价都由这条航线给出；六条航线各有独立航班状态，不同航线互不占用倒计时。
-- 去程一人交 1 张船票、5 秒倒计时后带走 BoatRange 内的所有玩家（搭便船合法）；
-- 返程按人付 10 × 3^(到达区序 − 2) 金币、立即传送；区域写入 PlayerData.Data.Zone、
-- 到达写入 Extra.travel.arrived（#92 存档用）。
-- 失败方式（先列后写）：
--   1. 没船票也能开船，或船票扣了却不开船、一次乘船扣两张票；倒计时中同一航线再交票被吞（应拒绝且不扣）；
--   2. 伪造 / 未登记的航线 id 也能开船，或换一条航线就被另一条的倒计时挡住（应各走各的）；
--   3. 倒计时没结束就传送，或到点不传送；到点只带走交票人（搭便船失败），或把船范围外的玩家也带走；
--   4. 返程不验金币 / 金币不足也传送 / 一人付费两人回家 / 传送失败不退款；
--   5. 落点不是本航线配置的目的地，或 Zone / 到达记录没更新；
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
        REUtil = package.loaded['common.REUtil'],
        PlayerData = package.loaded['server.Mgr.MgrPlayerData'],
        DataClass = package.loaded['server.Data.PlayerData'],
    }
    package.loaded['common.GameCfg'] = nil
    self.cfg = require('common.GameCfg')
    self.cfg.Debug = { Enabled = false }
    self.routes = self.cfg.Ferry.Routes
    self.route = self.routes[1]
    _G.Vector3 = { New = vec }

    -- PlayerData 在模块加载时抓住 GameCfg 实例（进图白送看那一刻的 Debug），
    -- 这里重载一次让本用例的玩家绑到「Debug 关闭」的那份配置上，库存完全由用例自己摆
    package.loaded['server.Data.PlayerData'] = nil
    local PlayerDataClass = require('server.Data.PlayerData')
    self.PlayerDataClass = PlayerDataClass
    -- 锚点坐标全部取自 #125 场景合同（Zones[].Scene.Entities 的 Ferry 实体），用例不另造坐标
    self.anchors = {}
    for _, zone in ipairs(self.cfg.Zones) do
        for _, entity in ipairs(zone.Scene.Entities) do
            if entity.Role == 'Ferry' then
                self.anchors[entity.Name] = {
                    Position = vec(entity.Position.x, entity.Position.y, entity.Position.z),
                }
            end
        end
    end
    local boat = self.anchors[self.route.Outbound.AnchorName].Position
    local safePoint = self.cfg.Zones[1].Scene.SafePoint
    self.players = {
        newPlayer(1, boat.x, boat.y, boat.z),            -- 船边（去程锚点上）
        newPlayer(2, boat.x + 1, boat.y, boat.z + 1.5),  -- 船边搭便船
        newPlayer(3, safePoint.x, safePoint.y, safePoint.z), -- 出生点，离船太远
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
    -- 锚点用场景合同里的名字登记；InRange 复刻「Radius+Slack 内（只看 x/z）」契约
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

function TestFerry:tearDown()
    package.loaded['common.GameCfg'] = self.saved.GameCfg
    package.loaded['common.REUtil'] = self.saved.REUtil
    package.loaded['server.Mgr.MgrPlayerData'] = self.saved.PlayerData
    package.loaded['server.Data.PlayerData'] = self.saved.DataClass
    _G.game = self.saved.game
    _G.Vector3 = self.saved.Vector3
    _G.REUtil = self.saved.REUtilG
end

function TestFerry:drain()
    while #self.queue > 0 do table.remove(self.queue, 1)() end
end

function TestFerry:lastReply(userId)
    local list = self.sent.FerryResult or {}
    for index = #list, 1, -1 do
        if list[index].userId == userId then return list[index].payload end
    end
end

function TestFerry:board(userId, seq, route)
    route = route or self.route
    return self.mgr:Handle(self.players[userId], { action = 'Board', routeId = route.Id, seq = seq })
end

function TestFerry:back(userId, seq, route)
    route = route or self.route
    return self.mgr:Handle(self.players[userId], { action = 'Return', routeId = route.Id, seq = seq })
end

-- 站到某条腿的锚点旁（可给 x/z 偏移）；坐标取自 #125 场景合同
function TestFerry:standAt(userId, name, offsetX, offsetZ)
    local anchor = self.anchors[name]
    lu.assertNotNil(anchor, '场景合同里没有这条摆渡锚点 ' .. tostring(name))
    self.players[userId].Character.Position = vec(anchor.Position.x + (offsetX or 0),
        anchor.Position.y, anchor.Position.z + (offsetZ or 0))
end

function TestFerry:sail(route)
    route = route or self.route
    self.now = self.now + route.Outbound.CountdownSec
    self.mgr:Update()
end

-- 配置钉住（#127）：六条航线各有 id、票、价、倒计时、锚点与落点；票与价随本区链推进
function TestFerry:test_config_pins()
    local ferry = self.cfg.Ferry
    lu.assertEquals(#self.routes, 6)
    for index, route in ipairs(self.routes) do
        local from, to = self.cfg.Zones[index], self.cfg.Zones[index + 1]
        lu.assertEquals(route.Id, from.Id .. '>' .. to.Id)
        lu.assertEquals(route.FromZoneId, from.Id)
        lu.assertEquals(route.ToZoneId, to.Id)
        lu.assertEquals(route.Outbound.Ticket, self.cfg.Content.Exchanges[index].Result)
        lu.assertNotNil(self.cfg.Items.Definitions[route.Outbound.Ticket], '去程票要在物品表里')
        lu.assertEquals(route.Outbound.CountdownSec, 5)
        lu.assertEquals(route.Outbound.Destination, to.Scene.SafePoint)
        lu.assertEquals(route.Return.Destination, from.Scene.SafePoint)
        lu.assertEquals(route.Return.Price, 10 * 3 ^ (index - 1))
        -- 锚点必须是本区场景合同里登记的 Ferry 实体：去程在出发区，返程在到达区
        lu.assertNotNil(self.anchors[route.Outbound.AnchorName])
        lu.assertNotNil(self.anchors[route.Return.AnchorName])
        lu.assertNotNil(route.Outbound.BoatRange)
        lu.assertNotNil(route.Return.Radius)
        lu.assertNotNil(self.cfg.Ferry.Route(route.Id))
    end
    lu.assertEquals(self.cfg.Ferry.HomeZone, 'fishPond')
    -- 第一段是既有现场：别名指向 Routes[1] 的两条腿（老消费端 #89 继续可用）
    lu.assertEquals(ferry.Outbound.AnchorName, 'FerryBoat')
    lu.assertEquals(ferry.Outbound, self.routes[1].Outbound)
    lu.assertEquals(ferry.Return, self.routes[1].Return)
    lu.assertNil(self.cfg.Ferry.Route('fishPond>volcanoIsland'))
    lu.assertNil(self.cfg.Ferry.Route(1))
    lu.assertNil(self.cfg.Ferry.Route(nil))
end

function TestFerry:test_zone_defaults_to_home()
    lu.assertEquals(self.data[1].Data.Zone, 'fishPond')
end

-- 验收 (a)：六条航线都能单人走完一圈，返程价 10/30/90/270/810/2430，船票与余额都只扣一次
function TestFerry:test_every_route_completes_solo_with_its_own_price()
    local seq = 0
    for index, route in ipairs(self.routes) do
        local player, data = self.players[1], self.data[1]
        lu.assertEquals(route.Return.Price, 10 * 3 ^ (index - 1))
        lu.assertTrue(data:AddItem(route.Outbound.Ticket))
        self:standAt(1, route.Outbound.AnchorName)
        seq = seq + 1
        lu.assertTrue(self:board(1, seq, route), '第' .. index .. '条航线应能交票')
        lu.assertEquals(data:ItemCount(route.Outbound.Ticket), 0, '去程票只扣一次')
        lu.assertEquals(data.Data.FishCoin, 0, '去程不收金币')
        self:sail(route)
        lu.assertEquals(player.teleports, index * 2 - 1)
        local destination = route.Outbound.Destination
        lu.assertEquals(player.Character.Position, vec(destination.x, destination.y, destination.z))
        lu.assertEquals(data.Data.Zone, route.ToZoneId)
        lu.assertEquals(data.Extra.travel.arrived[route.ToZoneId], 1, '到达记录要落进存档')

        lu.assertTrue(data:AddCoin(route.Return.Price, nil, 'test'))
        self:standAt(1, route.Return.AnchorName)
        seq = seq + 1
        lu.assertTrue(self:back(1, seq, route), '第' .. index .. '条航线应能返程')
        lu.assertEquals(data.Data.FishCoin, 0, '返程价只扣一次')
        lu.assertEquals(player.teleports, index * 2)
        local back = route.Return.Destination
        lu.assertEquals(player.Character.Position, vec(back.x, back.y, back.z))
        lu.assertEquals(data.Data.Zone, route.FromZoneId)
    end
end

function TestFerry:test_board_requires_ticket_and_consumes_exactly_one()
    lu.assertFalse(self:board(1, 1))
    lu.assertEquals(self:lastReply(1).reason, 'ticket')
    lu.assertNil(self.mgr.Flights[self.route.Id])
    lu.assertTrue(self.data[1]:AddItem(self.route.Outbound.Ticket))
    lu.assertTrue(self.data[1]:AddItem(self.route.Outbound.Ticket))
    lu.assertTrue(self:board(1, 2))
    lu.assertEquals(self.data[1]:ItemCount(self.route.Outbound.Ticket), 1)
    lu.assertNotNil(self.mgr.Flights[self.route.Id])
    lu.assertTrue(self:lastReply(1).ok)
    lu.assertEquals((self.broadcasts[#self.broadcasts]).phase, 'countdown')
    lu.assertEquals((self.broadcasts[#self.broadcasts]).routeId, self.route.Id)
end

function TestFerry:test_board_replay_and_stale_seq_rejected()
    lu.assertTrue(self.data[1]:AddItem(self.route.Outbound.Ticket))
    lu.assertTrue(self.data[1]:AddItem(self.route.Outbound.Ticket))
    lu.assertTrue(self:board(1, 5))
    lu.assertFalse(self:board(1, 5))
    lu.assertFalse(self:board(1, 4))
    lu.assertEquals(self.data[1]:ItemCount(self.route.Outbound.Ticket), 1)
end

-- 同一个航线倒计时中再交票：拒绝且不扣（第二张票还在）
function TestFerry:test_second_ticket_on_same_route_rejected_not_consumed()
    lu.assertTrue(self.data[1]:AddItem(self.route.Outbound.Ticket))
    lu.assertTrue(self.data[2]:AddItem(self.route.Outbound.Ticket))
    lu.assertTrue(self:board(1, 1))
    lu.assertFalse(self:board(2, 1))
    lu.assertEquals(self:lastReply(2).reason, 'sailing')
    lu.assertEquals(self.data[2]:ItemCount(self.route.Outbound.Ticket), 1)
end

-- 验收 (b)(d)：不同航线各有各的倒计时，互不占用；到点时没交票的搭便船者一起被带走
function TestFerry:test_routes_keep_independent_countdowns_and_abiders_ride_free()
    local routeA, routeB = self.routes[1], self.routes[2]
    lu.assertTrue(self.data[1]:AddItem(routeA.Outbound.Ticket))
    lu.assertTrue(self.data[2]:AddItem(routeB.Outbound.Ticket))
    self:standAt(1, routeA.Outbound.AnchorName)
    self:standAt(2, routeB.Outbound.AnchorName)
    self:standAt(3, routeB.Outbound.AnchorName, 1) -- 没票的搭便船玩家
    lu.assertTrue(self:board(1, 1, routeA))
    self.now = self.now + 2 -- 把两条航线的开船时刻错开，才能看出各自记账
    lu.assertTrue(self:board(2, 1, routeB))
    lu.assertNotNil(self.mgr.Flights[routeA.Id])
    lu.assertNotNil(self.mgr.Flights[routeB.Id])

    -- A 到点：只带走 A 船上的人，B 的倒计时不受影响
    self.now = self.mgr.Flights[routeA.Id].DepartAt
    self.mgr:Update()
    lu.assertNil(self.mgr.Flights[routeA.Id])
    lu.assertNotNil(self.mgr.Flights[routeB.Id])
    lu.assertEquals(self.data[1].Data.Zone, routeA.ToZoneId)
    lu.assertEquals(self.players[2].teleports, 0)
    lu.assertEquals(self.players[3].teleports, 0)
    lu.assertEquals(self.data[2]:ItemCount(routeB.Outbound.Ticket), 0, 'B 的票在交票时就扣掉，只扣一次')

    -- B 到点：交票人与搭便船者一起走，搭便船者不付任何代价，也要有到达记录
    self.now = self.mgr.Flights[routeB.Id].DepartAt
    self.mgr:Update()
    lu.assertEquals(self.players[2].teleports, 1)
    lu.assertEquals(self.players[3].teleports, 1)
    lu.assertEquals(self.data[2].Data.Zone, routeB.ToZoneId)
    lu.assertEquals(self.data[3].Data.Zone, routeB.ToZoneId)
    lu.assertEquals(self.data[3].Data.FishCoin, 0)
    lu.assertEquals(self.data[3]:ItemCount(routeB.Outbound.Ticket), 0)
    lu.assertEquals(self.data[3].Extra.travel.arrived[routeB.ToZoneId], 1)
    lu.assertEquals((self.broadcasts[#self.broadcasts]).phase, 'departed')
    lu.assertEquals((self.broadcasts[#self.broadcasts]).routeId, routeB.Id)
end

-- 验收 (b)：伪造航线 id、站在别的航线锚点、金币不足都拒收且不动账
function TestFerry:test_forged_route_far_position_and_missing_coin_are_rejected()
    local route = self.route
    lu.assertTrue(self.data[1]:AddItem(route.Outbound.Ticket))
    self:standAt(1, route.Outbound.AnchorName)
    for _, forged in ipairs({ 'fishPond>volcanoIsland', 'Z9', 1, true, '' }) do
        lu.assertFalse(self.mgr:Handle(self.players[1], { action = 'Board', routeId = forged, seq = 1 }))
        lu.assertEquals(self:lastReply(1).reason, 'route')
    end
    lu.assertFalse(self.mgr:Handle(self.players[1], { action = 'Board', seq = 1 }))
    lu.assertEquals(self:lastReply(1).reason, 'route')
    lu.assertFalse(self.mgr:Handle(self.players[1],
        { action = 'Return', routeId = route.Id .. 'x', seq = 1 }))
    lu.assertEquals(self:lastReply(1).reason, 'route')
    lu.assertEquals(self.data[1]:ItemCount(route.Outbound.Ticket), 1, '拒收不动账')
    lu.assertNil(self.mgr.Flights[route.Id])

    -- 航线 id 是对的，但人不在这个锚点旁
    self:standAt(1, self.routes[3].Outbound.AnchorName)
    lu.assertFalse(self:board(1, 1, route))
    lu.assertEquals(self:lastReply(1).reason, 'range')
    lu.assertEquals(self.data[1]:ItemCount(route.Outbound.Ticket), 1)
    lu.assertNil(self.mgr.Flights[route.Id])

    -- 返程金币不足
    self:standAt(1, route.Return.AnchorName)
    lu.assertFalse(self:back(1, 2, route))
    lu.assertEquals(self:lastReply(1).reason, 'coin')
    lu.assertEquals(self.data[1].Data.FishCoin, 0)
    lu.assertEquals(self.players[1].teleports, 0)
end

function TestFerry:test_board_waits_for_durable_ticket_before_publishing_countdown()
    self.data[1]:AddItem(self.route.Outbound.Ticket)
    local before = self.data[1].Data.Containers
    self.defer = true
    lu.assertTrue(self:board(1, 1))
    lu.assertNotNil(before.itemBar[1], '落账前不能删除真实船票')
    lu.assertNil(self.mgr.Flights[self.route.Id])
    lu.assertNil(self:lastReply(1))
    lu.assertEquals(#self.broadcasts, 0)
    self:drain()
    lu.assertEquals(self.data[1]:ItemCount(self.route.Outbound.Ticket), 0)
    lu.assertNotNil(self.mgr.Flights[self.route.Id])
    lu.assertTrue(self:lastReply(1).ok)
end

function TestFerry:test_no_departure_before_countdown_ends()
    lu.assertTrue(self.data[1]:AddItem(self.route.Outbound.Ticket))
    lu.assertTrue(self:board(1, 1))
    self.now = self.now + self.route.Outbound.CountdownSec - 0.5
    self.mgr:Update()
    lu.assertEquals(self.players[1].teleports, 0)
    lu.assertNotNil(self.mgr.Flights[self.route.Id])
end

function TestFerry:test_departure_takes_everyone_in_boat_range_only()
    lu.assertTrue(self.data[1]:AddItem(self.route.Outbound.Ticket))
    lu.assertTrue(self:board(1, 1))
    self:sail()
    local dest = self.route.Outbound.Destination
    for _, userId in ipairs({ 1, 2 }) do
        lu.assertEquals(self.players[userId].teleports, 1)
        lu.assertEquals(self.players[userId].Character.Position, vec(dest.x, dest.y, dest.z))
        lu.assertEquals(self.data[userId].Data.Zone, self.route.ToZoneId)
    end
    -- 范围外的不动
    lu.assertEquals(self.players[3].teleports, 0)
    lu.assertEquals(self.data[3].Data.Zone, 'fishPond')
    lu.assertNil(self.mgr.Flights[self.route.Id])
    lu.assertEquals((self.broadcasts[#self.broadcasts]).phase, 'departed')
end

function TestFerry:test_departure_skips_player_without_character()
    lu.assertTrue(self.data[1]:AddItem(self.route.Outbound.Ticket))
    lu.assertTrue(self:board(1, 1))
    self.players[2].Character = nil
    self:sail()
    lu.assertEquals(self.players[1].teleports, 1)
    lu.assertEquals(self.players[3].teleports, 0)
end

-- 验收 (d)：返程按人付费、立即出发；别人没付钱就回不去
function TestFerry:test_return_charges_each_player_and_teleports_immediately()
    local point = self.route.Return
    self:standAt(1, self.route.Return.AnchorName)
    self:standAt(2, self.route.Return.AnchorName, 1)
    lu.assertTrue(self.data[1]:AddCoin(point.Price, nil, 'test'))
    self.data[1].Data.Zone = self.route.ToZoneId
    self.data[2].Data.Zone = self.route.ToZoneId
    lu.assertTrue(self:back(1, 1))
    lu.assertEquals(self.data[1].Data.FishCoin, 0)
    lu.assertEquals(self.players[1].Character.Position,
        vec(point.Destination.x, point.Destination.y, point.Destination.z))
    lu.assertEquals(self.data[1].Data.Zone, self.route.FromZoneId)
    -- 没付费的搭不了返程
    lu.assertFalse(self:back(2, 1))
    lu.assertEquals(self:lastReply(2).reason, 'coin')
    lu.assertEquals(self.players[2].teleports, 0)
    lu.assertEquals(self.data[2].Data.Zone, self.route.ToZoneId)
    -- 自己掏钱就自己回，与别人无关（按人返程）
    lu.assertTrue(self.data[2]:AddCoin(point.Price, nil, 'test'))
    lu.assertTrue(self:back(2, 2))
    lu.assertEquals(self.data[2].Data.FishCoin, 0)
    lu.assertEquals(self.players[2].teleports, 1)
    lu.assertEquals(self.data[2].Data.Zone, self.route.FromZoneId)
end

function TestFerry:test_return_refunds_when_teleport_fails()
    local point = self.route.Return
    self:standAt(1, self.route.Return.AnchorName)
    lu.assertTrue(self.data[1]:AddCoin(point.Price, nil, 'test'))
    self.players[1].Character = nil
    lu.assertFalse(self:back(1, 1))
    lu.assertEquals(self.data[1].Data.FishCoin, point.Price)
end

function TestFerry:test_actions_require_range()
    lu.assertTrue(self.data[3]:AddItem(self.route.Outbound.Ticket))
    lu.assertFalse(self:board(3, 1)) -- 出生点离船太远
    lu.assertEquals(self:lastReply(3).reason, 'range')
    lu.assertEquals(self.data[3]:ItemCount(self.route.Outbound.Ticket), 1)
    lu.assertTrue(self.data[3]:AddCoin(self.route.Return.Price, nil, 'test'))
    lu.assertFalse(self:back(3, 2))
    lu.assertEquals(self.data[3].Data.FishCoin, self.route.Return.Price)
end

-- 锚点缺失是场景配置事故：这条航线取消、退票给交票人、广播 cancelled（带航线 id）让客户端收倒计时条
function TestFerry:test_missing_anchor_cancels_and_refunds_ticket()
    lu.assertTrue(self.data[1]:AddItem(self.route.Outbound.Ticket))
    lu.assertTrue(self:board(1, 1))
    self.anchors[self.route.Outbound.AnchorName] = nil
    self:sail()
    lu.assertEquals(self.data[1]:ItemCount(self.route.Outbound.Ticket), 1)
    lu.assertEquals(self.players[1].teleports, 0)
    lu.assertEquals((self.broadcasts[#self.broadcasts]).phase, 'cancelled')
    lu.assertEquals((self.broadcasts[#self.broadcasts]).routeId, self.route.Id)
end

function TestFerry:test_cancelled_flight_refund_is_durable_and_retries_once()
    self.data[1]:AddItem(self.route.Outbound.Ticket)
    lu.assertTrue(self:board(1, 1))
    self.anchors[self.route.Outbound.AnchorName] = nil
    self.writeFailure = true
    self:sail()
    lu.assertEquals(self.data[1]:ItemCount(self.route.Outbound.Ticket), 0)
    lu.assertEquals(self.data[1].Data.Containers.itemBar[1], nil,
        '写入失败不能凭空塞回船票；开发赠礼也替代不了恢复记账')
    lu.assertEquals(self.players[1].teleports, 0)
    self.writeFailure = false
    self.loseReply = true
    self.save:Update()
    self.mgr:Update()
    self.mgr:Update()
    lu.assertEquals(self.data[1]:ItemCount(self.route.Outbound.Ticket), 1)
    self.save:LoadInto(self.players[1], self.data[1])
    lu.assertEquals(self.data[1]:ItemCount(self.route.Outbound.Ticket), 1)
end

function TestFerry:test_rejoin_recovers_unfinished_board_once_without_starting_a_flight()
    self.data[1]:AddItem(self.route.Outbound.Ticket)
    self:board(1, 1)
    self.mgr:OnPlayerRemoving(self.players[1])
    local player = newPlayer(1, -8, 2.2, 24)
    local data = self.PlayerDataClass.New(player)
    self.players[1], self.data[1] = player, data
    self.save:LoadInto(player, data)
    self.mgr.Flights = {}
    self.mgr:Update()
    lu.assertEquals(data:ItemCount(self.route.Outbound.Ticket), 1)
    lu.assertEquals(player.teleports, 0)
    self.mgr:Update()
    lu.assertEquals(data:ItemCount(self.route.Outbound.Ticket), 1)
    lu.assertNil(self.mgr.Flights[self.route.Id])
end

function TestFerry:test_departed_board_stays_consumed_after_rejoin()
    self.data[1]:AddItem(self.route.Outbound.Ticket)
    self:board(1, 1)
    self:sail()
    local player = newPlayer(1, 100, 6, 103)
    local data = self.PlayerDataClass.New(player)
    self.players[1], self.data[1] = player, data
    self.save:LoadInto(player, data)
    self.mgr:Update()
    lu.assertEquals(data:ItemCount(self.route.Outbound.Ticket), 0)
    lu.assertEquals(data.Data.Zone, self.route.ToZoneId)
    -- 到达记录跟区域一起落进存档，重进后再跑一次 Update 也不会重复累加
    lu.assertEquals(data.Extra.travel.arrived[self.route.ToZoneId], 1)
    self.mgr:Update()
    lu.assertEquals(data.Extra.travel.arrived[self.route.ToZoneId], 1)
end

function TestFerry:test_return_waits_for_payment_and_recovery_before_teleport()
    local player, data = self.players[1], self.data[1]
    self:standAt(1, self.route.Return.AnchorName)
    data:AddCoin(40)
    self.defer = true
    lu.assertTrue(self:back(1, 1))
    lu.assertEquals(data.Data.FishCoin, 40)
    lu.assertEquals(player.teleports, 0)
    lu.assertNil(self:lastReply(1))
    self:drain()
    lu.assertEquals(data.Data.FishCoin, 40 - self.route.Return.Price)
    lu.assertEquals(player.teleports, 1)
    lu.assertTrue(self:lastReply(1).ok)
end

function TestFerry:test_return_operation_replay_after_rejoin_never_charges_or_teleports()
    local player, data = self.players[1], self.data[1]
    self:standAt(1, self.route.Return.AnchorName)
    data:AddCoin(40)
    self:back(1, 1)
    local operation = self:lastReply(1).operation
    lu.assertNotNil(operation, '返回服务端操作身份供跨会话补发')
    self.mgr:OnPlayerRemoving(player)
    player = newPlayer(1, 101, 6, 103)
    data = assert(loadfile('server/Data/PlayerData.lua'))().New(player)
    self.players[1], self.data[1] = player, data
    self.save:LoadInto(player, data)
    lu.assertTrue(self.mgr:Handle(player,
        { action = 'Return', routeId = self.route.Id, seq = 1, requestId = operation }))
    lu.assertEquals(data.Data.FishCoin, 40 - self.route.Return.Price)
    lu.assertEquals(player.teleports, 0)
    lu.assertTrue(self:lastReply(1).ok)
end

function TestFerry:test_return_failure_keeps_durable_refund_until_storage_recovers()
    local player, data = self.players[1], self.data[1]
    self:standAt(1, self.route.Return.AnchorName)
    data:AddCoin(40)
    player.Character.SetPosition = function()
        self.writeFailure = true
        error('引擎拒绝传送')
    end
    self:back(1, 1)
    lu.assertEquals(data.Data.FishCoin, 40 - self.route.Return.Price, '退款未落账不能裸加金币')
    lu.assertNil(self:lastReply(1), '退款未落账不能声称已处理')
    self.writeFailure = false
    self.loseReply = true
    self.save:Update()
    lu.assertEquals(data.Data.FishCoin, 40)
    lu.assertFalse(self:lastReply(1).ok)
    local operation = self:lastReply(1).operation
    lu.assertTrue(self.mgr:Handle(player,
        { action = 'Return', routeId = self.route.Id, seq = 2, requestId = operation }))
    lu.assertEquals(self:lastReply(1).reason, 'teleport')
    lu.assertEquals(data.Data.FishCoin, 40)
    self.save:LoadInto(player, data)
    self.mgr:Update()
    lu.assertEquals(data.Data.FishCoin, 40)
end

function TestFerry:test_return_callback_after_leaving_never_teleports()
    local player, data = self.players[1], self.data[1]
    self:standAt(1, self.route.Return.AnchorName)
    data:AddCoin(40)
    self.defer = true
    self:back(1, 1)
    self.mgr:OnPlayerRemoving(player)
    self:drain()
    lu.assertEquals(player.teleports, 0)
    lu.assertNil(self:lastReply(1))
end

function TestFerry:test_return_teleport_failure_reports_teleport_reason()
    local point = self.route.Return
    self:standAt(1, self.route.Return.AnchorName)
    lu.assertTrue(self.data[1]:AddCoin(point.Price, nil, 'test'))
    -- 人在范围内但引擎拒绝传送（SetPosition 抛错），命中退款 + 'teleport' 分支
    self.players[1].Character.SetPosition = function() error('boom') end
    lu.assertFalse(self:back(1, 1))
    lu.assertEquals(self:lastReply(1).reason, 'teleport')
    lu.assertEquals(self.data[1].Data.FishCoin, point.Price)
end

function TestFerry:test_leaving_during_payment_does_not_reserve_the_boat_forever()
    self.data[1]:AddItem(self.route.Outbound.Ticket)
    self.data[2]:AddItem(self.route.Outbound.Ticket)
    self.defer = true
    self:board(1, 1)
    self.mgr:OnPlayerRemoving(self.players[1])
    lu.assertTrue(self:board(2, 1))
    self:drain()
    lu.assertEquals(self.mgr.Flights[self.route.Id].player.UserId, 2)
    lu.assertEquals(self.data[2]:ItemCount(self.route.Outbound.Ticket), 0)
    lu.assertFalse(self:lastReply(1) and self:lastReply(1).ok or false)
end

-- 交票人掉线只取消自己那条航线，别的航线照常
function TestFerry:test_payer_leaving_cancels_only_its_own_route()
    local routeA, routeB = self.routes[1], self.routes[2]
    lu.assertTrue(self.data[1]:AddItem(routeA.Outbound.Ticket))
    lu.assertTrue(self.data[2]:AddItem(routeB.Outbound.Ticket))
    self:standAt(1, routeA.Outbound.AnchorName)
    self:standAt(2, routeB.Outbound.AnchorName)
    lu.assertTrue(self:board(1, 1, routeA))
    lu.assertTrue(self:board(2, 1, routeB))
    self.mgr:OnPlayerRemoving(self.players[1])
    lu.assertNil(self.mgr.Flights[routeA.Id])
    lu.assertNotNil(self.mgr.Flights[routeB.Id])
    lu.assertEquals((self.broadcasts[#self.broadcasts]).routeId, routeA.Id)
    -- B 到点照常开船，把 B 船上的人带走
    self.now = self.mgr.Flights[routeB.Id].DepartAt
    self.mgr:Update()
    lu.assertEquals(self.data[2].Data.Zone, routeB.ToZoneId)
end

function TestFerry:test_pending_board_excludes_second_payer_and_failed_write_grants_nothing()
    self.data[1]:AddItem(self.route.Outbound.Ticket)
    self.data[2]:AddItem(self.route.Outbound.Ticket)
    self.writeFailure = true
    self:board(1, 1)
    lu.assertFalse(self:board(2, 1))
    lu.assertEquals(self.data[2]:ItemCount(self.route.Outbound.Ticket), 1)
    lu.assertNil(self.mgr.Flights[self.route.Id])
    lu.assertEquals(#self.broadcasts, 0)
    lu.assertNil(self:lastReply(1))
    self.writeFailure = false
    self.save:Update()
    lu.assertEquals(self.mgr.Flights[self.route.Id].player.UserId, 1)
    lu.assertEquals(self.data[1]:ItemCount(self.route.Outbound.Ticket), 0)
end

function TestFerry:test_missing_save_and_forged_request_never_grant_travel()
    self.data[1]:AddItem(self.route.Outbound.Ticket)
    self.mgr.Save = nil
    lu.assertFalse(self:board(1, 1))
    self.mgr.Save = self.save
    lu.assertFalse(self.mgr:Handle(self.players[1], { action = 'Board', routeId = self.route.Id, seq = 2,
        requestId = { id = '1:99', sequence = 99, kind = 'ferry:board', requestKey = 'forged' } }))
    lu.assertFalse(self:board(1, math.huge))
    lu.assertEquals(self.data[1]:ItemCount(self.route.Outbound.Ticket), 1)
    lu.assertNil(self.mgr.Flights[self.route.Id])
end

function TestFerry:test_board_request_replay_only_returns_receipt_during_countdown()
    self.data[1]:AddItem(self.route.Outbound.Ticket)
    self:board(1, 1)
    local operation = self:lastReply(1).operation
    local broadcasts = #self.broadcasts
    lu.assertTrue(self.mgr:Handle(self.players[1],
        { action = 'Board', routeId = self.route.Id, seq = 2, requestId = operation }))
    lu.assertTrue(self:lastReply(1).ok)
    lu.assertEquals(#self.broadcasts, broadcasts)
    lu.assertEquals(self.data[1]:ItemCount(self.route.Outbound.Ticket), 0)
end

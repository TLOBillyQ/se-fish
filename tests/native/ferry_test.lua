-- 迁移自 tests/gameplay/ferry_test.lua（#85）；行为契约原文见 #89、#127、#125、#123、#140、#92。
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
-- it 名字沿用旧方法名，注册顺序 = LuaUnit sortedPairs 的实际执行顺序。

local moduleNames = { 'common.GameCfg', 'common.REUtil',
  'server.Mgr.MgrPlayerData', 'server.Data.PlayerData' }

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

describe('摆渡（MgrFerry × MgrSave × PlayerData）', function()
  local env
  local restore

  before_each(function()
    -- 快照先于任何改动：before_each 中途失败时 after_each 仍能还原。
    restore = {
      game = rawget(_G, 'game'), Vector3 = rawget(_G, 'Vector3'), REUtilG = rawget(_G, 'REUtil'),
    }
    for _, name in ipairs(moduleNames) do
      restore[name] = package.loaded[name]
    end
    package.loaded['common.GameCfg'] = nil
    env = { now = 100, sent = {}, broadcasts = {}, values = {}, queue = {},
      defer = false, writeFailure = false, loseReply = false }
    env.cfg = require('common.GameCfg')
    env.cfg.Debug = { Enabled = false }
    env.routes = env.cfg.Ferry.Routes
    env.route = env.routes[1]
    _G.Vector3 = { New = vec }

    -- PlayerData 在模块加载时抓住 GameCfg 实例（进图白送看那一刻的 Debug），
    -- 这里重载一次让本用例的玩家绑到「Debug 关闭」的那份配置上，库存完全由用例自己摆
    package.loaded['server.Data.PlayerData'] = nil
    local PlayerDataClass = require('server.Data.PlayerData')
    env.PlayerDataClass = PlayerDataClass
    -- 锚点坐标全部取自 #125 场景合同（Zones[].Scene.Entities 的 Ferry 实体），用例不另造坐标
    env.anchors = {}
    for _, zone in ipairs(env.cfg.Zones) do
      for _, entity in ipairs(zone.Scene.Entities) do
        if entity.Role == 'Ferry' then
          env.anchors[entity.Name] = {
            Position = vec(entity.Position.x, entity.Position.y, entity.Position.z),
          }
        end
      end
    end
    local boat = env.anchors[env.route.Outbound.AnchorName].Position
    local safePoint = env.cfg.Zones[1].Scene.SafePoint
    env.players = {
      newPlayer(1, boat.x, boat.y, boat.z),            -- 船边（去程锚点上）
      newPlayer(2, boat.x + 1, boat.y, boat.z + 1.5),  -- 船边搭便船
      newPlayer(3, safePoint.x, safePoint.y, safePoint.z), -- 出生点，离船太远
    }
    env.data = {}
    for _, player in ipairs(env.players) do
      env.data[player.UserId] = PlayerDataClass.New(player, function() end)
      env.data[player.UserId]:Init()
    end

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

    env.mgr = assert(loadfile('server/Mgr/MgrFerry.lua'))()
    env.mgr.World = { GetServerTime = function() return env.now end }
    -- 锚点用场景合同里的名字登记；InRange 复刻「Radius+Slack 内（只看 x/z）」契约
    env.mgr.Interact = {
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
    env.mgr.PlayerData = package.loaded['server.Mgr.MgrPlayerData']
    env.mgr.OnlinePlayers = function() return env.players end
    env.store = {
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
    env.save = assert(loadfile('server/Mgr/MgrSave.lua'))()
    env.mgr.Save = env.save
    for _, player in ipairs(env.players) do env.save:LoadInto(player, env.data[player.UserId]) end
  end)

  after_each(function()
    package.loaded['common.GameCfg'] = restore and restore.GameCfg
    package.loaded['common.REUtil'] = restore and restore.REUtil
    package.loaded['server.Mgr.MgrPlayerData'] = restore and restore.MgrPlayerData
    package.loaded['server.Data.PlayerData'] = restore and restore.DataClass
    _G.game = restore and restore.game
    _G.Vector3 = restore and restore.Vector3
    _G.REUtil = restore and restore.REUtilG
    env = nil
    restore = nil
  end)

  local function drain()
    while #env.queue > 0 do table.remove(env.queue, 1)() end
  end

  local function lastReply(userId)
    local list = env.sent.FerryResult or {}
    for index = #list, 1, -1 do
      if list[index].userId == userId then return list[index].payload end
    end
  end

  local function board(userId, seq, route)
    route = route or env.route
    return env.mgr:Handle(env.players[userId], { action = 'Board', routeId = route.Id, seq = seq })
  end

  local function back(userId, seq, route)
    route = route or env.route
    return env.mgr:Handle(env.players[userId], { action = 'Return', routeId = route.Id, seq = seq })
  end

  -- 站到某条腿的锚点旁（可给 x/z 偏移）；坐标取自 #125 场景合同
  local function standAt(userId, name, offsetX, offsetZ)
    local anchor = env.anchors[name]
    assert.message('场景合同里没有这条摆渡锚点 ' .. tostring(name)).is_not_nil(anchor)
    env.players[userId].Character.Position = vec(anchor.Position.x + (offsetX or 0),
      anchor.Position.y, anchor.Position.z + (offsetZ or 0))
  end

  local function sail(route)
    route = route or env.route
    env.now = env.now + route.Outbound.CountdownSec
    env.mgr:Update()
  end

  it('test_actions_require_range', function()
    assert.is_true(env.data[3]:AddItem(env.route.Outbound.Ticket))
    assert.is_false(board(3, 1)) -- 出生点离船太远
    assert.same('range', lastReply(3).reason)
    assert.same(1, env.data[3]:ItemCount(env.route.Outbound.Ticket))
    assert.is_true(env.data[3]:AddCoin(env.route.Return.Price, nil, 'test'))
    assert.is_false(back(3, 2))
    assert.same(env.route.Return.Price, env.data[3].Data.FishCoin)
  end)

  it('test_board_replay_and_stale_seq_rejected', function()
    assert.is_true(env.data[1]:AddItem(env.route.Outbound.Ticket))
    assert.is_true(env.data[1]:AddItem(env.route.Outbound.Ticket))
    assert.is_true(board(1, 5))
    assert.is_false(board(1, 5))
    assert.is_false(board(1, 4))
    assert.same(1, env.data[1]:ItemCount(env.route.Outbound.Ticket))
  end)

  it('test_board_request_replay_only_returns_receipt_during_countdown', function()
    env.data[1]:AddItem(env.route.Outbound.Ticket)
    board(1, 1)
    local operation = lastReply(1).operation
    local broadcasts = #env.broadcasts
    assert.is_true(env.mgr:Handle(env.players[1],
      { action = 'Board', routeId = env.route.Id, seq = 2, requestId = operation }))
    assert.is_true(lastReply(1).ok)
    assert.same(broadcasts, #env.broadcasts)
    assert.same(0, env.data[1]:ItemCount(env.route.Outbound.Ticket))
  end)

  it('test_board_requires_ticket_and_consumes_exactly_one', function()
    assert.is_false(board(1, 1))
    assert.same('ticket', lastReply(1).reason)
    assert.is_nil(env.mgr.Flights[env.route.Id])
    assert.is_true(env.data[1]:AddItem(env.route.Outbound.Ticket))
    assert.is_true(env.data[1]:AddItem(env.route.Outbound.Ticket))
    assert.is_true(board(1, 2))
    assert.same(1, env.data[1]:ItemCount(env.route.Outbound.Ticket))
    assert.is_not_nil(env.mgr.Flights[env.route.Id])
    assert.is_true(lastReply(1).ok)
    assert.same('countdown', (env.broadcasts[#env.broadcasts]).phase)
    assert.same(env.route.Id, (env.broadcasts[#env.broadcasts]).routeId)
  end)

  it('test_board_waits_for_durable_ticket_before_publishing_countdown', function()
    env.data[1]:AddItem(env.route.Outbound.Ticket)
    local before = env.data[1].Data.Containers
    env.defer = true
    assert.is_true(board(1, 1))
    assert.message('落账前不能删除真实船票').is_not_nil(before.itemBar[1])
    assert.is_nil(env.mgr.Flights[env.route.Id])
    assert.is_nil(lastReply(1))
    assert.same(0, #env.broadcasts)
    drain()
    assert.same(0, env.data[1]:ItemCount(env.route.Outbound.Ticket))
    assert.is_not_nil(env.mgr.Flights[env.route.Id])
    assert.is_true(lastReply(1).ok)
  end)

  it('test_cancelled_flight_refund_is_durable_and_retries_once', function()
    env.data[1]:AddItem(env.route.Outbound.Ticket)
    assert.is_true(board(1, 1))
    env.anchors[env.route.Outbound.AnchorName] = nil
    env.writeFailure = true
    sail()
    assert.same(0, env.data[1]:ItemCount(env.route.Outbound.Ticket))
    assert.message('写入失败不能凭空塞回船票；开发赠礼也替代不了恢复记账')
      .is_nil(env.data[1].Data.Containers.itemBar[1])
    assert.same(0, env.players[1].teleports)
    env.writeFailure = false
    env.loseReply = true
    env.save:Update()
    env.mgr:Update()
    env.mgr:Update()
    assert.same(1, env.data[1]:ItemCount(env.route.Outbound.Ticket))
    env.save:LoadInto(env.players[1], env.data[1])
    assert.same(1, env.data[1]:ItemCount(env.route.Outbound.Ticket))
  end)

  it('test_config_pins', function()
    -- 配置钉住（#127）：六条航线各有 id、票、价、倒计时、锚点与落点；票与价随本区链推进
    local ferry = env.cfg.Ferry
    assert.same(6, #env.routes)
    for index, route in ipairs(env.routes) do
      local from, to = env.cfg.Zones[index], env.cfg.Zones[index + 1]
      assert.same(from.Id .. '>' .. to.Id, route.Id)
      assert.same(from.Id, route.FromZoneId)
      assert.same(to.Id, route.ToZoneId)
      assert.same(env.cfg.Content.Exchanges[index].Result, route.Outbound.Ticket)
      assert.message('去程票要在物品表里').is_not_nil(env.cfg.Items.Definitions[route.Outbound.Ticket])
      assert.same(5, route.Outbound.CountdownSec)
      assert.same(to.Scene.SafePoint, route.Outbound.Destination)
      assert.same(from.Scene.SafePoint, route.Return.Destination)
      assert.same(10 * 3 ^ (index - 1), route.Return.Price)
      -- 锚点必须是本区场景合同里登记的 Ferry 实体：去程在出发区，返程在到达区
      assert.is_not_nil(env.anchors[route.Outbound.AnchorName])
      assert.is_not_nil(env.anchors[route.Return.AnchorName])
      assert.is_not_nil(route.Outbound.BoatRange)
      assert.is_not_nil(route.Return.Radius)
      assert.is_not_nil(env.cfg.Ferry.Route(route.Id))
    end
    assert.same('fishPond', env.cfg.Ferry.HomeZone)
    -- 第一段是既有现场：别名指向 Routes[1] 的两条腿（老消费端 #89 继续可用）
    assert.same('FerryBoat', ferry.Outbound.AnchorName)
    assert.same(env.routes[1].Outbound, ferry.Outbound)
    assert.same(env.routes[1].Return, ferry.Return)
    assert.is_nil(env.cfg.Ferry.Route('fishPond>volcanoIsland'))
    assert.is_nil(env.cfg.Ferry.Route(1))
    assert.is_nil(env.cfg.Ferry.Route(nil))
  end)

  it('test_departed_board_stays_consumed_after_rejoin', function()
    env.data[1]:AddItem(env.route.Outbound.Ticket)
    board(1, 1)
    sail()
    local player = newPlayer(1, 100, 6, 103)
    local data = env.PlayerDataClass.New(player)
    env.players[1], env.data[1] = player, data
    env.save:LoadInto(player, data)
    env.mgr:Update()
    assert.same(0, data:ItemCount(env.route.Outbound.Ticket))
    assert.same(env.route.ToZoneId, data.Data.Zone)
    -- 到达记录跟区域一起落进存档，重进后再跑一次 Update 也不会重复累加
    assert.same(1, data.Extra.travel.arrived[env.route.ToZoneId])
    env.mgr:Update()
    assert.same(1, data.Extra.travel.arrived[env.route.ToZoneId])
  end)

  it('test_departure_skips_player_without_character', function()
    assert.is_true(env.data[1]:AddItem(env.route.Outbound.Ticket))
    assert.is_true(board(1, 1))
    env.players[2].Character = nil
    sail()
    assert.same(1, env.players[1].teleports)
    assert.same(0, env.players[3].teleports)
  end)

  it('test_departure_takes_everyone_in_boat_range_only', function()
    assert.is_true(env.data[1]:AddItem(env.route.Outbound.Ticket))
    assert.is_true(board(1, 1))
    sail()
    local dest = env.route.Outbound.Destination
    for _, userId in ipairs({ 1, 2 }) do
      assert.same(1, env.players[userId].teleports)
      assert.same(vec(dest.x, dest.y, dest.z), env.players[userId].Character.Position)
      assert.same(env.route.ToZoneId, env.data[userId].Data.Zone)
    end
    -- 范围外的不动
    assert.same(0, env.players[3].teleports)
    assert.same('fishPond', env.data[3].Data.Zone)
    assert.is_nil(env.mgr.Flights[env.route.Id])
    assert.same('departed', (env.broadcasts[#env.broadcasts]).phase)
  end)

  it('test_every_route_completes_solo_with_its_own_price', function()
    -- 验收 (a)：六条航线都能单人走完一圈，返程价 10/30/90/270/810/2430，船票与余额都只扣一次
    local seq = 0
    for index, route in ipairs(env.routes) do
      local player, data = env.players[1], env.data[1]
      assert.same(10 * 3 ^ (index - 1), route.Return.Price)
      assert.is_true(data:AddItem(route.Outbound.Ticket))
      standAt(1, route.Outbound.AnchorName)
      seq = seq + 1
      assert.message('第' .. index .. '条航线应能交票').is_true(board(1, seq, route))
      assert.message('去程票只扣一次').same(0, data:ItemCount(route.Outbound.Ticket))
      assert.message('去程不收金币').same(0, data.Data.FishCoin)
      sail(route)
      assert.same(index * 2 - 1, player.teleports)
      local destination = route.Outbound.Destination
      assert.same(vec(destination.x, destination.y, destination.z), player.Character.Position)
      assert.same(route.ToZoneId, data.Data.Zone)
      assert.message('到达记录要落进存档').same(1, data.Extra.travel.arrived[route.ToZoneId])

      assert.is_true(data:AddCoin(route.Return.Price, nil, 'test'))
      standAt(1, route.Return.AnchorName)
      seq = seq + 1
      assert.message('第' .. index .. '条航线应能返程').is_true(back(1, seq, route))
      assert.message('返程价只扣一次').same(0, data.Data.FishCoin)
      assert.same(index * 2, player.teleports)
      local backPoint = route.Return.Destination
      assert.same(vec(backPoint.x, backPoint.y, backPoint.z), player.Character.Position)
      assert.same(route.FromZoneId, data.Data.Zone)
    end
  end)

  it('test_forged_route_far_position_and_missing_coin_are_rejected', function()
    -- 验收 (b)：伪造航线 id、站在别的航线锚点、金币不足都拒收且不动账
    local route = env.route
    assert.is_true(env.data[1]:AddItem(route.Outbound.Ticket))
    standAt(1, route.Outbound.AnchorName)
    for _, forged in ipairs({ 'fishPond>volcanoIsland', 'Z9', 1, true, '' }) do
      assert.is_false(env.mgr:Handle(env.players[1], { action = 'Board', routeId = forged, seq = 1 }))
      assert.same('route', lastReply(1).reason)
    end
    assert.is_false(env.mgr:Handle(env.players[1], { action = 'Board', seq = 1 }))
    assert.same('route', lastReply(1).reason)
    assert.is_false(env.mgr:Handle(env.players[1],
      { action = 'Return', routeId = route.Id .. 'x', seq = 1 }))
    assert.same('route', lastReply(1).reason)
    assert.message('拒收不动账').same(1, env.data[1]:ItemCount(route.Outbound.Ticket))
    assert.is_nil(env.mgr.Flights[route.Id])

    -- 航线 id 是对的，但人不在这个锚点旁
    standAt(1, env.routes[3].Outbound.AnchorName)
    assert.is_false(board(1, 1, route))
    assert.same('range', lastReply(1).reason)
    assert.same(1, env.data[1]:ItemCount(route.Outbound.Ticket))
    assert.is_nil(env.mgr.Flights[route.Id])

    -- 返程金币不足
    standAt(1, route.Return.AnchorName)
    assert.is_false(back(1, 2, route))
    assert.same('coin', lastReply(1).reason)
    assert.same(0, env.data[1].Data.FishCoin)
    assert.same(0, env.players[1].teleports)
  end)

  it('test_leaving_during_payment_does_not_reserve_the_boat_forever', function()
    env.data[1]:AddItem(env.route.Outbound.Ticket)
    env.data[2]:AddItem(env.route.Outbound.Ticket)
    env.defer = true
    board(1, 1)
    env.mgr:OnPlayerRemoving(env.players[1])
    assert.is_true(board(2, 1))
    drain()
    assert.same(2, env.mgr.Flights[env.route.Id].player.UserId)
    assert.same(0, env.data[2]:ItemCount(env.route.Outbound.Ticket))
    assert.is_false(lastReply(1) and lastReply(1).ok or false)
  end)

  it('test_missing_anchor_cancels_and_refunds_ticket', function()
    -- 锚点缺失是场景配置事故：这条航线取消、退票给交票人、广播 cancelled（带航线 id）让客户端收倒计时条
    assert.is_true(env.data[1]:AddItem(env.route.Outbound.Ticket))
    assert.is_true(board(1, 1))
    env.anchors[env.route.Outbound.AnchorName] = nil
    sail()
    assert.same(1, env.data[1]:ItemCount(env.route.Outbound.Ticket))
    assert.same(0, env.players[1].teleports)
    assert.same('cancelled', (env.broadcasts[#env.broadcasts]).phase)
    assert.same(env.route.Id, (env.broadcasts[#env.broadcasts]).routeId)
  end)

  it('test_missing_save_and_forged_request_never_grant_travel', function()
    env.data[1]:AddItem(env.route.Outbound.Ticket)
    env.mgr.Save = nil
    assert.is_false(board(1, 1))
    env.mgr.Save = env.save
    assert.is_false(env.mgr:Handle(env.players[1], { action = 'Board', routeId = env.route.Id, seq = 2,
      requestId = { id = '1:99', sequence = 99, kind = 'ferry:board', requestKey = 'forged' } }))
    assert.is_false(board(1, math.huge))
    assert.same(1, env.data[1]:ItemCount(env.route.Outbound.Ticket))
    assert.is_nil(env.mgr.Flights[env.route.Id])
  end)

  it('test_no_departure_before_countdown_ends', function()
    assert.is_true(env.data[1]:AddItem(env.route.Outbound.Ticket))
    assert.is_true(board(1, 1))
    env.now = env.now + env.route.Outbound.CountdownSec - 0.5
    env.mgr:Update()
    assert.same(0, env.players[1].teleports)
    assert.is_not_nil(env.mgr.Flights[env.route.Id])
  end)

  it('test_payer_leaving_cancels_only_its_own_route', function()
    -- 交票人掉线只取消自己那条航线，别的航线照常
    local routeA, routeB = env.routes[1], env.routes[2]
    assert.is_true(env.data[1]:AddItem(routeA.Outbound.Ticket))
    assert.is_true(env.data[2]:AddItem(routeB.Outbound.Ticket))
    standAt(1, routeA.Outbound.AnchorName)
    standAt(2, routeB.Outbound.AnchorName)
    assert.is_true(board(1, 1, routeA))
    assert.is_true(board(2, 1, routeB))
    env.mgr:OnPlayerRemoving(env.players[1])
    assert.is_nil(env.mgr.Flights[routeA.Id])
    assert.is_not_nil(env.mgr.Flights[routeB.Id])
    assert.same(routeA.Id, (env.broadcasts[#env.broadcasts]).routeId)
    -- B 到点照常开船，把 B 船上的人带走
    env.now = env.mgr.Flights[routeB.Id].DepartAt
    env.mgr:Update()
    assert.same(routeB.ToZoneId, env.data[2].Data.Zone)
  end)

  it('test_pending_board_excludes_second_payer_and_failed_write_grants_nothing', function()
    env.data[1]:AddItem(env.route.Outbound.Ticket)
    env.data[2]:AddItem(env.route.Outbound.Ticket)
    env.writeFailure = true
    board(1, 1)
    assert.is_false(board(2, 1))
    assert.same(1, env.data[2]:ItemCount(env.route.Outbound.Ticket))
    assert.is_nil(env.mgr.Flights[env.route.Id])
    assert.same(0, #env.broadcasts)
    assert.is_nil(lastReply(1))
    env.writeFailure = false
    env.save:Update()
    assert.same(1, env.mgr.Flights[env.route.Id].player.UserId)
    assert.same(0, env.data[1]:ItemCount(env.route.Outbound.Ticket))
  end)

  it('test_rejoin_recovers_unfinished_board_once_without_starting_a_flight', function()
    env.data[1]:AddItem(env.route.Outbound.Ticket)
    board(1, 1)
    env.mgr:OnPlayerRemoving(env.players[1])
    local player = newPlayer(1, -8, 2.2, 24)
    local data = env.PlayerDataClass.New(player)
    env.players[1], env.data[1] = player, data
    env.save:LoadInto(player, data)
    env.mgr.Flights = {}
    env.mgr:Update()
    assert.same(1, data:ItemCount(env.route.Outbound.Ticket))
    assert.same(0, player.teleports)
    env.mgr:Update()
    assert.same(1, data:ItemCount(env.route.Outbound.Ticket))
    assert.is_nil(env.mgr.Flights[env.route.Id])
  end)

  it('test_return_callback_after_leaving_never_teleports', function()
    local player, data = env.players[1], env.data[1]
    standAt(1, env.route.Return.AnchorName)
    data:AddCoin(40)
    env.defer = true
    back(1, 1)
    env.mgr:OnPlayerRemoving(player)
    drain()
    assert.same(0, player.teleports)
    assert.is_nil(lastReply(1))
  end)

  it('test_return_charges_each_player_and_teleports_immediately', function()
    -- 验收 (d)：返程按人付费、立即出发；别人没付钱就回不去
    local point = env.route.Return
    standAt(1, env.route.Return.AnchorName)
    standAt(2, env.route.Return.AnchorName, 1)
    assert.is_true(env.data[1]:AddCoin(point.Price, nil, 'test'))
    env.data[1].Data.Zone = env.route.ToZoneId
    env.data[2].Data.Zone = env.route.ToZoneId
    assert.is_true(back(1, 1))
    assert.same(0, env.data[1].Data.FishCoin)
    assert.same(vec(point.Destination.x, point.Destination.y, point.Destination.z),
      env.players[1].Character.Position)
    assert.same(env.route.FromZoneId, env.data[1].Data.Zone)
    -- 没付费的搭不了返程
    assert.is_false(back(2, 1))
    assert.same('coin', lastReply(2).reason)
    assert.same(0, env.players[2].teleports)
    assert.same(env.route.ToZoneId, env.data[2].Data.Zone)
    -- 自己掏钱就自己回，与别人无关（按人返程）
    assert.is_true(env.data[2]:AddCoin(point.Price, nil, 'test'))
    assert.is_true(back(2, 2))
    assert.same(0, env.data[2].Data.FishCoin)
    assert.same(1, env.players[2].teleports)
    assert.same(env.route.FromZoneId, env.data[2].Data.Zone)
  end)

  it('test_return_failure_keeps_durable_refund_until_storage_recovers', function()
    local player, data = env.players[1], env.data[1]
    standAt(1, env.route.Return.AnchorName)
    data:AddCoin(40)
    player.Character.SetPosition = function()
      env.writeFailure = true
      error('引擎拒绝传送')
    end
    back(1, 1)
    assert.message('退款未落账不能裸加金币').same(40 - env.route.Return.Price, data.Data.FishCoin)
    assert.message('退款未落账不能声称已处理').is_nil(lastReply(1))
    env.writeFailure = false
    env.loseReply = true
    env.save:Update()
    assert.same(40, data.Data.FishCoin)
    assert.is_false(lastReply(1).ok)
    local operation = lastReply(1).operation
    assert.is_true(env.mgr:Handle(player,
      { action = 'Return', routeId = env.route.Id, seq = 2, requestId = operation }))
    assert.same('teleport', lastReply(1).reason)
    assert.same(40, data.Data.FishCoin)
    env.save:LoadInto(player, data)
    env.mgr:Update()
    assert.same(40, data.Data.FishCoin)
  end)

  it('test_return_operation_replay_after_rejoin_never_charges_or_teleports', function()
    local player, data = env.players[1], env.data[1]
    standAt(1, env.route.Return.AnchorName)
    data:AddCoin(40)
    back(1, 1)
    local operation = lastReply(1).operation
    assert.message('返回服务端操作身份供跨会话补发').is_not_nil(operation)
    env.mgr:OnPlayerRemoving(player)
    player = newPlayer(1, 101, 6, 103)
    data = assert(loadfile('server/Data/PlayerData.lua'))().New(player)
    env.players[1], env.data[1] = player, data
    env.save:LoadInto(player, data)
    assert.is_true(env.mgr:Handle(player,
      { action = 'Return', routeId = env.route.Id, seq = 1, requestId = operation }))
    assert.same(40 - env.route.Return.Price, data.Data.FishCoin)
    assert.same(0, player.teleports)
    assert.is_true(lastReply(1).ok)
  end)

  it('test_return_refunds_when_teleport_fails', function()
    local point = env.route.Return
    standAt(1, env.route.Return.AnchorName)
    assert.is_true(env.data[1]:AddCoin(point.Price, nil, 'test'))
    env.players[1].Character = nil
    assert.is_false(back(1, 1))
    assert.same(point.Price, env.data[1].Data.FishCoin)
  end)

  it('test_return_teleport_failure_reports_teleport_reason', function()
    local point = env.route.Return
    standAt(1, env.route.Return.AnchorName)
    assert.is_true(env.data[1]:AddCoin(point.Price, nil, 'test'))
    -- 人在范围内但引擎拒绝传送（SetPosition 抛错），命中退款 + 'teleport' 分支
    env.players[1].Character.SetPosition = function() error('boom') end
    assert.is_false(back(1, 1))
    assert.same('teleport', lastReply(1).reason)
    assert.same(point.Price, env.data[1].Data.FishCoin)
  end)

  it('test_return_waits_for_payment_and_recovery_before_teleport', function()
    local player, data = env.players[1], env.data[1]
    standAt(1, env.route.Return.AnchorName)
    data:AddCoin(40)
    env.defer = true
    assert.is_true(back(1, 1))
    assert.same(40, data.Data.FishCoin)
    assert.same(0, player.teleports)
    assert.is_nil(lastReply(1))
    drain()
    assert.same(40 - env.route.Return.Price, data.Data.FishCoin)
    assert.same(1, player.teleports)
    assert.is_true(lastReply(1).ok)
  end)

  it('test_routes_keep_independent_countdowns_and_abiders_ride_free', function()
    -- 验收 (b)(d)：不同航线各有各的倒计时，互不占用；到点时没交票的搭便船者一起被带走
    local routeA, routeB = env.routes[1], env.routes[2]
    assert.is_true(env.data[1]:AddItem(routeA.Outbound.Ticket))
    assert.is_true(env.data[2]:AddItem(routeB.Outbound.Ticket))
    standAt(1, routeA.Outbound.AnchorName)
    standAt(2, routeB.Outbound.AnchorName)
    standAt(3, routeB.Outbound.AnchorName, 1) -- 没票的搭便船玩家
    assert.is_true(board(1, 1, routeA))
    env.now = env.now + 2 -- 把两条航线的开船时刻错开，才能看出各自记账
    assert.is_true(board(2, 1, routeB))
    assert.is_not_nil(env.mgr.Flights[routeA.Id])
    assert.is_not_nil(env.mgr.Flights[routeB.Id])

    -- A 到点：只带走 A 船上的人，B 的倒计时不受影响
    env.now = env.mgr.Flights[routeA.Id].DepartAt
    env.mgr:Update()
    assert.is_nil(env.mgr.Flights[routeA.Id])
    assert.is_not_nil(env.mgr.Flights[routeB.Id])
    assert.same(routeA.ToZoneId, env.data[1].Data.Zone)
    assert.same(0, env.players[2].teleports)
    assert.same(0, env.players[3].teleports)
    assert.message('B 的票在交票时就扣掉，只扣一次').same(0, env.data[2]:ItemCount(routeB.Outbound.Ticket))

    -- B 到点：交票人与搭便船者一起走，搭便船者不付任何代价，也要有到达记录
    env.now = env.mgr.Flights[routeB.Id].DepartAt
    env.mgr:Update()
    assert.same(1, env.players[2].teleports)
    assert.same(1, env.players[3].teleports)
    assert.same(routeB.ToZoneId, env.data[2].Data.Zone)
    assert.same(routeB.ToZoneId, env.data[3].Data.Zone)
    assert.same(0, env.data[3].Data.FishCoin)
    assert.same(0, env.data[3]:ItemCount(routeB.Outbound.Ticket))
    assert.same(1, env.data[3].Extra.travel.arrived[routeB.ToZoneId])
    assert.same('departed', (env.broadcasts[#env.broadcasts]).phase)
    assert.same(routeB.Id, (env.broadcasts[#env.broadcasts]).routeId)
  end)

  it('test_second_ticket_on_same_route_rejected_not_consumed', function()
    -- 同一个航线倒计时中再交票：拒绝且不扣（第二张票还在）
    assert.is_true(env.data[1]:AddItem(env.route.Outbound.Ticket))
    assert.is_true(env.data[2]:AddItem(env.route.Outbound.Ticket))
    assert.is_true(board(1, 1))
    assert.is_false(board(2, 1))
    assert.same('sailing', lastReply(2).reason)
    assert.same(1, env.data[2]:ItemCount(env.route.Outbound.Ticket))
  end)

  it('test_teleport_notifies_special_item_before_moving', function()
    -- #140 T19：传送前必须通知特殊道具结束飞行（摆渡不得把关重力/滞空带到新区）；
    -- 未注入 SpecialItem 时传送照旧（其余用例即此路径的回归）。
    local calls = {}
    env.mgr.SpecialItem = { OnTeleport = function(_, player) calls[#calls + 1] = player.UserId end }
    local dest = { x = 100, y = 6, z = 100 }
    assert.is_true(env.mgr:Teleport(env.players[1], dest))
    assert.same({ 1 }, calls)
    assert.same(100, env.players[1].Character.Position.x)
  end)

  it('test_zone_defaults_to_home', function()
    assert.same('fishPond', env.data[1].Data.Zone)
  end)
end)

-- 迁移自 tests/gameplay/ferry_ui_test.lua（#85）；行为契约原文见 #127、#125。
-- #127 T06 摆渡界面（客户端）：六条航线十二条腿，每条腿的请求带自己的航线 id；
-- 倒计时按航线分开记账，不同航线不串台；倒计时条只显示最近的一班并写明目的区。
-- 失败方式（先列后写）：
--   1. 只建第一区的两条腿（其余航线点不到），或点某条腿发出的 routeId 是别条航线的；
--   2. 倒计时不分航线：B 航线的广播把 A 的倒计时改掉，或 A 到点把 B 也清掉；
--   3. 不带 routeId 的状态包也当成本地倒计时生效；
--   4. 文字泡不在本腿 Radius 内也显示（或半径用错）；
--   5. 提示不写目的区（返程回到出发区却报目的区），或失败原因没有对应提示。
-- seam：直接调 ScreenFerry 的 Start/Update*，替换 game/REUtil/EUI 边界（与 item_bar_ui_test 同款）。
-- it 名字沿用旧方法名，注册顺序 = LuaUnit sortedPairs 的实际执行顺序。

local moduleNames = { 'common.GameCfg', 'common.REUtil', 'common.Util',
  'client.InteractionBubble', 'client.ScreenHandlers.ScreenFerry' }

local globalNames = { 'game', 'Vector3', 'Vector2', 'Color', 'REUtil', 'LocalMsgNotice' }

local function signal()
  local listeners = {}
  return {
    Connect = function(_, fn)
      listeners[#listeners + 1] = fn
      return { Disconnect = function()
        for i, cb in ipairs(listeners) do
          if cb == fn then table.remove(listeners, i) break end
        end
      end }
    end,
    Fire = function(_, ...) for _, fn in ipairs(listeners) do fn(...) end end,
    Count = function() return #listeners end,
  }
end

local function vec(x, y, z) return { x = x, y = y, z = z } end

describe('摆渡界面（ScreenFerry）', function()
  local env
  local restore

  before_each(function()
    -- 快照先于任何改动：before_each 中途失败时 after_each 仍能还原。
    restore = {}
    for _, name in ipairs(globalNames) do
      restore[name] = rawget(_G, name)
    end
    for _, name in ipairs(moduleNames) do
      restore[name] = package.loaded[name]
      package.loaded[name] = nil
    end
    env = { nodes = {}, sceneNodes = {}, commands = {}, notices = {}, events = {} }
    env.cfg = require('common.GameCfg')
    env.routes = env.cfg.Ferry.Routes

    -- 摆渡锚点（#125 场景合同里的 Ferry 实体）连未建区一起登记，十二条腿都能建出来
    env.anchors = {}
    for _, zone in ipairs(env.cfg.Zones) do
      for _, entity in ipairs(zone.Scene.Entities) do
        if entity.Role == 'Ferry' then
          env.anchors[entity.Name] = { Name = entity.Name,
            Position = vec(entity.Position.x, entity.Position.y, entity.Position.z) }
        end
      end
    end
    local world = { FindFirstChild = function(_, name) return env.anchors[name] end }
    function world:CreateUnit(kind, attrs)
      local node = { Kind = kind, OnClicked = signal() }
      for key, value in pairs(attrs) do node[key] = value end
      node.Destroy = function() self.Destroyed = true end
      if node.Name then env.nodes[node.Name] = node end
      return node
    end

    local eui = {
      CreateSceneNodeAtPosition = function(_, position)
        local node = { Position = position, Visible = true, OnClicked = signal() }
        node.Destroy = function() self.Destroyed = true end
        env.sceneNodes[#env.sceneNodes + 1] = node
        return node
      end,
      GetRootNode = function() return { Name = 'Root' } end,
      GetDeviceResolution = function() return { x = 1920, y = 1080 } end,
    }
    env.localPlayer = { PlayerGui = { EuiManager = eui },
      Character = { Position = vec(9999, 0, 9999) } }

    _G.LocalMsgNotice = function(msg) env.notices[#env.notices + 1] = msg end
    _G.Vector3 = { New = vec }
    _G.Vector2 = { New = function(x, y) return { x = x, y = y } end }
    _G.Color = { New = function(...) return { ... } end }
    _G.game = { GetService = function(_, name)
      if name == 'World' then return world end
      if name == 'Players' then return { LocalPlayer = env.localPlayer } end
      if name == 'Task' then return { Wait = function() end } end
      if name == 'RunService' then return { IsClient = function() return true end,
        IsServer = function() return false end, Heartbeat = signal() } end
    end }
    local reStub = { GetRE = function(_, name)
      if not env.events[name] then
        env.events[name] = {
          OnClientEvent = signal(), OnServerEvent = signal(),
          FireServer = function(_, payload)
            env.commands[#env.commands + 1] = { name = name, payload = payload }
          end,
        }
      end
      return env.events[name]
    end }
    package.loaded['common.REUtil'] = reStub
    _G.REUtil = reStub

    env.handler = assert(loadfile('client/ScreenHandlers/ScreenFerry.lua'))()
    env.handler:Start()
  end)

  after_each(function()
    for _, name in ipairs(moduleNames) do
      package.loaded[name] = restore[name]
    end
    for _, name in ipairs(globalNames) do
      _G[name] = restore[name]
    end
    env = nil
    restore = nil
  end)

  it('test_countdown_is_per_route_and_label_follows_the_soonest', function()
    -- 倒计时按航线各记各的；倒计时条显示最近的一班并写明目的区
    local state = env.events.FerryState.OnClientEvent
    local routeA, routeB = env.routes[1], env.routes[2]
    state:Fire({ phase = 'countdown', routeId = routeA.Id, seconds = 5 })
    state:Fire({ phase = 'countdown', routeId = routeB.Id, seconds = 8 })
    env.handler:UpdateCountdown(4)
    assert.same(1, env.handler.Countdowns[routeA.Id])
    assert.same(4, env.handler.Countdowns[routeB.Id])
    assert.same('前往虾池 1 秒', env.nodes.FerryCountdown.Text)
    assert.is_true(env.nodes.FerryCountdown.Visible)
    -- A 到点只清 A，B 继续走（不串台）
    env.handler:UpdateCountdown(1)
    assert.is_nil(env.handler.Countdowns[routeA.Id])
    assert.same(3, env.handler.Countdowns[routeB.Id])
    assert.same('前往蟹湖 3 秒', env.nodes.FerryCountdown.Text)
    env.handler:UpdateCountdown(3)
    assert.same({}, env.handler.Countdowns)
    assert.is_false(env.nodes.FerryCountdown.Visible)
    -- 不带航线 id 的状态包不生效
    state:Fire({ phase = 'countdown', seconds = 5 })
    assert.same({}, env.handler.Countdowns)
  end)

  it('test_each_leg_sends_its_own_route_id', function()
    -- 点哪条腿就发哪条航线的 id（去程 Board / 返程 Return），seq 单调递增
    local routeA, routeB = env.routes[1], env.routes[2]
    env.nodes['BtnFerry' .. routeA.Outbound.AnchorName].OnClicked:Fire()
    env.nodes['BtnFerry' .. routeB.Return.AnchorName].OnClicked:Fire()
    assert.same(2, #env.commands)
    assert.same('FerryAction', env.commands[1].name)
    assert.same({ action = 'Board', routeId = routeA.Id, seq = 1 }, env.commands[1].payload)
    assert.same({ action = 'Return', routeId = routeB.Id, seq = 2 }, env.commands[2].payload)
  end)

  it('test_leg_bubble_shows_only_within_its_radius', function()
    -- 文字泡只在本腿半径内显示，且不影响别条腿
    local leg, other = env.handler.Legs['1:out'], env.handler.Legs['2:out']
    env.handler:UpdateLegs()
    assert.is_false(leg.Node.Visible)
    assert.is_false(other.Node.Visible)
    local center = leg.Center
    env.localPlayer.Character.Position = vec(center.x + leg.Radius - 0.1, center.y, center.z)
    env.handler:UpdateLegs()
    assert.is_true(leg.Node.Visible)
    assert.is_false(other.Node.Visible)
    env.localPlayer.Character.Position = vec(center.x + leg.Radius + 0.1, center.y, center.z)
    env.handler:UpdateLegs()
    assert.is_false(leg.Node.Visible)
  end)

  it('test_notices_name_the_route_and_its_destination', function()
    -- 状态与回包提示都带目的区；返程回的是出发区，失败原因各有对应提示
    local state, result = env.events.FerryState.OnClientEvent, env.events.FerryResult.OnClientEvent
    local routeA, routeB = env.routes[1], env.routes[2]
    state:Fire({ phase = 'countdown', routeId = routeA.Id, seconds = 5 })
    state:Fire({ phase = 'departed', routeId = routeA.Id })
    assert.is_nil(env.handler.Countdowns[routeA.Id])
    assert.same('已经到虾池了', env.notices[#env.notices])
    state:Fire({ phase = 'cancelled', routeId = routeB.Id })
    assert.same('前往蟹湖的航班取消，船票已退', env.notices[#env.notices])
    result:Fire({ ok = true, action = 'Board', routeId = routeA.Id, seconds = 5 })
    assert.same('船票已交，5 秒后开船', env.notices[#env.notices])
    result:Fire({ ok = true, action = 'Return', routeId = routeA.Id, price = 10 })
    assert.same('已经回到鱼塘，金币 -10', env.notices[#env.notices])
    result:Fire({ ok = false, action = 'Board', routeId = 'fishPond>volcanoIsland', reason = 'route' })
    assert.same('找不到这条航线，请重进本图', env.notices[#env.notices])
    result:Fire({ ok = false, action = 'Return', routeId = routeA.Id, reason = 'coin' })
    assert.same('金币不够，船家不开船', env.notices[#env.notices])
  end)

  it('test_twelve_legs_cover_six_routes', function()
    -- 十二条腿都建出来，每条腿用本航线的锚点与半径，按钮名互不重复
    assert.same(6, #env.routes)
    local total = 0
    for _ in pairs(env.handler.Legs) do total = total + 1 end
    assert.same(12, total)
    for index, route in ipairs(env.routes) do
      assert.same(route.Outbound.Radius, env.handler.Legs[index .. ':out'].Radius)
      assert.same(env.anchors[route.Outbound.AnchorName].Position, env.handler.Legs[index .. ':out'].Center)
      assert.same(env.anchors[route.Return.AnchorName].Position, env.handler.Legs[index .. ':return'].Center)
      assert.is_not_nil(env.nodes['BtnFerry' .. route.Outbound.AnchorName])
      assert.is_not_nil(env.nodes['BtnFerry' .. route.Return.AnchorName])
    end
    assert.is_not_nil(env.nodes.FerryCountdown)
    assert.same(12, #env.sceneNodes)
  end)
end)

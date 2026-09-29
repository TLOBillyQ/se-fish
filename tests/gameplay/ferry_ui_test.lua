-- #127 T06 摆渡界面（客户端）：六条航线十二条腿，每条腿的请求带自己的航线 id；
-- 倒计时按航线分开记账，不同航线不串台；倒计时条只显示最近的一班并写明目的区。
-- 失败方式（先列后写）：
--   1. 只建第一区的两条腿（其余航线点不到），或点某条腿发出的 routeId 是别条航线的；
--   2. 倒计时不分航线：B 航线的广播把 A 的倒计时改掉，或 A 到点把 B 也清掉；
--   3. 不带 routeId 的状态包也当成本地倒计时生效；
--   4. 文字泡不在本腿 Radius 内也显示（或半径用错）；
--   5. 提示不写目的区（返程回到出发区却报目的区），或失败原因没有对应提示。
-- seam：直接调 ScreenFerry 的 Start/Update*，替换 game/REUtil/EUI 边界（与 item_bar_ui_test 同款）。
local lu = require('luaunit')

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

TestScreenFerry = {}

function TestScreenFerry:setUp()
    local env = self
    self.previous = { game = rawget(_G, 'game'), Vector3 = rawget(_G, 'Vector3'),
        Vector2 = rawget(_G, 'Vector2'), Color = rawget(_G, 'Color'),
        REUtil = rawget(_G, 'REUtil'), LocalMsgNotice = rawget(_G, 'LocalMsgNotice') }
    self.previousLoaded = {}
    for _, name in ipairs({ 'common.GameCfg', 'common.REUtil', 'common.Util',
        'client.InteractionBubble', 'client.ScreenHandlers.ScreenFerry' }) do
        self.previousLoaded[name] = package.loaded[name]
        package.loaded[name] = nil
    end
    self.cfg = require('common.GameCfg')
    self.routes = self.cfg.Ferry.Routes

    -- 摆渡锚点（#125 场景合同里的 Ferry 实体）连未建区一起登记，十二条腿都能建出来
    self.anchors = {}
    for _, zone in ipairs(self.cfg.Zones) do
        for _, entity in ipairs(zone.Scene.Entities) do
            if entity.Role == 'Ferry' then
                self.anchors[entity.Name] = { Name = entity.Name,
                    Position = vec(entity.Position.x, entity.Position.y, entity.Position.z) }
            end
        end
    end
    self.nodes = {}
    local world = { FindFirstChild = function(_, name) return env.anchors[name] end }
    function world:CreateUnit(kind, attrs)
        local node = { Kind = kind, OnClicked = signal() }
        for key, value in pairs(attrs) do node[key] = value end
        node.Destroy = function() self.Destroyed = true end
        if node.Name then env.nodes[node.Name] = node end
        return node
    end

    self.sceneNodes = {}
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
    self.localPlayer = { PlayerGui = { EuiManager = eui },
        Character = { Position = vec(9999, 0, 9999) } }

    self.commands, self.notices, self.events = {}, {}, {}
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

    self.handler = assert(loadfile('client/ScreenHandlers/ScreenFerry.lua'))()
    self.handler:Start()
end

function TestScreenFerry:tearDown()
    for name, module in pairs(self.previousLoaded) do package.loaded[name] = module end
    for _, key in ipairs({ 'game', 'Vector3', 'Vector2', 'Color', 'REUtil', 'LocalMsgNotice' }) do
        _G[key] = self.previous[key]
    end
end

-- 十二条腿都建出来，每条腿用本航线的锚点与半径，按钮名互不重复
function TestScreenFerry:test_twelve_legs_cover_six_routes()
    lu.assertEquals(#self.routes, 6)
    local total = 0
    for _ in pairs(self.handler.Legs) do total = total + 1 end
    lu.assertEquals(total, 12)
    for index, route in ipairs(self.routes) do
        lu.assertEquals(self.handler.Legs[index .. ':out'].Radius, route.Outbound.Radius)
        lu.assertEquals(self.handler.Legs[index .. ':out'].Center,
            self.anchors[route.Outbound.AnchorName].Position)
        lu.assertEquals(self.handler.Legs[index .. ':return'].Center,
            self.anchors[route.Return.AnchorName].Position)
        lu.assertNotNil(self.nodes['BtnFerry' .. route.Outbound.AnchorName])
        lu.assertNotNil(self.nodes['BtnFerry' .. route.Return.AnchorName])
    end
    lu.assertNotNil(self.nodes.FerryCountdown)
    lu.assertEquals(#self.sceneNodes, 12)
end

-- 点哪条腿就发哪条航线的 id（去程 Board / 返程 Return），seq 单调递增
function TestScreenFerry:test_each_leg_sends_its_own_route_id()
    local routeA, routeB = self.routes[1], self.routes[2]
    self.nodes['BtnFerry' .. routeA.Outbound.AnchorName].OnClicked:Fire()
    self.nodes['BtnFerry' .. routeB.Return.AnchorName].OnClicked:Fire()
    lu.assertEquals(#self.commands, 2)
    lu.assertEquals(self.commands[1].name, 'FerryAction')
    lu.assertEquals(self.commands[1].payload, { action = 'Board', routeId = routeA.Id, seq = 1 })
    lu.assertEquals(self.commands[2].payload, { action = 'Return', routeId = routeB.Id, seq = 2 })
end

-- 倒计时按航线各记各的；倒计时条显示最近的一班并写明目的区
function TestScreenFerry:test_countdown_is_per_route_and_label_follows_the_soonest()
    local state = self.events.FerryState.OnClientEvent
    local routeA, routeB = self.routes[1], self.routes[2]
    state:Fire({ phase = 'countdown', routeId = routeA.Id, seconds = 5 })
    state:Fire({ phase = 'countdown', routeId = routeB.Id, seconds = 8 })
    self.handler:UpdateCountdown(4)
    lu.assertEquals(self.handler.Countdowns[routeA.Id], 1)
    lu.assertEquals(self.handler.Countdowns[routeB.Id], 4)
    lu.assertEquals(self.nodes.FerryCountdown.Text, '前往虾池 1 秒')
    lu.assertTrue(self.nodes.FerryCountdown.Visible)
    -- A 到点只清 A，B 继续走（不串台）
    self.handler:UpdateCountdown(1)
    lu.assertNil(self.handler.Countdowns[routeA.Id])
    lu.assertEquals(self.handler.Countdowns[routeB.Id], 3)
    lu.assertEquals(self.nodes.FerryCountdown.Text, '前往蟹湖 3 秒')
    self.handler:UpdateCountdown(3)
    lu.assertEquals(self.handler.Countdowns, {})
    lu.assertFalse(self.nodes.FerryCountdown.Visible)
    -- 不带航线 id 的状态包不生效
    state:Fire({ phase = 'countdown', seconds = 5 })
    lu.assertEquals(self.handler.Countdowns, {})
end

-- 文字泡只在本腿半径内显示，且不影响别条腿
function TestScreenFerry:test_leg_bubble_shows_only_within_its_radius()
    local leg, other = self.handler.Legs['1:out'], self.handler.Legs['2:out']
    self.handler:UpdateLegs()
    lu.assertFalse(leg.Node.Visible)
    lu.assertFalse(other.Node.Visible)
    local center = leg.Center
    self.localPlayer.Character.Position = vec(center.x + leg.Radius - 0.1, center.y, center.z)
    self.handler:UpdateLegs()
    lu.assertTrue(leg.Node.Visible)
    lu.assertFalse(other.Node.Visible)
    self.localPlayer.Character.Position = vec(center.x + leg.Radius + 0.1, center.y, center.z)
    self.handler:UpdateLegs()
    lu.assertFalse(leg.Node.Visible)
end

-- 状态与回包提示都带目的区；返程回的是出发区，失败原因各有对应提示
function TestScreenFerry:test_notices_name_the_route_and_its_destination()
    local state, result = self.events.FerryState.OnClientEvent, self.events.FerryResult.OnClientEvent
    local routeA, routeB = self.routes[1], self.routes[2]
    state:Fire({ phase = 'countdown', routeId = routeA.Id, seconds = 5 })
    state:Fire({ phase = 'departed', routeId = routeA.Id })
    lu.assertNil(self.handler.Countdowns[routeA.Id])
    lu.assertEquals(self.notices[#self.notices], '已经到虾池了')
    state:Fire({ phase = 'cancelled', routeId = routeB.Id })
    lu.assertEquals(self.notices[#self.notices], '前往蟹湖的航班取消，船票已退')
    result:Fire({ ok = true, action = 'Board', routeId = routeA.Id, seconds = 5 })
    lu.assertEquals(self.notices[#self.notices], '船票已交，5 秒后开船')
    result:Fire({ ok = true, action = 'Return', routeId = routeA.Id, price = 10 })
    lu.assertEquals(self.notices[#self.notices], '已经回到鱼塘，金币 -10')
    result:Fire({ ok = false, action = 'Board', routeId = 'fishPond>volcanoIsland', reason = 'route' })
    lu.assertEquals(self.notices[#self.notices], '找不到这条航线，请重进本图')
    result:Fire({ ok = false, action = 'Return', routeId = routeA.Id, reason = 'coin' })
    lu.assertEquals(self.notices[#self.notices], '金币不够，船家不开船')
end

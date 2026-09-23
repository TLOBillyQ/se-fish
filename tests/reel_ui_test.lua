local lu = require('luaunit')

TestReelUI = {}

local function signal()
    local listeners = {}
    return { Connect = function(_, fn)
        listeners[#listeners + 1] = fn
        return { Disconnect = function() end }
    end, Fire = function(_, ...)
        for _, fn in ipairs(listeners) do fn(...) end
    end }
end

function TestReelUI:setUp()
    self.globals = { game = _G.game, Vector2 = _G.Vector2, Color = _G.Color,
        REUtil = _G.REUtil, GameUI = _G.GameUI, LocalReelIn = _G.LocalReelIn,
        MgrGameUI = _G.MgrGameUI }
    self.modules = {}
    for _, name in ipairs({ 'common.REUtil', 'common.Util', 'client.GameUI',
        'client.ScreenHandlers.ScreenMain', 'client.LocalReelIn' }) do
        self.modules[name] = package.loaded[name]
    end
    local env = self
    self.events, self.sent, self.nodes = {}, {}, {}
    self.heartbeat = signal()
    self.now = 0
    local world = { GetServerTime = function() return env.now end }
    function world:CreateUnit(kind, attrs)
        local node = { Kind = kind, OnClicked = signal() }
        for key, value in pairs(attrs) do node[key] = value end
        function node:Destroy() self.Destroyed = true end
        env.nodes[node.Name] = node
        return node
    end
    _G.game = { GetService = function(_, name)
        if name == 'World' then return world end
        if name == 'RunService' then return { Heartbeat = env.heartbeat } end
        return {}
    end }
    _G.Vector2 = { New = function(x, y) return { x = x, y = y } end }
    _G.Color = { New = function(...) return { ... } end }
    self.root = { Visible = false, Name = 'ScreenMain',
        FindFirstChild = function() return nil end }
    local uiRoot = { FindFirstChild = function(_, name)
        if name == 'ScreenMain' then return env.root end
    end }
    _G.GameUI = { GetEuiManager = function() return {
        GetDeviceResolution = function() return { x = 1920, y = 1080 } end,
    } end, GetUIRoot = function() return uiRoot end }
    local remote = { GetRE = function(_, name)
        if not env.events[name] then
            env.events[name] = { OnClientEvent = signal(), FireServer = function(_, payload)
                env.sent[#env.sent + 1] = { name = name, payload = payload }
            end }
        end
        return env.events[name]
    end }
    _G.REUtil = remote
    package.loaded['common.REUtil'] = remote
    package.loaded['common.Util'] = {}
    package.loaded['client.GameUI'] = _G.GameUI
    self.reel = assert(loadfile('client/LocalReelIn.lua'))()
    _G.LocalReelIn = self.reel
    self.reel:Start()
    self.handler = assert(loadfile('client/ScreenHandlers/ScreenMain.lua'))()
    package.loaded['client.ScreenHandlers.ScreenMain'] = self.handler
    self.ui = assert(loadfile('client/MgrGameUI.lua'))()
    self.ui:OpenScreen('ScreenMain')
end

function TestReelUI:tearDown()
    for name, value in pairs(self.modules) do package.loaded[name] = value end
    for _, name in ipairs({ 'common.REUtil', 'common.Util', 'client.GameUI',
        'client.ScreenHandlers.ScreenMain', 'client.LocalReelIn' }) do
        if not self.modules[name] then package.loaded[name] = nil end
    end
    for name, value in pairs(self.globals) do _G[name] = value end
    for _, name in ipairs({ 'game', 'Vector2', 'Color', 'REUtil', 'GameUI',
        'LocalReelIn', 'MgrGameUI' }) do
        if not self.globals[name] then _G[name] = nil end
    end
end

-- 让本地追平走完：时间跳过 ChaseSec（0.25 秒，期间按 5%/秒衰减 1.25%）再逐帧刷新
function TestReelUI:settle()
    self.now = self.now + 0.25
    self.heartbeat:Fire()
end

-- #38：点击立即显示 +5%，服务端报告落后超过 5% 时逐帧平滑追平
function TestReelUI:test_click_feedback_and_smooth_chase_on_the_bar()
    self.events.ItemBarState.OnClientEvent:Fire({ slots = {
        [1] = { itemId = 'starterRod', count = 1 },
    }, bait = { worm = 1 }, selectedSlot = 1 })
    self.events.CastState.OnClientEvent:Fire({ phase = 'hooked', reelSession = 'p1' })
    self.events.ReelInRE.OnClientEvent:Fire({ action = 'started', session = 'p1', progress = 50 })
    self.nodes.ItemAction2.OnClicked:Fire()
    lu.assertEquals(self.nodes.ReelProgress.Percent, 55)
    self.now = 0.1
    self.heartbeat:Fire()
    local sent = self.sent[#self.sent]
    lu.assertEquals(sent.payload, { s = 'p1', n = 1, q = 1 })
    lu.assertAlmostEquals(self.nodes.ReelProgress.Percent, 54.5, 1e-9)
    self.events.ReelInRE.OnClientEvent:Fire({ action = 'progress', session = 'p1', progress = 40, accepted = 0, q = 1 })
    lu.assertAlmostEquals(self.nodes.ReelProgress.Percent, 54.5, 1e-9)
    self.now = 0.19
    self.heartbeat:Fire()
    local mid = self.nodes.ReelProgress.Percent
    lu.assertTrue(mid < 54.5 and mid > 39.55, tostring(mid))
    self.now = 0.3
    self.heartbeat:Fire()
    lu.assertAlmostEquals(self.nodes.ReelProgress.Percent, 39, 1e-9)
end

function TestReelUI:test_close_flush_and_stale_echo_cannot_reopen()
    self.events.ItemBarState.OnClientEvent:Fire({ slots = {
        [1] = { itemId = 'starterRod', count = 1 },
    }, bait = { worm = 1 }, selectedSlot = 1 })
    self.events.CastState.OnClientEvent:Fire({ phase = 'hooked', reelSession = 's1' })
    lu.assertEquals(self.reel.SessionId, 's1')
    lu.assertEquals(self.nodes.ReelProgress.Kind, 'EUILoadingBar')
    lu.assertFalse(self.nodes.ReelProgress.TouchEnabled)
    lu.assertFalse(self.nodes.ReelProgress.SwallowTouchEnabled)
    lu.assertEquals(self.nodes.ReelProgress.Percent, 50)
    self.events.ReelInRE.OnClientEvent:Fire({ action = 'progress', session = 's1', progress = 37.25 })
    lu.assertEquals(self.nodes.ReelProgress.Percent, 50)
    self:settle()
    lu.assertEquals(self.nodes.ReelProgress.Percent, 36)
    self.nodes.ReelProgress.OnClicked:Fire()
    lu.assertEquals(self.reel.Aggregator:PendingCount(), 0)
    self.nodes.ItemAction2.OnClicked:Fire()
    self.ui:CloseScreen('ScreenMain')
    lu.assertEquals(self.sent[#self.sent - 1], {
        name = 'ReelInRE', payload = { s = 's1', n = 1, q = 1 } })
    lu.assertEquals(self.sent[#self.sent], {
        name = 'CloseReelIn', payload = { session = 's1' } })
    lu.assertFalse(self.nodes.ReelProgress.Visible)
    lu.assertFalse(self.nodes.ItemAction2.TouchEnabled)
    local sent = #self.sent
    self.nodes.ItemAction2.OnClicked:Fire()
    self.events.ReelInRE.OnClientEvent:Fire({ action = 'started', session = 's1', progress = 50 })
    self.events.CastState.OnClientEvent:Fire({ phase = 'hooked', reelSession = 's1' })
    lu.assertNil(self.reel.SessionId)
    lu.assertEquals(#self.sent, sent)
    self.ui:OpenScreen('ScreenMain')
    lu.assertNil(self.reel.SessionId)
    self.events.CastState.OnClientEvent:Fire({ phase = 'hooked', reelSession = 's1' })
    lu.assertNil(self.reel.SessionId)
    lu.assertFalse(self.nodes.ReelProgress.Visible)
    self.events.CastState.OnClientEvent:Fire({ phase = 'hooked', reelSession = 's2' })
    lu.assertEquals(self.reel.SessionId, 's2')
    lu.assertTrue(self.nodes.ItemAction2.TouchEnabled)
    lu.assertTrue(self.nodes.ReelProgress.Visible)
    self.events.ReelInRE.OnClientEvent:Fire({ action = 'progress', session = 's2', progress = 0 })
    self:settle()
    lu.assertEquals(self.nodes.ReelProgress.Percent, 0)
    self.events.ReelInRE.OnClientEvent:Fire({ action = 'progress', session = 's2', progress = 100 })
    self:settle()
    lu.assertEquals(self.nodes.ReelProgress.Percent, 98.75)
end

function TestReelUI:test_started_during_closed_screen_is_cancelled_without_opening()
    self.ui:CloseScreen('ScreenMain')
    self.events.ReelInRE.OnClientEvent:Fire({ action = 'started', session = 'late', progress = 50 })
    lu.assertEquals(self.sent[#self.sent], {
        name = 'CloseReelIn', payload = { session = 'late' } })
    lu.assertNil(self.reel.SessionId)
    self.ui:OpenScreen('ScreenMain')
    self.events.CastState.OnClientEvent:Fire({ phase = 'hooked', reelSession = 'late' })
    lu.assertNil(self.reel.SessionId)
    lu.assertFalse(self.nodes.ItemAction2.TouchEnabled)
end

-- #37：上岸瞬间「收线」按钮灰化且不可点，回到 idle 后恢复成抛竿
function TestReelUI:test_landed_greys_out_action_button()
    self.events.ItemBarState.OnClientEvent:Fire({ slots = {
        [1] = { itemId = 'starterRod', count = 1 },
    }, bait = { worm = 1 }, selectedSlot = 1 })
    local normal = self.nodes.ItemAction2.ButtonNormalColor
    self.events.CastState.OnClientEvent:Fire({ phase = 'hooked', reelSession = 'g1' })
    self.events.CastState.OnClientEvent:Fire({ phase = 'landed', reelSession = 'g1' })
    lu.assertFalse(self.nodes.ItemAction2.TouchEnabled)
    lu.assertEquals(self.nodes.ItemAction2.ButtonNormalColor, { 120, 120, 120, 255 })
    local sent = #self.sent
    self.nodes.ItemAction2.OnClicked:Fire()
    lu.assertEquals(#self.sent, sent)
    self.events.CastState.OnClientEvent:Fire({ phase = 'idle' })
    lu.assertTrue(self.nodes.ItemAction2.TouchEnabled)
    lu.assertEquals(self.nodes.ItemAction2.ButtonNormalColor, normal)
    lu.assertEquals(self.nodes.BtnItemActionLabel.Text, '抛竿')
end

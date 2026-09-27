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
    self.globals = { game = _G.game, Vector2 = _G.Vector2, Vector3 = _G.Vector3, Color = _G.Color,
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
    self.projected = { x = 960, y = 540, z = 4 }
    self.camera = { WorldToViewportPoint = function(_, position)
        env.lastProjected = position
        return env.projected, true
    end }
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
        if name == 'CameraService' then return env.camera end
        return {}
    end }
    _G.Vector2 = { New = function(x, y) return { x = x, y = y } end }
    _G.Vector3 = { New = function(x, y, z) return { x = x, y = y, z = z } end }
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
    for _, name in ipairs({ 'game', 'Vector2', 'Vector3', 'Color', 'REUtil', 'GameUI',
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

-- #41：服务端报告头上顶着鱼时 2 号位显示「放下」并只发放下请求；没带 holding 就回到抛竿
function TestReelUI:test_holding_fish_turns_action_into_drop()
    self.events.ItemBarState.OnClientEvent:Fire({ slots = {
        [1] = { itemId = 'starterRod', count = 1 },
    }, bait = { worm = 1 }, selectedSlot = 1 })
    self.events.CastState.OnClientEvent:Fire({ phase = 'idle', holding = { fishId = 'bass', mult = 1.2 } })
    lu.assertEquals(self.nodes.BtnItemActionLabel.Text, '放下')
    lu.assertTrue(self.nodes.ItemAction2.TouchEnabled)
    local sent = #self.sent
    self.nodes.ItemAction2.OnClicked:Fire()
    lu.assertEquals(#self.sent, sent + 1)
    lu.assertEquals(self.sent[#self.sent].name, 'CastAction')
    lu.assertEquals(self.sent[#self.sent].payload, { action = 'Drop' })
    self.events.CastState.OnClientEvent:Fire({ phase = 'idle' })
    lu.assertEquals(self.nodes.BtnItemActionLabel.Text, '抛竿')
end

function TestReelUI:test_holding_fish_shows_drop_even_without_rod_selected()
    self.events.ItemBarState.OnClientEvent:Fire({ slots = {
        [1] = { itemId = 'starterRod', count = 1 },
    }, bait = { worm = 1 } })
    self.events.CastState.OnClientEvent:Fire({ phase = 'idle', holding = { fishId = 'carp', mult = 1 } })
    lu.assertTrue(self.nodes.ItemAction2.Visible)
    lu.assertEquals(self.nodes.BtnItemActionLabel.Text, '放下')
end

function TestReelUI:test_waiting_feedback_tracks_landing_and_does_not_repeat_on_snapshot()
    local state = { phase = 'cast', castId = 1, zoneId = 'WaterCircle2',
        landing = { x = 12, y = 3, z = 27 } }
    self.events.CastState.OnClientEvent:Fire(state)
    lu.assertTrue(self.nodes.CastFloat.Visible)
    lu.assertEquals(self.nodes.CastFloat.Text, '●')
    lu.assertEquals(self.nodes.CastWaitHint.Text, '等待上钩…')
    lu.assertTrue(self.nodes.CastSplashHint.Visible)
    lu.assertEquals(self.nodes.CastSplashHint.Text, '已入水，等待上钩')
    lu.assertEquals(self.lastProjected, state.landing)
    lu.assertEquals(self.nodes.CastFloat.Position, { x = 960, y = 540 })
    self.projected = { x = 900, y = 400, z = 4 }
    self.heartbeat:Fire()
    lu.assertEquals(self.nodes.CastFloat.Position, { x = 900, y = 680 })
    self.now = 4
    self.heartbeat:Fire()
    lu.assertFalse(self.nodes.CastSplashHint.Visible)
    self.events.CastState.OnClientEvent:Fire(state)
    lu.assertFalse(self.nodes.CastSplashHint.Visible)
    lu.assertTrue(self.nodes.CastFloat.Visible)
end

function TestReelUI:test_failure_result_marks_landing_and_does_not_replace_cast_state()
    local landing = { x = 12, y = 3, z = 27 }
    self.events.CastState.OnClientEvent:Fire({ result = { reason = 'invalidLanding', landing = landing } })
    lu.assertEquals(self.nodes.CastFailureHint.Text, '落点不在可钓水域，请重新抛竿')
    lu.assertTrue(self.nodes.CastFailureHint.Visible)
    lu.assertTrue(self.nodes.CastFailureMark.Visible)
    lu.assertEquals(self.lastProjected, landing)
    lu.assertNil(self.handler.CastState)
    self.now = 3
    self.heartbeat:Fire()
    lu.assertFalse(self.nodes.CastFailureHint.Visible)
    lu.assertFalse(self.nodes.CastFailureMark.Visible)
    self.events.CastState.OnClientEvent:Fire({ result = { reason = 'cooldown' } })
    lu.assertTrue(self.nodes.CastFailureHint.Visible)
    lu.assertFalse(self.nodes.CastFailureMark.Visible)
    self.events.CastState.OnClientEvent:Fire({ phase = 'cast', castId = 1,
        zoneId = 'WaterCircle2', landing = landing })
    lu.assertFalse(self.nodes.CastFailureHint.Visible)
    lu.assertTrue(self.nodes.CastFloat.Visible)
end

function TestReelUI:test_invalid_landing_feedback_clears_on_interrupt_and_new_failure_survives()
    self.events.ItemBarState.OnClientEvent:Fire({ slots = {
        [1] = { itemId = 'starterRod', count = 1 },
    }, bait = { worm = 2 }, selectedSlot = 1 })
    local landing = { x = 12, y = 3, z = 27 }
    self.events.CastState.OnClientEvent:Fire({ phase = 'idle', result = {
        reason = 'invalidLanding', landing = landing,
    } })
    lu.assertTrue(self.nodes.CastFailureMark.Visible)
    lu.assertEquals(self.nodes.CastFailureMark.Position, { x = 960, y = 540 })
    lu.assertEquals(self.nodes.BtnItemActionLabel.Text, '抛竿')
    lu.assertTrue(self.nodes.ItemAction2.TouchEnabled)
    self.nodes.ItemAction2.OnClicked:Fire()
    lu.assertEquals(self.sent[#self.sent], { name = 'CastAction', payload = {
        action = 'Cast', slot = 1, itemId = 'starterRod',
    } })
    self.events.CastState.OnClientEvent:Fire({ phase = 'idle' })
    lu.assertFalse(self.nodes.CastFailureMark.Visible)
    lu.assertFalse(self.nodes.CastFailureHint.Visible)
    self.events.CastState.OnClientEvent:Fire({ result = {
        reason = 'invalidLanding', landing = landing,
    } })
    lu.assertTrue(self.nodes.CastFailureMark.Visible)
    self.now = 1
    self.heartbeat:Fire()
    lu.assertTrue(self.nodes.CastFailureMark.Visible)
    self.projected = { x = 900, y = 400, z = 4 }
    self.heartbeat:Fire()
    lu.assertEquals(self.nodes.CastFailureMark.Position, { x = 900, y = 680 })
    self.ui:CloseScreen('ScreenMain')
    lu.assertFalse(self.nodes.CastFailureMark.Visible)
    self.ui:OpenScreen('ScreenMain')
    lu.assertFalse(self.nodes.CastFailureHint.Visible)
    self.handler:Destroy()
    lu.assertTrue(self.nodes.CastFailureMark.Destroyed)
end

function TestReelUI:test_stale_snapshot_and_cast_do_not_clear_new_invalid_landing_feedback()
    self.events.CastState.OnClientEvent:Fire({ phase = 'cast', castId = 1,
        zoneId = 'WaterCircle2', landing = { x = 12, y = 3, z = 27 } })
    self.events.CastState.OnClientEvent:Fire({ phase = 'idle' })
    self.events.CastState.OnClientEvent:Fire({ phase = 'cast', castId = 2,
        zoneId = 'WaterCircle2', landing = { x = 12, y = 3, z = 27 } })
    self.events.CastState.OnClientEvent:Fire({ phase = 'idle' })
    self.events.CastState.OnClientEvent:Fire({ result = {
        reason = 'invalidLanding', landing = { x = 24, y = 3, z = 30 },
    } })
    self.events.CastState.OnClientEvent:Fire({ phase = 'idle', snapshot = true })
    lu.assertTrue(self.nodes.CastFailureMark.Visible)
    lu.assertTrue(self.nodes.CastFailureHint.Visible)
    self.events.CastState.OnClientEvent:Fire({ phase = 'cast', castId = 1,
        zoneId = 'WaterCircle2', landing = { x = 12, y = 3, z = 27 } })
    lu.assertTrue(self.nodes.CastFailureMark.Visible)
    lu.assertEquals(self.handler.CastState.phase, 'idle')
end

function TestReelUI:test_empty_draw_clears_waiting_and_recast_replaces_feedback()
    self.events.ItemBarState.OnClientEvent:Fire({ slots = {
        [1] = { itemId = 'starterRod', count = 1 },
    }, bait = { worm = 2 }, selectedSlot = 1 })
    local landing = { x = 12, y = 3, z = 27 }
    self.events.CastState.OnClientEvent:Fire({ phase = 'cast', castId = 1,
        zoneId = 'WaterCircle2', landing = landing })
    lu.assertTrue(self.nodes.CastFloat.Visible)
    self.events.CastState.OnClientEvent:Fire({ phase = 'idle', castId = 1,
        result = { reason = 'noFish' } })
    lu.assertEquals(self.nodes.CastFailureHint.Text, '本次没有鱼上钩，请重新抛竿')
    lu.assertTrue(self.nodes.CastFailureHint.Visible)
    lu.assertFalse(self.nodes.CastFloat.Visible)
    lu.assertFalse(self.nodes.CastWaitHint.Visible)
    lu.assertFalse(self.nodes.CastSplashHint.Visible)
    lu.assertTrue(self.nodes.ItemAction2.TouchEnabled)
    lu.assertEquals(self.nodes.BtnItemActionLabel.Text, '抛竿')
    self.nodes.ItemAction2.OnClicked:Fire()
    lu.assertEquals(self.sent[#self.sent].payload, {
        action = 'Cast', slot = 1, itemId = 'starterRod',
    })
    self.events.CastState.OnClientEvent:Fire({ phase = 'cast', castId = 2,
        zoneId = 'WaterCircle2', landing = landing })
    lu.assertTrue(self.nodes.CastFloat.Visible)
    lu.assertFalse(self.nodes.CastFailureHint.Visible)
    self.events.CastState.OnClientEvent:Fire({ phase = 'idle', castId = 1,
        result = { reason = 'noFish' } })
    lu.assertEquals(self.handler.CastState.castId, 2)
    lu.assertTrue(self.nodes.CastWaitHint.Visible)
    lu.assertFalse(self.nodes.CastFailureHint.Visible)
end

function TestReelUI:test_failure_result_is_not_replayed_after_reopen()
    self.events.CastState.OnClientEvent:Fire({ result = { reason = 'noFish' } })
    lu.assertEquals(self.nodes.CastFailureHint.Text, '本次没有鱼上钩，请重新抛竿')
    self.ui:CloseScreen('ScreenMain')
    lu.assertFalse(self.nodes.CastFailureHint.Visible)
    self.ui:OpenScreen('ScreenMain')
    self.events.CastState.OnClientEvent:Fire({ phase = 'idle', snapshot = true })
    lu.assertFalse(self.nodes.CastFailureHint.Visible)
end

function TestReelUI:test_waiting_feedback_clears_on_hook_reel_death_and_recast()
    local function cast(id)
        self.events.CastState.OnClientEvent:Fire({ phase = 'cast', castId = id,
            zoneId = 'WaterCircle2', landing = { x = 12, y = 3, z = 27 } })
    end
    cast(1)
    self.events.CastState.OnClientEvent:Fire({ phase = 'hooked', reelSession = 'hook1' })
    lu.assertFalse(self.nodes.CastFloat.Visible)
    lu.assertFalse(self.nodes.CastWaitHint.Visible)
    lu.assertFalse(self.nodes.CastSplashHint.Visible)
    self.events.CastState.OnClientEvent:Fire({ phase = 'idle' })
    cast(2)
    lu.assertTrue(self.nodes.CastSplashHint.Visible)
    self.events.CastState.OnClientEvent:Fire({ phase = 'idle' })
    lu.assertFalse(self.nodes.CastFloat.Visible)
    cast(3)
    self.events.CastState.OnClientEvent:Fire({ phase = 'idle' })
    lu.assertFalse(self.nodes.CastWaitHint.Visible)
    cast(4)
    lu.assertTrue(self.nodes.CastFloat.Visible)
    self.events.CastState.OnClientEvent:Fire({ phase = 'cast', castId = 5, snapshot = true,
        zoneId = 'WaterCircle2', landing = { x = 0, y = 3, z = 0 } })
    lu.assertFalse(self.nodes.CastSplashHint.Visible)
    self.events.CastState.OnClientEvent:Fire({ phase = 'cast', castId = 1,
        zoneId = 'WaterCircle2', landing = { x = 12, y = 3, z = 27 } })
    lu.assertEquals(self.handler.CastState.castId, 5)
    lu.assertFalse(self.nodes.CastSplashHint.Visible)
end

function TestReelUI:test_reopen_restores_waiting_without_splash_and_destroy_cleans_nodes()
    local state = { phase = 'cast', castId = 9, zoneId = 'WaterCircle2',
        landing = { x = 12, y = 3, z = 27 } }
    self.events.CastState.OnClientEvent:Fire(state)
    self.ui:CloseScreen('ScreenMain')
    lu.assertFalse(self.nodes.CastFloat.Visible)
    lu.assertFalse(self.nodes.CastWaitHint.Visible)
    lu.assertFalse(self.nodes.CastSplashHint.Visible)
    self.ui:OpenScreen('ScreenMain')
    self.events.CastState.OnClientEvent:Fire({ phase = 'cast', castId = 9, snapshot = true,
        zoneId = 'WaterCircle2', landing = state.landing })
    lu.assertTrue(self.nodes.CastFloat.Visible)
    lu.assertTrue(self.nodes.CastWaitHint.Visible)
    lu.assertFalse(self.nodes.CastSplashHint.Visible)
    self.events.CastState.OnClientEvent:Fire({ phase = 'idle' })
    self.ui:CloseScreen('ScreenMain')
    self.ui:OpenScreen('ScreenMain')
    self.events.CastState.OnClientEvent:Fire({ phase = 'cast', castId = 10, snapshot = true,
        zoneId = 'WaterCircle2', landing = state.landing })
    lu.assertTrue(self.nodes.CastWaitHint.Visible)
    lu.assertFalse(self.nodes.CastSplashHint.Visible)
    local float = self.nodes.CastFloat
    self.handler:Destroy()
    lu.assertTrue(float.Destroyed)
end

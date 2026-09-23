local lu = require('luaunit')

TestReelSession = {}
local function signal()
    local callbacks = {}
    return {
        Connect = function(_, fn)
            callbacks[#callbacks + 1] = fn
            return { Disconnect = function() end }
        end,
        Fire = function(_, ...) for _, fn in ipairs(callbacks) do fn(...) end end,
    }
end

function TestReelSession:setUp()
    self.originalRE = package.loaded['common.REUtil']
    self.originalMgr = package.loaded['server.Mgr.MgrReelIn']
    self.originalGame = _G.game
    self.events = {}
    self.now = 0
    local env = self
    package.loaded['common.REUtil'] = { GetRE = function(_, name)
        if not env.events[name] then
            env.events[name] = { OnServerEvent = signal(), FireClient = function(_, player, value)
                player.messages[#player.messages + 1] = value
            end }
        end
        return env.events[name]
    end }
    _G.game = { GetService = function(_, name)
        if name == 'World' then return { GetServerTime = function() return env.now end } end
    end }
    package.loaded['server.Mgr.MgrReelIn'] = nil
    self.mgr = require('server.Mgr.MgrReelIn')
    self.cast = { Sessions = {}, FinishReel = function(_, player, id, outcome)
        local current = env.cast.Sessions[player.UserId]
        if current and current.player == player and current.session.reelSession == id then
            current.session.phase = outcome
            player.results[#player.results + 1] = outcome
        end
    end }
    self.mgr.Cast = self.cast
    self.mgr:Start()
    self.a = { UserId = 1, messages = {}, results = {}, CharacterAdded = signal(), CharacterRemoving = signal() }
    self.b = { UserId = 2, messages = {}, results = {}, CharacterAdded = signal(), CharacterRemoving = signal() }
    for _, player in ipairs({ self.a, self.b }) do
        self.mgr:OnPlayerAdded(player)
        self.cast.Sessions[player.UserId] = { player = player, session = { phase = 'hooked', reelSession = 's' .. player.UserId } }
        self.mgr:Begin(player, 's' .. player.UserId, 0)
    end
end

function TestReelSession:tearDown()
    self.mgr:OnPlayerRemoving(self.a)
    self.mgr:OnPlayerRemoving(self.b)
    package.loaded['server.Mgr.MgrReelIn'] = self.originalMgr
    package.loaded['common.REUtil'] = self.originalRE
    _G.game = self.originalGame
end

function TestReelSession:test_identity_session_sequence_and_clamp()
    local re = self.events.ReelInRE.OnServerEvent
    re:Fire(self.a, { s = 's2', n = 10, q = 1 })
    re:Fire({ UserId = 1 }, { s = 's1', n = 10, q = 1 })
    re:Fire(self.a, { s = 's1', n = 0.5, q = 1 })
    lu.assertEquals(#self.a.messages, 1)
    self.now = 2
    re:Fire(self.a, { s = 's1', n = 8, q = 1 })
    lu.assertEquals(self.a.messages[#self.a.messages].accepted, 8)
    re:Fire(self.a, { s = 's1', n = 8, q = 1 })
    re:Fire(self.a, { s = 's1', n = 8, q = 2 })
    lu.assertEquals(self.a.messages[#self.a.messages].accepted, 2)
    lu.assertEquals(#self.b.messages, 1)
end

function TestReelSession:test_close_cannot_end_another_player_and_finishes_once()
    local close = self.events.CloseReelIn.OnServerEvent
    close:Fire(self.a, { session = 's2' })
    lu.assertNotNil(self.mgr.Sessions[2])
    close:Fire(self.a, { session = 's1' })
    close:Fire(self.a, { session = 's1' })
    lu.assertEquals(self.a.results, { 'unhooked' })
    lu.assertNotNil(self.mgr.Sessions[2])
end

function TestReelSession:test_death_and_offline_clear_only_once()
    self.a.CharacterRemoving:Fire()
    self.mgr:OnPlayerRemoving(self.a)
    lu.assertEquals(self.a.results, { 'unhooked' })
    self.now = 10.2
    self.mgr:Update()
    self.now = 10.4
    self.mgr:Update()
    lu.assertEquals(self.b.results, { 'unhooked' })
end

function TestReelSession:test_offline_drops_authority_without_reply()
    local count = #self.a.messages
    self.mgr:OnPlayerRemoving(self.a)
    self.mgr:OnPlayerRemoving(self.a)
    lu.assertNil(self.mgr.Sessions[1])
    lu.assertEquals(#self.a.messages, count)
    lu.assertEquals(self.a.results, { 'unhooked' })
end

function TestReelSession:test_controller_died_clears_session_once()
    local controller = { Died = signal() }
    self.a.Character = { Controller = controller }
    self.a.CharacterAdded:Fire(self.a.Character)
    controller.Died:Fire()
    lu.assertEquals(self.a.results, { 'unhooked' })
    self.a.CharacterRemoving:Fire()
    lu.assertEquals(self.a.results, { 'unhooked' })
end

function TestReelSession:test_duplicate_begin_preserves_sequence_and_budget()
    local first = self.mgr.Sessions[1]
    self.events.ReelInRE.OnServerEvent:Fire(self.a, { s = 's1', n = 3, q = 1 })
    lu.assertTrue(self.mgr:Begin(self.a, 's1', self.now))
    lu.assertIs(self.mgr.Sessions[1], first)
    lu.assertEquals(self.mgr.Sessions[1].Receiver:Accept(0, { s = 's1', n = 1, q = 1 }).Reason, 'order')
    lu.assertEquals(self.mgr.Sessions[1].Receiver.Window:Used(0), 3)
end

function TestReelSession:test_started_callback_can_close_before_begin_returns()
    self.mgr:Finish(self.mgr.Sessions[1], 'unhooked')
    self.cast.Sessions[1].session.phase = 'hooked'
    self.cast.Sessions[1].session.reelSession = 'next'
    local event = self.events.ReelInRE
    local original = event.FireClient
    event.FireClient = function(_, player, value)
        original(event, player, value)
        if value.action == 'started' then self.mgr:Close(player, { session = value.session }) end
    end
    lu.assertFalse(self.mgr:Begin(self.a, 'next', 0))
    lu.assertNil(self.mgr.Sessions[1])
    lu.assertEquals(self.a.results, { 'unhooked', 'unhooked' })
end

function TestReelSession:test_cast_update_does_not_broadcast_hook_after_synchronous_close()
    self.mgr:Finish(self.mgr.Sessions[1], 'unhooked')
    local original = package.loaded['server.Mgr.MgrPlayerData']
    package.loaded['server.Mgr.MgrPlayerData'] = {}
    local cast = assert(loadfile('server/Mgr/MgrCast.lua'))()
    package.loaded['server.Mgr.MgrPlayerData'] = original
    cast.World = self.mgr.World
    cast.ReelIn = self.mgr
    cast.Sessions[1] = { player = self.a, session = {
        phase = 'cast', hookAt = 0, zoneId = 'WaterCircle2', rodLevel = 1,
    } }
    self.mgr.Cast = cast
    local re = self.events.ReelInRE
    local send = re.FireClient
    re.FireClient = function(_, player, value)
        send(re, player, value)
        if value.action == 'started' then self.mgr:Close(player, { session = value.session }) end
    end
    cast:Update()
    lu.assertNil(cast.Sessions[1])
    local states = self.events.CastState
    lu.assertNotNil(states)
    for _, message in ipairs(self.a.messages) do
        lu.assertNotEquals(message.phase, 'hooked')
    end
end

function TestReelSession:test_old_player_removal_does_not_disconnect_replacement()
    local old = self.a
    local replacement = { UserId = 1, messages = {}, results = {},
        CharacterAdded = signal(), CharacterRemoving = signal() }
    self.mgr:OnPlayerAdded(replacement)
    self.cast.Sessions[1] = { player = replacement,
        session = { phase = 'hooked', reelSession = 'next' } }
    lu.assertTrue(self.mgr:Begin(replacement, 'next', 0))
    self.mgr:OnPlayerRemoving(old)
    lu.assertNotNil(self.mgr.Connections[1])
    replacement.CharacterRemoving:Fire()
    lu.assertEquals(replacement.results, { 'unhooked' })
    self.mgr:OnPlayerRemoving(replacement)
end

function TestReelSession:test_land_result_is_a_single_handoff()
    self.events.ReelInRE.OnServerEvent:Fire(self.a, { s = 's1', n = 10, q = 1 })
    lu.assertEquals(self.a.results, { 'landed' })
    self.events.ReelInRE.OnServerEvent:Fire(self.a, { s = 's1', n = 10, q = 2 })
    lu.assertEquals(self.a.results, { 'landed' })
end

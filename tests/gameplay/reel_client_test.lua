local lu = require('luaunit')

TestReelClient = {}

local function signal()
    local callbacks = {}
    return { Connect = function(_, fn)
        callbacks[#callbacks + 1] = fn
        return { Disconnect = function() end }
    end, Fire = function(_, value)
        for _, fn in ipairs(callbacks) do fn(value) end
    end }
end

function TestReelClient:setUp()
    self.originalRE = package.loaded['common.REUtil']
    self.originalClient = package.loaded['client.LocalReelIn']
    self.originalGame = _G.game
    self.sent = {}
    self.events = {}
    self.heartbeat = signal()
    local env = self
    package.loaded['common.REUtil'] = { GetRE = function(_, name)
        if not env.events[name] then
            env.events[name] = { OnClientEvent = signal(), FireServer = function(_, payload)
                env.sent[#env.sent + 1] = { name = name, payload = payload }
            end }
        end
        return env.events[name]
    end }
    _G.game = { GetService = function(_, name)
        if name == 'World' then return { GetServerTime = function() return env.now end } end
        if name == 'RunService' then return { Heartbeat = env.heartbeat } end
    end }
    package.loaded['client.LocalReelIn'] = nil
    self.client = require('client.LocalReelIn')
    self.client:Start()
    self.now = 0
end

function TestReelClient:tearDown()
    package.loaded['common.REUtil'] = self.originalRE
    package.loaded['client.LocalReelIn'] = self.originalClient
    _G.game = self.originalGame
end

function TestReelClient:test_snapshot_does_not_reset_pending_and_close_flushes_first()
    local client = self.client
    client:SetSession('s1')
    client:Click()
    client:SetSession('s1')
    client:Close()
    lu.assertEquals(self.sent, {
        { name = 'ReelInRE', payload = { s = 's1', n = 1, q = 1 } },
        { name = 'CloseReelIn', payload = { session = 's1' } },
    })
    client:Close()
    lu.assertEquals(#self.sent, 2)
end

function TestReelClient:test_restart_does_not_stack_listeners_or_leave_pending_clicks()
    local first = self.client.Connection
    local update = self.client.UpdateConnection
    self.client:Start()
    lu.assertIs(self.client.Connection, first)
    lu.assertIs(self.client.UpdateConnection, update)
    self.client:SetSession('s1')
    self.client:Click()
    self.client:Stop()
    lu.assertNil(self.client.SessionId)
    lu.assertNil(self.client.Connection)
    lu.assertEquals(self.sent[#self.sent], { name = 'CloseReelIn', payload = { session = 's1' } })
    self.client:Start()
    lu.assertNotIs(self.client.Connection, first)
end

function TestReelClient:test_heartbeat_collects_after_hundred_ms()
    self.client:SetSession('s1')
    self.client:Click()
    self.now = 0.09
    self.heartbeat:Fire()
    lu.assertEquals(#self.sent, 0)
    self.now = 0.11
    self.heartbeat:Fire()
    lu.assertEquals(self.sent[1], { name = 'ReelInRE',
        payload = { s = 's1', n = 1, q = 1 } })
end

-- #133：界面被遮挡只影响表现——不主动收线、不重置计时，待发批次先送出去
function TestReelClient:test_suspend_flushes_pending_and_keeps_the_session()
    self.client:SetSession('s1')
    self.client:Click()
    self.client:Suspend()
    lu.assertEquals(self.sent, { { name = 'ReelInRE', payload = { s = 's1', n = 1, q = 1 } } })
    lu.assertEquals(self.client.SessionId, 's1')
    lu.assertNotNil(self.client.Display)
    lu.assertTrue(self.client.Suspended)
end

function TestReelClient:test_started_while_suspended_is_kept_and_usable_after_resume()
    self.client:Suspend()
    self.events.ReelInRE.OnClientEvent:Fire({ action = 'started', session = 's1', progress = 50 })
    lu.assertEquals(#self.sent, 0)
    lu.assertEquals(self.client.SessionId, 's1')
    self.client:Resume()
    self.client:Click()
    self.now = 0.1
    self.heartbeat:Fire()
    lu.assertEquals(self.sent[#self.sent], { name = 'ReelInRE',
        payload = { s = 's1', n = 1, q = 1 } })
end

-- 会话真结束后，迟到的 started 回声不能再把界面拉回收线中
function TestReelClient:test_ended_session_ignores_late_started_echo()
    self.client:SetSession('s1')
    self.client:Clear('s1')
    self.events.ReelInRE.OnClientEvent:Fire({ action = 'started', session = 's1', progress = 50 })
    lu.assertNil(self.client.SessionId)
end

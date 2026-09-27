-- #110 失败方式：有效抛竿没有权威落点/水域、重复扣饵或重复事实；重发状态改变结果；
-- 上钩/收竿/死亡后仍等待；离线后仍保留会话或给旧玩家发状态。
local lu = require('luaunit')
local GameCfg = require('common.GameCfg')
local PlayerData = require('server.Data.PlayerData')

TestCastWaiting = {}

local function signal()
    local callbacks = {}
    return { Connect = function(_, fn)
        callbacks[#callbacks + 1] = fn
        return { Disconnect = function() end }
    end, Fire = function(_, ...)
        for _, fn in ipairs(callbacks) do fn(...) end
    end }
end

function TestCastWaiting:setUp()
    self.savedGame = _G.game
    self.savedRE = package.loaded['common.REUtil']
    self.savedData = package.loaded['server.Mgr.MgrPlayerData']
    self.savedFish = package.loaded['server.Mgr.MgrFishUnit']
    self.now, self.events, self.states, self.facts = 0, {}, {}, {}
    local env = self
    _G.game = { GetService = function(_, name)
        if name == 'World' then return { GetServerTime = function() return env.now end } end
    end }
    package.loaded['common.REUtil'] = { GetRE = function(_, name)
        if not env.events[name] then
            env.events[name] = { OnServerEvent = signal(), FireClient = function(_, player, value)
                env.states[#env.states + 1] = { player = player, value = value }
            end }
        end
        return env.events[name]
    end, CheckRECD = function() return false end }
    package.loaded['server.Mgr.MgrFishUnit'] = { CanCast = function() return true end, HeldInfo = function() end }
    self.player = { UserId = 110, SetAttribute = function() end, Character = {
        Position = { x = -11.75, y = 2, z = 22.75 },
        Rotation = { GetForward = function() return { x = 0, y = 0, z = 1 } end },
    } }
    self.data = PlayerData.New(self.player)
    self.data:Init()
    self.data:SelectSlot(1)
    self.data:SelectBait(GameCfg.Items.Id.Worm)
    package.loaded['server.Mgr.MgrPlayerData'] = {
        GetDataInst = function(_, player) return player == env.player and env.data end,
        SendItemBar = function() end,
    }
    self.cast = assert(loadfile('server/Mgr/MgrCast.lua'))()
    self.reel = assert(loadfile('server/Mgr/MgrReelIn.lua'))()
    self.reel.Cast = self.cast
    self.cast.ReelIn = self.reel
    self.reel:Start()
    self.cast.Quest = { Notify = function(_, kind, player, payload)
        env.facts[#env.facts + 1] = { kind = kind, player = player, payload = payload }
    end }
    self.cast:Start()
end

function TestCastWaiting:tearDown()
    self.reel:Stop()
    self.cast:Stop()
    self.data:Destroy()
    package.loaded['common.REUtil'] = self.savedRE
    package.loaded['server.Mgr.MgrPlayerData'] = self.savedData
    package.loaded['server.Mgr.MgrFishUnit'] = self.savedFish
    _G.game = self.savedGame
end

function TestCastWaiting:castRod()
    self.events.CastAction.OnServerEvent:Fire(self.player, {
        action = 'Cast', slot = 1, itemId = GameCfg.Items.Id.StarterRod,
    })
end

function TestCastWaiting:lastState()
    return self.states[#self.states].value
end

function TestCastWaiting:test_valid_cast_sends_waiting_landing_and_consumes_bait_once()
    self:castRod()
    local state = self:lastState()
    lu.assertEquals(state.phase, 'cast')
    lu.assertEquals(state.zoneId, 'WaterCircle2')
    lu.assertEquals(type(state.castId), 'number')
    lu.assertEquals(state.landing.x, -11.75)
    lu.assertEquals(state.landing.z, 27.75)
    lu.assertEquals(self.data:GetItemBarSnapshot().bait.worm, 9)
    self:castRod()
    self.events.RequestCastState.OnServerEvent:Fire(self.player)
    lu.assertEquals(self:lastState().phase, 'cast')
    lu.assertEquals(self:lastState().castId, state.castId)
    lu.assertTrue(self:lastState().snapshot)
    lu.assertEquals(self:lastState().landing, state.landing)
    lu.assertEquals(self:lastState().zoneId, state.zoneId)
    lu.assertEquals(self.data:GetItemBarSnapshot().bait.worm, 9)
    lu.assertEquals(#self.facts, 1)
    lu.assertEquals(self.facts[1].kind, 'CastWater')
end

function TestCastWaiting:test_hook_handoff_and_reel_clear_waiting()
    self:castRod()
    self.now = GameCfg.Casting.HookDelaySec
    self.cast:Update()
    lu.assertEquals(self:lastState().phase, 'hooked')
    lu.assertEquals(self:lastState().reelSession, self.reel.Sessions[self.player.UserId].Id)
    lu.assertEquals(self.states[#self.states - 1].value.action, 'started')
    local reelId = self:lastState().reelSession
    self.events.CastAction.OnServerEvent:Fire(self.player, { action = 'Reel' })
    lu.assertEquals(self:lastState().phase, 'hooked')
    self.events.CloseReelIn.OnServerEvent:Fire(self.player, { session = reelId })
    lu.assertEquals(self:lastState().action, 'unhooked')
    lu.assertEquals(self.states[#self.states - 1].value.phase, 'idle')
    lu.assertNil(self.reel.Sessions[self.player.UserId])
end

function TestCastWaiting:test_reel_death_and_offline_end_waiting()
    self:castRod()
    self.events.CastAction.OnServerEvent:Fire(self.player, { action = 'Reel' })
    lu.assertEquals(self:lastState().phase, 'idle')
    self:castRod()
    self.cast:Abort(self.player)
    lu.assertEquals(self:lastState().phase, 'idle')
    self:castRod()
    local sent = #self.states
    self.cast:OnPlayerRemoving(self.player)
    lu.assertNil(self.cast.Sessions[self.player.UserId])
    lu.assertEquals(#self.states, sent)
    self.now = GameCfg.Casting.HookDelaySec
    self.cast:Update()
    lu.assertEquals(#self.states, sent)
    lu.assertEquals(self.data:GetItemBarSnapshot().bait.worm, 7)
end

-- #110 失败方式：有效抛竿没有权威落点/水域、重复扣饵或重复事实；重发状态改变结果；
-- 上钩/收竿/死亡后仍等待；离线后仍保留会话或给旧玩家发状态。
-- 抛竿失败：无效落点误扣饵/建会话；前置失败无区别或重放；重复抛竿误清当前会话；
-- 空抽保留会话/退还鱼饵，或失败反馈先于结束状态。
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
    self.cooldown, self.canCast, self.consumeCount = false, true, 0
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
    end, CheckRECD = function() return env.cooldown end }
    package.loaded['server.Mgr.MgrFishUnit'] = {
        CanCast = function() return env.canCast end, HeldInfo = function() end,
    }
    self.player = { UserId = 110, SetAttribute = function() end, Character = {
        Position = { x = -11.75, y = 2, z = 22.75 },
        Rotation = { GetForward = function() return { x = 0, y = 0, z = 1 } end },
    } }
    self.data = PlayerData.New(self.player)
    self.data:Init()
    self.data:SelectSlot(1)
    self.data:SelectBait(GameCfg.Items.Id.Worm)
    local consume = self.data.ConsumeSelectedBait
    self.data.ConsumeSelectedBait = function(data)
        env.consumeCount = env.consumeCount + 1
        return consume(data)
    end
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

function TestCastWaiting:test_invalid_landing_rejects_before_bait_and_result_is_not_replayed()
    self.player.Character.Position = { x = 10, y = 2, z = 20 }
    self:castRod()
    local result = self:lastState()
    lu.assertEquals(result.phase, 'idle')
    lu.assertEquals(result.result.reason, 'invalidLanding')
    lu.assertEquals(result.result.landing, { x = 10, y = 2, z = 25 })
    lu.assertNil(self.cast.Sessions[self.player.UserId])
    lu.assertEquals(self.consumeCount, 0)
    lu.assertEquals(self.data:GetItemBarSnapshot().bait.worm, 10)
    lu.assertEquals(#self.facts, 0)
    self.events.RequestCastState.OnServerEvent:Fire(self.player)
    lu.assertEquals(self:lastState().phase, 'idle')
    lu.assertNil(self:lastState().result)
end

function TestCastWaiting:test_water_edge_repeated_failures_then_success_keep_bait_and_quest_fact()
    -- 虾池东侧边界 x=108，线内含边界，线外拒绝；不改水区判定。
    local position = self.player.Character.Position
    position.y, position.z = 5, 101
    for _, x in ipairs({ 108.001, 108.002 }) do
        position.x = x
        self:castRod()
        lu.assertEquals(self:lastState().phase, 'idle')
        lu.assertEquals(self:lastState().result.reason, 'invalidLanding')
        lu.assertEquals(self:lastState().result.landing, { x = x, y = 5, z = 106 })
        lu.assertEquals(self.data:GetItemBarSnapshot().bait.worm, 10)
        lu.assertEquals(#self.facts, 0)
        self.events.RequestCastState.OnServerEvent:Fire(self.player)
        lu.assertNil(self:lastState().result)
    end
    position.x = 108
    self:castRod()
    lu.assertEquals(self:lastState().phase, 'cast')
    lu.assertEquals(self:lastState().zoneId, 'ShrimpPool')
    lu.assertEquals(self:lastState().landing, { x = 108, y = 5.6, z = 106 })
    lu.assertEquals(self.data:GetItemBarSnapshot().bait.worm, 9)
    lu.assertEquals(#self.facts, 1)
    lu.assertEquals(self.facts[1].kind, 'CastWater')
end

function TestCastWaiting:test_prerequisite_reasons_and_unavailable_are_distinct()
    local function expect(reason, act)
        local before = #self.states
        act()
        lu.assertEquals(#self.states, before + 1)
        lu.assertEquals(self:lastState().result.reason, reason)
        lu.assertNil(self.cast.Sessions[self.player.UserId])
        self.events.RequestCastState.OnServerEvent:Fire(self.player)
        lu.assertNil(self:lastState().result)
    end
    self.canCast = false
    expect('holding', function() self:castRod() end)
    self.canCast = true
    expect('invalidRod', function()
        self.events.CastAction.OnServerEvent:Fire(self.player, { action = 'Cast', slot = 2, itemId = 'wrong' })
    end)
    self.cooldown = true
    expect('cooldown', function() self:castRod() end)
    self.cooldown = false
    self.data.Data.SelectedBait = 'worm'
    self.data.Data.Bait.worm = 0
    expect('baitUnavailable', function() self:castRod() end)
    self.data.Data.Bait.worm = 10
    self.data:SelectBait('worm')
    self.player.Character = nil
    expect('unavailable', function() self:castRod() end)
    self.player.Character = { Position = { x = -11.75, y = 2, z = 22.75 },
        Rotation = { GetForward = function() error('rotation-failed') end } }
    expect('unavailable', function() self:castRod() end)
    lu.assertEquals(self.consumeCount, 1)
end

function TestCastWaiting:test_repeated_cast_does_not_clear_existing_session()
    self:castRod()
    local session = self.cast.Sessions[self.player.UserId]
    self:castRod()
    lu.assertEquals(self:lastState().result.reason, 'alreadyCasting')
    lu.assertEquals(self.cast.Sessions[self.player.UserId], session)
    lu.assertEquals(self.consumeCount, 1)
    self.events.RequestCastState.OnServerEvent:Fire(self.player)
    lu.assertEquals(self:lastState().phase, 'cast')
    lu.assertNil(self:lastState().result)
end

function TestCastWaiting:test_empty_draw_ends_session_after_bait_consumed_then_reports_no_fish()
    self:castRod()
    local remaining = self.data:GetItemBarSnapshot().bait.worm
    local original = GameCfg.Casting.Zones.WaterCircle2
    GameCfg.Casting.Zones.WaterCircle2 = {}
    self.now = GameCfg.Casting.HookDelaySec
    local ok, err = pcall(function() self.cast:Update() end)
    GameCfg.Casting.Zones.WaterCircle2 = original
    if not ok then error(err) end
    lu.assertNil(self.cast.Sessions[self.player.UserId])
    lu.assertEquals(self.states[#self.states - 1].value.phase, 'idle')
    lu.assertNil(self.states[#self.states - 1].value.result)
    lu.assertEquals(self:lastState().result.reason, 'noFish')
    lu.assertEquals(self:lastState().phase, 'idle')
    lu.assertEquals(self.data:GetItemBarSnapshot().bait.worm, remaining)
    lu.assertEquals(self.consumeCount, 1)
    self.events.RequestCastState.OnServerEvent:Fire(self.player)
    lu.assertNil(self:lastState().result)
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

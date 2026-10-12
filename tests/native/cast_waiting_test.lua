-- 迁移自 tests/gameplay/cast_waiting_test.lua（#85）；行为契约原文见 #110。
-- #110 失败方式：有效抛竿没有权威落点/水域、重复扣饵或重复事实；重发状态改变结果；
-- 上钩/收竿/死亡后仍等待；离线后仍保留会话或给旧玩家发状态。
-- 抛竿失败：无效落点误扣饵/建会话；前置失败无区别或重放；重复抛竿误清当前会话；
-- 空抽保留会话/退还鱼饵，或失败反馈先于结束状态。
-- it 名字沿用旧方法名，注册顺序 = LuaUnit sortedPairs 的实际执行顺序。

local GameCfg = require('common.GameCfg')
local PlayerData = require('server.Data.PlayerData')

local function signal()
  local callbacks = {}
  return { Connect = function(_, fn)
    callbacks[#callbacks + 1] = fn
    return { Disconnect = function() end }
  end, Fire = function(_, ...)
    for _, fn in ipairs(callbacks) do fn(...) end
  end }
end

describe('抛竿与等待上钩（MgrCast）', function()
  local env
  local restore

  before_each(function()
    -- 快照先于任何改动：before_each 中途失败时 after_each 仍能还原。
    restore = {
      game = _G.game,
      RE = package.loaded['common.REUtil'],
      Data = package.loaded['server.Mgr.MgrPlayerData'],
      Fish = package.loaded['server.Mgr.MgrFishUnit'],
    }
    env = { now = 0, events = {}, states = {}, facts = {}, cooldown = false, canCast = true, consumeCount = 0 }
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
    env.player = { UserId = 110, SetAttribute = function() end, Character = {
      Position = { x = -11.75, y = 2, z = -17.25 },
      Rotation = { GetForward = function() return { x = 0, y = 0, z = 1 } end },
    } }
    env.data = PlayerData.New(env.player)
    env.data:Init()
    env.data:SelectSlot(1)
    env.data:SelectBait(GameCfg.Items.Id.Worm)
    local consume = env.data.ConsumeSelectedBait
    env.data.ConsumeSelectedBait = function(data)
      env.consumeCount = env.consumeCount + 1
      return consume(data)
    end
    package.loaded['server.Mgr.MgrPlayerData'] = {
      GetDataInst = function(_, player) return player == env.player and env.data end,
      SendItemBar = function() end,
    }
    env.cast = assert(loadfile('server/Mgr/MgrCast.lua'))()
    env.reel = assert(loadfile('server/Mgr/MgrReelIn.lua'))()
    env.reel.Cast = env.cast
    env.cast.ReelIn = env.reel
    env.reel:Start()
    env.cast.Quest = { Notify = function(_, kind, player, payload)
      env.facts[#env.facts + 1] = { kind = kind, player = player, payload = payload }
    end }
    env.cast:Start()
  end)

  after_each(function()
    -- 对未跑完的 before_each 幂等：谁建起来就关谁，没建起来的跳过。
    if env then
      if env.reel then env.reel:Stop() end
      if env.cast then env.cast:Stop() end
      if env.data then env.data:Destroy() end
    end
    package.loaded['common.REUtil'] = restore and restore.RE
    package.loaded['server.Mgr.MgrPlayerData'] = restore and restore.Data
    package.loaded['server.Mgr.MgrFishUnit'] = restore and restore.Fish
    _G.game = restore and restore.game
    env = nil
    restore = nil
  end)

  local function castRod()
    env.events.CastAction.OnServerEvent:Fire(env.player, {
      action = 'Cast', slot = 1, itemId = GameCfg.Items.Id.StarterRod,
    })
  end

  local function lastState()
    return env.states[#env.states].value
  end

  it('test_disabling_debug_clears_pending_fish_and_blocks_hooked_override', function()
    local savedDebug, savedVector = GameCfg.Debug, _G.Vector3
    GameCfg.Debug = { Enabled = true, InitialGrants = savedDebug.InitialGrants }
    _G.Vector3 = { New = function(_, x, y, z) return { x = x, y = y, z = z } end }
    local spawned = 0
    env.cast.FishUnit.SpawnLanded = function() spawned = spawned + 1; return { Id = spawned } end
    -- 失败也要把配置与全局还回去：保留旧套件的"部分失败清理"语义。
    local ok, err = pcall(function()
      env.cast:SetNextFish(env.player, 'eel')
      castRod()
      env.now = GameCfg.Casting.HookDelaySec
      env.cast:Update()
      local session = env.cast.Sessions[env.player.UserId].session
      GameCfg.Debug.Enabled = false
      env.cast:Update()
      assert.is_nil(env.cast.NextFish[env.player.UserId])
      env.cast:FinishReel(env.player, session.reelSession, 'landed')
      assert.same(0, spawned)
      GameCfg.Debug.Enabled = true
      castRod()
      env.now = env.now + GameCfg.Casting.HookDelaySec
      env.cast:Update()
      assert.is_nil(env.cast.Sessions[env.player.UserId].session.forcedFishSerial)
    end)
    GameCfg.Debug, _G.Vector3 = savedDebug, savedVector
    if not ok then error(err) end
  end)

  it('test_empty_draw_ends_session_after_bait_consumed_then_reports_no_fish', function()
    castRod()
    local castId = lastState().castId
    local remaining = env.data:GetItemBarSnapshot().bait.worm
    local original = GameCfg.Casting.Zones.WaterCircle2
    GameCfg.Casting.Zones.WaterCircle2 = {}
    env.now = GameCfg.Casting.HookDelaySec
    local ok, err = pcall(function() env.cast:Update() end)
    GameCfg.Casting.Zones.WaterCircle2 = original
    if not ok then error(err) end
    assert.is_nil(env.cast.Sessions[env.player.UserId])
    assert.same('idle', lastState().phase)
    assert.same(castId, lastState().castId)
    assert.same('noFish', lastState().result.reason)
    assert.same(remaining, env.data:GetItemBarSnapshot().bait.worm)
    assert.same(1, env.consumeCount)
    env.events.RequestCastState.OnServerEvent:Fire(env.player)
    assert.is_nil(lastState().result)
    castRod()
    assert.same('cast', lastState().phase)
    assert.is_true(lastState().castId > castId)
    assert.same(remaining - 1, env.data:GetItemBarSnapshot().bait.worm)
    assert.same(2, #env.facts)
  end)

  it('test_hook_handoff_and_reel_clear_waiting', function()
    castRod()
    env.now = GameCfg.Casting.HookDelaySec
    env.cast:Update()
    assert.same('hooked', lastState().phase)
    assert.same(lastState().reelSession, env.reel.Sessions[env.player.UserId].Id)
    assert.same('started', env.states[#env.states - 1].value.action)
    local reelId = lastState().reelSession
    env.events.CastAction.OnServerEvent:Fire(env.player, { action = 'Reel' })
    assert.same('hooked', lastState().phase)
    env.events.CloseReelIn.OnServerEvent:Fire(env.player, { session = reelId })
    assert.same('unhooked', lastState().action)
    assert.same('idle', env.states[#env.states - 1].value.phase)
    assert.is_nil(env.reel.Sessions[env.player.UserId])
  end)

  it('test_invalid_landing_rejects_before_bait_and_result_is_not_replayed', function()
    env.player.Character.Position = { x = 10, y = 2, z = -20 }
    castRod()
    local result = lastState()
    assert.same('idle', result.phase)
    assert.same('invalidLanding', result.result.reason)
    assert.same({ x = 10, y = 2, z = -15 }, result.result.landing)
    assert.is_nil(env.cast.Sessions[env.player.UserId])
    assert.same(0, env.consumeCount)
    assert.same(10, env.data:GetItemBarSnapshot().bait.worm)
    assert.same(0, #env.facts)
    env.events.RequestCastState.OnServerEvent:Fire(env.player)
    assert.same('idle', lastState().phase)
    assert.is_nil(lastState().result)
  end)

  it('test_new_request_same_fish_survives_older_landing', function()
    local savedVector, savedDebug = _G.Vector3, GameCfg.Debug
    _G.Vector3 = { New = function(_, x, y, z) return { x = x, y = y, z = z } end }
    GameCfg.Debug = { Enabled = true, InitialGrants = savedDebug.InitialGrants }
    env.cast.FishUnit.SpawnLanded = function() return { Id = 1 } end
    local ok, err = pcall(function()
      env.cast:SetNextFish(env.player, 'eel')
      castRod()
      env.now = GameCfg.Casting.HookDelaySec
      env.cast:Update()
      local session = env.cast.Sessions[env.player.UserId].session
      local firstSerial = session.forcedFishSerial
      env.cast:SetNextFish(env.player, 'eel')
      assert.not_same(firstSerial, env.cast.NextFish[env.player.UserId].serial)
      env.cast:FinishReel(env.player, session.reelSession, 'landed')
      assert.is_nil(env.cast.NextFish[env.player.UserId])
    end)
    GameCfg.Debug, _G.Vector3 = savedDebug, savedVector
    if not ok then error(err) end
  end)

  it('test_next_fish_applies_to_already_hooked_fish', function()
    local savedDebug = GameCfg.Debug
    GameCfg.Debug = { Enabled = true, InitialGrants = savedDebug.InitialGrants }
    local ok, err = pcall(function()
      castRod()
      env.now = GameCfg.Casting.HookDelaySec
      env.cast:Update()
      local session = env.cast.Sessions[env.player.UserId].session
      env.cast:SetNextFish(env.player, 'eel')
      assert.same('eel', session.fishId)
      assert.same('eel', lastState().fishId)
      assert.same(session.forcedFishSerial, env.cast.NextFish[env.player.UserId].serial)
    end)
    GameCfg.Debug = savedDebug
    if not ok then error(err) end
  end)

  it('test_next_fish_cleared_on_player_removal', function()
    env.cast:SetNextFish(env.player, 'eel')
    env.cast:OnPlayerRemoving(env.player)
    assert.is_nil(env.cast.NextFish[env.player.UserId])
  end)

  it('test_next_fish_only_consumed_after_successful_landing', function()
    local savedVector = _G.Vector3
    local savedDebug = GameCfg.Debug
    local spawnCount = 0
    _G.Vector3 = { New = function(_, x, y, z) return { x = x, y = y, z = z } end }
    GameCfg.Debug = { Enabled = true, InitialGrants = savedDebug.InitialGrants }
    env.cast.FishUnit.SpawnLanded = function()
      spawnCount = spawnCount + 1
      if spawnCount == 1 then return nil, 'failed' end
      return { Id = spawnCount }
    end
    local ok, err = pcall(function()
      env.cast:SetNextFish(env.player, 'eel')
      castRod()
      env.now = GameCfg.Casting.HookDelaySec
      env.cast:Update()
      local first = env.cast.Sessions[env.player.UserId].session
      assert.same('eel', first.fishId)
      env.cast:FinishReel(env.player, first.reelSession, 'landed')
      assert.same('eel', env.cast.NextFish[env.player.UserId].fishId)
      env.cast:EndSession(env.player, env.cast.Sessions[env.player.UserId])
      castRod()
      env.now = env.now + GameCfg.Casting.HookDelaySec
      env.cast:Update()
      local second = env.cast.Sessions[env.player.UserId].session
      assert.same('eel', second.fishId)
      env.cast:FinishReel(env.player, second.reelSession, 'landed')
      assert.is_nil(env.cast.NextFish[env.player.UserId])
      env.cast:EndSession(env.player, env.cast.Sessions[env.player.UserId])
      castRod()
      env.now = env.now + GameCfg.Casting.HookDelaySec
      local originalRows = GameCfg.Casting.Zones.WaterCircle2
      GameCfg.Casting.Zones.WaterCircle2 = { { Id = 'carp', Bait = 'worm', RodLevel = 1, DrawWeight = 1 } }
      env.cast:Update()
      GameCfg.Casting.Zones.WaterCircle2 = originalRows
      assert.same('carp', env.cast.Sessions[env.player.UserId].session.fishId)
    end)
    GameCfg.Debug, _G.Vector3 = savedDebug, savedVector
    if not ok then error(err) end
  end)

  it('test_next_fish_survives_unhooked_reel', function()
    local savedDebug = GameCfg.Debug
    GameCfg.Debug = { Enabled = true, InitialGrants = savedDebug.InitialGrants }
    local ok, err = pcall(function()
      env.cast:SetNextFish(env.player, 'eel')
      castRod()
      env.now = GameCfg.Casting.HookDelaySec
      env.cast:Update()
      local session = env.cast.Sessions[env.player.UserId].session
      assert.same('eel', session.fishId)
      env.cast:FinishReel(env.player, session.reelSession, 'unhooked')
      assert.same('eel', env.cast.NextFish[env.player.UserId].fishId)
    end)
    GameCfg.Debug = savedDebug
    if not ok then error(err) end
  end)

  it('test_prerequisite_reasons_and_unavailable_are_distinct', function()
    local function expect(reason, act)
      local before = #env.states
      act()
      assert.same(before + 1, #env.states)
      assert.same(reason, lastState().result.reason)
      assert.is_nil(env.cast.Sessions[env.player.UserId])
      env.events.RequestCastState.OnServerEvent:Fire(env.player)
      assert.is_nil(lastState().result)
    end
    env.canCast = false
    expect('holding', castRod)
    env.canCast = true
    expect('invalidRod', function()
      env.events.CastAction.OnServerEvent:Fire(env.player, { action = 'Cast', slot = 2, itemId = 'wrong' })
    end)
    env.cooldown = true
    expect('cooldown', castRod)
    env.cooldown = false
    env.data.Data.SelectedBait = 'worm'
    env.data.Data.Bait.worm = 0
    expect('baitUnavailable', castRod)
    env.data.Data.Bait.worm = 10
    env.data:SelectBait('worm')
    env.player.Character = nil
    expect('unavailable', castRod)
    env.player.Character = { Position = { x = -11.75, y = 2, z = -17.25 },
      Rotation = { GetForward = function() error('rotation-failed') end } }
    expect('unavailable', castRod)
    assert.same(1, env.consumeCount)
  end)

  it('test_reel_death_and_offline_end_waiting', function()
    castRod()
    env.events.CastAction.OnServerEvent:Fire(env.player, { action = 'Reel' })
    assert.same('idle', lastState().phase)
    castRod()
    env.cast:Abort(env.player)
    assert.same('idle', lastState().phase)
    castRod()
    local sent = #env.states
    env.cast:OnPlayerRemoving(env.player)
    assert.is_nil(env.cast.Sessions[env.player.UserId])
    assert.same(sent, #env.states)
    env.now = GameCfg.Casting.HookDelaySec
    env.cast:Update()
    assert.same(sent, #env.states)
    assert.same(7, env.data:GetItemBarSnapshot().bait.worm)
  end)

  it('test_repeated_cast_does_not_clear_existing_session', function()
    castRod()
    local session = env.cast.Sessions[env.player.UserId]
    castRod()
    assert.same('alreadyCasting', lastState().result.reason)
    assert.same(session, env.cast.Sessions[env.player.UserId])
    assert.same(1, env.consumeCount)
    env.events.RequestCastState.OnServerEvent:Fire(env.player)
    assert.same('cast', lastState().phase)
    assert.is_nil(lastState().result)
  end)

  it('test_valid_cast_sends_waiting_landing_and_consumes_bait_once', function()
    castRod()
    local state = lastState()
    assert.same('cast', state.phase)
    assert.same('WaterCircle2', state.zoneId)
    assert.same('number', type(state.castId))
    assert.same(-11.75, state.landing.x)
    assert.same(-12.25, state.landing.z)
    assert.same(9, env.data:GetItemBarSnapshot().bait.worm)
    castRod()
    env.events.RequestCastState.OnServerEvent:Fire(env.player)
    assert.same('cast', lastState().phase)
    assert.same(state.castId, lastState().castId)
    assert.is_true(lastState().snapshot)
    assert.same(state.landing, lastState().landing)
    assert.same(state.zoneId, lastState().zoneId)
    assert.same(9, env.data:GetItemBarSnapshot().bait.worm)
    assert.same(1, #env.facts)
    assert.same('CastWater', env.facts[1].kind)
  end)

  it('test_water_edge_repeated_failures_then_success_keep_bait_and_quest_fact', function()
    -- 虾池旋转后的西侧边界 x=232，线内含边界，线外拒绝。
    local position = env.player.Character.Position
    env.player.Character.Rotation = { GetForward = function() return { x = 0, y = 0, z = -1 } end }
    position.y, position.z = 5, -1
    for _, x in ipairs({ 231.999, 231.998 }) do
      position.x = x
      castRod()
      assert.same('idle', lastState().phase)
      assert.same('invalidLanding', lastState().result.reason)
      assert.same({ x = x, y = 5, z = -6 }, lastState().result.landing)
      assert.same(10, env.data:GetItemBarSnapshot().bait.worm)
      assert.same(0, #env.facts)
      env.events.RequestCastState.OnServerEvent:Fire(env.player)
      assert.is_nil(lastState().result)
    end
    position.x = 232
    castRod()
    assert.same('cast', lastState().phase)
    assert.same('ShrimpPool', lastState().zoneId)
    assert.same({ x = 232, y = 5.6, z = -6 }, lastState().landing)
    assert.same(9, env.data:GetItemBarSnapshot().bait.worm)
    assert.same(1, #env.facts)
    assert.same('CastWater', env.facts[1].kind)
  end)
end)

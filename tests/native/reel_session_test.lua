-- 迁移自 tests/gameplay/reel_session_test.lua（#85）。
-- 被测接缝：server.Mgr.MgrReelIn 的会话生命周期（Begin / Update / Interrupt / Close / Finish / 玩家进出）。
-- it 名字沿用旧方法名，注册顺序 = LuaUnit sortedPairs 的实际执行顺序。
-- 旧 setUp 每个方法重跑一次（含 reload MgrReelIn、注入 Cast 桩、建两个玩家并 Begin），
-- 因此映射为 describe 内的逐例 before_each/after_each，不是 suite 级 setup/teardown。

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

describe('收线会话管理器（MgrReelIn）', function()
  local env
  local restore

  before_each(function()
    -- 快照先于任何改动：before_each 中途失败时 after_each 仍能还原。
    restore = {
      RE = package.loaded['common.REUtil'],
      mgr = package.loaded['server.Mgr.MgrReelIn'],
      game = _G.game,
    }
    env = { events = {}, now = 0 }
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
    env.mgr = require('server.Mgr.MgrReelIn')
    env.cast = { Sessions = {}, FinishReel = function(_, player, id, outcome)
      local current = env.cast.Sessions[player.UserId]
      if current and current.player == player and current.session.reelSession == id then
        current.session.phase = outcome
        player.results[#player.results + 1] = outcome
      end
    end }
    env.mgr.Cast = env.cast
    env.mgr:Start()
    env.a = { UserId = 1, messages = {}, results = {}, CharacterAdded = signal(), CharacterRemoving = signal() }
    env.b = { UserId = 2, messages = {}, results = {}, CharacterAdded = signal(), CharacterRemoving = signal() }
    for _, player in ipairs({ env.a, env.b }) do
      env.mgr:OnPlayerAdded(player)
      env.cast.Sessions[player.UserId] = { player = player, session = { phase = 'hooked', reelSession = 's' .. player.UserId } }
      env.mgr:Begin(player, 's' .. player.UserId, 0)
    end
  end)

  after_each(function()
    -- 对未跑完的 before_each 幂等：mgr 没建起来就只还原缓存。
    if env and env.mgr then
      env.mgr:OnPlayerRemoving(env.a)
      env.mgr:OnPlayerRemoving(env.b)
    end
    package.loaded['server.Mgr.MgrReelIn'] = restore and restore.mgr or nil
    package.loaded['common.REUtil'] = restore and restore.RE or nil
    _G.game = restore and restore.game or nil
    env = nil
    restore = nil
  end)

  it('test_cast_update_does_not_broadcast_hook_after_synchronous_close', function()
    env.mgr:Finish(env.mgr.Sessions[1], 'unhooked')
    local original = package.loaded['server.Mgr.MgrPlayerData']
    package.loaded['server.Mgr.MgrPlayerData'] = {}
    local cast = assert(loadfile('server/Mgr/MgrCast.lua'))()
    package.loaded['server.Mgr.MgrPlayerData'] = original
    cast.World = env.mgr.World
    cast.ReelIn = env.mgr
    cast.Sessions[1] = { player = env.a, session = {
      phase = 'cast', hookAt = 0, zoneId = 'WaterCircle2', rodLevel = 1,
    } }
    env.mgr.Cast = cast
    local re = env.events.ReelInRE
    local send = re.FireClient
    re.FireClient = function(_, player, value)
      send(re, player, value)
      if value.action == 'started' then env.mgr:Close(player, { session = value.session }) end
    end
    cast:Update()
    assert.is_nil(cast.Sessions[1])
    local states = env.events.CastState
    assert.is_not_nil(states)
    for _, message in ipairs(env.a.messages) do
      assert.not_same('hooked', message.phase)
    end
  end)

  it('test_close_cannot_end_another_player_and_finishes_once', function()
    local close = env.events.CloseReelIn.OnServerEvent
    close:Fire(env.a, { session = 's2' })
    assert.is_not_nil(env.mgr.Sessions[2])
    close:Fire(env.a, { session = 's1' })
    close:Fire(env.a, { session = 's1' })
    assert.same({ 'unhooked' }, env.a.results)
    assert.is_not_nil(env.mgr.Sessions[2])
  end)

  it('test_controller_died_clears_session_once', function()
    local controller = { Died = signal() }
    env.a.Character = { Controller = controller }
    env.a.CharacterAdded:Fire(env.a.Character)
    controller.Died:Fire()
    assert.same({ 'unhooked' }, env.a.results)
    env.a.CharacterRemoving:Fire()
    assert.same({ 'unhooked' }, env.a.results)
  end)

  it('test_death_and_offline_clear_only_once', function()
    env.a.CharacterRemoving:Fire()
    env.mgr:OnPlayerRemoving(env.a)
    assert.same({ 'unhooked' }, env.a.results)
    env.now = 10.2
    env.mgr:Update()
    env.now = 10.4
    env.mgr:Update()
    assert.same({ 'unhooked' }, env.b.results)
  end)

  it('test_duplicate_begin_preserves_sequence_and_budget', function()
    local first = env.mgr.Sessions[1]
    env.events.ReelInRE.OnServerEvent:Fire(env.a, { s = 's1', n = 3, q = 1 })
    assert.is_true(env.mgr:Begin(env.a, 's1', env.now))
    assert.are.equal(first, env.mgr.Sessions[1])
    assert.same('order', env.mgr.Sessions[1].Receiver:Accept(0, { s = 's1', n = 1, q = 1 }).Reason)
    assert.same(3, env.mgr.Sessions[1].Receiver.Window:Used(0))
  end)

  it('test_grace_never_extends_past_two_hundred_ms', function()
    env.now = 10.179
    env.mgr:Update()
    assert.is_nil(env.a.results[1])
    env.now = 10.201
    env.events.ReelInRE.OnServerEvent:Fire(env.a, { s = 's1', n = 10, q = 1 })
    assert.same({ 'unhooked' }, env.a.results)
    assert.is_nil(env.mgr.Sessions[1])
    assert.is_not_nil(env.mgr.Sessions[2])
  end)

  it('test_identity_session_sequence_and_clamp', function()
    local re = env.events.ReelInRE.OnServerEvent
    re:Fire(env.a, { s = 's2', n = 10, q = 1 })
    re:Fire({ UserId = 1 }, { s = 's1', n = 10, q = 1 })
    re:Fire(env.a, { s = 's1', n = 0.5, q = 1 })
    assert.same(1, #env.a.messages)
    env.now = 2
    re:Fire(env.a, { s = 's1', n = 8, q = 1 })
    assert.same(8, env.a.messages[#env.a.messages].accepted)
    re:Fire(env.a, { s = 's1', n = 8, q = 1 })
    re:Fire(env.a, { s = 's1', n = 8, q = 2 })
    assert.same(2, env.a.messages[#env.a.messages].accepted)
    assert.same(1, #env.b.messages)
  end)

  it('test_interrupt_breaks_hooked_session', function()
    -- #131：濒死/死亡打断收线；与 Died / CharacterRemoving 同语义（unhooked），幂等且不波及他人
    env.mgr:Interrupt(env.a)
    assert.same({ 'unhooked' }, env.a.results)
    assert.is_nil(env.mgr.Sessions[1])
    assert.is_not_nil(env.mgr.Sessions[2])
    env.mgr:Interrupt(env.a)
    assert.same(1, #env.a.results)
    env.mgr:Interrupt(nil)
    assert.is_not_nil(env.mgr.Sessions[2])
  end)

  it('test_land_result_is_a_single_handoff', function()
    env.events.ReelInRE.OnServerEvent:Fire(env.a, { s = 's1', n = 10, q = 1 })
    assert.same({ 'landed' }, env.a.results)
    env.events.ReelInRE.OnServerEvent:Fire(env.a, { s = 's1', n = 10, q = 2 })
    assert.same({ 'landed' }, env.a.results)
  end)

  it('test_no_click_unhooks_after_hundred_eighty_ms', function()
    env.now = 10.181
    env.mgr:Update()
    assert.same({ 'unhooked' }, env.a.results)
  end)

  it('test_offline_drops_authority_without_reply', function()
    local count = #env.a.messages
    env.mgr:OnPlayerRemoving(env.a)
    env.mgr:OnPlayerRemoving(env.a)
    assert.is_nil(env.mgr.Sessions[1])
    assert.same(count, #env.a.messages)
    assert.same({ 'unhooked' }, env.a.results)
  end)

  it('test_old_player_removal_does_not_disconnect_replacement', function()
    local old = env.a
    local replacement = { UserId = 1, messages = {}, results = {},
      CharacterAdded = signal(), CharacterRemoving = signal() }
    env.mgr:OnPlayerAdded(replacement)
    env.cast.Sessions[1] = { player = replacement,
      session = { phase = 'hooked', reelSession = 'next' } }
    assert.is_true(env.mgr:Begin(replacement, 'next', 0))
    env.mgr:OnPlayerRemoving(old)
    assert.is_not_nil(env.mgr.Connections[1])
    replacement.CharacterRemoving:Fire()
    assert.same({ 'unhooked' }, replacement.results)
    env.mgr:OnPlayerRemoving(replacement)
  end)

  it('test_progress_reply_echoes_batch_sequence', function()
    -- #38：progress 回包带上本批序号，客户端据此确认在途点击
    env.events.ReelInRE.OnServerEvent:Fire(env.a, { s = 's1', n = 3, q = 7 })
    local reply = env.a.messages[#env.a.messages]
    assert.same('progress', reply.action)
    assert.same(7, reply.q)
    assert.same(3, reply.accepted)
  end)

  it('test_restart_cleans_connections_and_sessions', function()
    local first = env.mgr.REConnection
    env.mgr:Start()
    assert.are.equal(first, env.mgr.REConnection)
    env.mgr:Stop()
    assert.is_nil(env.mgr.REConnection)
    assert.is_nil(env.mgr.Sessions[1])
    assert.is_nil(env.mgr.Connections[1])
    env.mgr:Start()
    assert.are_not.equal(first, env.mgr.REConnection)
  end)

  it('test_started_callback_can_close_before_begin_returns', function()
    env.mgr:Finish(env.mgr.Sessions[1], 'unhooked')
    env.cast.Sessions[1].session.phase = 'hooked'
    env.cast.Sessions[1].session.reelSession = 'next'
    local event = env.events.ReelInRE
    local original = event.FireClient
    event.FireClient = function(_, player, value)
      original(event, player, value)
      if value.action == 'started' then env.mgr:Close(player, { session = value.session }) end
    end
    assert.is_false(env.mgr:Begin(env.a, 'next', 0))
    assert.is_nil(env.mgr.Sessions[1])
    assert.same({ 'unhooked', 'unhooked' }, env.a.results)
  end)

  it('test_update_does_not_change_delayed_batch_result', function()
    local progress = env.mgr.Sessions[1].Progress
    env.now = 10.159
    env.mgr:Update()
    assert.is_nil(env.a.results[1])
    assert.near(0, progress.Progress, 0.5)
    env.now = 10.17
    env.events.ReelInRE.OnServerEvent:Fire(env.a, { s = 's1', n = 2, q = 1 })
    local direct = require('common.ReelProgress').New(0, require('common.GameCfg').ReelIn)
    direct:Advance(10.17, 2, 0.1)
    assert.is_nil(env.a.results[1])
    assert.near(direct.Progress, progress.Progress, 0.5)
  end)
end)

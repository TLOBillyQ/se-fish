-- 迁移自 tests/gameplay/reel_unhook_test.lua（#85）；行为契约原文见 #133。
-- #133 脱钩→收竿→可再抛竿。失败方式（先列后写）：
--   1. 收线到 0 脱钩后直接回到 idle（线还没收，玩家能立刻再抛竿）；
--   2. 脱钩时把鱼竿归位 / 生成活鱼 / 报「上岸」事实；
--   3. unhooked 阶段按收竿不生效，或收竿后仍不能再次抛竿；
--   4. 死亡 / 离线打断走成 unhooked，把「收竿」留给一个已经没线的玩家；
--   5. unhooked 阶段重复收竿回包两次、或再次抛竿被受理。
-- it 名字沿用旧方法名，注册顺序 = LuaUnit sortedPairs 的实际执行顺序。

local moduleNames = { 'common.REUtil', 'server.Mgr.MgrPlayerData', 'server.Mgr.MgrFishUnit' }

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

local function vec(x, y, z)
  return { x = x, y = y, z = z }
end

describe('脱钩后收回鱼线（MgrCast × MgrReelIn）', function()
  local env
  local restore

  before_each(function()
    restore = { game = rawget(_G, 'game'), Vector3 = rawget(_G, 'Vector3') }
    for _, name in ipairs(moduleNames) do
      restore[name] = package.loaded[name]
    end
    env = { now = 0, events = {}, messages = {}, spawned = {}, facts = {} }
    _G.Vector3 = { New = vec }
    _G.game = { GetService = function(_, name)
      if name == 'World' then return { GetServerTime = function() return env.now end } end
    end }
    package.loaded['common.REUtil'] = {
      GetRE = function(_, name)
        if not env.events[name] then
          env.events[name] = { OnServerEvent = signal(), FireClient = function(_, player, value)
            player.messages[#player.messages + 1] = { name = name, value = value }
          end }
        end
        return env.events[name]
      end,
      CheckRECD = function() return false end,
    }
    env.data = { Data = { SelectedSlot = 1, FishCoin = 0, Bait = { worm = 3 }, SelectedBait = 'worm',
      Containers = { itemBar = { [1] = { itemId = 'starterRod', count = 1, containerId = 'itemBar' } } } } }
    function env.data:ConsumeSelectedBait() return true, 'worm' end
    function env.data:RestoreSlot(index) self.Data.SelectedSlot = index return true end
    package.loaded['server.Mgr.MgrPlayerData'] = {
      GetDataInst = function(_, player) return player == env.player and env.data or nil end,
      SendItemBar = function() end,
    }
    package.loaded['server.Mgr.MgrFishUnit'] = {
      CanCast = function() return true end,
      HeldInfo = function() end,
      SpawnLanded = function(_, player, opts)
        env.spawned[#env.spawned + 1] = opts
        return { Id = #env.spawned }
      end,
    }
    env.reel = assert(loadfile('server/Mgr/MgrReelIn.lua'))()
    env.cast = assert(loadfile('server/Mgr/MgrCast.lua'))()
    env.cast.ReelIn = env.reel
    env.reel.Cast = env.cast
    env.cast.Quest = { Notify = function(_, kind, _, payload)
      env.facts[#env.facts + 1] = { kind = kind, eventId = payload.eventId }
      return true
    end }
    env.reel:Start()
    env.cast:Start()
    env.player = { UserId = 7, messages = {}, Character = { Position = vec(-11.75, 2, -17.25),
      Rotation = { GetForward = function() return vec(0, 0, 1) end },
      Animator = { LoadAnimation = function() return { Play = function() end } end } } }
    env.reel:OnPlayerAdded(env.player)
  end)

  after_each(function()
    -- 逐例清理，且对未跑完的 before_each 幂等：模块没加载起来就只还原全局与缓存。
    if env then
      if env.reel then env.reel:Stop() end
      if env.cast then env.cast:Stop() end
    end
    for _, name in ipairs(moduleNames) do
      package.loaded[name] = restore[name]
    end
    _G.game = restore.game
    _G.Vector3 = restore.Vector3
    env = nil
    restore = nil
  end)

  -- 直接摆一个已上钩的会话，省掉抛竿与抽签
  local function hook(fishId, mult)
    local id = 'r' .. tostring(#env.spawned) .. ':' .. tostring(env.now)
    env.cast.Sessions[env.player.UserId] = { player = env.player, session = {
      phase = 'hooked', fishId = fishId, mult = mult, reelSession = id, reelSerial = 1, slot = 1,
    } }
    assert.is_true(env.reel:Begin(env.player, id, env.now))
    return id
  end

  local function lastState()
    local last
    for _, message in ipairs(env.player.messages) do
      if message.name == 'CastState' then last = message.value end
    end
    return last
  end

  it('test_death_while_line_is_out_reels_it_back', function()
    hook('bass', 1.2)
    env.now = 30
    env.reel:Update()
    assert.same('unhooked', env.cast.Sessions[env.player.UserId].session.phase)
    -- MgrFishUnit:OnDied 的入口：死亡不该给玩家留下一条只能靠按按钮收回的线
    env.cast:Abort(env.player)
    assert.is_nil(env.cast.Sessions[env.player.UserId])
    assert.same('idle', lastState().phase)
  end)

  it('test_interrupt_and_offline_end_the_session_instead_of_leaving_a_line_out', function()
    hook('bass', 1.2)
    env.reel:Interrupt(env.player)
    assert.is_nil(env.cast.Sessions[env.player.UserId])
    assert.same('idle', lastState().phase)
    assert.same(0, #env.spawned)
    hook('carp', 1.1)
    env.reel:OnPlayerRemoving(env.player)
    assert.is_nil(env.cast.Sessions[env.player.UserId])
  end)

  it('test_progress_zero_leaves_the_line_out_until_reeled', function()
    local id = hook('bass', 1.2)
    env.data.Data.SelectedSlot = nil
    env.now = 30
    env.reel:Update()
    local current = env.cast.Sessions[env.player.UserId]
    assert.message('脱钩后会话不该被清掉：线还在水里').is_not_nil(current)
    assert.same('unhooked', current.session.phase)
    assert.same('unhooked', lastState().phase)
    assert.is_nil(env.reel.Sessions[env.player.UserId])
    assert.same(0, #env.spawned)
    assert.is_nil(env.data.Data.SelectedSlot)
    assert.same(0, #env.facts)
    assert.same(id, current.session.reelSession)
  end)

  it('test_reel_back_returns_to_idle_and_allows_casting_again', function()
    hook('bass', 1.2)
    env.now = 30
    env.reel:Update()
    env.events.CastAction.OnServerEvent:Fire(env.player, { action = 'Reel' })
    assert.is_nil(env.cast.Sessions[env.player.UserId])
    assert.same('idle', lastState().phase)
    local sent = #env.player.messages
    env.events.CastAction.OnServerEvent:Fire(env.player, { action = 'Reel' })
    assert.same(sent, #env.player.messages)
    env.now = 31
    env.events.CastAction.OnServerEvent:Fire(env.player, {
      action = 'Cast', slot = 1, itemId = 'starterRod' })
    local current = env.cast.Sessions[env.player.UserId]
    assert.is_not_nil(current)
    assert.same('cast', current.session.phase)
    assert.same('cast', lastState().phase)
  end)

  it('test_repeated_events_after_unhooking_do_not_jump_state', function()
    -- 重复 / 迟到事件不跳状态：脱钩后再收到「上岸」或又一次「脱钩」都停在 unhooked
    local id = hook('bass', 1.2)
    env.now = 30
    env.reel:Update()
    local sent = #env.player.messages
    env.cast:FinishReel(env.player, id, 'landed')
    env.cast:FinishReel(env.player, id, 'unhooked', nil, true)
    assert.same('unhooked', env.cast.Sessions[env.player.UserId].session.phase)
    assert.same(sent, #env.player.messages)
    assert.same(0, #env.spawned)
    assert.same(0, #env.facts)
  end)

  it('test_unhooked_blocks_casting_until_reeled_back', function()
    hook('bass', 1.2)
    env.now = 30
    env.reel:Update()
    assert.same('unhooked', env.cast.Sessions[env.player.UserId].session.phase)
    env.events.CastAction.OnServerEvent:Fire(env.player, {
      action = 'Cast', slot = 1, itemId = 'starterRod' })
    assert.same('alreadyCasting', lastState().result.reason)
    assert.same('unhooked', env.cast.Sessions[env.player.UserId].session.phase)
    assert.same(0, #env.spawned)
  end)
end)

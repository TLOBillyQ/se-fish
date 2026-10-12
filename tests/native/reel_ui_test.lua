-- 迁移自 tests/gameplay/reel_ui_test.lua（#85）；行为契约原文见 #38、#37、#41、#133。
-- 被测接缝：ScreenMain 界面上的收线表现（MgrGameUI 打开/关闭 × client.LocalReelIn × EUI 节点）。
-- it 名字沿用旧方法名，注册顺序 = LuaUnit sortedPairs 的实际执行顺序。
-- 加载顺序依赖（保持原样）：先 loadfile LocalReelIn 并 Start，注册 _G.LocalReelIn；
-- 再 loadfile ScreenMain 处理器并塞进 package.loaded；最后 loadfile MgrGameUI（它把 _G.MgrGameUI
-- 与界面节点绑上），才能 OpenScreen('ScreenMain')。

local moduleNames = { 'common.REUtil', 'common.Util', 'client.GameUI',
  'client.ScreenHandlers.ScreenMain', 'client.LocalReelIn' }

local globalNames = { 'game', 'Vector2', 'Vector3', 'Color', 'REUtil', 'GameUI',
  'LocalReelIn', 'MgrGameUI' }

local function signal()
  local listeners = {}
  return { Connect = function(_, fn)
    listeners[#listeners + 1] = fn
    return { Disconnect = function() end }
  end, Fire = function(_, ...)
    for _, fn in ipairs(listeners) do fn(...) end
  end }
end

describe('收线界面表现（ScreenMain × LocalReelIn × MgrGameUI）', function()
  local env
  local restore

  before_each(function()
    -- 快照先于任何改动：before_each 中途失败时 after_each 仍能还原。
    restore = {}
    for _, name in ipairs(globalNames) do
      restore[name] = rawget(_G, name)
    end
    for _, name in ipairs(moduleNames) do
      restore[name] = package.loaded[name]
    end
    env = { events = {}, sent = {}, nodes = {}, heartbeat = signal(), now = 0 }
    local world = { GetServerTime = function() return env.now end }
    env.projected = { x = 960, y = 540, z = 4 }
    env.camera = { WorldToViewportPoint = function(_, position)
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
    env.root = { Visible = false, Name = 'ScreenMain',
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
    env.reel = assert(loadfile('client/LocalReelIn.lua'))()
    _G.LocalReelIn = env.reel
    env.reel:Start()
    env.handler = assert(loadfile('client/ScreenHandlers/ScreenMain.lua'))()
    package.loaded['client.ScreenHandlers.ScreenMain'] = env.handler
    env.ui = assert(loadfile('client/MgrGameUI.lua'))()
    env.ui:OpenScreen('ScreenMain')
  end)

  after_each(function()
    for _, name in ipairs(moduleNames) do
      package.loaded[name] = restore[name]
    end
    for _, name in ipairs(globalNames) do
      _G[name] = restore[name]
    end
    env = nil
    restore = nil
  end)

  -- 让本地追平走完：时间跳过 ChaseSec（0.25 秒，期间按 5%/秒衰减 1.25%）再逐帧刷新
  local function settle()
    env.now = env.now + 0.25
    env.heartbeat:Fire()
  end

  it('test_click_feedback_and_smooth_chase_on_the_bar', function()
    -- #38：点击立即显示 +5%，服务端报告落后超过 5% 时逐帧平滑追平
    env.events.ItemBarState.OnClientEvent:Fire({ slots = {
      [1] = { itemId = 'starterRod', count = 1 },
    }, bait = { worm = 1 }, selectedSlot = 1 })
    env.events.CastState.OnClientEvent:Fire({ phase = 'hooked', reelSession = 'p1' })
    env.events.ReelInRE.OnClientEvent:Fire({ action = 'started', session = 'p1', progress = 50 })
    env.nodes.ItemAction2.OnClicked:Fire()
    assert.same(55, env.nodes.ReelProgress.Percent)
    env.now = 0.1
    env.heartbeat:Fire()
    local sent = env.sent[#env.sent]
    assert.same({ s = 'p1', n = 1, q = 1 }, sent.payload)
    assert.near(54.5, env.nodes.ReelProgress.Percent, 1e-9)
    env.events.ReelInRE.OnClientEvent:Fire({ action = 'progress', session = 'p1', progress = 40, accepted = 0, q = 1 })
    assert.near(54.5, env.nodes.ReelProgress.Percent, 1e-9)
    env.now = 0.19
    env.heartbeat:Fire()
    local mid = env.nodes.ReelProgress.Percent
    assert.message(tostring(mid)).is_true(mid < 54.5 and mid > 39.55)
    env.now = 0.3
    env.heartbeat:Fire()
    assert.near(39, env.nodes.ReelProgress.Percent, 1e-9)
  end)

  it('test_close_flushes_pending_without_reeling_in_and_reopen_keeps_progress', function()
    -- #133：关界面（被商店/背包盖住）只影响表现——待发批次先 flush，但不收线、不重置；
    -- 重开界面接着显示同一个进度，而不是跳回 50。
    env.events.ItemBarState.OnClientEvent:Fire({ slots = {
      [1] = { itemId = 'starterRod', count = 1 },
    }, bait = { worm = 1 }, selectedSlot = 1 })
    env.events.CastState.OnClientEvent:Fire({ phase = 'hooked', reelSession = 's1' })
    env.events.ReelInRE.OnClientEvent:Fire({ action = 'started', session = 's1', progress = 50 })
    assert.same('s1', env.reel.SessionId)
    assert.is_false(env.nodes.ReelProgress.TouchEnabled)
    assert.is_false(env.nodes.ReelProgress.SwallowTouchEnabled)
    env.nodes.ItemAction2.OnClicked:Fire()
    assert.same(55, env.nodes.ReelProgress.Percent)
    env.ui:CloseScreen('ScreenMain')
    assert.same({ name = 'ReelInRE', payload = { s = 's1', n = 1, q = 1 } }, env.sent[#env.sent])
    assert.same('s1', env.reel.SessionId)
    assert.is_false(env.nodes.ReelProgress.Visible)
    assert.is_false(env.nodes.ItemAction2.TouchEnabled)
    -- 遮挡期间服务端照常衰减到 30，本地追平；没有点击就不再上行（进度条不可见，只看本地显示值）
    env.now = 0.5
    env.events.ReelInRE.OnClientEvent:Fire({ action = 'progress', session = 's1', progress = 30, accepted = 0, q = 1 })
    settle()
    assert.near(28.75, env.reel:DisplayProgress(), 1e-9)
    env.ui:OpenScreen('ScreenMain')
    env.events.CastState.OnClientEvent:Fire({ phase = 'hooked', reelSession = 's1', snapshot = true })
    assert.same('s1', env.reel.SessionId)
    assert.is_true(env.nodes.ItemAction2.TouchEnabled)
    assert.is_true(env.nodes.ReelProgress.Visible)
    assert.near(28.75, env.nodes.ReelProgress.Percent, 1e-9)
    -- 全程只有一次上行（关界面前那批），从头到尾没有 CloseReelIn
    local batches, closes = 0, 0
    for _, message in ipairs(env.sent) do
      if message.name == 'ReelInRE' then batches = batches + 1
      elseif message.name == 'CloseReelIn' then closes = closes + 1 end
    end
    assert.same(1, batches)
    assert.same(0, closes)
  end)

  it('test_empty_draw_clears_waiting_and_recast_replaces_feedback', function()
    env.events.ItemBarState.OnClientEvent:Fire({ slots = {
      [1] = { itemId = 'starterRod', count = 1 },
    }, bait = { worm = 2 }, selectedSlot = 1 })
    local landing = { x = 12, y = 3, z = 27 }
    env.events.CastState.OnClientEvent:Fire({ phase = 'cast', castId = 1,
      zoneId = 'WaterCircle2', landing = landing })
    assert.is_true(env.nodes.CastFloat.Visible)
    env.events.CastState.OnClientEvent:Fire({ result = { reason = 'cooldown' } })
    assert.same(1, env.handler.CastState.castId)
    env.events.CastState.OnClientEvent:Fire({ phase = 'idle', result = { reason = 'invalidLanding' } })
    assert.same(1, env.handler.CastState.castId)
    env.events.CastState.OnClientEvent:Fire({ phase = 'idle', castId = 1,
      result = { reason = 'noFish' } })
    assert.same('本次没有鱼上钩，请重新抛竿', env.nodes.CastFailureHint.Text)
    assert.is_true(env.nodes.CastFailureHint.Visible)
    assert.is_false(env.nodes.CastFloat.Visible)
    assert.is_false(env.nodes.CastWaitHint.Visible)
    assert.is_false(env.nodes.CastSplashHint.Visible)
    assert.is_true(env.nodes.ItemAction2.TouchEnabled)
    assert.same('抛竿', env.nodes.BtnItemActionLabel.Text)
    env.nodes.ItemAction2.OnClicked:Fire()
    assert.same({ action = 'Cast', slot = 1, itemId = 'starterRod' }, env.sent[#env.sent].payload)
    env.events.CastState.OnClientEvent:Fire({ phase = 'cast', castId = 2,
      zoneId = 'WaterCircle2', landing = landing })
    assert.is_true(env.nodes.CastFloat.Visible)
    assert.is_false(env.nodes.CastFailureHint.Visible)
    env.events.CastState.OnClientEvent:Fire({ phase = 'idle', castId = 1,
      result = { reason = 'noFish' } })
    assert.same(2, env.handler.CastState.castId)
    assert.is_true(env.nodes.CastWaitHint.Visible)
    assert.is_false(env.nodes.CastFailureHint.Visible)
  end)

  it('test_failure_result_is_not_replayed_after_reopen', function()
    env.events.CastState.OnClientEvent:Fire({ result = { reason = 'noFish' } })
    assert.same('本次没有鱼上钩，请重新抛竿', env.nodes.CastFailureHint.Text)
    env.ui:CloseScreen('ScreenMain')
    assert.is_false(env.nodes.CastFailureHint.Visible)
    env.ui:OpenScreen('ScreenMain')
    env.events.CastState.OnClientEvent:Fire({ phase = 'idle', snapshot = true })
    assert.is_false(env.nodes.CastFailureHint.Visible)
  end)

  it('test_failure_result_marks_landing_and_does_not_replace_cast_state', function()
    local landing = { x = 12, y = 3, z = 27 }
    env.events.CastState.OnClientEvent:Fire({ result = { reason = 'invalidLanding', landing = landing } })
    assert.same('落点不在可钓水域，请重新抛竿', env.nodes.CastFailureHint.Text)
    assert.is_true(env.nodes.CastFailureHint.Visible)
    assert.is_true(env.nodes.CastFailureMark.Visible)
    assert.same(landing, env.lastProjected)
    assert.is_nil(env.handler.CastState)
    env.now = 3
    env.heartbeat:Fire()
    assert.is_false(env.nodes.CastFailureHint.Visible)
    assert.is_false(env.nodes.CastFailureMark.Visible)
    env.events.CastState.OnClientEvent:Fire({ result = { reason = 'cooldown' } })
    assert.is_true(env.nodes.CastFailureHint.Visible)
    assert.is_false(env.nodes.CastFailureMark.Visible)
    env.events.CastState.OnClientEvent:Fire({ phase = 'cast', castId = 1,
      zoneId = 'WaterCircle2', landing = landing })
    assert.is_false(env.nodes.CastFailureHint.Visible)
    assert.is_true(env.nodes.CastFloat.Visible)
  end)

  it('test_holding_fish_shows_drop_even_without_rod_selected', function()
    env.events.ItemBarState.OnClientEvent:Fire({ slots = {
      [1] = { itemId = 'starterRod', count = 1 },
    }, bait = { worm = 1 } })
    env.events.CastState.OnClientEvent:Fire({ phase = 'idle', holding = { fishId = 'carp', mult = 1 } })
    assert.is_true(env.nodes.ItemAction2.Visible)
    assert.same('放下', env.nodes.BtnItemActionLabel.Text)
  end)

  it('test_holding_fish_turns_action_into_drop', function()
    -- #41：服务端报告头上顶着鱼时 2 号位显示「放下」并只发放下请求；没带 holding 就回到抛竿
    env.events.ItemBarState.OnClientEvent:Fire({ slots = {
      [1] = { itemId = 'starterRod', count = 1 },
    }, bait = { worm = 1 }, selectedSlot = 1 })
    env.events.CastState.OnClientEvent:Fire({ phase = 'idle', holding = { fishId = 'bass', mult = 1.2 } })
    assert.same('放下', env.nodes.BtnItemActionLabel.Text)
    assert.is_true(env.nodes.ItemAction2.TouchEnabled)
    local sent = #env.sent
    env.nodes.ItemAction2.OnClicked:Fire()
    assert.same(sent + 1, #env.sent)
    assert.same('CastAction', env.sent[#env.sent].name)
    assert.same({ action = 'Drop' }, env.sent[#env.sent].payload)
    env.events.CastState.OnClientEvent:Fire({ phase = 'idle' })
    assert.same('抛竿', env.nodes.BtnItemActionLabel.Text)
  end)

  it('test_hook_while_screen_is_hidden_is_kept_and_shown_on_reopen', function()
    -- #133：界面被遮挡期间上钩：不取消收线、也不自动开界面；重开后接着显示
    env.events.ItemBarState.OnClientEvent:Fire({ slots = {
      [1] = { itemId = 'starterRod', count = 1 },
    }, bait = { worm = 1 }, selectedSlot = 1 })
    env.ui:CloseScreen('ScreenMain')
    local sent = #env.sent
    env.events.CastState.OnClientEvent:Fire({ phase = 'hooked', reelSession = 'late' })
    env.events.ReelInRE.OnClientEvent:Fire({ action = 'started', session = 'late', progress = 50 })
    assert.same('late', env.reel.SessionId)
    assert.same(sent, #env.sent)
    for _, message in ipairs(env.sent) do
      assert.not_same('CloseReelIn', message.name)
    end
    assert.is_false(env.nodes.ItemAction2.TouchEnabled)
    env.now = 0.5
    env.events.ReelInRE.OnClientEvent:Fire({ action = 'progress', session = 'late', progress = 45, accepted = 0, q = 1 })
    settle()
    assert.is_false(env.nodes.ReelProgress.Visible)
    env.ui:OpenScreen('ScreenMain')
    env.events.CastState.OnClientEvent:Fire({ phase = 'hooked', reelSession = 'late', snapshot = true })
    assert.is_true(env.nodes.ItemAction2.TouchEnabled)
    assert.same('点击收线', env.nodes.BtnItemActionLabel.Text)
    -- 重开接着遮挡时的进度（50 - 3.75），不是新建会话跳回 50
    assert.near(46.25, env.nodes.ReelProgress.Percent, 1e-9)
  end)

  it('test_invalid_landing_feedback_clears_on_interrupt_and_new_failure_survives', function()
    env.events.ItemBarState.OnClientEvent:Fire({ slots = {
      [1] = { itemId = 'starterRod', count = 1 },
    }, bait = { worm = 2 }, selectedSlot = 1 })
    local landing = { x = 12, y = 3, z = 27 }
    env.events.CastState.OnClientEvent:Fire({ phase = 'idle', result = {
      reason = 'invalidLanding', landing = landing,
    } })
    assert.is_true(env.nodes.CastFailureMark.Visible)
    assert.same({ x = 960, y = 540 }, env.nodes.CastFailureMark.Position)
    assert.same('抛竿', env.nodes.BtnItemActionLabel.Text)
    assert.is_true(env.nodes.ItemAction2.TouchEnabled)
    env.nodes.ItemAction2.OnClicked:Fire()
    assert.same({ name = 'CastAction', payload = {
      action = 'Cast', slot = 1, itemId = 'starterRod',
    } }, env.sent[#env.sent])
    env.events.CastState.OnClientEvent:Fire({ phase = 'idle' })
    assert.is_false(env.nodes.CastFailureMark.Visible)
    assert.is_false(env.nodes.CastFailureHint.Visible)
    env.events.CastState.OnClientEvent:Fire({ result = {
      reason = 'invalidLanding', landing = landing,
    } })
    assert.is_true(env.nodes.CastFailureMark.Visible)
    env.now = 1
    env.heartbeat:Fire()
    assert.is_true(env.nodes.CastFailureMark.Visible)
    env.projected = { x = 900, y = 400, z = 4 }
    env.heartbeat:Fire()
    assert.same({ x = 900, y = 680 }, env.nodes.CastFailureMark.Position)
    env.ui:CloseScreen('ScreenMain')
    assert.is_false(env.nodes.CastFailureMark.Visible)
    env.ui:OpenScreen('ScreenMain')
    assert.is_false(env.nodes.CastFailureHint.Visible)
    env.handler:Destroy()
    assert.is_true(env.nodes.CastFailureMark.Destroyed)
  end)

  it('test_landed_greys_out_action_button', function()
    -- #37：上岸瞬间「收线」按钮灰化且不可点，回到 idle 后恢复成抛竿
    env.events.ItemBarState.OnClientEvent:Fire({ slots = {
      [1] = { itemId = 'starterRod', count = 1 },
    }, bait = { worm = 1 }, selectedSlot = 1 })
    local normal = env.nodes.ItemAction2.ButtonNormalColor
    env.events.CastState.OnClientEvent:Fire({ phase = 'hooked', reelSession = 'g1' })
    env.events.CastState.OnClientEvent:Fire({ phase = 'landed', reelSession = 'g1' })
    assert.is_false(env.nodes.ItemAction2.TouchEnabled)
    assert.same({ 120, 120, 120, 255 }, env.nodes.ItemAction2.ButtonNormalColor)
    local sent = #env.sent
    env.nodes.ItemAction2.OnClicked:Fire()
    assert.same(sent, #env.sent)
    env.events.CastState.OnClientEvent:Fire({ phase = 'idle' })
    assert.is_true(env.nodes.ItemAction2.TouchEnabled)
    assert.same(normal, env.nodes.ItemAction2.ButtonNormalColor)
    assert.same('抛竿', env.nodes.BtnItemActionLabel.Text)
  end)

  it('test_reopen_restores_waiting_without_splash_and_destroy_cleans_nodes', function()
    local state = { phase = 'cast', castId = 9, zoneId = 'WaterCircle2',
      landing = { x = 12, y = 3, z = 27 } }
    env.events.CastState.OnClientEvent:Fire(state)
    env.ui:CloseScreen('ScreenMain')
    assert.is_false(env.nodes.CastFloat.Visible)
    assert.is_false(env.nodes.CastWaitHint.Visible)
    assert.is_false(env.nodes.CastSplashHint.Visible)
    env.ui:OpenScreen('ScreenMain')
    env.events.CastState.OnClientEvent:Fire({ phase = 'cast', castId = 9, snapshot = true,
      zoneId = 'WaterCircle2', landing = state.landing })
    assert.is_true(env.nodes.CastFloat.Visible)
    assert.is_true(env.nodes.CastWaitHint.Visible)
    assert.is_false(env.nodes.CastSplashHint.Visible)
    env.events.CastState.OnClientEvent:Fire({ phase = 'idle' })
    env.ui:CloseScreen('ScreenMain')
    env.ui:OpenScreen('ScreenMain')
    env.events.CastState.OnClientEvent:Fire({ phase = 'cast', castId = 10, snapshot = true,
      zoneId = 'WaterCircle2', landing = state.landing })
    assert.is_true(env.nodes.CastWaitHint.Visible)
    assert.is_false(env.nodes.CastSplashHint.Visible)
    local float = env.nodes.CastFloat
    env.handler:Destroy()
    assert.is_true(float.Destroyed)
  end)

  it('test_stale_snapshot_and_cast_do_not_clear_new_invalid_landing_feedback', function()
    env.events.CastState.OnClientEvent:Fire({ phase = 'cast', castId = 1,
      zoneId = 'WaterCircle2', landing = { x = 12, y = 3, z = 27 } })
    env.events.CastState.OnClientEvent:Fire({ phase = 'idle' })
    env.events.CastState.OnClientEvent:Fire({ phase = 'cast', castId = 2,
      zoneId = 'WaterCircle2', landing = { x = 12, y = 3, z = 27 } })
    env.events.CastState.OnClientEvent:Fire({ phase = 'idle' })
    env.events.CastState.OnClientEvent:Fire({ result = {
      reason = 'invalidLanding', landing = { x = 24, y = 3, z = 30 },
    } })
    env.events.CastState.OnClientEvent:Fire({ phase = 'idle', snapshot = true })
    assert.is_true(env.nodes.CastFailureMark.Visible)
    assert.is_true(env.nodes.CastFailureHint.Visible)
    env.events.CastState.OnClientEvent:Fire({ phase = 'cast', castId = 1,
      zoneId = 'WaterCircle2', landing = { x = 12, y = 3, z = 27 } })
    assert.is_true(env.nodes.CastFailureMark.Visible)
    assert.same('idle', env.handler.CastState.phase)
  end)

  it('test_unhooked_phase_reels_back_without_showing_the_bar', function()
    -- #133：脱钩后按钮变「收竿」且可点；收竿回包 idle 后恢复「抛竿」
    env.events.ItemBarState.OnClientEvent:Fire({ slots = {
      [1] = { itemId = 'starterRod', count = 1 },
    }, bait = { worm = 1 }, selectedSlot = 1 })
    env.events.CastState.OnClientEvent:Fire({ phase = 'hooked', reelSession = 'e1' })
    env.events.ReelInRE.OnClientEvent:Fire({ action = 'started', session = 'e1', progress = 50 })
    env.events.ReelInRE.OnClientEvent:Fire({ action = 'unhooked', session = 'e1' })
    env.events.CastState.OnClientEvent:Fire({ phase = 'unhooked', reelSession = 'e1' })
    assert.is_nil(env.reel.SessionId)
    assert.same('收竿', env.nodes.BtnItemActionLabel.Text)
    assert.is_true(env.nodes.ItemAction2.TouchEnabled)
    assert.is_false(env.nodes.ReelProgress.Visible)
    local sent = #env.sent
    env.nodes.ItemAction2.OnClicked:Fire()
    assert.same(sent + 1, #env.sent)
    assert.same({ name = 'CastAction', payload = { action = 'Reel' } }, env.sent[#env.sent])
    env.events.CastState.OnClientEvent:Fire({ phase = 'idle' })
    assert.same('抛竿', env.nodes.BtnItemActionLabel.Text)
    assert.is_true(env.nodes.ItemAction2.TouchEnabled)
  end)

  it('test_waiting_feedback_clears_on_hook_reel_death_and_recast', function()
    local function cast(id)
      env.events.CastState.OnClientEvent:Fire({ phase = 'cast', castId = id,
        zoneId = 'WaterCircle2', landing = { x = 12, y = 3, z = 27 } })
    end
    cast(1)
    env.events.CastState.OnClientEvent:Fire({ phase = 'hooked', reelSession = 'hook1' })
    assert.is_false(env.nodes.CastFloat.Visible)
    assert.is_false(env.nodes.CastWaitHint.Visible)
    assert.is_false(env.nodes.CastSplashHint.Visible)
    env.events.CastState.OnClientEvent:Fire({ phase = 'idle' })
    cast(2)
    assert.is_true(env.nodes.CastSplashHint.Visible)
    env.events.CastState.OnClientEvent:Fire({ phase = 'idle' })
    assert.is_false(env.nodes.CastFloat.Visible)
    cast(3)
    env.events.CastState.OnClientEvent:Fire({ phase = 'idle' })
    assert.is_false(env.nodes.CastWaitHint.Visible)
    cast(4)
    assert.is_true(env.nodes.CastFloat.Visible)
    env.events.CastState.OnClientEvent:Fire({ phase = 'cast', castId = 5, snapshot = true,
      zoneId = 'WaterCircle2', landing = { x = 0, y = 3, z = 0 } })
    assert.is_false(env.nodes.CastSplashHint.Visible)
    env.events.CastState.OnClientEvent:Fire({ phase = 'cast', castId = 1,
      zoneId = 'WaterCircle2', landing = { x = 12, y = 3, z = 27 } })
    assert.same(5, env.handler.CastState.castId)
    assert.is_false(env.nodes.CastSplashHint.Visible)
  end)

  it('test_waiting_feedback_tracks_landing_and_does_not_repeat_on_snapshot', function()
    local state = { phase = 'cast', castId = 1, zoneId = 'WaterCircle2',
      landing = { x = 12, y = 3, z = 27 } }
    env.events.CastState.OnClientEvent:Fire(state)
    assert.is_true(env.nodes.CastFloat.Visible)
    assert.same('●', env.nodes.CastFloat.Text)
    assert.same('等待上钩…', env.nodes.CastWaitHint.Text)
    assert.is_true(env.nodes.CastSplashHint.Visible)
    assert.same('已入水，等待上钩', env.nodes.CastSplashHint.Text)
    assert.same(state.landing, env.lastProjected)
    assert.same({ x = 960, y = 540 }, env.nodes.CastFloat.Position)
    env.projected = { x = 900, y = 400, z = 4 }
    env.heartbeat:Fire()
    assert.same({ x = 900, y = 680 }, env.nodes.CastFloat.Position)
    env.now = 4
    env.heartbeat:Fire()
    assert.is_false(env.nodes.CastSplashHint.Visible)
    env.events.CastState.OnClientEvent:Fire(state)
    assert.is_false(env.nodes.CastSplashHint.Visible)
    assert.is_true(env.nodes.CastFloat.Visible)
  end)
end)

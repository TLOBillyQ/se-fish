-- 迁移自 tests/gameplay/reel_client_test.lua（#85）。
-- 被测接缝：client.LocalReelIn（客户端收线本地状态机 + 批次上报）。
-- it 名字沿用旧方法名，注册顺序 = LuaUnit sortedPairs 的实际执行顺序。
-- setUp/tearDown 逐例化为 before_each/after_each：旧 runner 每个方法都跑一次夹具。

local function signal()
  local callbacks = {}
  return { Connect = function(_, fn)
    callbacks[#callbacks + 1] = fn
    return { Disconnect = function() end }
  end, Fire = function(_, value)
    for _, fn in ipairs(callbacks) do fn(value) end
  end }
end

describe('客户端收线状态机（LocalReelIn）', function()
  -- ctx 承载旧 self 的字段；after_each 对未完成的 before_each 幂等。
  local ctx
  local restore

  before_each(function()
    -- 先抓快照再动任何全局：夹具中途失败时 after_each 才有得还原。
    restore = {
      RE = package.loaded['common.REUtil'],
      client = package.loaded['client.LocalReelIn'],
      game = _G.game,
    }
    ctx = { sent = {}, events = {}, heartbeat = signal() }
    local env = ctx
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
    ctx.client = require('client.LocalReelIn')
    ctx.client:Start()
    ctx.now = 0
  end)

  after_each(function()
    package.loaded['common.REUtil'] = restore and restore.RE or nil
    package.loaded['client.LocalReelIn'] = restore and restore.client or nil
    _G.game = restore and restore.game or nil
    ctx = nil
    restore = nil
  end)

  it('test_ended_session_ignores_late_started_echo', function()
    -- 会话真结束后，迟到的 started 回声不能再把界面拉回收线中
    ctx.client:SetSession('s1')
    ctx.client:Clear('s1')
    ctx.events.ReelInRE.OnClientEvent:Fire({ action = 'started', session = 's1', progress = 50 })
    assert.is_nil(ctx.client.SessionId)
  end)

  it('test_heartbeat_collects_after_hundred_ms', function()
    ctx.client:SetSession('s1')
    ctx.client:Click()
    ctx.now = 0.09
    ctx.heartbeat:Fire()
    assert.same(0, #ctx.sent)
    ctx.now = 0.11
    ctx.heartbeat:Fire()
    assert.same({ name = 'ReelInRE', payload = { s = 's1', n = 1, q = 1 } }, ctx.sent[1])
  end)

  it('test_hook_while_screen_is_hidden_is_kept_and_usable_after_reopen', function()
    ctx.client:Suspend()
    ctx.events.ReelInRE.OnClientEvent:Fire({ action = 'started', session = 's1', progress = 50 })
    assert.same(0, #ctx.sent)
    assert.same('s1', ctx.client.SessionId)
    ctx.client:Click()
    ctx.now = 0.1
    ctx.heartbeat:Fire()
    assert.same({ name = 'ReelInRE', payload = { s = 's1', n = 1, q = 1 } }, ctx.sent[#ctx.sent])
  end)

  it('test_restart_does_not_stack_listeners_or_leave_pending_clicks', function()
    local first = ctx.client.Connection
    local update = ctx.client.UpdateConnection
    ctx.client:Start()
    assert.are.equal(first, ctx.client.Connection)
    assert.are.equal(update, ctx.client.UpdateConnection)
    ctx.client:SetSession('s1')
    ctx.client:Click()
    ctx.client:Stop()
    assert.is_nil(ctx.client.SessionId)
    assert.is_nil(ctx.client.Connection)
    assert.same({ name = 'CloseReelIn', payload = { session = 's1' } }, ctx.sent[#ctx.sent])
    ctx.client:Start()
    assert.are_not.equal(first, ctx.client.Connection)
  end)

  it('test_snapshot_does_not_reset_pending_and_close_flushes_first', function()
    local client = ctx.client
    client:SetSession('s1')
    client:Click()
    client:SetSession('s1')
    client:Close()
    assert.same({
      { name = 'ReelInRE', payload = { s = 's1', n = 1, q = 1 } },
      { name = 'CloseReelIn', payload = { session = 's1' } },
    }, ctx.sent)
    client:Close()
    assert.same(2, #ctx.sent)
  end)

  it('test_suspend_flushes_pending_and_keeps_the_session', function()
    -- #133：界面被遮挡只影响表现——不主动收线、不重置计时，待发批次先送出去
    ctx.client:SetSession('s1')
    ctx.client:Click()
    ctx.client:Suspend()
    assert.same({ { name = 'ReelInRE', payload = { s = 's1', n = 1, q = 1 } } }, ctx.sent)
    assert.same('s1', ctx.client.SessionId)
    assert.is_not_nil(ctx.client.Display)
  end)
end)

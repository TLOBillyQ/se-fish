-- #90 迁移：高频输入限频契约（原 tests/gameplay/rate_limit_test.lua，25 例，纯模块单测 M0-V5）。
-- describe / it 名沿用旧类名与方法名；注册顺序 = 旧套件实际执行顺序（LuaUnit 按 `类名.方法名` 全局字典序，
-- 故同类内方法按字典序、同类的方法连续执行，跨类不交错）。
-- 时间全部由调用方注入（试玩里是 World:GetServerTime() 的秒）：窗口/聚合器/接收器的时刻都是入参，
-- 本文件不替换任何全局与模块缓存，没有需要逐案例恢复的时间替换；helper 的基线快照/恢复照常逐例生效。
local GameCfg = require("common.GameCfg")
local RateLimit = require("common.RateLimit")

local function newWindow()
  return RateLimit.NewWindow(1.0, 10)
end

describe("TestRateLimitAggregator", function()
  local function newAggregator()
    return RateLimit.NewAggregator({ SessionId = "s-1", AggregateSec = 0.1 })
  end

  -- 窗口到期产出一个 {s,n,q}：n 是窗口内点击数，q 从 1 开始单调递增。
  it("test_collect_emits_payload_with_count_and_monotonic_seq", function()
    local agg = newAggregator()
    agg:Click(0)
    agg:Click(0.02)
    agg:Click(0.08)

    local first = agg:Collect(0.1)
    assert.same({ s = "s-1", n = 3, q = 1 }, first)
    assert.is_nil(agg:Collect(0.2))

    agg:Click(0.21)
    local second = agg:Collect(0.31)
    assert.same({ s = "s-1", n = 1, q = 2 }, second)
  end)

  -- C-1：100ms 聚合。窗口未到不发包；没点击也不发包（nil = 这一帧不发包）。
  it("test_collect_waits_for_the_window", function()
    local agg = newAggregator()

    assert.is_nil(agg:Collect(0))
    agg:Click(0)
    assert.is_nil(agg:Collect(0.05))
  end)

  -- C-10 骨架：窗口未满而会话结束（脱钩/关界面/上岸）要立即 flush。
  it("test_flush_emits_immediately", function()
    local agg = newAggregator()
    agg:Click(0)

    assert.same({ s = "s-1", n = 1, q = 1 }, agg:Flush())
    assert.is_nil(agg:Flush())
    assert.same(0, agg:PendingCount())
  end)

  -- C-3：载荷字段恰好三个（字段数固定是「字节上界与点击频率无关」的依据）。
  it("test_payload_has_exactly_the_three_contract_fields", function()
    local agg = newAggregator()
    agg:Click(0)
    local payload = agg:Collect(0.1)

    local allowed = {}
    for _, name in ipairs(RateLimit.PAYLOAD_FIELDS) do
      allowed[name] = true
    end

    local count = 0
    for name in pairs(payload) do
      count = count + 1
      assert.message("载荷多出契约外字段 " .. tostring(name)).is_true(allowed[name])
    end
    assert.same(#RateLimit.PAYLOAD_FIELDS, count)

    assert.same("s-1", payload.s)
    assert.is_true(payload.n <= GameCfg.HighFreqInput.MaxCount)
    assert.is_true(payload.q >= 1)
  end)

  it("test_rejects_bad_config", function()
    assert.error_matches(function() RateLimit.NewAggregator({ AggregateSec = 0.1 }) end, "会话 id", nil, true)
    assert.error_matches(function() RateLimit.NewAggregator({ SessionId = 1, AggregateSec = 0.1 }) end,
      "会话 id", nil, true)
    assert.error_matches(function() RateLimit.NewAggregator({ SessionId = "s-1", AggregateSec = 0 }) end,
      "AggregateSec", nil, true)
  end)

  -- 换会话：没发出去的那一批丢掉，序号从 1 重来（服务端 SetSession 会同步清 lastSeq）。
  it("test_set_session_drops_pending_and_resets_seq", function()
    local agg = newAggregator()
    agg:Click(0)
    agg:SetSession("s-2")

    assert.same(0, agg:PendingCount())
    agg:Click(1)
    assert.same({ s = "s-2", n = 1, q = 1 }, agg:Collect(1.1))
  end)
end)

describe("TestRateLimitConfig", function()
  -- GameCfg 的常量与 #15 定案一致，且真能建出窗口/聚合器（配置与逻辑对得上）。
  it("test_gamecfg_constants_match_the_decision", function()
    assert.same(1.0, GameCfg.HighFreqInput.WindowSec)
    assert.same(10, GameCfg.HighFreqInput.MaxCount)
    assert.same(0.1, GameCfg.HighFreqInput.AggregateSec)

    local cfg = GameCfg.HighFreqInput
    local win = RateLimit.NewWindow(cfg.WindowSec, cfg.MaxCount)
    assert.same(cfg.MaxCount, win:Admit(0, 99))

    local agg = RateLimit.NewAggregator({ SessionId = "s-1", AggregateSec = cfg.AggregateSec })
    agg:Click(0)
    assert.is_nil(agg:Collect(cfg.AggregateSec / 2))
    assert.same(1, agg:Collect(cfg.AggregateSec).n)
  end)
end)

describe("TestRateLimitReceiver", function()
  local function newReceiver(sessionId)
    return RateLimit.NewReceiver({ SessionId = sessionId, WindowSec = 1.0, MaxCount = 10 })
  end

  it("test_accepts_current_session_payload", function()
    local rx = newReceiver("s-1")

    local result = rx:Accept(0, { s = "s-1", n = 3, q = 1 })
    assert.same("ok", result.Status)
    assert.same(3, result.Accepted)
    assert.is_false(result.Clamped)
  end)

  -- 端到端：客户端聚合出来的载荷原样喂给服务端接收侧（M1 就是这么接的）。
  it("test_aggregator_payload_flows_through_receiver", function()
    local agg = RateLimit.NewAggregator({ SessionId = "s-1", AggregateSec = 0.1 })
    local rx = newReceiver("s-1")

    for _ = 1, 12 do
      agg:Click(0)
    end
    local payload = agg:Flush()

    local result = rx:Accept(0, payload)
    assert.same("ok", result.Status)
    assert.same(12, result.Requested)
    assert.same(10, result.Accepted) -- 窗口 1s ≤ 10，多出的 2 次被 clamp
    assert.same("order", rx:Accept(0.01, payload).Reason) -- 同一个包重放一次被序号挡掉
  end)

  -- C-3：丢弃旧序号（重复包、乱序包）。
  it("test_drops_old_sequence", function()
    local rx = newReceiver("s-1")
    rx:Accept(0, { s = "s-1", n = 1, q = 2 })

    assert.same("order", rx:Accept(0.01, { s = "s-1", n = 1, q = 2 }).Reason)
    assert.same("order", rx:Accept(0.01, { s = "s-1", n = 1, q = 1 }).Reason)
    assert.same("ok", rx:Accept(0.01, { s = "s-1", n = 1, q = 3 }).Status)
  end)

  -- C-3：丢弃非当前会话（含「当前没有会话」）。
  it("test_drops_other_session_payload", function()
    local rx = newReceiver("s-1")

    assert.same("session", rx:Accept(0, { s = "s-2", n = 1, q = 1 }).Reason)

    local idle = newReceiver(nil)
    assert.same("session", idle:Accept(0, { s = "s-1", n = 1, q = 1 }).Reason)
  end)

  it("test_end_session_drops_everything", function()
    local rx = newReceiver("s-1")
    rx:EndSession()

    assert.same("session", rx:Accept(0, { s = "s-1", n = 1, q = 1 }).Reason)
  end)

  -- 恶意大包：一次报 n=10^9 只采纳窗口额度，不报错、不崩、不影响后续判定。
  it("test_huge_count_is_clamped", function()
    local rx = newReceiver("s-1")

    local result = rx:Accept(0, { s = "s-1", n = 1e9, q = 1 })
    assert.same("ok", result.Status)
    assert.same(10, result.Accepted)
    assert.is_true(result.Clamped)
    assert.same(0, rx:Accept(0, { s = "s-1", n = 1, q = 2 }).Accepted)
  end)

  -- 类型校验在最前：畸形包一律 bad-payload，且不能抛错
  -- （n 为 nan 时若放行，会污染窗口账目、把限流静默关掉——比对抛错更难发现）。
  it("test_malformed_payload_is_dropped_not_raised", function()
    local rx = newReceiver("s-1")

    assert.same("bad-payload", rx:Accept(0, nil).Reason)
    assert.same("bad-payload", rx:Accept(0, "s-1").Reason)
    assert.same("bad-payload", rx:Accept(0, { n = 1, q = 1 }).Reason)        -- 缺 s
    assert.same("bad-payload", rx:Accept(0, { s = 1, n = 1, q = 1 }).Reason)   -- s 不是字符串
    assert.same("bad-payload", rx:Accept(0, { s = "s-1", n = "3", q = 1 }).Reason)
    assert.same("bad-payload", rx:Accept(0, { s = "s-1", n = 0, q = 1 }).Reason)
    assert.same("bad-payload", rx:Accept(0, { s = "s-1", n = 1 / 0, q = 1 }).Reason)
    assert.same("bad-payload", rx:Accept(0, { s = "s-1", n = 0 / 0, q = 1 }).Reason)
    assert.same("bad-payload", rx:Accept(0, { s = "s-1", n = 1 }).Reason)     -- 缺 q
    assert.same("bad-payload", rx:Accept(0, { s = "s-1", n = 1, q = 0 }).Reason)
    assert.same("bad-payload", rx:Accept(0, { s = "s-1", n = 1.5, q = 1 }).Reason)
    assert.same("bad-payload", rx:Accept(0, { s = "s-1", n = 1, q = 1.5 }).Reason)
  end)

  -- 合法但超限的包照样 ok（Accepted=0）：限流不产生错误路径，也不向玩家报错（C-2/R-5）。
  it("test_over_limit_is_ok_with_zero_accepted", function()
    local rx = newReceiver("s-1")
    rx:Accept(0, { s = "s-1", n = 10, q = 1 })

    local result = rx:Accept(0.1, { s = "s-1", n = 4, q = 2 })
    assert.same("ok", result.Status)
    assert.same(0, result.Accepted)
    assert.same(4, result.Requested)
    assert.is_true(result.Clamped)
  end)

  it("test_session_switch_then_old_payloads_drop", function()
    local rx = newReceiver("s-1")
    rx:Accept(0, { s = "s-1", n = 5, q = 1 })
    rx:SetSession("s-2")

    assert.same("session", rx:Accept(0.1, { s = "s-1", n = 1, q = 2 }).Reason)
    -- 新会话的序号从 1 重来也能过（SetSession 把 lastSeq 清了），且滑动窗已清零。
    assert.same(5, rx:Accept(0.1, { s = "s-2", n = 5, q = 1 }).Accepted)
  end)
end)

describe("TestRateLimitWindow", function()
  -- 非法批量（nan / 负数 / 非数字）一律按 0 采纳，不抛错。
  -- 注意 nan 不是靠 math.floor 挡的（math.floor(nan) 返回 nan，不抛错），而是靠 Admit 入口的有限性校验挡的：
  -- 放 nan 进窗口账目会让限流静默失效，见 common/RateLimit.lua 的 isFiniteNumber 注释。
  it("test_bad_count_is_zero_not_an_error", function()
    local win = newWindow()

    assert.same(0, win:Admit(0, 0 / 0))
    assert.same(0, win:Admit(0, -3))
    assert.same(0, win:Admit(0, "5"))
    assert.same(0, win:Used(0))
  end)

  -- 一批请求本身超限：clamp 到窗口额度（请求 n=25 → 采纳 10），不是整批丢弃。
  it("test_batch_is_clamped_not_dropped", function()
    local win = newWindow()

    assert.same(10, win:Admit(0, 25))
  end)

  -- 部分 clamp：已经用掉 6 次，再请求 8 次只能采纳 4 次。
  it("test_batch_is_clamped_to_remaining_budget", function()
    local win = newWindow()
    win:Admit(0, 6)

    assert.same(4, win:Admit(0, 8))
    assert.same(10, win:Used(0))
  end)

  -- 超限不报错：第 11 次返回 0（而不是抛错，也不是「整包丢弃」的信号）。
  it("test_over_limit_clamps_to_zero_without_error", function()
    local win = newWindow()
    win:Admit(0, 10)

    assert.same(0, win:Admit(0, 1))
  end)

  -- 配置非法一律抛错；LuaUnit assertErrorMsgContains 是 plain 子串（不剥 path:line）。
  it("test_rejects_bad_config", function()
    assert.error_matches(function() RateLimit.NewWindow(0, 10) end, "WindowSec", nil, true)
    assert.error_matches(function() RateLimit.NewWindow(1.0, 0) end, "MaxCount", nil, true)
  end)

  it("test_reset_clears_the_window", function()
    local win = newWindow()
    win:Admit(0, 10)
    win:Reset()

    assert.same(0, win:Used(0))
    assert.same(10, win:Admit(0, 10))
  end)

  -- C-2：每玩家滑动窗 1s ≤ 10 次，超限 clamp、不丢弃、不报错。
  it("test_window_allows_ten_per_second", function()
    local win = newWindow()
    local accepted = 0
    for _ = 1, 12 do
      accepted = accepted + win:Admit(0, 1)
    end

    assert.same(10, accepted)
    assert.same(10, win:Used(0))
    assert.same(0, win:Remaining(0))
  end)

  -- 额度是随时间滑回来的，不是「每秒清零后重新计数」。
  it("test_window_frees_budget_over_time", function()
    local win = newWindow()
    win:Admit(0, 4)
    win:Admit(0.5, 6)

    assert.same(0, win:Remaining(0.6))
    assert.same(4, win:Remaining(1.0))  -- t=0 那批过期
    assert.same(10, win:Remaining(1.5)) -- t=0.5 那批也过期
  end)

  -- 窗口口径 (t-1, t]：t=0 用满后，t=0.999 仍被限，t=1.0 正好过期、额度回满。
  it("test_window_slides_at_the_boundary", function()
    local win = newWindow()
    win:Admit(0, 10)

    assert.same(0, win:Admit(0.999, 1))
    assert.same(10, win:Admit(1.0, 10))
  end)
end)

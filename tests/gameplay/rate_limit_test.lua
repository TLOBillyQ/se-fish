-- 纯模块单测：高频输入契约 common/RateLimit.lua（M0-V5）。
-- 时间全部由调用方注入（试玩里是 World:GetServerTime() 的秒），所以这里用假时刻表就能把
-- 滑动窗、聚合窗口、会话/序号丢弃全跑一遍，不用起引擎（C-11 的「纯函数单测」）。
local lu = require("luaunit")
local GameCfg = require("common.GameCfg")
local RateLimit = require("common.RateLimit")

local function newWindow()
  return RateLimit.NewWindow(1.0, 10)
end

TestRateLimitWindow = {}

-- C-2：每玩家滑动窗 1s ≤ 10 次，超限 clamp、不丢弃、不报错。
function TestRateLimitWindow:test_window_allows_ten_per_second()
  local win = newWindow()
  local accepted = 0
  for _ = 1, 12 do
    accepted = accepted + win:Admit(0, 1)
  end

  lu.assertEquals(accepted, 10)
  lu.assertEquals(win:Used(0), 10)
  lu.assertEquals(win:Remaining(0), 0)
end

-- 超限不报错：第 11 次返回 0（而不是抛错，也不是「整包丢弃」的信号）。
function TestRateLimitWindow:test_over_limit_clamps_to_zero_without_error()
  local win = newWindow()
  win:Admit(0, 10)

  lu.assertEquals(win:Admit(0, 1), 0)
end

-- 一批请求本身超限：clamp 到窗口额度（请求 n=25 → 采纳 10），不是整批丢弃。
function TestRateLimitWindow:test_batch_is_clamped_not_dropped()
  local win = newWindow()

  lu.assertEquals(win:Admit(0, 25), 10)
end

-- 部分 clamp：已经用掉 6 次，再请求 8 次只能采纳 4 次。
function TestRateLimitWindow:test_batch_is_clamped_to_remaining_budget()
  local win = newWindow()
  win:Admit(0, 6)

  lu.assertEquals(win:Admit(0, 8), 4)
  lu.assertEquals(win:Used(0), 10)
end

-- 窗口口径 (t-1, t]：t=0 用满后，t=0.999 仍被限，t=1.0 正好过期、额度回满。
function TestRateLimitWindow:test_window_slides_at_the_boundary()
  local win = newWindow()
  win:Admit(0, 10)

  lu.assertEquals(win:Admit(0.999, 1), 0)
  lu.assertEquals(win:Admit(1.0, 10), 10)
end

-- 额度是随时间滑回来的，不是「每秒清零后重新计数」。
function TestRateLimitWindow:test_window_frees_budget_over_time()
  local win = newWindow()
  win:Admit(0, 4)
  win:Admit(0.5, 6)

  lu.assertEquals(win:Remaining(0.6), 0)
  lu.assertEquals(win:Remaining(1.0), 4)  -- t=0 那批过期
  lu.assertEquals(win:Remaining(1.5), 10) -- t=0.5 那批也过期
end

-- 非法批量（nan / 负数 / 非数字）一律按 0 采纳，不抛错。
-- 注意 nan 不是靠 math.floor 挡的（math.floor(nan) 返回 nan，不抛错），而是靠 Admit 入口的有限性校验挡的：
-- 放 nan 进窗口账目会让限流静默失效，见 common/RateLimit.lua 的 isFiniteNumber 注释。
function TestRateLimitWindow:test_bad_count_is_zero_not_an_error()
  local win = newWindow()

  lu.assertEquals(win:Admit(0, 0 / 0), 0)
  lu.assertEquals(win:Admit(0, -3), 0)
  lu.assertEquals(win:Admit(0, "5"), 0)
  lu.assertEquals(win:Used(0), 0)
end

function TestRateLimitWindow:test_reset_clears_the_window()
  local win = newWindow()
  win:Admit(0, 10)
  win:Reset()

  lu.assertEquals(win:Used(0), 0)
  lu.assertEquals(win:Admit(0, 10), 10)
end

function TestRateLimitWindow:test_rejects_bad_config()
  lu.assertErrorMsgContains("WindowSec", RateLimit.NewWindow, 0, 10)
  lu.assertErrorMsgContains("MaxCount", RateLimit.NewWindow, 1.0, 0)
end

TestRateLimitAggregator = {}

local function newAggregator()
  return RateLimit.NewAggregator({ SessionId = "s-1", AggregateSec = 0.1 })
end

-- C-1：100ms 聚合。窗口未到不发包；没点击也不发包（nil = 这一帧不发包）。
function TestRateLimitAggregator:test_collect_waits_for_the_window()
  local agg = newAggregator()

  lu.assertIs(agg:Collect(0), nil)
  agg:Click(0)
  lu.assertIs(agg:Collect(0.05), nil)
end

-- 窗口到期产出一个 {s,n,q}：n 是窗口内点击数，q 从 1 开始单调递增。
function TestRateLimitAggregator:test_collect_emits_payload_with_count_and_monotonic_seq()
  local agg = newAggregator()
  agg:Click(0)
  agg:Click(0.02)
  agg:Click(0.08)

  local first = agg:Collect(0.1)
  lu.assertEquals(first, { s = "s-1", n = 3, q = 1 })
  lu.assertIs(agg:Collect(0.2), nil)

  agg:Click(0.21)
  local second = agg:Collect(0.31)
  lu.assertEquals(second, { s = "s-1", n = 1, q = 2 })
end

-- C-3：载荷字段恰好三个（字段数固定是「字节上界与点击频率无关」的依据）。
function TestRateLimitAggregator:test_payload_has_exactly_the_three_contract_fields()
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
    lu.assertTrue(allowed[name], "载荷多出契约外字段 " .. tostring(name))
  end
  lu.assertEquals(count, #RateLimit.PAYLOAD_FIELDS)

  lu.assertEquals(payload.s, "s-1")
  lu.assertTrue(payload.n <= GameCfg.HighFreqInput.MaxCount)
  lu.assertTrue(payload.q >= 1)
end

-- C-10 骨架：窗口未满而会话结束（脱钩/关界面/上岸）要立即 flush。
function TestRateLimitAggregator:test_flush_emits_immediately()
  local agg = newAggregator()
  agg:Click(0)

  lu.assertEquals(agg:Flush(), { s = "s-1", n = 1, q = 1 })
  lu.assertIs(agg:Flush(), nil)
  lu.assertEquals(agg:PendingCount(), 0)
end

-- 换会话：没发出去的那一批丢掉，序号从 1 重来（服务端 SetSession 会同步清 lastSeq）。
function TestRateLimitAggregator:test_set_session_drops_pending_and_resets_seq()
  local agg = newAggregator()
  agg:Click(0)
  agg:SetSession("s-2")

  lu.assertEquals(agg:PendingCount(), 0)
  agg:Click(1)
  lu.assertEquals(agg:Collect(1.1), { s = "s-2", n = 1, q = 1 })
end

function TestRateLimitAggregator:test_rejects_bad_config()
  lu.assertErrorMsgContains("会话 id", RateLimit.NewAggregator, { AggregateSec = 0.1 })
  lu.assertErrorMsgContains("会话 id", RateLimit.NewAggregator, { SessionId = 1, AggregateSec = 0.1 })
  lu.assertErrorMsgContains("AggregateSec", RateLimit.NewAggregator, { SessionId = "s-1", AggregateSec = 0 })
end

TestRateLimitReceiver = {}

local function newReceiver(sessionId)
  return RateLimit.NewReceiver({ SessionId = sessionId, WindowSec = 1.0, MaxCount = 10 })
end

function TestRateLimitReceiver:test_accepts_current_session_payload()
  local rx = newReceiver("s-1")

  local result = rx:Accept(0, { s = "s-1", n = 3, q = 1 })
  lu.assertEquals(result.Status, "ok")
  lu.assertEquals(result.Accepted, 3)
  lu.assertFalse(result.Clamped)
end

-- C-3：丢弃非当前会话（含「当前没有会话」）。
function TestRateLimitReceiver:test_drops_other_session_payload()
  local rx = newReceiver("s-1")

  lu.assertEquals(rx:Accept(0, { s = "s-2", n = 1, q = 1 }).Reason, "session")

  local idle = newReceiver(nil)
  lu.assertEquals(idle:Accept(0, { s = "s-1", n = 1, q = 1 }).Reason, "session")
end

-- C-3：丢弃旧序号（重复包、乱序包）。
function TestRateLimitReceiver:test_drops_old_sequence()
  local rx = newReceiver("s-1")
  rx:Accept(0, { s = "s-1", n = 1, q = 2 })

  lu.assertEquals(rx:Accept(0.01, { s = "s-1", n = 1, q = 2 }).Reason, "order")
  lu.assertEquals(rx:Accept(0.01, { s = "s-1", n = 1, q = 1 }).Reason, "order")
  lu.assertEquals(rx:Accept(0.01, { s = "s-1", n = 1, q = 3 }).Status, "ok")
end

-- 类型校验在最前：畸形包一律 bad-payload，且不能抛错
-- （n 为 nan 时若放行，会污染窗口账目、把限流静默关掉——比对抛错更难发现）。
function TestRateLimitReceiver:test_malformed_payload_is_dropped_not_raised()
  local rx = newReceiver("s-1")

  lu.assertEquals(rx:Accept(0, nil).Reason, "bad-payload")
  lu.assertEquals(rx:Accept(0, "s-1").Reason, "bad-payload")
  lu.assertEquals(rx:Accept(0, { n = 1, q = 1 }).Reason, "bad-payload")        -- 缺 s
  lu.assertEquals(rx:Accept(0, { s = 1, n = 1, q = 1 }).Reason, "bad-payload")   -- s 不是字符串
  lu.assertEquals(rx:Accept(0, { s = "s-1", n = "3", q = 1 }).Reason, "bad-payload")
  lu.assertEquals(rx:Accept(0, { s = "s-1", n = 0, q = 1 }).Reason, "bad-payload")
  lu.assertEquals(rx:Accept(0, { s = "s-1", n = 1 / 0, q = 1 }).Reason, "bad-payload")
  lu.assertEquals(rx:Accept(0, { s = "s-1", n = 0 / 0, q = 1 }).Reason, "bad-payload")
  lu.assertEquals(rx:Accept(0, { s = "s-1", n = 1 }).Reason, "bad-payload")     -- 缺 q
  lu.assertEquals(rx:Accept(0, { s = "s-1", n = 1, q = 0 }).Reason, "bad-payload")
  lu.assertEquals(rx:Accept(0, { s = "s-1", n = 1.5, q = 1 }).Reason, "bad-payload")
  lu.assertEquals(rx:Accept(0, { s = "s-1", n = 1, q = 1.5 }).Reason, "bad-payload")
end

-- 恶意大包：一次报 n=10^9 只采纳窗口额度，不报错、不崩、不影响后续判定。
function TestRateLimitReceiver:test_huge_count_is_clamped()
  local rx = newReceiver("s-1")

  local result = rx:Accept(0, { s = "s-1", n = 1e9, q = 1 })
  lu.assertEquals(result.Status, "ok")
  lu.assertEquals(result.Accepted, 10)
  lu.assertTrue(result.Clamped)
  lu.assertEquals(rx:Accept(0, { s = "s-1", n = 1, q = 2 }).Accepted, 0)
end

-- 合法但超限的包照样 ok（Accepted=0）：限流不产生错误路径，也不向玩家报错（C-2/R-5）。
function TestRateLimitReceiver:test_over_limit_is_ok_with_zero_accepted()
  local rx = newReceiver("s-1")
  rx:Accept(0, { s = "s-1", n = 10, q = 1 })

  local result = rx:Accept(0.1, { s = "s-1", n = 4, q = 2 })
  lu.assertEquals(result.Status, "ok")
  lu.assertEquals(result.Accepted, 0)
  lu.assertEquals(result.Requested, 4)
  lu.assertTrue(result.Clamped)
end

function TestRateLimitReceiver:test_session_switch_then_old_payloads_drop()
  local rx = newReceiver("s-1")
  rx:Accept(0, { s = "s-1", n = 5, q = 1 })
  rx:SetSession("s-2")

  lu.assertEquals(rx:Accept(0.1, { s = "s-1", n = 1, q = 2 }).Reason, "session")
  -- 新会话的序号从 1 重来也能过（SetSession 把 lastSeq 清了），且滑动窗已清零。
  lu.assertEquals(rx:Accept(0.1, { s = "s-2", n = 5, q = 1 }).Accepted, 5)
end

function TestRateLimitReceiver:test_end_session_drops_everything()
  local rx = newReceiver("s-1")
  rx:EndSession()

  lu.assertEquals(rx:Accept(0, { s = "s-1", n = 1, q = 1 }).Reason, "session")
end

-- 端到端：客户端聚合出来的载荷原样喂给服务端接收侧（M1 就是这么接的）。
function TestRateLimitReceiver:test_aggregator_payload_flows_through_receiver()
  local agg = RateLimit.NewAggregator({ SessionId = "s-1", AggregateSec = 0.1 })
  local rx = newReceiver("s-1")

  for _ = 1, 12 do
    agg:Click(0)
  end
  local payload = agg:Flush()

  local result = rx:Accept(0, payload)
  lu.assertEquals(result.Status, "ok")
  lu.assertEquals(result.Requested, 12)
  lu.assertEquals(result.Accepted, 10) -- 窗口 1s ≤ 10，多出的 2 次被 clamp
  lu.assertEquals(rx:Accept(0.01, payload).Reason, "order") -- 同一个包重放一次被序号挡掉
end

TestRateLimitConfig = {}

-- GameCfg 的常量与 #15 定案一致，且真能建出窗口/聚合器（配置与逻辑对得上）。
function TestRateLimitConfig:test_gamecfg_constants_match_the_decision()
  lu.assertEquals(GameCfg.HighFreqInput.WindowSec, 1.0)
  lu.assertEquals(GameCfg.HighFreqInput.MaxCount, 10)
  lu.assertEquals(GameCfg.HighFreqInput.AggregateSec, 0.1)

  local cfg = GameCfg.HighFreqInput
  local win = RateLimit.NewWindow(cfg.WindowSec, cfg.MaxCount)
  lu.assertEquals(win:Admit(0, 99), cfg.MaxCount)

  local agg = RateLimit.NewAggregator({ SessionId = "s-1", AggregateSec = cfg.AggregateSec })
  agg:Click(0)
  lu.assertIs(agg:Collect(cfg.AggregateSec / 2), nil)
  lu.assertEquals(agg:Collect(cfg.AggregateSec).n, 1)
end

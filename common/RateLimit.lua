-- 高频输入契约（M0-V5）。来源：#14 调研结论（docs/research/remoteevent-limits.md）+ #15 决策的工程备案。
--
-- 四件套：客户端聚合窗口 → {s,n,q} 载荷 → 服务端滑动窗限流（超限 clamp）→ 服务端权威结果下发
-- （下发是 M1 收线会话的事，本文件不管）。本文件只放**纯函数**：时间全部由调用方注入
-- （R-3：World:GetServerTime() 是唯一权威时钟，单位秒、float），不 require 引擎、不碰 game，
-- 所以能在宿主机 lua 单测里跑（tests/rate_limit_test.lua，C-11 的「纯函数单测」）。
--
-- 为什么服务端自己限流：官方只给协议规范（五层校验：身份/类型/频率/业务条件/结果下发），
-- 频率上限、包大小上限、超限行为、通道数上限全无官方数值（R-1/R-4）；超限行为未知 ⇒
-- 不能依赖「限流会报错」，结果必须服务端权威下发（R-5）。
--
-- 「clamp 不丢弃、不向玩家报错」（C-2）：Window:Admit 返回的是**采纳数**而不是布尔——超限时
-- 采纳数被压到窗口剩余额度（可能是 0），请求本身照样算已处理，所以既没有错误路径可被玩家感知，
-- 也没有「丢弃」路径需要业务处理。真正会丢的是会话/序号不匹配的包（C-3），那是去重不是限流。
--
-- 与 common/REUtil.lua 的关系：CheckRECD 是「每通道一个固定 CD」的粗粒度拦截，滑动窗是新加的一层
-- 次数限流（C-7）；REUtil:CheckRECD 及其调用点一律不动，别的通道照旧。

local RateLimit = {}

-- 采纳结果：Status 只有 ok / dropped 两态；dropped 的 Reason 见下。
-- 注意 ok 的 Accepted 可能是 0（超限 clamp 到零），那不是错误。
RateLimit.Result = { Ok = "ok", Dropped = "dropped" }
RateLimit.Reason = {
    BadPayload = "bad-payload", -- 不是 table / 字段缺或类型不对（客户端可控输入，先查类型）
    Session = "session",        -- 不是当前会话（旧会话、或当前没有会话）
    Order = "order",            -- 序号不新（重复包、乱序包）
}

-- 载荷字段固定这三个（C-3）；字节上界就由「字段数固定 + n 受窗口上限压制」推出，见台账。
RateLimit.PAYLOAD_FIELDS = { "s", "n", "q" }

-- 客户端可控的数字：nan / ±inf / 非数字一律算非法。
-- 为什么必须显式查 nan（本机 Lua 5.4.6 实测，不是「math.floor 会抛错」）：
--   `pcall(math.floor, 0/0)` → `true, -nan(ind)`，math.floor 本身不抛错；
--   真实危害有两条——① nan 进了窗口账目（UsedCount）后 Remaining 也是 nan、所有比较恒为 false，
--   Admit 每次都「采纳」，**限流被静默关掉**（不报错、不丢弃，最难发现的一种坏法）；
--   ② nan 流到整数化处（当表键、`x | 0`、`string.format("%d")`）才抛 "table index is NaN" /
--   "number has no integer representation"。
-- 入口这一道有限性校验同时挡掉「崩」与「静默失真」，是服务端唯一的输入闸门。
local function isFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

-- 会话 id 用字符串，双端一致：一边用数字一边用字符串会让会话校验永远不通过（静默丢包）。
local function checkSessionId(sessionId, where)
    if type(sessionId) ~= "string" or sessionId == "" then
        error(where .. ": 会话 id 必须是非空字符串")
    end
end

-- ============================ 滑动窗（服务端限流）============================

local Window = {}
Window.__index = Window

-- WindowSec 秒内最多采纳 MaxCount 次（C-2 的 1s ≤ 10）。
-- 只记「被采纳过的批次」，每批采纳数 ≥ 1，所以窗口内活跃批次数 ≤ MaxCount，队列长度有界。
function RateLimit.NewWindow(windowSec, maxCount)
    if not isFiniteNumber(windowSec) or windowSec <= 0 then
        error("RateLimit.NewWindow: WindowSec 必须是正数")
    end
    if not isFiniteNumber(maxCount) or maxCount < 1 then
        error("RateLimit.NewWindow: MaxCount 必须是 ≥1 的数")
    end

    return setmetatable({
        WindowSec = windowSec,
        MaxCount = math.floor(maxCount),
        Bursts = {},      -- Bursts[First..Last] = {Time = 时刻, Count = 该次采纳数}
        First = 1,
        Last = 0,
        UsedCount = 0,
    }, Window)
end

-- 时间口径：窗口看的是 (now - WindowSec, now]，即正好落在 now - WindowSec 上的批次已经过期。
-- now 必须单调不减（GetServerTime 满足）；万一回退，只是少清几条、判得更保守，不会算多。
function Window:Trim(now)
    local deadline = now - self.WindowSec
    while self.First <= self.Last and self.Bursts[self.First].Time <= deadline do
        self.UsedCount = self.UsedCount - self.Bursts[self.First].Count
        self.Bursts[self.First] = nil
        self.First = self.First + 1
    end
end

function Window:Used(now)
    self:Trim(now)
    return self.UsedCount
end

function Window:Remaining(now)
    return self.MaxCount - self:Used(now)
end

-- 采纳 count 次里的多少：返回实际采纳数 0 ≤ accepted ≤ count。
-- 超限不报错、不丢弃请求，只把采纳数 clamp 到窗口剩余额度（C-2）。
function Window:Admit(now, count)
    if not isFiniteNumber(count) or count < 1 then
        return 0
    end

    self:Trim(now)
    local accepted = math.min(math.floor(count), self.MaxCount - self.UsedCount)
    if accepted <= 0 then
        return 0
    end

    self.Last = self.Last + 1
    self.Bursts[self.Last] = { Time = now, Count = accepted }
    self.UsedCount = self.UsedCount + accepted
    return accepted
end

-- 清空（会话结束、玩家离开时调用；对应「玩家离开时清理按玩家保存的限频表」）。
function Window:Reset()
    self.Bursts = {}
    self.First = 1
    self.Last = 0
    self.UsedCount = 0
end

-- ============================ 客户端聚合（上行批发）============================

local Aggregator = {}
Aggregator.__index = Aggregator

-- opts：SessionId（本次收线会话 id，进载荷 s）、AggregateSec（聚合窗口秒数，C-1 的 100ms = 0.1）。
-- 点击只记账、不立刻发包：Collect 到窗口才产出一个 {s,n,q}（C-1：100ms 聚合、10Hz 上行）。
function RateLimit.NewAggregator(opts)
    opts = opts or {}
    checkSessionId(opts.SessionId, "RateLimit.NewAggregator")
    if not isFiniteNumber(opts.AggregateSec) or opts.AggregateSec <= 0 then
        error("RateLimit.NewAggregator: AggregateSec 必须是正数")
    end

    return setmetatable({
        SessionId = opts.SessionId,
        AggregateSec = opts.AggregateSec,
        Pending = 0,      -- 本批已攒的点击数
        WindowStart = nil,-- 本批第一个点击的时刻；本批发出去后重新计
        Seq = 0,          -- 本会话内单调递增的序号（换会话归零）
    }, Aggregator)
end

-- 换会话：丢掉没发出去的那一批、序号从 1 重来。
-- 切换顺序：会话 id 由服务端下发，客户端**拿到之后**才换（服务端先 SetSession、客户端后 SetSession）——
-- 反过来的话新会话的头几个包会撞上服务端的旧会话校验，被当成 session 不匹配丢掉。
function Aggregator:SetSession(sessionId)
    checkSessionId(sessionId, "RateLimit.Aggregator:SetSession")
    self.SessionId = sessionId
    self.Pending = 0
    self.WindowStart = nil
    self.Seq = 0
end

-- 记一次点击（计数型，C-16 的收线就是这一类）。
function Aggregator:Click(now)
    if self.Pending == 0 then
        self.WindowStart = now
    end
    self.Pending = self.Pending + 1
end

-- 窗口到期就产出载荷；没到窗口、或本批没有点击，都返回 nil（nil 表示这一帧不发包）。
function Aggregator:Collect(now)
    if self.Pending == 0 or now - self.WindowStart < self.AggregateSec then
        return nil
    end

    return self:Flush()
end

-- 立刻产出并清空本批（C-10：窗口未满而会话结束/关界面要立即 flush）。
function Aggregator:Flush()
    if self.Pending == 0 then
        return nil
    end

    self.Seq = self.Seq + 1
    local payload = { s = self.SessionId, n = self.Pending, q = self.Seq }
    self.Pending = 0
    self.WindowStart = nil
    return payload
end

function Aggregator:PendingCount()
    return self.Pending
end

-- ============================ 服务端接收（校验 + 限流）============================

local Receiver = {}
Receiver.__index = Receiver

-- opts：SessionId（当前会话 id，nil 表示当前没有会话 ⇒ 任何包都丢）、WindowSec、MaxCount。
function RateLimit.NewReceiver(opts)
    opts = opts or {}
    return setmetatable({
        SessionId = opts.SessionId, -- 允许先为 nil（进图/未开始收线时没有会话）
        Window = RateLimit.NewWindow(opts.WindowSec, opts.MaxCount),
        LastSeq = nil,
    }, Receiver)
end

-- 开/换一次会话：旧序号作废、滑动窗清零。
function Receiver:SetSession(sessionId)
    checkSessionId(sessionId, "RateLimit.Receiver:SetSession")
    self.SessionId = sessionId
    self.LastSeq = nil
    self.Window:Reset()
end

function Receiver:EndSession()
    self.SessionId = nil
    self.LastSeq = nil
    self.Window:Reset()
end

local function drop(reason, seq)
    return { Status = RateLimit.Result.Dropped, Reason = reason, Seq = seq }
end

-- 校验一条上行载荷并采纳。msg 是客户端可控输入：先查类型，再查会话，再查序号，
-- 全过了才动滑动窗与 lastSeq（CODING_STANDARDS 的「五层校验」里前四层）。
-- 返回 {Status, Reason?, Requested?, Accepted?, Seq?, Clamped?}：
--   Status="ok" 时 Accepted 是采纳数（可能被 clamp 到 0），Clamped 标记「本该更多但被限流压了」。
function Receiver:Accept(now, msg)
    if type(msg) ~= "table" then
        return drop(RateLimit.Reason.BadPayload, nil)
    end

    local n = msg.n
    local q = msg.q
    if type(msg.s) ~= "string" or msg.s == ""
        or not isFiniteNumber(n) or n < 1 or n ~= math.floor(n)
        or not isFiniteNumber(q) or q < 1 or q ~= math.floor(q) then
        return drop(RateLimit.Reason.BadPayload, nil)
    end

    if self.SessionId == nil or msg.s ~= self.SessionId then
        return drop(RateLimit.Reason.Session, q)
    end

    if self.LastSeq ~= nil and q <= self.LastSeq then
        return drop(RateLimit.Reason.Order, q)
    end

    self.LastSeq = q
    local accepted = self.Window:Admit(now, n)
    return {
        Status = RateLimit.Result.Ok,
        Requested = math.floor(n),
        Accepted = accepted,
        Seq = q,
        Clamped = accepted < math.floor(n),
    }
end

return RateLimit

-- #149 T28 全服纪录。失败方式（先列后写）：
--   1. 重量两位小数被截成整数或写成浮点，放大/还原不对称，误差随写入放大；
--   2. 更小的重量覆盖了更大纪录；同重量两次请求按到达顺序抖动，跨服竞态下谁保持不确定；
--   3. 重量与保持者错配：重量更新了名字还是旧的，或纪录只有重量没有身份；
--   4. 盲盒/抽奖解锁一条鱼也提交纪录；
--   5. 平台失败/限流时把「读不到」当成「没有纪录」，或显示上一次的错值冒充当前值；
--   6. 延迟重试把过期候选盖到更新的纪录上；写频随上岸次数线性增长。
-- seam：common/Records 纯逻辑 + MgrRecords 公共接口（注入内存假适配器替换平台边界）+ 客户端数据通道。
local lu = require('luaunit')
local GameCfg = require('common.GameCfg')
local Records = require('common.Records')
local PlayerData = require('server.Data.PlayerData')

TestRecordsCore = {}

-- 重量 → 整数：定标因子 100（两位小数），读出还原后与写入值逐位相等
function TestRecordsCore:test_weight_scales_to_integer_and_round_trips()
    -- 期望值取自「两位小数放大 100 倍」的定义，与实现写法无关
    for _, pair in ipairs({ { 0.01, 1 }, { 0.2, 20 }, { 0.12, 12 }, { 1, 100 }, { 0.5, 50 },
        { 12.34, 1234 }, { 99.99, 9999 }, { 1234.56, 123456 } }) do
        lu.assertEquals(Records.Scale(pair[1]), pair[2], '重量 ' .. tostring(pair[1]))
        lu.assertEquals(Records.Unscale(pair[2]), pair[1], '还原必须与写入一致')
    end
    lu.assertEquals(GameCfg.Records.Scale, 100)
    -- 两位小数是存储精度上限：第三位不参与存储，不产生「读回比写入更精确」的假象
    lu.assertEquals(Records.Scale(0.125), 13)
end

-- 非法值不猜：非数字、非正、NaN、无穷与超越上限都拒绝，绝不四舍五入成假纪录
function TestRecordsCore:test_illegal_and_overflow_weights_are_rejected()
    for _, bad in ipairs({ nil, 'x', {}, true, 0, -1, 0 / 0, math.huge, -math.huge }) do
        local scaled, reason = Records.Scale(bad)
        lu.assertNil(scaled, tostring(bad))
        lu.assertEquals(reason, 'invalid', tostring(bad))
    end
    local over = GameCfg.Records.MaxScaled / GameCfg.Records.Scale + 1
    lu.assertNil(Records.Scale(over))
    lu.assertEquals(select(2, Records.Scale(over)), 'overflow')
end

-- 决胜：更大者胜；同重量按 UserID 升序（小者保持）；与到达顺序无关
function TestRecordsCore:test_heavier_wins_and_lighter_never_overwrites()
    local held = Records.Entry(200, 7, '甲')
    lu.assertTrue(Records.Wins(Records.Entry(201, 9, '乙'), held))
    lu.assertFalse(Records.Wins(Records.Entry(199, 1, '丙'), held))
    lu.assertFalse(Records.Wins(Records.Entry(200, 7, '甲'), held))
    lu.assertTrue(Records.Wins(Records.Entry(200, 7, '甲'), nil))
    lu.assertTrue(Records.Wins(Records.Entry(200, 7, '甲'), { w = 'x' }))
end

function TestRecordsCore:test_equal_weight_tiebreak_is_order_independent()
    local a = Records.Entry(300, 5, '甲')
    local b = Records.Entry(300, 3, '乙')
    local first = Records.Wins(a, nil) and a or nil
    if Records.Wins(b, first) then first = b end
    local second = Records.Wins(b, nil) and b or nil
    if Records.Wins(a, second) then second = a end
    lu.assertEquals(first.u, 3, '先到 5 后到 3 与先到 3 后到 5 结果必须一致')
    lu.assertEquals(first, second)
    lu.assertEquals(first.n, '乙')
end

-- 身份与重量写在同一条记录里：读回时要么两者都在，要么整条不算纪录
function TestRecordsCore:test_entry_keeps_weight_and_holder_together()
    local entry = Records.Entry(1234, 42, '张三')
    lu.assertEquals(entry, { w = 1234, u = 42, n = '张三' })
    lu.assertNil(Records.Valid({ w = 1234 }))
    lu.assertNil(Records.Valid({ u = 42, n = '张三' }))
    lu.assertNil(Records.Valid({ w = 1234, u = '42' }))
    lu.assertNil(Records.Valid('1234'))
    -- 名字超长只降级名字（退兜底），不整条丢掉重量与身份
    local longName = Records.Valid({ w = 1234, u = 42, n = string.rep('x', 200) })
    lu.assertEquals(longName, { w = 1234, u = 42, n = nil })
    local nameless = Records.Valid({ w = 1234, u = 42 })
    lu.assertEquals(nameless.n, nil)
    lu.assertEquals(Records.Holder(nameless), '玩家42', '显示名缺失退成玩家ID，不拿 ID 冒充名字')
    lu.assertEquals(Records.Holder(Records.Entry(1234, 42, '张三')), '张三')
end

-- 文案：有纪录/暂无/暂不可用三态分开，不可用不等于没有纪录
function TestRecordsCore:test_state_and_text_never_fabricate_a_record()
    local ok = Records.State(Records.Entry(1234, 42, '张三'))
    lu.assertEquals(ok.state, 'ok')
    lu.assertEquals(ok.weight, 12.34)
    lu.assertEquals(Records.Describe(ok), '全服纪录：12.34 kg（张三）')
    lu.assertEquals(Records.State(nil), { state = 'missing' })
    lu.assertEquals(Records.Describe({ state = 'missing' }), '全服纪录：暂无')
    lu.assertEquals(Records.Describe({ state = 'unavailable' }), '全服纪录：暂不可用')
    lu.assertEquals(Records.Describe(nil), '全服纪录：暂不可用', '未知状态按不可用展示，不当作暂无')
end

-- 服务层：真实 MgrRecords，只替换平台适配器（内存假实现，能表达超时/限流/不可用）
TestRecordsService = {}

local function readSource(path)
    local file = io.open(path, 'r')
    if not file then return nil end
    local text = file:read('*a')
    file:close()
    return text
end

function TestRecordsService:setUp()
    self.oldGame = _G.game
    self.oldREUtil = _G.REUtil
    self.clock, self.queue = 100, {}
    self.store, self.calls, self.writes, self.readCalls = {}, 0, 0, 0
    self.readFail, self.writeFail, self.writeFailRounds = nil, nil, 0
    local env = self
    self.adapter = {
        Read = function(_, fishId)
            env.readCalls = env.readCalls + 1
            if env.readFail then return false, nil, env.readFail end
            return true, env.store[fishId], nil
        end,
        -- 假适配器的 CAS 语义与真实适配器一致：decide(current) 返回 nil 就一个字节都不写
        Submit = function(_, fishId, decide)
            env.calls = env.calls + 1
            if env.writeFailRounds > 0 then
                env.writeFailRounds = env.writeFailRounds - 1
                return false, nil, env.writeFail or 'unavailable'
            end
            local next_ = decide(env.store[fishId])
            if not next_ then return true, false, env.store[fishId], nil end
            env.store[fishId] = next_
            env.writes = env.writes + 1
            return true, true, next_, nil
        end,
    }
    _G.game = { GetService = function(_, name)
        if name == 'Task' then return { Spawn = function(_, fn) env.queue[#env.queue + 1] = fn end,
            Wait = function() end } end
        if name == 'World' then return { GetServerTime = function() return env.clock end } end
        if name == 'Players' then return { GetPlayers = function() return {} end } end
        if name == 'DataStoreService' then return { GetDataStore = function() return {} end } end
    end }
    self.mgr = assert(loadfile('server/Mgr/MgrRecords.lua'))()
    self.mgr.Adapter = self.adapter
end

function TestRecordsService:tearDown()
    _G.game, _G.REUtil = self.oldGame, self.oldREUtil
end

function TestRecordsService:drain()
    while #self.queue > 0 do table.remove(self.queue, 1)() end
end

function TestRecordsService:advance(seconds)
    self.clock = self.clock + seconds
    self.mgr:Update()
end

function TestRecordsService:player(userId, name) return { UserId = userId, Name = name } end

function TestRecordsService:test_heavier_landing_updates_record_with_holder_pair()
    lu.assertTrue(self.mgr:NoteLanding(self:player(7, '甲'), 'goldfish', 0.25))
    lu.assertEquals(self.calls, 0, '合并窗口内不发写请求')
    self:advance(GameCfg.Records.FlushIntervalSec)
    self:drain()
    -- 重量与保持者同一条记录、同一次写入
    lu.assertEquals(self.store.goldfish, { w = 25, u = 7, n = '甲' })
    local state = self.mgr:State('goldfish')
    lu.assertEquals(state.state, 'ok')
    lu.assertEquals(state.scaled, 25)
    lu.assertEquals(state.weight, 0.25)
    lu.assertEquals(state.userId, 7)
    lu.assertEquals(state.holder, '甲')
    lu.assertEquals(state.stale, false)
end

function TestRecordsService:test_lighter_landing_never_overwrites_and_costs_no_write()
    self.store.goldfish = { w = 25, u = 7, n = '甲' }
    self.mgr:Read('goldfish', function() end)
    self:drain()
    self.calls, self.writes = 0, 0
    lu.assertTrue(self.mgr:NoteLanding(self:player(9, '乙'), 'goldfish', 0.2))
    self:advance(GameCfg.Records.FlushIntervalSec)
    self:drain()
    lu.assertEquals(self.store.goldfish, { w = 25, u = 7, n = '甲' })
    lu.assertEquals(self.calls, 0, '已知现有纪录更大时一个写请求都不发')
end

function TestRecordsService:test_equal_weight_keeps_smaller_user_id_whatever_the_order()
    self.store.goldfish = { w = 25, u = 7, n = '甲' }
    self.mgr:Read('goldfish', function() end)
    self:drain()
    -- 同重量、UserID 更大：不换人
    self.mgr:NoteLanding(self:player(9, '乙'), 'goldfish', 0.25)
    self:advance(GameCfg.Records.FlushIntervalSec)
    self:drain()
    lu.assertEquals(self.store.goldfish, { w = 25, u = 7, n = '甲' })
    -- 同重量、UserID 更小：换人（规则与到达顺序无关）
    self.store.goldfish = { w = 25, u = 7, n = '甲' }
    self.mgr:NoteLanding(self:player(3, '丙'), 'goldfish', 0.25)
    self:advance(GameCfg.Records.FlushIntervalSec * 2)
    self:drain()
    lu.assertEquals(self.store.goldfish, { w = 25, u = 3, n = '丙' })
    lu.assertEquals(self.mgr:State('goldfish').holder, '丙')
end

function TestRecordsService:test_landings_inside_one_window_merge_into_a_single_write()
    for index = 1, 20 do
        self.mgr:NoteLanding(self:player(index, 'P' .. index), 'carp', 0.01 * index)
    end
    lu.assertEquals(self.calls, 0)
    self:advance(GameCfg.Records.FlushIntervalSec)
    self:drain()
    lu.assertEquals(self.calls, 1, '一个窗口内同鱼种只发一次写')
    lu.assertEquals(self.store.carp, { w = 20, u = 20, n = 'P20' }, '窗口内只保留最大候选')
    self:drain()
    lu.assertEquals(self.calls, 1)
end

function TestRecordsService:test_invalid_or_overflowing_weight_is_never_submitted()
    lu.assertFalse(self.mgr:NoteLanding(self:player(7, '甲'), 'goldfish', 0))
    lu.assertFalse(self.mgr:NoteLanding(self:player(7, '甲'), 'goldfish', 'x'))
    lu.assertFalse(self.mgr:NoteLanding(self:player(7, '甲'), 'noSuchFish', 1))
    lu.assertFalse(self.mgr:NoteLanding(nil, 'goldfish', 1))
    local _, reason = self.mgr:NoteLanding(self:player(7, '甲'), 'goldfish',
        GameCfg.Records.MaxScaled / GameCfg.Records.Scale + 1)
    lu.assertEquals(reason, 'overflow')
    self:advance(GameCfg.Records.FlushIntervalSec * 2)
    self:drain()
    lu.assertEquals(self.calls, 0)
    lu.assertEquals(self.store, {})
    lu.assertEquals(self.mgr.Stats.Rejected, 5)
end

function TestRecordsService:test_delayed_retry_never_overwrites_a_newer_record()
    self.writeFail, self.writeFailRounds = 'timeout', 1
    self.mgr:NoteLanding(self:player(7, '甲'), 'bass', 0.5)
    self:advance(GameCfg.Records.FlushIntervalSec)
    self:drain()
    lu.assertNil(self.store.bass, '第一次写超时，什么都没落地')
    lu.assertEquals(self.mgr.Stats.Failures, 1)
    lu.assertEquals(self.mgr.Stats.Retries, 1)
    -- 退避等待期间，别的服务器已经把纪录换成更大的（跨服竞态）
    self.store.bass = { w = 90, u = 3, n = '丙' }
    lu.assertEquals(self.mgr.Pending.bass.attempts, 1)
    self:advance(GameCfg.Records.RetryDelaySec)
    self:drain()
    lu.assertEquals(self.store.bass, { w = 90, u = 3, n = '丙' }, '过期候选不许盖掉更新的纪录')
    lu.assertNil(self.mgr.Pending.bass, '过期候选重试后丢弃，不再占写频')
    lu.assertEquals(self.writes, 0)
end

function TestRecordsService:test_retry_exhaustion_drops_the_candidate_and_logs()
    self.writeFail, self.writeFailRounds = 'throttled', 99
    self.mgr:NoteLanding(self:player(7, '甲'), 'bass', 0.5)
    for _ = 1, GameCfg.Records.MaxRetries + 2 do
        self:advance(GameCfg.Records.FlushIntervalSec + GameCfg.Records.RetryDelaySec)
        self:drain()
    end
    lu.assertNil(self.mgr.Pending.bass)
    lu.assertEquals(self.mgr.Stats.Dropped, 1)
    lu.assertEquals(self.store, {}, '一直失败也不许写假值')
end

-- 读失败：如实说「暂不可用」，不许说成「暂无纪录」，也不许显示数字
function TestRecordsService:test_failed_read_is_unavailable_not_missing()
    local seen
    self.mgr:Read('goldfish', function(state) seen = state end)
    self:drain()
    lu.assertEquals(seen.state, 'missing', '服务可用、只是这条鱼还没纪录')
    self.readFail = 'throttled'
    self:advance(GameCfg.Records.MissCacheTtlSec + 1)
    self.mgr:Read('goldfish', function(state) seen = state end)
    self:drain()
    lu.assertEquals(seen.state, 'unavailable')
    lu.assertNil(seen.scaled)
    lu.assertEquals(seen.error, 'throttled')
    lu.assertEquals(Records.Describe(seen), '全服纪录：暂不可用')
    -- 负缓存：短时间内重复请求不再打平台
    local calls = self.readCalls
    self.mgr:Read('goldfish', function(state) seen = state end)
    self:drain()
    lu.assertEquals(self.readCalls, calls)
    lu.assertEquals(seen.state, 'unavailable')
end

-- 冷启动（还没读过）也按「暂不可用」，绝不当作「暂无纪录」
function TestRecordsService:test_state_before_any_read_is_unavailable()
    lu.assertEquals(self.mgr:State('goldfish').state, 'unavailable')
    lu.assertEquals(Records.Describe(self.mgr:State('goldfish')), '全服纪录：暂不可用')
end

-- 读失败不许抹掉上一次可信值：照旧值展示并标 stale
function TestRecordsService:test_read_failure_keeps_last_known_value_and_marks_it_stale()
    self.store.goldfish = { w = 25, u = 7, n = '甲' }
    local seen
    self.mgr:Read('goldfish', function(state) seen = state end)
    self:drain()
    lu.assertEquals(seen.state, 'ok')
    lu.assertEquals(seen.stale, false)
    self.readFail = 'timeout'
    self:advance(GameCfg.Records.HolderCacheTtlSec + 1)
    self.mgr:Read('goldfish', function(state) seen = state end)
    self:drain()
    lu.assertEquals(seen.state, 'ok')
    lu.assertEquals(seen.weight, 0.25, '平台读不到时沿用上一次真实值，不编新值')
    lu.assertEquals(seen.holder, '甲')
    lu.assertTrue(seen.stale)
    lu.assertEquals(seen.error, nil)
end

-- 同一鱼种的并发读合并成一次平台调用（打开图鉴时几十条一起要）
function TestRecordsService:test_concurrent_reads_share_one_platform_call()
    local first, second
    self.mgr:Read('goldfish', function(state) first = state end)
    self.mgr:Read('goldfish', function(state) second = state end)
    lu.assertEquals(self.readCalls, 0, '还没进平台调用')
    self:drain()
    lu.assertEquals(self.readCalls, 1)
    lu.assertEquals(first.state, 'missing')
    lu.assertEquals(second, first)
end

-- 坏数据（缺重量或缺身份）不展示：当作这条还没有纪录，而不是拼一个半截纪录出来
function TestRecordsService:test_corrupt_stored_value_is_never_shown()
    local adapter = assert(loadfile('server/Data/RecordsAdapter.lua'))()
    local values = { corrupt = { w = 25 }, nameless = { u = 7, n = '甲' }, ok = { w = 25, u = 7, n = '甲' } }
    local function field(key) return values[key:sub(5)] end
    local platform = {
        GetAsync = function(_, key) return field(key) end,
        UpdateAsync = function(_, key, transform)
            local value = transform(field(key))
            if value then values[key:sub(5)] = value end
            return value
        end,
    }
    _G.game = { GetService = function(_, name)
        if name == 'DataStoreService' then return { GetDataStore = function() return platform end } end
        if name == 'World' then return { GetServerTime = function() return 100 end } end
    end }
    local ok, entry = adapter:Read('corrupt')
    lu.assertTrue(ok, '读成功但值不可信')
    lu.assertNil(entry, '只有重量的半截记录不算纪录')
    lu.assertNil(select(2, adapter:Read('nameless')), '缺重量的记录不算纪录')
    lu.assertEquals(select(2, adapter:Read('ok')), { w = 25, u = 7, n = '甲' })
end

-- 适配器把平台异常翻译成稳定类别，调用方不依赖错误码文本
function TestRecordsService:test_adapter_classifies_platform_failures()
    local adapter = assert(loadfile('server/Data/RecordsAdapter.lua'))()
    local failure
    local platform = { GetAsync = function() error(failure) end }
    _G.game = { GetService = function(_, name)
        if name == 'DataStoreService' then return { GetDataStore = function() return platform end } end
    end }
    for _, pair in ipairs({ { 'Request was throttled', 'throttled' },
        { 'request limit reached', 'throttled' }, { 'connection timed out', 'timeout' },
        { 'some new platform text', 'unknown' } }) do
        failure = pair[1]
        lu.assertEquals(select(3, adapter:Read('goldfish')), pair[2], pair[1])
    end
    _G.game = { GetService = function() error('no DataStoreService') end }
    adapter.Checked, adapter.Holder = nil, nil
    lu.assertEquals(select(3, adapter:Read('goldfish')), 'unavailable')
end

-- 端到端：真实 MgrCompendium（上岸入账）+ 真实 MgrRecords + 真实 MgrSave，只换平台适配器
TestRecordsIntegration = {}

function TestRecordsIntegration:setUp()
    self.oldGame, self.oldREUtil = _G.game, _G.REUtil
    self.values, self.queue, self.datas, self.sent = {}, {}, {}, {}
    self.clock, self.records, self.calls, self.pending = 100, {}, 0, {}
    self.recordsFail, self.cooldowns = false, {}
    local env = self
    self.store = {
        GetAsync = function(_, key) return env.values[key] end,
        UpdateAsync = function(_, key, transform)
            local value = transform(env.values[key])
            if value then env.values[key] = value end
            return value
        end,
        SetAsync = function(_, key, value) env.values[key] = value end,
    }
    self.adapter = {
        Read = function(_, fishId)
            if env.recordsFail then return false, nil, 'unavailable' end
            return true, env.records[fishId], nil
        end,
        Submit = function(_, fishId, decide)
            env.calls = env.calls + 1
            if env.recordsFail then return false, nil, nil, 'unavailable' end
            local next_ = decide(env.records[fishId])
            if not next_ then return true, false, env.records[fishId], nil end
            env.records[fishId] = next_
            return true, true, next_, nil
        end,
    }
    _G.game = { GetService = function(_, name)
        if name == 'Task' then return { Spawn = function(_, fn) env.queue[#env.queue + 1] = fn end,
            Wait = function() end } end
        if name == 'DataStoreService' then return { GetDataStore = function() return env.store end } end
        if name == 'World' then return { GetServerTime = function() return env.clock end } end
        if name == 'Players' then return { GetPlayers = function() return {} end } end
    end }
    _G.REUtil = {
        GetRE = function(_, name)
            local event = env.pending[name]
            if not event then
                event = { Server = {}, Client = {} }
                event.OnServerEvent = { Connect = function(_, fn) event.Server[#event.Server + 1] = fn end }
                event.OnClientEvent = { Connect = function(_, fn) event.Client[#event.Client + 1] = fn end }
                event.FireServer = function(_, player, payload)
                    for _, fn in ipairs(event.Server) do fn(player, payload) end
                end
                event.FireClient = function(_, player, payload)
                    env.sent[#env.sent + 1] = { name = name, player = player, payload = payload }
                end
                env.pending[name] = event
            end
            return event
        end,
        CheckRECD = function(_, _, name, duration)
            local until_ = env.cooldowns and env.cooldowns[name]
            if until_ and until_ > env.clock then return true end
            env.cooldowns = env.cooldowns or {}
            env.cooldowns[name] = env.clock + (duration or 1)
            return false
        end,
    }
    self.save = assert(loadfile('server/Mgr/MgrSave.lua'))()
    self.comp = assert(loadfile('server/Mgr/MgrCompendium.lua'))()
    self.rec = assert(loadfile('server/Mgr/MgrRecords.lua'))()
    self.rec.Adapter = self.adapter
    self.comp.Save = self.save
    self.comp.Records = self.rec
    self.datas = {}
    local accessor = { GetDataInst = function(_, player) return env.datas[player.UserId] end }
    self.comp.PlayerData, self.rec.PlayerData = accessor, accessor
    self.rec:Start()
end

function TestRecordsIntegration:tearDown()
    _G.game, _G.REUtil = self.oldGame, self.oldREUtil
end

function TestRecordsIntegration:drain()
    while #self.queue > 0 do table.remove(self.queue, 1)() end
end

function TestRecordsIntegration:join(id, name)
    local player = { UserId = id, Name = name, SetAttribute = function() end }
    local data = PlayerData.New(player)
    data:Init(true)
    self.datas[id] = data
    self.save:LoadInto(player, data)
    self:drain()
    return player, data
end

function TestRecordsIntegration:window()
    self.clock = self.clock + GameCfg.Records.FlushIntervalSec
    self.rec:Update()
    self:drain()
end

-- 只有刷新了个人最大重量的上岸才提交，且窗口合并后才真的写
function TestRecordsIntegration:test_only_a_landing_that_improves_the_personal_best_submits()
    local player = self:join(30, '甲')
    self.comp:RecordLanding(player, { fishId = 'goldfish', mult = 2, reelSerial = 1 })
    self:drain()
    lu.assertEquals(self.calls, 0, '上岸只入队，等合并窗口')
    self:window()
    lu.assertEquals(self.records.goldfish, { w = 20, u = 30, n = '甲' })
    -- 第二次上岸更小：不刷新个人纪录，也就不提交
    self.comp:RecordLanding(player, { fishId = 'goldfish', mult = 1.15, reelSerial = 2 })
    self:drain()
    self:window()
    lu.assertEquals(self.records.goldfish, { w = 20, u = 30, n = '甲' })
    lu.assertEquals(self.calls, 1, '没刷新个人纪录就不提交')
end

-- 盲盒/击杀/掉落没有进纪录的写通道：唯一入口是「上岸」
function TestRecordsIntegration:test_blindbox_and_kills_have_no_write_path_into_records()
    local player = self:join(31, '甲')
    player.Name = '甲'
    self.datas[31].Extra.lottery.pity = 3
    self.comp:RecordLanding(player, { fishId = 'carp', mult = 1, reelSerial = 1 })
    self:drain()
    self:window()
    lu.assertEquals(self.records.carp, { w = 500, u = 31, n = '甲' })
    self.calls = 0
    -- 盲盒解锁只动 extra.lottery（图鉴条目与纪录都不碰）
    self.datas[31].Extra.lottery.lastUnlock = 'goldfish'
    self.rec:Update()
    self:drain()
    lu.assertEquals(self.calls, 0)
    lu.assertNil(self.records.goldfish)
    -- 源码级：只有上岸入账调用 NoteLanding，击杀/掉落/商店都不引用纪录
    local callers = {}
    for _, path in ipairs({ 'server/Mgr/MgrCompendium.lua', 'server/Mgr/MgrLoot.lua',
        'server/Mgr/MgrShop.lua', 'server/Mgr/MgrFishUnit.lua' }) do
        local source = readSource(path)
        lu.assertNotNil(source, path)
        if source:find('NoteLanding', 1, true) then callers[#callers + 1] = path end
    end
    lu.assertEquals(callers, { 'server/Mgr/MgrCompendium.lua' })
end

-- 平台不可用：个人图鉴照常记账，纪录一律报「暂不可用」，不显示伪纪录
function TestRecordsIntegration:test_platform_failure_keeps_personal_compendium_and_shows_no_fake_record()
    local player = self:join(32, '乙')
    self.recordsFail = true
    self.comp:RecordLanding(player, { fishId = 'goldfish', mult = 2, reelSerial = 1 })
    self:drain()
    local view = self.comp:Snapshot(player)
    lu.assertEquals(view.weights.goldfish, 0.2, '个人最大重量照常入账')
    lu.assertEquals(view.catches.goldfish, 1)
    for _ = 1, GameCfg.Records.MaxRetries + 2 do
        self.clock = self.clock + GameCfg.Records.FlushIntervalSec + GameCfg.Records.RetryDelaySec
        self.rec:Update()
        self:drain()
    end
    lu.assertEquals(self.records, {}, '平台失败一个字节都不写')
    local seen
    self.rec:Read('goldfish', function(state) seen = state end)
    self:drain()
    lu.assertEquals(seen.state, 'unavailable')
    lu.assertEquals(Records.Describe(seen), '全服纪录：暂不可用')
    lu.assertNil(seen.scaled)
    -- 个人图鉴的快照不掺全服纪录字段，读不到纪录也不会污染个人数据
    lu.assertEquals(view.total, 1)
end

-- 图鉴查询：只认服务端读到的状态，序号重放不重复回包
function TestRecordsIntegration:test_client_query_replies_with_server_truth()
    local player = self:join(33, '丙')
    self.records.goldfish = { w = 25, u = 7, n = '甲' }
    local request = _G.REUtil:GetRE('RecordsRequest')
    request.FireServer(request, player, { fishId = 'goldfish', seq = 1 })
    self:drain()
    lu.assertEquals(#self.sent, 1)
    lu.assertEquals(self.sent[1].name, 'RecordsState')
    lu.assertEquals(self.sent[1].player, player)
    lu.assertEquals(self.sent[1].payload.state, 'ok')
    lu.assertEquals(self.sent[1].payload.weight, 0.25)
    lu.assertEquals(self.sent[1].payload.holder, '甲')
    lu.assertEquals(self.sent[1].payload.seq, 1)
    -- 同序号重放：不再回包
    self.clock = self.clock + 1
    request.FireServer(request, player, { fishId = 'goldfish', seq = 1 })
    self:drain()
    lu.assertEquals(#self.sent, 1)
    -- 新序号：回包
    self.clock = self.clock + 1
    request.FireServer(request, player, { fishId = 'bass', seq = 2 })
    self:drain()
    lu.assertEquals(#self.sent, 2)
    lu.assertEquals(self.sent[2].payload.state, 'missing')
end

-- 对账：个人最大重量高于全服纪录（上次提交被平台丢掉）时补交，且只补更高的
function TestRecordsIntegration:test_query_reconciles_a_dropped_submission()
    local player, data = self:join(34, '丁')
    data.Extra.collection.weights.goldfish = 0.5
    self.records.goldfish = { w = 20, u = 9, n = '乙' }
    local request = _G.REUtil:GetRE('RecordsRequest')
    request.FireServer(request, player, { fishId = 'goldfish', seq = 1 })
    self:drain()
    lu.assertEquals(self.sent[1].payload.weight, 0.2, '先回当前真实纪录（补交还没落地）')
    self:window()
    lu.assertEquals(self.records.goldfish, { w = 50, u = 34, n = '丁' })
    -- 个人纪录不高于全服纪录：不补交、不写
    self.clock = self.clock + 1
    self.calls = 0
    data.Extra.collection.weights.bass = 0.2
    self.records.bass = { w = 500, u = 9, n = '乙' }
    request.FireServer(request, player, { fishId = 'bass', seq = 2 })
    self:drain()
    self:window()
    lu.assertEquals(self.records.bass, { w = 500, u = 9, n = '乙' })
    lu.assertEquals(self.calls, 0)
end

-- 平台读不到时不补交：连当前纪录都不知道，不猜、不写
function TestRecordsIntegration:test_no_reconcile_while_the_platform_is_unreadable()
    local player, data = self:join(35, '戊')
    data.Extra.collection.weights.goldfish = 0.5
    self.recordsFail = true
    local request = _G.REUtil:GetRE('RecordsRequest')
    request.FireServer(request, player, { fishId = 'goldfish', seq = 1 })
    self:drain()
    lu.assertEquals(self.sent[1].payload.state, 'unavailable')
    self.clock = self.clock + GameCfg.Records.FlushIntervalSec * 2
    self.rec:Update()
    self:drain()
    lu.assertEquals(self.calls, 0, '读不到当前纪录就不补交')
end

-- 个人最大重量的整数化读数（PlayerData 侧只加读数，不改 #133 的存储语义）
function TestRecordsIntegration:test_personal_best_scaled_reads_the_collection_weight()
    local _, data = self:join(36, '己')
    lu.assertNil(data:PersonalBestScaled('goldfish'))
    data.Extra.collection.weights.goldfish = 0.12
    lu.assertEquals(data:PersonalBestScaled('goldfish'), 12)
    lu.assertNil(data:PersonalBestScaled(nil))
    lu.assertNil(data:PersonalBestScaled(1))
end

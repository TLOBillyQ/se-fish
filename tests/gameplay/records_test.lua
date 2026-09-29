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

-- #138 T17 抽奖机纯逻辑（common/LotteryDraw）失败方式先列：
--   1. 权重表错位：单轴抽样区间与原表 22/20/18/16/14/5/5 不符（含边界值落错图案）；
--   2. 三轴不独立：一次抽样复用给三轴，或三轴共用同一 RNG 序列段；
--   3. 两同倍数错位：用了别图案的倍数，或「恰两同」判成「至少两同」（三同也发金币）；
--   4. 三同不优先：三同被两同分支抢走大奖；
--   5. 武器组五选一的组内随机越界或拿错组；
--   6. 静态期望漂移：权重/倍数改动后两同金币期望偏离原表 2.119671。
-- seam：common.LotteryDraw 的 RollAxis / RollAxes / Evaluate / ChooseWeapon，注入确定性 RNG（系统边界：随机数）。
local lu = require('luaunit')
local GameCfg = require('common.GameCfg')
local Draw = require('common.LotteryDraw')

TestLotteryDraw = {}

-- 逐项钉表（原表「渔力全开--抽奖表.xlsx」R3..R9）：权重与两同倍数是独立真源字面量
local EXPECTED = {
    { name = '鳄雀鳝', weight = 22, pairMultiplier = 2 },
    { name = '小白龙', weight = 20, pairMultiplier = 3 },
    { name = '蟹老板', weight = 18, pairMultiplier = 5 },
    { name = '三头鲨', weight = 16, pairMultiplier = 7 },
    { name = '虎鲸', weight = 14, pairMultiplier = 10 },
    { name = '风神翼龙', weight = 5, pairMultiplier = 15 },
    { name = '哥斯拉', weight = 5, pairMultiplier = 20 },
}

function TestLotteryDraw:test_weights_and_pair_multipliers_match_source_table()
    local patterns = GameCfg.Lottery.Patterns
    lu.assertEquals(#patterns, 7)
    for index, expected in ipairs(EXPECTED) do
        local pattern = patterns[index]
        lu.assertEquals(pattern.number, index)
        lu.assertEquals(pattern.name, expected.name)
        lu.assertEquals(pattern.weight, expected.weight)
        lu.assertEquals(pattern.pairMultiplier, expected.pairMultiplier)
    end
end

-- 静态期望（原表合计行 R10「返奖倍率」2.119671）：恰两同概率 3·p²·(1−p) 乘对应倍数之和。
-- 期望字面量来自原表，公式来自 GameSpec §14「恰好两同」，两者都不是实现代码。
function TestLotteryDraw:test_static_pair_expectation_matches_source_table()
    local expectation = 0
    for _, pattern in ipairs(GameCfg.Lottery.Patterns) do
        local p = pattern.weight / 100
        expectation = expectation + 3 * p * p * (1 - p) * pattern.pairMultiplier
    end
    lu.assertAlmostEquals(expectation, 2.119671, 1e-9)
end

-- 单轴区间边界：roll 取 1..100 均匀整数，累计权重划区间（1..22→鳄雀鳝，23..42→小白龙，…，96..100→哥斯拉）
function TestLotteryDraw:test_roll_axis_hits_weight_interval_boundaries()
    local bounds = { { 1, 22, 1 }, { 23, 42, 2 }, { 43, 60, 3 }, { 61, 76, 4 },
        { 77, 90, 5 }, { 91, 95, 6 }, { 96, 100, 7 } }
    for _, bound in ipairs(bounds) do
        local lo, hi, number = bound[1], bound[2], bound[3]
        lu.assertEquals(Draw.RollAxis(function() return lo end), number, '下界 ' .. lo)
        lu.assertEquals(Draw.RollAxis(function() return hi end), number, '上界 ' .. hi)
    end
end

function TestLotteryDraw:test_roll_axes_samples_three_times_independently()
    local rolls = { 1, 43, 96 } -- 鳄雀鳝 / 蟹老板 / 哥斯拉
    local index = 0
    local axes = Draw.RollAxes(function()
        index = index + 1
        return rolls[index]
    end)
    lu.assertEquals(index, 3)
    lu.assertEquals(axes, { 1, 3, 7 })
end

function TestLotteryDraw:test_evaluate_triple_first_then_exactly_two()
    lu.assertEquals(Draw.Evaluate({ 4, 4, 4 }), { outcome = 'triple', pattern = 4 })
    -- 恰两同：三种位置组合都是两同，图案取相同那一对
    lu.assertEquals(Draw.Evaluate({ 2, 2, 5 }), { outcome = 'pair', pattern = 2 })
    lu.assertEquals(Draw.Evaluate({ 5, 2, 2 }), { outcome = 'pair', pattern = 2 })
    lu.assertEquals(Draw.Evaluate({ 2, 5, 2 }), { outcome = 'pair', pattern = 2 })
    lu.assertEquals(Draw.Evaluate({ 1, 2, 3 }), { outcome = 'none' })
end

function TestLotteryDraw:test_choose_weapon_picks_uniformly_within_the_group()
    local pattern1 = GameCfg.Lottery.Patterns[1]
    for index, itemKey in ipairs(pattern1.tripleReward.itemKeys) do
        lu.assertEquals(Draw.ChooseWeapon(pattern1, function() return index end), itemKey)
    end
    -- 非武器组（加速药水）没有组内选择
    lu.assertNil(Draw.ChooseWeapon(GameCfg.Lottery.Patterns[4], function() return 1 end))
end

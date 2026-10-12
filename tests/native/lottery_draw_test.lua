-- 原生 Busted（#87 迁移自 tests/gameplay/lottery_draw_test.lua 的 TestLotteryDraw）。
-- #138 T17 抽奖机纯逻辑（common/LotteryDraw）失败方式先列：
--   1. 权重表错位：单轴抽样区间与原表 22/20/18/16/14/5/5 不符（含边界值落错图案）；
--   2. 三轴不独立：一次抽样复用给三轴，或三轴共用同一 RNG 序列段；
--   3. 两同倍数错位：用了别图案的倍数，或「恰两同」判成「至少两同」（三同也发金币）；
--   4. 三同不优先：三同被两同分支抢走大奖；
--   5. 武器组五选一的组内随机越界或拿错组；
--   6. 静态期望漂移：权重/倍数改动后两同金币期望偏离原表 2.119671。
-- seam：common.LotteryDraw 的 RollAxis / RollAxes / Evaluate / ChooseWeapon，注入确定性 RNG（系统边界：随机数）。
-- 迁移说明：案例按旧 LuaUnit 实际执行序（方法名字典序）逐个 it 注册；
--   唯一的 assertAlmostEquals(实际, 期望, 容差) 映射为 assert.near(期望, 实际, 容差)。
local GameCfg = require("common.GameCfg")
local Draw = require("common.LotteryDraw")
local RandomGuard = require("tests.support.random_guard")

-- 逐项钉表（原表「渔力全开--抽奖表.xlsx」R3..R9）：权重与两同倍数是独立真源字面量
local EXPECTED = {
  { name = "鳄雀鳝", weight = 22, pairMultiplier = 2 },
  { name = "小白龙", weight = 20, pairMultiplier = 3 },
  { name = "蟹老板", weight = 18, pairMultiplier = 5 },
  { name = "三头鲨", weight = 16, pairMultiplier = 7 },
  { name = "虎鲸", weight = 14, pairMultiplier = 10 },
  { name = "风神翼龙", weight = 5, pairMultiplier = 15 },
  { name = "哥斯拉", weight = 5, pairMultiplier = 20 },
}

describe("抽奖机纯逻辑（common/LotteryDraw）", function()
  -- 随机数全部经参数注入；逐案例还原全局 math.random，杜绝替换泄漏。
  after_each(RandomGuard.restore)

  it("test_choose_weapon_picks_uniformly_within_the_group", function()
    local pattern1 = GameCfg.Lottery.Patterns[1]
    for index, itemKey in ipairs(pattern1.tripleReward.itemKeys) do
      assert.same(itemKey, Draw.ChooseWeapon(pattern1, function()
        return index
      end))
    end
    -- 非武器组（加速药水）没有组内选择
    assert.is_nil(Draw.ChooseWeapon(GameCfg.Lottery.Patterns[4], function()
      return 1
    end))
  end)

  it("test_evaluate_triple_first_then_exactly_two", function()
    assert.same({ outcome = "triple", pattern = 4 }, Draw.Evaluate({ 4, 4, 4 }))
    -- 恰两同：三种位置组合都是两同，图案取相同那一对
    assert.same({ outcome = "pair", pattern = 2 }, Draw.Evaluate({ 2, 2, 5 }))
    assert.same({ outcome = "pair", pattern = 2 }, Draw.Evaluate({ 5, 2, 2 }))
    assert.same({ outcome = "pair", pattern = 2 }, Draw.Evaluate({ 2, 5, 2 }))
    assert.same({ outcome = "none" }, Draw.Evaluate({ 1, 2, 3 }))
  end)

  it("test_roll_axes_samples_three_times_independently", function()
    local rolls = { 1, 43, 96 } -- 鳄雀鳝 / 蟹老板 / 哥斯拉
    local index = 0
    local axes = Draw.RollAxes(function()
      index = index + 1
      return rolls[index]
    end)
    assert.same(3, index)
    assert.same({ 1, 3, 7 }, axes)
  end)

  it("test_roll_axis_hits_weight_interval_boundaries", function()
    -- 单轴区间边界：roll 取 1..100 均匀整数，累计权重划区间（1..22→鳄雀鳝，23..42→小白龙，…，96..100→哥斯拉）
    local bounds = {
      { 1, 22, 1 }, { 23, 42, 2 }, { 43, 60, 3 }, { 61, 76, 4 },
      { 77, 90, 5 }, { 91, 95, 6 }, { 96, 100, 7 },
    }
    for _, bound in ipairs(bounds) do
      local lo, hi, number = bound[1], bound[2], bound[3]
      assert.same(number, Draw.RollAxis(function()
        return lo
      end), "下界 " .. lo)
      assert.same(number, Draw.RollAxis(function()
        return hi
      end), "上界 " .. hi)
    end
  end)

  it("test_static_pair_expectation_matches_source_table", function()
    -- 静态期望（原表合计行 R10「返奖倍率」2.119671）：恰两同概率 3·p²·(1−p) 乘对应倍数之和。
    -- 期望字面量来自原表，公式来自 GameSpec §14「恰好两同」，两者都不是实现代码。
    local expectation = 0
    for _, pattern in ipairs(GameCfg.Lottery.Patterns) do
      local p = pattern.weight / 100
      expectation = expectation + 3 * p * p * (1 - p) * pattern.pairMultiplier
    end
    assert.near(2.119671, expectation, 1e-9)
  end)

  it("test_weights_and_pair_multipliers_match_source_table", function()
    local patterns = GameCfg.Lottery.Patterns
    assert.same(7, #patterns)
    for index, expected in ipairs(EXPECTED) do
      local pattern = patterns[index]
      assert.same(index, pattern.number)
      assert.same(expected.name, pattern.name)
      assert.same(expected.weight, pattern.weight)
      assert.same(expected.pairMultiplier, pattern.pairMultiplier)
    end
  end)
end)

-- 原生 Busted（#87 迁移自 tests/gameplay/blindbox_draw_test.lua 的 TestBlindboxDraw）。
-- #147 T26 盲盒抽样纯逻辑（common/BlindboxDraw.lua，GameSpec §15 与地图盲盒表）失败方式先列：
--   1. 权重区间错位：累计权重边界归属错（roll 恰等于累计值时归错项）、rng 越界/非数不拒绝；
--   2. 保底时机错：连续 48 次未中就触发保底，或 49 次未中的第 50 抽不保底；
--   3. 保底奖项错：保底出的不是极品美人鱼/极品蛇颈龙，或两件不等概率；
--   4. 大奖重置错：抽出大奖不清零连续未中计数，或未中大奖反而清零；
--   5. 十连逐抽错：十连中途出大奖后，余下的抽数仍沿用旧计数（应逐抽结算、立即重置）；
--   6. 倍率/价格口径错：结果带非 1 的个体倍率，或基础售价与地图盲盒表不符（钉表）。
-- seam：BlindboxDraw.Draw / DrawMany（纯函数）；随机数经 rng(n)（返回 1..n 均匀整数）注入，
--   脚本化序列锁定边界；配置真源是 common/cfg/Blindbox.lua（权重和 1000、期望 166.075 已有钉表）。
-- 迁移说明：案例按旧 LuaUnit 实际执行序（方法名字典序）逐个 it 注册；断言按语义映射，见 issue-87-mapping.md。
local BlindboxDraw = require("common.BlindboxDraw")
local BlindboxCfg = require("common.cfg.Blindbox")
local RandomGuard = require("tests.support.random_guard")

-- 脚本化 RNG：按队列逐个吐 roll（1..n），耗尽报错
local function scripted(rolls)
  local queue = {}
  for _, roll in ipairs(rolls) do
    queue[#queue + 1] = roll
  end
  return function()
    local roll = table.remove(queue, 1)
    assert(roll, "测试脚本 RNG 序列耗尽")
    return roll
  end
end

describe("盲盒抽样纯逻辑（common/BlindboxDraw）", function()
  -- 逐案例随机函数守卫：本批随机全部经 rng 参数注入，没有替换 math.random，
  -- 但 MgrSave / MgrLoot 会读全局 math.random()，故逐案例还原，杜绝替换泄漏到后续案例。
  after_each(RandomGuard.restore)

  it("test_bad_rng_rolls_are_rejected", function()
    for _, roll in ipairs({ 0, 1001, 1.5, "x" }) do
      assert.is_nil(BlindboxDraw.Draw(0, scripted({ roll })), "roll=" .. tostring(roll))
    end
  end)

  it("test_draw_many_rejects_bad_count_and_bad_roll", function()
    assert.is_nil(BlindboxDraw.DrawMany(0, 0, scripted({})))
    assert.is_nil(BlindboxDraw.DrawMany(11, 0, scripted({})))
    local draws = BlindboxDraw.DrawMany(2, 0, scripted({ 1, 9999 }))
    assert.is_nil(draws) -- 任一抽 rng 越界整批不成立（不落账，调用方不结算）
  end)

  it("test_draw_result_carries_name_price_and_fixed_multiplier", function()
    local draw = BlindboxDraw.Draw(0, scripted({ 5 })) -- 极品美人鱼
    assert.same("极品美人鱼", draw.itemName)
    assert.same(1000, draw.basePrice)
    assert.same(1, draw.multiplier) -- 盲盒个体倍率固定 1
    assert.is_true(draw.jackpot)
    assert.is_false(draw.guaranteed) -- 自然中大奖不是保底
  end)

  it("test_natural_jackpot_resets_pity", function()
    local draw = BlindboxDraw.Draw(30, scripted({ 3 })) -- 极品美人鱼（权重区）
    assert.is_true(draw.jackpot)
    assert.is_false(draw.guaranteed)
    assert.same(0, draw.pityAfter)
  end)

  it("test_no_guarantee_before_49_misses", function()
    local draw = BlindboxDraw.Draw(48, scripted({ 500 })) -- 权重中段普通项
    assert.is_not_nil(draw)
    assert.is_false(draw.guaranteed)
    assert.is_false(draw.jackpot)
    assert.same(48, draw.pityBefore)
    assert.same(49, draw.pityAfter)
  end)

  it("test_ordinary_miss_increments_pity", function()
    local draw = BlindboxDraw.Draw(0, scripted({ 1000 })) -- 极品罗非鱼
    assert.is_false(draw.jackpot)
    assert.same(1, draw.pityAfter)
  end)

  it("test_pity_guarantees_jackpot_on_the_50th_draw", function()
    local draw = BlindboxDraw.Draw(49, scripted({ 1 })) -- 保底二选一取第 1 件
    assert.is_not_nil(draw)
    assert.is_true(draw.guaranteed)
    assert.is_true(draw.jackpot)
    assert.same("item108", draw.itemKey) -- 极品美人鱼
    assert.same(49, draw.pityBefore)
    assert.same(0, draw.pityAfter) -- 大奖清零
    local other = BlindboxDraw.Draw(49, scripted({ 2 }))
    assert.same("item107", other.itemKey) -- 极品蛇颈龙（等概率第二件）
    assert.is_true(other.guaranteed)
  end)

  it("test_pity_picks_equal_chance_between_two_jackpots", function()
    assert.same(BlindboxCfg.Pity.prizeItemKeys[1], BlindboxDraw.Draw(49, scripted({ 1 })).itemKey)
    assert.same(BlindboxCfg.Pity.prizeItemKeys[2], BlindboxDraw.Draw(49, scripted({ 2 })).itemKey)
    assert.is_nil(BlindboxDraw.Draw(49, scripted({ 3 }))) -- 越界拒绝
  end)

  it("test_ten_draws_cross_the_guarantee_line", function()
    local rolls = { 1000, 1000, 1000, 1000, 2, 1000, 1000, 1000, 1000, 1000 }
    local draws, pityAfter = BlindboxDraw.DrawMany(10, 45, scripted(rolls))
    assert.same(10, #draws)
    for index = 1, 4 do
      assert.is_false(draws[index].guaranteed)
      assert.same(45 + index, draws[index].pityAfter)
    end
    assert.is_true(draws[5].guaranteed) -- pity=49 进场的一抽
    assert.same("item107", draws[5].itemKey)
    assert.same(0, draws[5].pityAfter)
    assert.same(0, draws[6].pityBefore)
    assert.same(5, pityAfter)
  end)

  it("test_ten_draws_settle_pity_per_draw_and_reset_mid_pack", function()
    -- 第 1 抽中大奖（roll 1..10），之后 9 抽全部普通（roll 1000 罗非鱼）
    local rolls = { 1 }
    for _ = 1, 9 do
      rolls[#rolls + 1] = 1000
    end
    local draws, pityAfter = BlindboxDraw.DrawMany(10, 0, scripted(rolls))
    assert.same(10, #draws)
    assert.is_true(draws[1].jackpot)
    assert.same(0, draws[1].pityAfter)
    for index = 2, 10 do
      assert.is_false(draws[index].jackpot)
      assert.same(index - 2, draws[index].pityBefore) -- 重置后重新累计
      assert.same(index - 1, draws[index].pityAfter)
    end
    assert.same(9, pityAfter)
  end)

  it("test_weighted_draw_hits_table_boundaries", function()
    -- 权重区间钉表（总权重 1000）：美人鱼 1-10，蛇颈龙 11-20，鱼龙 21-40，罗非鱼 976-1000
    local cases = {
      { roll = 1, itemKey = "item108" }, -- 区间下界：极品美人鱼
      { roll = 10, itemKey = "item108" }, -- 区间上界仍归美人鱼
      { roll = 11, itemKey = "item107" }, -- 蛇颈龙下界
      { roll = 20, itemKey = "item107" },
      { roll = 21, itemKey = "item106" }, -- 极品鱼龙下界
      { roll = 40, itemKey = "item106" },
      { roll = 1000, itemKey = "item7" }, -- 末项：极品罗非鱼
      { roll = 977, itemKey = "item7" },
      { roll = 976, itemKey = "item7" },
    }
    for _, case in ipairs(cases) do
      local draw = BlindboxDraw.Draw(0, scripted({ case.roll }))
      assert.is_not_nil(draw, "roll=" .. case.roll)
      assert.same(case.itemKey, draw.itemKey, "roll=" .. case.roll)
    end
  end)
end)

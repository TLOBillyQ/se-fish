-- #147 T26 盲盒抽样纯逻辑（common/BlindboxDraw.lua，GameSpec §15 与地图盲盒表）失败方式先列：
--   1. 权重区间错位：累计权重边界归属错（roll 恰等于累计值时归错项）、rng 越界/非数不拒绝；
--   2. 保底时机错：连续 48 次未中就触发保底，或 49 次未中的第 50 抽不保底；
--   3. 保底奖项错：保底出的不是极品美人鱼/极品蛇颈龙，或两件不等概率；
--   4. 大奖重置错：抽出大奖不清零连续未中计数，或未中大奖反而清零；
--   5. 十连逐抽错：十连中途出大奖后，余下的抽数仍沿用旧计数（应逐抽结算、立即重置）；
--   6. 倍率/价格口径错：结果带非 1 的个体倍率，或基础售价与地图盲盒表不符（钉表）。
-- seam：BlindboxDraw.Draw / DrawMany（纯函数）；随机数经 rng(n)（返回 1..n 均匀整数）注入，
--   脚本化序列锁定边界；配置真源是 common/cfg/Blindbox.lua（权重和 1000、期望 166.075 已有钉表）。
local lu = require('luaunit')
local BlindboxDraw = require('common.BlindboxDraw')
local BlindboxCfg = require('common.cfg.Blindbox')

TestBlindboxDraw = {}

-- 脚本化 RNG：按队列逐个吐 roll（1..n），耗尽报错
local function scripted(rolls)
    local queue = {}
    for _, roll in ipairs(rolls) do queue[#queue + 1] = roll end
    return function()
        local roll = table.remove(queue, 1)
        assert(roll, '测试脚本 RNG 序列耗尽')
        return roll
    end
end

-- 权重区间钉表（总权重 1000）：美人鱼 1-10，蛇颈龙 11-20，鱼龙 21-40，罗非鱼 976-1000
function TestBlindboxDraw:test_weighted_draw_hits_table_boundaries()
    local cases = {
        { roll = 1, itemKey = 'item108' },    -- 区间下界：极品美人鱼
        { roll = 10, itemKey = 'item108' },   -- 区间上界仍归美人鱼
        { roll = 11, itemKey = 'item107' },   -- 蛇颈龙下界
        { roll = 20, itemKey = 'item107' },
        { roll = 21, itemKey = 'item106' },   -- 极品鱼龙下界
        { roll = 40, itemKey = 'item106' },
        { roll = 1000, itemKey = 'item7' },   -- 末项：极品罗非鱼
        { roll = 977, itemKey = 'item7' },
        { roll = 976, itemKey = 'item7' },
    }
    for _, case in ipairs(cases) do
        local draw = BlindboxDraw.Draw(0, scripted({ case.roll }))
        lu.assertNotNil(draw, 'roll=' .. case.roll)
        lu.assertEquals(draw.itemKey, case.itemKey, 'roll=' .. case.roll)
    end
end

function TestBlindboxDraw:test_draw_result_carries_name_price_and_fixed_multiplier()
    local draw = BlindboxDraw.Draw(0, scripted({ 5 })) -- 极品美人鱼
    lu.assertEquals(draw.itemName, '极品美人鱼')
    lu.assertEquals(draw.basePrice, 1000)
    lu.assertEquals(draw.multiplier, 1) -- 盲盒个体倍率固定 1
    lu.assertTrue(draw.jackpot)
    lu.assertFalse(draw.guaranteed) -- 自然中大奖不是保底
end

function TestBlindboxDraw:test_bad_rng_rolls_are_rejected()
    for _, roll in ipairs({ 0, 1001, 1.5, 'x' }) do
        lu.assertNil(BlindboxDraw.Draw(0, scripted({ roll })), 'roll=' .. tostring(roll))
    end
end

-- 连续 49 次未中，第 50 抽保底：pity=49 时强制大奖，与 rng 抽权重无关
function TestBlindboxDraw:test_pity_guarantees_jackpot_on_the_50th_draw()
    local draw = BlindboxDraw.Draw(49, scripted({ 1 })) -- 保底二选一取第 1 件
    lu.assertNotNil(draw)
    lu.assertTrue(draw.guaranteed)
    lu.assertTrue(draw.jackpot)
    lu.assertEquals(draw.itemKey, 'item108') -- 极品美人鱼
    lu.assertEquals(draw.pityBefore, 49)
    lu.assertEquals(draw.pityAfter, 0) -- 大奖清零
    local other = BlindboxDraw.Draw(49, scripted({ 2 }))
    lu.assertEquals(other.itemKey, 'item107') -- 极品蛇颈龙（等概率第二件）
    lu.assertTrue(other.guaranteed)
end

-- 保底奖项等概率：两件大奖各占一半（脚本化全排列即可钉死映射）
function TestBlindboxDraw:test_pity_picks_equal_chance_between_two_jackpots()
    lu.assertEquals(BlindboxDraw.Draw(49, scripted({ 1 })).itemKey, BlindboxCfg.Pity.prizeItemKeys[1])
    lu.assertEquals(BlindboxDraw.Draw(49, scripted({ 2 })).itemKey, BlindboxCfg.Pity.prizeItemKeys[2])
    lu.assertNil(BlindboxDraw.Draw(49, scripted({ 3 }))) -- 越界拒绝
end

-- 48 次未中不保底：pity=48 仍按权重抽，未中则 pity 49
function TestBlindboxDraw:test_no_guarantee_before_49_misses()
    local draw = BlindboxDraw.Draw(48, scripted({ 500 })) -- 权重中段普通项
    lu.assertNotNil(draw)
    lu.assertFalse(draw.guaranteed)
    lu.assertFalse(draw.jackpot)
    lu.assertEquals(draw.pityBefore, 48)
    lu.assertEquals(draw.pityAfter, 49)
end

-- 自然抽中大奖（非保底）也立即清零
function TestBlindboxDraw:test_natural_jackpot_resets_pity()
    local draw = BlindboxDraw.Draw(30, scripted({ 3 })) -- 极品美人鱼（权重区）
    lu.assertTrue(draw.jackpot)
    lu.assertFalse(draw.guaranteed)
    lu.assertEquals(draw.pityAfter, 0)
end

function TestBlindboxDraw:test_ordinary_miss_increments_pity()
    local draw = BlindboxDraw.Draw(0, scripted({ 1000 })) -- 极品罗非鱼
    lu.assertFalse(draw.jackpot)
    lu.assertEquals(draw.pityAfter, 1)
end

-- 十连逐抽：每抽独立结算 pity；中途出大奖立即重置，后续抽用新计数
function TestBlindboxDraw:test_ten_draws_settle_pity_per_draw_and_reset_mid_pack()
    -- 第 1 抽中大奖（roll 1..10），之后 9 抽全部普通（roll 1000 罗非鱼）
    local rolls = { 1 }
    for _ = 1, 9 do rolls[#rolls + 1] = 1000 end
    local draws, pityAfter = BlindboxDraw.DrawMany(10, 0, scripted(rolls))
    lu.assertEquals(#draws, 10)
    lu.assertTrue(draws[1].jackpot)
    lu.assertEquals(draws[1].pityAfter, 0)
    for index = 2, 10 do
        lu.assertFalse(draws[index].jackpot)
        lu.assertEquals(draws[index].pityBefore, index - 2) -- 重置后重新累计
        lu.assertEquals(draws[index].pityAfter, index - 1)
    end
    lu.assertEquals(pityAfter, 9)
end

-- 十连跨过保底线：带 45 次未中进场，第 5 抽（累计第 50 次）触发保底
function TestBlindboxDraw:test_ten_draws_cross_the_guarantee_line()
    local rolls = { 1000, 1000, 1000, 1000, 2, 1000, 1000, 1000, 1000, 1000 }
    local draws, pityAfter = BlindboxDraw.DrawMany(10, 45, scripted(rolls))
    lu.assertEquals(#draws, 10)
    for index = 1, 4 do
        lu.assertFalse(draws[index].guaranteed)
        lu.assertEquals(draws[index].pityAfter, 45 + index)
    end
    lu.assertTrue(draws[5].guaranteed) -- pity=49 进场的一抽
    lu.assertEquals(draws[5].itemKey, 'item107')
    lu.assertEquals(draws[5].pityAfter, 0)
    lu.assertEquals(draws[6].pityBefore, 0)
    lu.assertEquals(pityAfter, 5)
end

function TestBlindboxDraw:test_draw_many_rejects_bad_count_and_bad_roll()
    lu.assertNil(BlindboxDraw.DrawMany(0, 0, scripted({})))
    lu.assertNil(BlindboxDraw.DrawMany(11, 0, scripted({})))
    local draws = BlindboxDraw.DrawMany(2, 0, scripted({ 1, 9999 }))
    lu.assertNil(draws) -- 任一抽 rng 越界整批不成立（不落账，调用方不结算）
end

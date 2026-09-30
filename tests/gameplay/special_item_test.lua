-- #140 T19 特殊道具（风神之翼 item169 / 哥斯拉变身 item170）：纯逻辑用例。
-- 服务端接缝（MgrSpecialItem 的选中调和、飞行驱动、吐息结算、冷却镜像）见
-- tests/gameplay/special_item_mgr_test.lua；这里只测 common/SpecialItem.lua 的确定性。
--
-- 测试接缝（写明）：
--   * Desired(itemId)：选中槽物品 → 期望生效效果（'wings'|'godzilla'|nil），
--     是「选中即生效」例外的唯一判定点（GameSpec §3.2）；
--   * StepFlightY / ClampXZ：飞行垂直步进与水平钳制，边界来自 FlightPath.BoundsOf
--     的场景合同（CeilingY = GroundY + MaxFlightHeight），不碰引擎；
--   * TickDamages / NewBreathLedger / BreathHit：吐息伤害计划与每施法一本的台账，
--     每目标按 tick 段结算、总和恰为票面 1000；
--   * CooldownRemaining：冷却判定（吐息 20 秒），只依赖绝对时刻，与变身状态解耦。
--
-- 失败方式（先列后写）：
--   1. 吐息 tick 序列总和 ≠ 1000（舍入漂移），或某段为非正整数；
--   2. 同一目标被同一 tick 段重复结算（重复段），或结满 1000 后还继续给伤害；
--   3. 冷却边界误判：恰好 20 秒整不算就绪，或 nil 记录被当成冷却中；
--   4. 非特殊道具被映射成特殊效果，或特殊道具漏映射；
--   5. 飞行 y 越过 20 米上限或跌破地面；松开不降、长按不升；非法 dt（NaN/负/超步长）污染状态；
--   6. 水平位置跨区不钳或钳错轴。
local lu = require('luaunit')
local GameCfg = require('common.GameCfg')
local SpecialItem = require('common.SpecialItem')

TestSpecialItem = {}

local function bounds()
    -- 与 FlightPath.BoundsOf 同形的场景合同边界：地面 5 米、上限 20 米
    return { MinX = -60, MaxX = 60, MinZ = -50, MaxZ = 70, GroundY = 5, CeilingY = 25, MaxHeight = 20 }
end

-- 失败方式 4：映射只认配置里的两个特殊道具
function TestSpecialItem:test_desired_maps_only_the_two_special_items()
    lu.assertEquals(SpecialItem.Desired('item169'), 'wings')
    lu.assertEquals(SpecialItem.Desired('item170'), 'godzilla')
    lu.assertNil(SpecialItem.Desired('item168'))
    lu.assertNil(SpecialItem.Desired('carp'))
    lu.assertNil(SpecialItem.Desired(nil))
    lu.assertNil(SpecialItem.Desired('item999'))
end

-- 失败方式 5：长按升空，到顶钳住；松开缓降，落地归位
function TestSpecialItem:test_flight_y_climbs_to_ceiling_and_descends_to_ground()
    local cfg = GameCfg.Ability.SpecialItem.Wings
    local b = bounds()
    local state = { Y = b.GroundY, Airborne = false }
    -- 长按 10 秒：必须停在 CeilingY，不越过 20 米上限
    for _ = 1, 40 do
        local y, airborne = SpecialItem.StepFlightY(cfg, state, true, 0.25, b)
        state.Y, state.Airborne = y, airborne
    end
    lu.assertEquals(state.Y, b.CeilingY)
    lu.assertTrue(state.Airborne)
    lu.assertTrue(state.Y <= b.GroundY + 20, 'y ' .. tostring(state.Y))
    -- 松开 20 秒：必须降回地面并落地
    for _ = 1, 80 do
        local y, airborne = SpecialItem.StepFlightY(cfg, state, false, 0.25, b)
        state.Y, state.Airborne = y, airborne
    end
    lu.assertEquals(state.Y, b.GroundY)
    lu.assertFalse(state.Airborne)
end

-- 失败方式 5：非法 dt 不污染状态（NaN / 负 / 超步长截断）
function TestSpecialItem:test_flight_y_rejects_bad_dt()
    local cfg = GameCfg.Ability.SpecialItem.Wings
    local b = bounds()
    local state = { Y = 10, Airborne = true }
    for _, bad in ipairs({ 0 / 0, math.huge, -1 }) do
        local y = SpecialItem.StepFlightY(cfg, state, true, bad, b)
        lu.assertEquals(y, 10, tostring(bad))
    end
    -- 超步长截断：1 秒当 MaxStepSec 算，不能一帧飞穿上限
    local y = SpecialItem.StepFlightY(cfg, { Y = b.CeilingY - 0.5, Airborne = true }, true, 1, b)
    lu.assertTrue(y <= b.CeilingY, 'y ' .. tostring(y))
    lu.assertTrue(y <= b.CeilingY - 0.5 + cfg.ClimbSpeed * cfg.MaxStepSec + 1e-9)
end

-- 失败方式 6：水平越界钳回本区（不能借飞行跨区）
function TestSpecialItem:test_clamp_xz_keeps_position_inside_the_zone()
    local b = bounds()
    local x, z, clamped = SpecialItem.ClampXZ(b, 999, -999)
    lu.assertEquals(x, b.MaxX)
    lu.assertEquals(z, b.MinZ)
    lu.assertTrue(clamped)
    local x2, z2, clamped2 = SpecialItem.ClampXZ(b, 0, 0)
    lu.assertEquals(x2, 0)
    lu.assertEquals(z2, 0)
    lu.assertFalse(clamped2)
end

-- 失败方式 1：tick 计划总和恰为票面总伤害，每段为正整数
function TestSpecialItem:test_breath_tick_plan_sums_to_exactly_the_total()
    local breath = GameCfg.Ability.SpecialItem.Godzilla.Breath
    local plan = SpecialItem.TickDamages(breath.TotalDamage, breath.DurationSec, breath.TickSec)
    lu.assertEquals(#plan, 12) -- 3 秒 / 0.25 秒 = 12 段
    local sum = 0
    for _, amount in ipairs(plan) do
        lu.assertTrue(amount > 0)
        lu.assertEquals(amount, math.floor(amount))
        sum = sum + amount
    end
    lu.assertEquals(sum, 1000)
end

-- 失败方式 2：台账按 tick 段结算，每目标总和恰 1000、无重复段
function TestSpecialItem:test_breath_ledger_caps_each_target_at_the_total()
    local breath = GameCfg.Ability.SpecialItem.Godzilla.Breath
    local ledger = SpecialItem.NewBreathLedger(breath)
    local total = 0
    for tick = 1, 12 do
        local amount = SpecialItem.BreathHit(ledger, 'fish:1', tick)
        lu.assertNotNil(amount)
        total = total + amount
    end
    lu.assertEquals(total, 1000)
    -- 重复段：同一 tick 对同一目标再次结算必须拒绝
    lu.assertNil(SpecialItem.BreathHit(ledger, 'fish:1', 5))
    -- 超段：计划外 tick 不给伤害（目标已结满 1000）
    lu.assertNil(SpecialItem.BreathHit(ledger, 'fish:1', 13))
    -- 另一目标独立成账：不被第一目标的消耗影响
    local other = 0
    for tick = 1, 12 do
        other = other + SpecialItem.BreathHit(ledger, 'player:9', tick)
    end
    lu.assertEquals(other, 1000)
    -- 中途离场：只结走过的段，不补发
    local partial = 0
    for tick = 1, 4 do
        partial = partial + SpecialItem.BreathHit(ledger, 'fish:2', tick)
    end
    lu.assertTrue(partial > 0 and partial < 1000)
end

-- 失败方式 3：冷却判定只看绝对时刻；边界恰好 20 秒整就绪
function TestSpecialItem:test_cooldown_ready_at_the_exact_boundary()
    lu.assertEquals(SpecialItem.CooldownRemaining(nil, 100, 20), 0)
    lu.assertAlmostEquals(SpecialItem.CooldownRemaining(100, 119.9, 20), 0.1, 1e-6)
    lu.assertEquals(SpecialItem.CooldownRemaining(100, 120, 20), 0)
    lu.assertEquals(SpecialItem.CooldownRemaining(100, 125, 20), 0)
    -- 倒流（时钟回拨）按未就绪处理，不出现负冷却
    lu.assertEquals(SpecialItem.CooldownRemaining(100, 90, 20), 30)
end

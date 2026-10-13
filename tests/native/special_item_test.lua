-- #90 迁移：特殊道具纯逻辑（原 tests/gameplay/special_item_test.lua，7 例）。
-- describe / it 名沿用旧类名与方法名；注册顺序 = 旧套件实际执行顺序（LuaUnit 按 `类名.方法名` 全局字典序）。
-- 本文件是纯逻辑用例，不改全局、不改模块缓存、不改配置，因此没有需要恢复的时间或随机替换；
-- 服务端接缝（MgrSpecialItem 的选中调和、飞行驱动、吐息结算、冷却镜像）见 tests/native/special_item_mgr_test.lua。
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
local GameCfg = require('common.GameCfg')
local SpecialItem = require('common.SpecialItem')

describe('TestSpecialItem', function()
    local function bounds()
        -- 与 FlightPath.BoundsOf 同形的场景合同边界：地面 5 米、上限 20 米
        return { MinX = -60, MaxX = 60, MinZ = -50, MaxZ = 70, GroundY = 5, CeilingY = 25, MaxHeight = 20 }
    end

    -- 失败方式 2：台账按 tick 段结算，每目标总和恰 1000、无重复段
    it('test_breath_ledger_caps_each_target_at_the_total', function()
        local breath = GameCfg.Ability.SpecialItem.Godzilla.Breath
        local ledger = SpecialItem.NewBreathLedger(breath)
        local total = 0
        for tick = 1, 12 do
            local amount = SpecialItem.BreathHit(ledger, 'fish:1', tick)
            assert.is_not_nil(amount)
            total = total + amount
        end
        assert.same(1000, total)
        -- 重复段：同一 tick 对同一目标再次结算必须拒绝
        assert.is_nil(SpecialItem.BreathHit(ledger, 'fish:1', 5))
        -- 超段：计划外 tick 不给伤害（目标已结满 1000）
        assert.is_nil(SpecialItem.BreathHit(ledger, 'fish:1', 13))
        -- 另一目标独立成账：不被第一目标的消耗影响
        local other = 0
        for tick = 1, 12 do
            other = other + SpecialItem.BreathHit(ledger, 'player:9', tick)
        end
        assert.same(1000, other)
        -- 中途离场：只结走过的段，不补发
        local partial = 0
        for tick = 1, 4 do
            partial = partial + SpecialItem.BreathHit(ledger, 'fish:2', tick)
        end
        assert.is_true(partial > 0 and partial < 1000)
    end)

    -- 失败方式 1：tick 计划总和恰为票面总伤害，每段为正整数
    it('test_breath_tick_plan_sums_to_exactly_the_total', function()
        local breath = GameCfg.Ability.SpecialItem.Godzilla.Breath
        local plan = SpecialItem.TickDamages(breath.TotalDamage, breath.DurationSec, breath.TickSec)
        assert.same(12, #plan) -- 3 秒 / 0.25 秒 = 12 段
        local sum = 0
        for _, amount in ipairs(plan) do
            assert.is_true(amount > 0)
            assert.same(math.floor(amount), amount)
            sum = sum + amount
        end
        assert.same(1000, sum)
    end)

    -- 失败方式 6：水平越界钳回本区（不能借飞行跨区）
    it('test_clamp_xz_keeps_position_inside_the_zone', function()
        local b = bounds()
        local x, z, clamped = SpecialItem.ClampXZ(b, 999, -999)
        assert.same(b.MaxX, x)
        assert.same(b.MinZ, z)
        assert.is_true(clamped)
        local x2, z2, clamped2 = SpecialItem.ClampXZ(b, 0, 0)
        assert.same(0, x2)
        assert.same(0, z2)
        assert.is_false(clamped2)
    end)

    -- 失败方式 3：冷却判定只看绝对时刻；边界恰好 20 秒整就绪
    it('test_cooldown_ready_at_the_exact_boundary', function()
        assert.same(0, SpecialItem.CooldownRemaining(nil, 100, 20))
        assert.near(0.1, SpecialItem.CooldownRemaining(100, 119.9, 20), 1e-6)
        assert.same(0, SpecialItem.CooldownRemaining(100, 120, 20))
        assert.same(0, SpecialItem.CooldownRemaining(100, 125, 20))
        -- 倒流（时钟回拨）按未就绪处理，不出现负冷却
        assert.same(30, SpecialItem.CooldownRemaining(100, 90, 20))
    end)

    -- 失败方式 4：映射只认配置里的两个特殊道具
    it('test_desired_maps_only_the_two_special_items', function()
        assert.same('wings', SpecialItem.Desired('item169'))
        assert.same('godzilla', SpecialItem.Desired('item170'))
        assert.is_nil(SpecialItem.Desired('item168'))
        assert.is_nil(SpecialItem.Desired('carp'))
        assert.is_nil(SpecialItem.Desired(nil))
        assert.is_nil(SpecialItem.Desired('item999'))
    end)

    -- 失败方式 5：长按升空，到顶钳住；松开缓降，落地归位
    it('test_flight_y_climbs_to_ceiling_and_descends_to_ground', function()
        local cfg = GameCfg.Ability.SpecialItem.Wings
        local b = bounds()
        local state = { Y = b.GroundY, Airborne = false }
        -- 长按 10 秒：必须停在 CeilingY，不越过 20 米上限
        for _ = 1, 40 do
            local y, airborne = SpecialItem.StepFlightY(cfg, state, true, 0.25, b)
            state.Y, state.Airborne = y, airborne
        end
        assert.same(b.CeilingY, state.Y)
        assert.is_true(state.Airborne)
        assert.message('y ' .. tostring(state.Y)).is_true(state.Y <= b.GroundY + 20)
        -- 松开 20 秒：必须降回地面并落地
        for _ = 1, 80 do
            local y, airborne = SpecialItem.StepFlightY(cfg, state, false, 0.25, b)
            state.Y, state.Airborne = y, airborne
        end
        assert.same(b.GroundY, state.Y)
        assert.is_false(state.Airborne)
    end)

    -- 失败方式 5：非法 dt 不污染状态（NaN / 负 / 超步长截断）
    it('test_flight_y_rejects_bad_dt', function()
        local cfg = GameCfg.Ability.SpecialItem.Wings
        local b = bounds()
        local state = { Y = 10, Airborne = true }
        for _, bad in ipairs({ 0 / 0, math.huge, -1 }) do
            local y = SpecialItem.StepFlightY(cfg, state, true, bad, b)
            assert.message(tostring(bad)).same(10, y)
        end
        -- 超步长截断：1 秒当 MaxStepSec 算，不能一帧飞穿上限
        local y = SpecialItem.StepFlightY(cfg, { Y = b.CeilingY - 0.5, Airborne = true }, true, 1, b)
        assert.message('y ' .. tostring(y)).is_true(y <= b.CeilingY)
        assert.is_true(y <= b.CeilingY - 0.5 + cfg.ClimbSpeed * cfg.MaxStepSec + 1e-9)
    end)
end)

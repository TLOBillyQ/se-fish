-- #139 T18 大奖成长切片 2：属性成长纯逻辑（common/AttrGrowth.lua）。
-- 失败方式（先列后写）：
--   1. 加速因子算错或超限不钳制：第 21 个加速药水算出超过 3 倍（统一规格 §2 封顶基础 3 倍/20 个）；
--   2. 移速没有单一计算处：虚弱（×0.5）、霜冻（×0.7）、麻痹（×0）在不同管理器各乘一遍，
--      恢复顺序依赖导致成长丢失（#131 已知边界的根因）；
--   3. 非法输入（负数/小数/NaN/非数）把属性带偏；
--   4. 血量上限与 BodyScale 钉表漂移（两处各算一遍）。
-- 接缝：纯逻辑模块，不碰引擎；数值全部来自 GameCfg 钉表（SpeedPotion/Survival/StatusEffects/BodyScale）。
local lu = require('luaunit')
local GameCfg = require('common.GameCfg')
local AttrGrowth = require('common.AttrGrowth')

TestAttrGrowth = {}

-- 加速因子：0 个 1 倍、1 个 1.1 倍、20 个 3 倍封顶；超限/非法输入钳制
function TestAttrGrowth:test_speed_factor_steps_and_caps()
    lu.assertAlmostEquals(AttrGrowth.SpeedFactor(0), 1.0, 1e-9)
    lu.assertAlmostEquals(AttrGrowth.SpeedFactor(1), 1.1, 1e-9)
    lu.assertAlmostEquals(AttrGrowth.SpeedFactor(10), 2.0, 1e-9)
    lu.assertAlmostEquals(AttrGrowth.SpeedFactor(20), 3.0, 1e-9)
    lu.assertAlmostEquals(AttrGrowth.SpeedFactor(21), 3.0, 1e-9, '第 21 个不得超过 3 倍')
    lu.assertAlmostEquals(AttrGrowth.SpeedFactor(999), 3.0, 1e-9)
    for _, bad in ipairs({ -1, 0 / 0, math.huge, 'x', nil }) do
        lu.assertAlmostEquals(AttrGrowth.SpeedFactor(bad), 1.0, 1e-9, tostring(bad))
    end
    -- 小数按 BodyScale 同口径取整：1.5 个按 1 个算
    lu.assertAlmostEquals(AttrGrowth.SpeedFactor(1.5), 1.1, 1e-9)
end

-- 有效移速单一计算：基础 × 加速成长 × 虚弱 × 霜冻；麻痹为 0
function TestAttrGrowth:test_effective_speed_single_formula()
    local base = GameCfg.Ability.MoveSpeed.Base -- 7
    -- 无修饰：基础 × 成长
    lu.assertAlmostEquals(AttrGrowth.EffectiveSpeed(base, 0, {}), 7, 1e-9)
    lu.assertAlmostEquals(AttrGrowth.EffectiveSpeed(base, 20, {}), 21, 1e-9)
    -- 虚弱在成长后的移速上乘 0.5（统一规格 §2）
    lu.assertAlmostEquals(AttrGrowth.EffectiveSpeed(base, 20, { weak = true }), 10.5, 1e-9)
    -- 霜冻 -30%（统一规格 §6.3 霜之新星）
    lu.assertAlmostEquals(AttrGrowth.EffectiveSpeed(base, 20, { frost = true }), 21 * 0.7, 1e-9)
    -- 虚弱 + 霜冻同帧：同一处连乘，7×3×0.5×0.7 = 7.35
    lu.assertAlmostEquals(AttrGrowth.EffectiveSpeed(base, 20, { weak = true, frost = true }),
        21 * 0.5 * 0.7, 1e-9)
    -- 麻痹：无论其他修饰都为 0
    lu.assertEquals(AttrGrowth.EffectiveSpeed(base, 20, { paralyzed = true }), 0)
    lu.assertEquals(AttrGrowth.EffectiveSpeed(base, 0,
        { paralyzed = true, weak = true, frost = true }), 0)
    -- 非法基准回落配置基准，绝不产出 NaN/负速
    for _, bad in ipairs({ 0 / 0, math.huge, -1, 'x', nil }) do
        lu.assertAlmostEquals(AttrGrowth.EffectiveSpeed(bad, 10, {}), base * 2, 1e-9, tostring(bad))
    end
end

-- 血量上限委托 BodyScale 钉表，不另起公式（0 个 300、10 个 900、超限钳制）
function TestAttrGrowth:test_max_health_delegates_to_body_scale_plan()
    lu.assertEquals(AttrGrowth.MaxHealth(0), 300)
    lu.assertEquals(AttrGrowth.MaxHealth(1), 360)
    lu.assertEquals(AttrGrowth.MaxHealth(10), 900)
    lu.assertEquals(AttrGrowth.MaxHealth(11), 900)
    lu.assertEquals(AttrGrowth.MaxHealth('x'), 300)
    local BodyScale = require('common.BodyScale')
    for n = 0, 12 do
        lu.assertEquals(AttrGrowth.MaxHealth(n), BodyScale.Plan(n).Health)
    end
end

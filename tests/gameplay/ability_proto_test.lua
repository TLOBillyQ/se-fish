-- #132 T11 原型（能力 A：三倍体型）单测。纯逻辑在 common/BodyScale.lua，数值在 GameCfg.Ability.BodyScale。
-- 失败方式（先列后写）：
--   1. 药水数越界：负数 / 小数 / 非数 / 超过上限仍继续变大；上限那一档没有封顶标记；
--   2. 倍率污染：NaN / inf / ≤0 / 非数的倍率被写进单位，派生量随之变 NaN；
--   3. 派生量不是线性放大：胶囊高 / 相机距离 / 交互距离仍按 1 倍算，三倍角色够不到地面物与抛竿点；
--   4. 挂点位移不随体型放大：三倍角色身上的挂件陷进身体（真机「挂点不穿出」的前置条件）；
--   5. 血量成长与体型成长脱钩：10 个药水不是 900 血 / 3 倍，或超限后血量继续涨。
local lu = require('luaunit')

TestBodyScale = {}

function TestBodyScale:setUp()
    self.Cfg = require('common.GameCfg')
    self.BodyScale = require('common.BodyScale')
end

function TestBodyScale:test_config_matches_spec_linear_growth_and_caps()
    local c = self.Cfg.Ability.BodyScale
    lu.assertEquals(c.Base, 1)
    lu.assertEquals(c.Step, 0.2)
    lu.assertEquals(c.Max, 3)
    lu.assertEquals(c.MaxPotions, 10)
    lu.assertEquals(c.HealthBase, 300)
    lu.assertEquals(c.HealthMax, 900)
    lu.assertEquals(c.HealthStepPercent, 20)
end

function TestBodyScale:test_plan_grows_linearly_and_caps_at_ten_potions()
    local plan = self.BodyScale.Plan(0)
    lu.assertEquals(plan.Scale, 1)
    lu.assertEquals(plan.Health, 300)
    lu.assertFalse(plan.Capped)
    plan = self.BodyScale.Plan(5)
    lu.assertEquals(plan.Scale, 2)
    lu.assertEquals(plan.Health, 600)
    plan = self.BodyScale.Plan(10)
    lu.assertEquals(plan.Scale, 3)
    lu.assertEquals(plan.Health, 900)
    lu.assertTrue(plan.Capped)
    -- 超限不再提升，且仍然给出上限值（业务侧据此拒绝使用，见 GameSpec §2）
    for _, over in ipairs({ 11, 99 }) do
        local capped = self.BodyScale.Plan(over)
        lu.assertEquals(capped.Scale, 3, tostring(over))
        lu.assertEquals(capped.Health, 900, tostring(over))
        lu.assertTrue(capped.Capped, tostring(over))
    end
end

function TestBodyScale:test_plan_rejects_non_numbers_and_negatives_as_zero()
    for _, bad in ipairs({ -1, -0.5, '3', nil, 0 / 0, math.huge }) do
        local plan = self.BodyScale.Plan(bad)
        lu.assertEquals(plan.Scale, 1, tostring(bad))
        lu.assertEquals(plan.Health, 300, tostring(bad))
        lu.assertEquals(plan.Potions, 0, tostring(bad))
    end
    -- 小数不是「非法」而是「不足一个」：向下取整，不把玩家的成长一笔抹掉
    local floored = self.BodyScale.Plan(1.5)
    lu.assertEquals(floored.Potions, 1)
    lu.assertEquals(floored.Scale, 1.2)
    lu.assertFalse(floored.Capped)
end

function TestBodyScale:test_sanitize_never_lets_a_bad_factor_through()
    local c = self.Cfg.Ability.BodyScale
    for _, bad in ipairs({ 0 / 0, math.huge, -math.huge, 0, -2, '2', nil }) do
        lu.assertEquals(self.BodyScale.Sanitize(bad), c.Base, tostring(bad))
    end
    lu.assertEquals(self.BodyScale.Sanitize(2.4), 2.4)
    lu.assertEquals(self.BodyScale.Sanitize(99), c.Max)
    lu.assertEquals(self.BodyScale.Sanitize(0.1), c.Base)
end

function TestBodyScale:test_derive_scales_capsule_camera_interact_and_socket()
    local c = self.Cfg.Ability.BodyScale
    local base = { CapsuleHeight = c.CapsuleHeight, CameraDistance = c.CameraDistance,
        InteractRange = c.InteractRange, SocketOffset = { x = 0, y = 2.4, z = 0 } }
    local one = self.BodyScale.Derive(1, base)
    lu.assertEquals(one, { Scale = 1, CapsuleHeight = 2, CameraDistance = 6, InteractRange = 2,
        SocketOffset = { x = 0, y = 2.4, z = 0 } })
    local three = self.BodyScale.Derive(3, base)
    lu.assertEquals(three.CapsuleHeight, 6)
    lu.assertEquals(three.CameraDistance, 18)
    lu.assertEquals(three.InteractRange, 6)
    lu.assertAlmostEquals(three.SocketOffset.x, 0, 1e-9)
    lu.assertAlmostEquals(three.SocketOffset.y, 7.2, 1e-9)
    lu.assertAlmostEquals(three.SocketOffset.z, 0, 1e-9)
    -- 挂点位移必须随体型放大，否则三倍角色身上的挂件陷进身体
    lu.assertTrue(three.SocketOffset.y > one.SocketOffset.y)
end

function TestBodyScale:test_derive_falls_back_to_one_x_when_factor_is_bad()
    local base = { CapsuleHeight = 2, CameraDistance = 6, InteractRange = 2 }
    for _, bad in ipairs({ 0 / 0, math.huge, 0, -1, nil, '3' }) do
        local derived = self.BodyScale.Derive(bad, base)
        lu.assertEquals(derived.Scale, 1, tostring(bad))
        lu.assertEquals(derived.CapsuleHeight, 2, tostring(bad))
        lu.assertEquals(derived.SocketOffset, nil, tostring(bad))
    end
    -- 基准量本身是坏值时也不能产出 NaN
    local derived = self.BodyScale.Derive(3, { CapsuleHeight = 0 / 0, CameraDistance = 'x' })
    lu.assertEquals(derived.CapsuleHeight, 0)
    lu.assertEquals(derived.CameraDistance, 0)
    lu.assertEquals(#tostring(derived), #tostring(derived)) -- 只保证不抛错
    lu.assertNotNil(derived)
    lu.assertFalse(derived.CapsuleHeight ~= derived.CapsuleHeight)
end

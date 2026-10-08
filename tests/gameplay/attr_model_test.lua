-- 失败方式：成长重复投影、乘区重复组合、麻痹残留、非法计数、上下限漂移。
-- 接缝：AttrModel.Plan 的公开投影，不复制 vendor 公式；期望来自既有玩法规格。
local lu = require('luaunit')
TestAttrModel = {}
function TestAttrModel:test_growth_components_use_existing_counts_and_one_multiplier()
    local model = require('common.AttrModel')
    local plan = model.Plan({ bodyPotions = 2, speedPotions = 3, baseSpeed = 7, moveMultiplier = 0.35, hunger = 500 })
    lu.assertEquals(plan.Body.Scale, 1.4)
    lu.assertEquals(plan.Attributes.PlayerMaxHealth.BaseExtra, 120)
    lu.assertAlmostEquals(plan.Attributes.PlayerWalkSpeed.Ratio, -0.545, 1e-9)
    lu.assertEquals(plan.Attributes.PlayerHunger.Base, 300)
end

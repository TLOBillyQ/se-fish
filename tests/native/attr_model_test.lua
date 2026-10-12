-- #89 迁移（原 tests/gameplay/attr_model_test.lua）：
-- 失败方式：成长重复投影、乘区重复组合、麻痹残留、非法计数、上下限漂移。
-- 接缝：AttrModel.Plan 的公开投影，不复制 vendor 公式；期望来自既有玩法规格。
-- describe/it 名沿用旧类名与方法名，案例顺序沿用旧 LuaUnit 的字典序执行序。
describe('TestAttrModel', function()
    -- 成长投影沿用现有计数、只组合一个乘区
    it('test_growth_components_use_existing_counts_and_one_multiplier', function()
        local model = require('common.AttrModel')
        local plan = model.Plan({ bodyPotions = 2, speedPotions = 3, baseSpeed = 7, moveMultiplier = 0.35, hunger = 500 })
        assert.same(1.4, plan.Body.Scale)
        assert.same(120, plan.Attributes.PlayerMaxHealth.BaseExtra)
        assert.near(-0.545, plan.Attributes.PlayerWalkSpeed.Ratio, 1e-9)
        assert.same(300, plan.Attributes.PlayerHunger.Base)
    end)

    -- 武器强化各分量保持线性与上下限
    it('test_weapon_upgrade_components_remain_linear_and_bounded', function()
        local model = require('common.AttrModel')
        local component = model.WeaponComponents('melee', 7)
        assert.same(1, component.Base)
        assert.near(0.7, component.Ratio, 1e-9)
        assert.same({ Base = 1, BaseExtra = 0, Ratio = 0, Bonus = 0 }, model.WeaponComponents('unknown', 99))
    end)
end)

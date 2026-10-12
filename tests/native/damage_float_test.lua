-- #90 迁移：伤害跳字（原 tests/gameplay/damage_float_test.lua，静态 2 类 2 例，旧套件实际只执行 1 例）。
-- describe / it 名沿用旧类名与方法名，注册顺序 = 旧套件实际执行顺序（TestDamageFloat 先于 TestDamageNotice）。
--
-- 迁移期发现的旧套件缺陷（保留案例、不改业务行为）：旧文件的全局类名 TestDamageNotice 与
-- tests/gameplay/vitals_test.lua 的同名类冲突，LuaUnit 按全局表收集测试类，同名只留一份，
-- 因此本文件这份 TestDamageNotice 的 test_rounding_and_effective_health 在旧套件里从未被执行。
-- Busted 每个案例文件是独立 chunk，describe 名不再互相覆盖，这条用例从此真正跑起来：
-- 已单独验证通过（见 issue-90-mapping.md），故按「不遗漏」原则保留，映射清单里记为「旧沉睡用例」。
-- 旧文件里恢复全局用的是 `for key, value in pairs(saved)`：saved 中值为 nil 的键会被 pairs 跳过，
-- 替身全局在「迁移前本来就不存在」时不会被清掉。本 spec 改为逐键 rawget 快照 + 显式赋回（含 nil）。
local DamageNotice = require('common.DamageNotice')
local GameCfg = require('common.GameCfg')
local DamageFloat = require('client.DamageFloat')

describe('TestDamageFloat', function()
    -- 旧 setUp/tearDown 的替身环境逐例建立与恢复：模块单例状态与全局都按案例回滚。
    local saved
    before_each(function()
        saved = {
            game = rawget(_G, 'game'), Vector2 = rawget(_G, 'Vector2'),
            Vector3 = rawget(_G, 'Vector3'), Color = rawget(_G, 'Color'),
        }
    end)
    after_each(function()
        DamageFloat:Clear()
        _G.game = saved.game
        _G.Vector2 = saved.Vector2
        _G.Vector3 = saved.Vector3
        _G.Color = saved.Color
    end)

    it('test_offscreen_and_reuse_reset', function()
        local time, visible = 0, false
        local created = {}
        _G.Vector2 = { New = function(x, y) return { x = x, y = y } end }
        _G.Vector3 = { New = function(x, y, z) return { x = x, y = y, z = z } end }
        _G.Color = { New = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end }
        _G.game = { GetService = function(_, name)
            if name == 'CameraService' then return { MainCamera = {}, WorldToViewportPoint = function(_, point)
                assert.same(5 + GameCfg.DamageFloat.HeadHeight, point.y)
                return { x = 100, y = 200, z = 2 }, visible
            end } end
            if name == 'World' then return {
                GetServerTime = function() return time end,
                CreateUnit = function(_, _, spec)
                    local node = { Parent = spec.Parent, Destroy = function(self) self.Destroyed = true end }
                    created[#created + 1] = node
                    return node
                end,
            } end
        end }
        DamageFloat:Bind({}, { x = 800, y = 600 })
        local payload = { targetType = 'fish', targetId = 7, amount = 0.5,
            position = { x = 3, y = 5, z = 9 } }
        DamageFloat:Show(payload)
        assert.same(0, #created)
        visible = true
        DamageFloat:Show(payload)
        assert.same('1', created[1].Text)
        assert.same(400, created[1].Position.y)
        DamageFloat:Show(payload)
        assert.same(2, #created)
        assert.not_equals(created[2].Position.x, created[1].Position.x)
        visible = false
        time = 0.5
        DamageFloat:Update()
        assert.is_false(DamageFloat.Active[1].Node.Visible)
        visible = true
        DamageFloat:Update()
        assert.is_true(DamageFloat.Active[1].Node.Visible)
        time = 1.1
        DamageFloat:Update()
        assert.same(2, #DamageFloat.Pool)
        payload.amount, payload.critical = 10, true
        DamageFloat:Show(payload)
        assert.same(2, #created)
        assert.same('10', DamageFloat.Active[1].Node.Text)
        assert.same(GameCfg.DamageFloat.CriticalFontSize, DamageFloat.Active[1].Node.FontSize)
        assert.same(1, DamageFloat.Active[1].Node.Opacity)
        DamageFloat:Clear()
        assert.same(0, #DamageFloat.Active)
        assert.is_true(created[1].Destroyed and created[2].Destroyed)
    end)
end)

describe('TestDamageNotice', function()
    it('test_rounding_and_effective_health', function()
        local pos = { x = 3, y = 4, z = 5 }
        for _, case in ipairs({ { 10, 7.3, 3 }, { 10, 7.6, 2 },
            { 10, 9.5, 1 }, { 10, 9.9, 1 }, { 4, 0, 4 } }) do
            local payload = DamageNotice.FromHealth(42, case[1], case[2], pos)
            assert.same(case[3], DamageFloat.DisplayAmount(payload.amount))
            assert.same(42, payload.targetId)
            assert.same(4, payload.position.y)
        end
        assert.is_nil(DamageNotice.FromHealth(42, 4, 4, pos))
        assert.is_nil(DamageNotice.FromHealth(42, 4, 5, pos))
    end)
end)

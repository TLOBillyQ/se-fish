-- #89 迁移（原 tests/gameplay/attr_presentation_test.lua）：
-- 失败方式：派生范围无消费者、非法复制属性扩大距离、相机覆盖其他模式、角色重建残留。
-- 接缝：BodyScale.InteractionRadius、LocalAttr.Refresh/Stop、MgrInteract.InRange。
-- 三个模块都经 loadfile 取全新实例（不经 require，不污染 package.loaded），
-- 旧套件没有 setUp/tearDown，因此逐例不需要 before_each/after_each 恢复全局。
-- describe/it 名沿用旧类名与方法名，案例顺序沿用旧 LuaUnit 的字典序执行序。
describe('TestAttrPresentation', function()
    -- 相机刷新尊重其他拥有者，Stop 时恢复
    it('test_camera_rebuild_restores_old_camera_and_uses_new_character_projection', function()
        local mgr = assert(loadfile('client/LocalAttr.lua'))()
        local first = { GetAttribute = function() return 18 end }
        local second = { GetAttribute = function() return 6 end }
        local camera = { Distance = 8, TrackingUnit = first }
        assert.is_true(mgr:Refresh(first, camera))
        camera.TrackingUnit = second
        assert.is_true(mgr:Refresh(second, camera))
        assert.same(6, camera.Distance)
        mgr:Stop()
        assert.same(8, camera.Distance)
    end)

    -- 相机刷新尊重外部改动（他人拥有）并在 Stop 后恢复；重新加载的实例不残留上一份
    it('test_camera_refresh_respects_other_owner_and_restores_on_stop', function()
        local env = setmetatable({}, { __index = _G })
        local mgr = assert(loadfile('client/LocalAttr.lua', 't', env))()
        local character = { GetAttribute = function() return 24 end }
        local camera = { Distance = 8, TrackingUnit = character }
        assert.is_true(mgr:Refresh(character, camera))
        assert.same(18, camera.Distance)
        camera.Distance = 12
        assert.is_false(mgr:Refresh(character, camera))
        assert.same(12, camera.Distance)
        mgr:Stop()
        assert.same(12, camera.Distance)
        local fresh = assert(loadfile('client/LocalAttr.lua', 't', env))()
        camera.Distance = 8
        assert.is_true(fresh:Refresh(character, camera))
        fresh:Stop()
        assert.same(8, camera.Distance)
    end)

    -- 交互半径按体型派生缩放，非法属性回落基础半径
    it('test_interaction_radius_scales_and_falls_back_for_invalid_attributes', function()
        local body = require('common.BodyScale')
        local value = body.Derive(3).InteractRange
        local character = { GetAttribute = function() return value end }
        assert.same(12, body.InteractionRadius(character, 4))
        value = math.huge
        assert.same(4, body.InteractionRadius(character, 4))
        value = body.Derive(100).InteractRange
        assert.same(12, body.InteractionRadius(character, 4))
    end)

    -- 服务端判定按体型缩放半径，同时保留 slack；没有角色时拒绝
    it('test_server_range_scales_radius_but_keeps_slack_and_rejects_missing_character', function()
        local mgr = assert(loadfile('server/Mgr/MgrInteract.lua'))()
        local anchor = { Position = { x = 0, z = 0 } }
        mgr.FindAnchor = function() return anchor end
        local value = require('common.BodyScale').Derive(3).InteractRange
        local character = { Position = { x = 12.5, z = 0 }, GetAttribute = function() return value end }
        local p = { Character = character }
        local point = { AnchorName = 'test', Radius = 4, Slack = 0.5 }
        assert.same(anchor, mgr:InRange(p, point))
        character.Position.x = 12.51
        assert.is_nil(mgr:InRange(p, point))
        value = math.huge
        character.Position.x = 4.5
        assert.same(anchor, mgr:InRange(p, point))
        character.Position.x = 4.51
        assert.is_nil(mgr:InRange(p, point))
        p.Character = nil
        assert.is_nil(mgr:InRange(p, point))
    end)
end)

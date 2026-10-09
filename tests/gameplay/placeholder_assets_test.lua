-- #44 内置素材占位：接缝为 GameCfg 应用结果（图标/品级颜色/分类模型）与特殊道具占位清理。
-- 失败方式（先列后写）：
--   1. 171 件物品缺图标或分类占位模型，98 种鱼缺品级颜色；
--   2. 已有正式图标的物品被占位表覆盖，正式交付无法直接替换；
--   3. 特殊道具模型创建失败时挂点残留，随后重试叠加；
--   4. 恢复后占位模型或挂点残留。
local lu = require('luaunit')
local GameCfg = require('common.GameCfg')

TestPlaceholderAssets = {}

function TestPlaceholderAssets:setUp()
    self.saved = {
        game = rawget(_G, 'game'), Vector3 = rawget(_G, 'Vector3'),
        wing = GameCfg.Ability.SpecialItem.Wings.AppearanceAssetId,
        godzilla = GameCfg.Ability.SpecialItem.Godzilla.AppearanceAssetId,
    }
end

function TestPlaceholderAssets:tearDown()
    _G.game, _G.Vector3 = self.saved.game, self.saved.Vector3
    GameCfg.Ability.SpecialItem.Wings.AppearanceAssetId = self.saved.wing
    GameCfg.Ability.SpecialItem.Godzilla.AppearanceAssetId = self.saved.godzilla
end

function TestPlaceholderAssets:test_all_content_has_placeholder_visual_and_existing_icons_survive()
    lu.assertEquals(GameCfg.Items.Definitions.starterRod.Icon, 'official://image/12024')
    lu.assertEquals(GameCfg.Fish.carp.VisualColor, { 255, 255, 255, 255 })
    lu.assertEquals(GameCfg.Fish.item7.VisualColor, { 255, 205, 65, 255 })
    lu.assertEquals(GameCfg.Fish.fish39Elite.VisualColor, { 255, 130, 65, 255 })
    lu.assertEquals(GameCfg.Fish.fish40Boss.VisualColor, { 240, 80, 80, 255 })
    lu.assertEquals(GameCfg.Items.Definitions.item143.Visual.Mesh, 'official://mesh/7000253')
    lu.assertEquals(GameCfg.Items.Definitions.item152.Visual.Mesh, 'official://mesh/57363')
    lu.assertEquals(GameCfg.Items.Definitions.item152.IconColor, { 110, 220, 100, 255 })
    lu.assertEquals(GameCfg.Items.Definitions.item169.Visual.Mesh, 'official://mesh/50227')
    for id, item in pairs(GameCfg.Items.Definitions) do
        lu.assertNotNil(item.Icon, id)
        lu.assertNotNil(item.Visual, id)
        lu.assertNotNil(item.IconColor, id)
    end
    for id, fish in pairs(GameCfg.Fish) do lu.assertNotNil(fish.VisualColor, id) end
end

-- 特殊道具占位模型生命周期：模型失败时挂点反向清理；恢复时模型与挂点都销毁。
function TestPlaceholderAssets:test_special_placeholder_cleans_up_on_create_failure_and_restore()
    GameCfg.Ability.SpecialItem.Wings.AppearanceAssetId = nil
    GameCfg.Ability.SpecialItem.Godzilla.AppearanceAssetId = nil
    _G.Vector3 = { New = function(x, y, z) return { x = x, y = y, z = z } end }
    local created = {}
    local failModel = true
    _G.game = { GetService = function(_, name)
        if name == 'World' then
            return {
                GetServerTime = function() return 1000 end,
                CreateUnit = function(_, unitType, values)
                    if failModel and unitType == 'WorldUnit' then error('no-model') end
                    local unit = { UnitType = unitType, Name = values.Name,
                        Destroy = function(self) self.Destroyed = true end }
                    created[#created + 1] = unit
                    return unit
                end,
            }
        end
        return {}
    end }
    local oldMgr = package.loaded['server.Mgr.MgrSpecialItem']
    package.loaded['server.Mgr.MgrSpecialItem'] = nil
    local mgr = assert(loadfile('server/Mgr/MgrSpecialItem.lua'))()
    local player = { UserId = 1, Character = { Controller = { GravityEnabled = true } } }
    local state = mgr:GetState(player)

    lu.assertFalse(mgr:Apply(player, state, 'wings'))
    lu.assertTrue(created[1].Destroyed)
    lu.assertNil(state.placeholderMount)
    lu.assertNil(state.placeholderModel)

    state.failures = nil
    failModel = false
    lu.assertTrue(mgr:Apply(player, state, 'wings'))
    lu.assertEquals(#created, 3)
    lu.assertTrue(mgr:Restore(player, state))
    lu.assertTrue(created[2].Destroyed)
    lu.assertTrue(created[3].Destroyed)
    package.loaded['server.Mgr.MgrSpecialItem'] = oldMgr
end

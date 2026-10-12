-- #44 内置素材占位：接缝为 GameCfg 应用结果（图标/品级颜色/分类模型）与特殊道具占位清理。
-- 失败方式（先列后写）：
--   1. 171 件物品缺图标或分类占位模型，98 种鱼缺品级颜色；
--   2. 已有正式图标的物品被占位表覆盖，正式交付无法直接替换；
--   3. 特殊道具模型创建失败时挂点残留，随后重试叠加；
--   4. 恢复后占位模型或挂点残留。
-- 迁移自 tests/gameplay/placeholder_assets_test.lua（#83）。旧入口的 setUp/tearDown 是逐例执行的，
-- 因此这里映射为 before_each/after_each；模块缓存与全局在 after_each 一律恢复，
-- 测试体中途失败也不把半成品环境留给后续案例。
local GameCfg = require('common.GameCfg')

describe("TestPlaceholderAssets", function()
  local env

  before_each(function()
    env = {
      saved = {
        game = rawget(_G, 'game'), Vector3 = rawget(_G, 'Vector3'),
        wing = GameCfg.Ability.SpecialItem.Wings.AppearanceAssetId,
        godzilla = GameCfg.Ability.SpecialItem.Godzilla.AppearanceAssetId,
        specialItem = package.loaded['server.Mgr.MgrSpecialItem'],
      },
    }
  end)

  after_each(function()
    _G.game, _G.Vector3 = env.saved.game, env.saved.Vector3
    GameCfg.Ability.SpecialItem.Wings.AppearanceAssetId = env.saved.wing
    GameCfg.Ability.SpecialItem.Godzilla.AppearanceAssetId = env.saved.godzilla
    package.loaded['server.Mgr.MgrSpecialItem'] = env.saved.specialItem
    env = nil
  end)

  it("test_all_content_has_placeholder_visual_and_existing_icons_survive", function()
    assert.are.equal('official://image/12024', GameCfg.Items.Definitions.starterRod.Icon)
    assert.same({ 255, 255, 255, 255 }, GameCfg.Fish.carp.VisualColor)
    assert.same({ 255, 205, 65, 255 }, GameCfg.Fish.item7.VisualColor)
    assert.same({ 255, 130, 65, 255 }, GameCfg.Fish.fish39Elite.VisualColor)
    assert.same({ 240, 80, 80, 255 }, GameCfg.Fish.fish40Boss.VisualColor)
    assert.are.equal('official://mesh/7000253', GameCfg.Items.Definitions.item143.Visual.Mesh)
    assert.are.equal('official://mesh/57363', GameCfg.Items.Definitions.item152.Visual.Mesh)
    assert.same({ 110, 220, 100, 255 }, GameCfg.Items.Definitions.item152.IconColor)
    assert.are.equal('official://mesh/50227', GameCfg.Items.Definitions.item169.Visual.Mesh)
    for id, item in pairs(GameCfg.Items.Definitions) do
      assert.is_not_nil(item.Icon, id)
      assert.is_not_nil(item.Visual, id)
      assert.is_not_nil(item.IconColor, id)
    end
    for id, fish in pairs(GameCfg.Fish) do assert.is_not_nil(fish.VisualColor, id) end
  end)

  -- 特殊道具占位模型生命周期：模型失败时挂点反向清理；恢复时模型与挂点都销毁。
  it("test_special_placeholder_cleans_up_on_create_failure_and_restore", function()
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
    package.loaded['server.Mgr.MgrSpecialItem'] = nil
    local mgr = assert(loadfile('server/Mgr/MgrSpecialItem.lua'))()
    local player = { UserId = 1, Character = { Controller = { GravityEnabled = true } } }
    local state = mgr:GetState(player)

    assert.is_false(mgr:Apply(player, state, 'wings'))
    assert.is_true(created[1].Destroyed)
    assert.is_nil(state.placeholderMount)
    assert.is_nil(state.placeholderModel)

    state.failures = nil
    failModel = false
    assert.is_true(mgr:Apply(player, state, 'wings'))
    assert.are.equal(3, #created)
    assert.is_true(mgr:Restore(player, state))
    assert.is_true(created[2].Destroyed)
    assert.is_true(created[3].Destroyed)
  end)
end)

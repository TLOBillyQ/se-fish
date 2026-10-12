-- #136 蟹湖最小内容接线（GameSpec §8.1 / §12、钓鱼表 R30–R43）：蟹湖水区进 Water.Zones、
-- 抽鱼池按原表（蟛蜞任意饵保底、寄居蟹起用鲱鱼罐头、梭子蟹起竿级 3）、帝王蟹入池、
-- 首领饵 item122 必出蟹老板、Z3_Shop 三级摊位上架鲱鱼罐头/捕蟹竿/霰弹枪与 3 级升级行。
-- 失败方式（先列后写）：
--   1. 蟹湖水区没进 Water.Zones / ZoneIdByWater（抛竿选不到蟹湖鱼表），或与其他水区水平重叠；
--   2. 抽鱼池行错：不挂饵出不了蟛蜞保底、挂鲱鱼罐头竿 1 能出竿 3 的蟹、漏极品行或帝王蟹行、
--      权重/竿级/饵与原表不符，或行指向不存在的鱼种；
--   3. 首领饵 item122 没登记（必出蟹老板失效），或登记错鱼种；
--   4. 蟹湖 14 行鱼种 implemented 未翻开、缺 Model、帝王蟹/蟹老板缺 Combat 标签与战斗参数；
--   5. Z3_Shop 摊位缺失或 Level 不是 3：买不到鲱鱼罐头 / 捕蟹竿 / 霰弹枪 / 3 级升级行；
--   6. 场景合同第三区缺烧烤锚点 Z3_Grill（#137 的接入点本单必须预置）。
-- 迁移自 tests/gameplay/crab_lake_cfg_test.lua（#83）。旧 setUp 会把 GameCfg 从模块缓存摘下重装、
-- tearDown 装回，映射为逐例 before_each/after_each 以保留「setup 失败仍清理模块缓存」的行为；
-- it 的书写顺序沿用旧入口的方法名字典序，与迁移前逐条对账。
describe("TestCrabLakeCfg", function()
  local cfg, savedCfg

  before_each(function()
    savedCfg = package.loaded['common.GameCfg']
    package.loaded['common.GameCfg'] = nil
    cfg = require('common.GameCfg')
  end)

  after_each(function()
    package.loaded['common.GameCfg'] = savedCfg
  end)

  local function crabWater(cfg)
    for _, zone in ipairs(cfg.Water.Zones) do
      if zone.Id == 'crabLake.water' then return zone end
    end
  end

  -- 抽鱼池：13 行（普通/极品 12 + 帝王蟹），数值逐行钉原表；首领饵由 BossBait 接管不入池
  it("test_casting_zone_matches_source_table", function()
    local rows = cfg.Casting.Zones['crabLake.water']
    assert.is_not_nil(rows, '蟹湖抽鱼池缺失')
    local expect = {
      { Id = 'item33', Bait = 0, RodLevel = 1, DrawWeight = 8 },
      { Id = 'item34', Bait = 'item115', RodLevel = 1, DrawWeight = 8 },
      { Id = 'item35', Bait = 'item115', RodLevel = 1, DrawWeight = 8 },
      { Id = 'item36', Bait = 'item115', RodLevel = 3, DrawWeight = 32 },
      { Id = 'item37', Bait = 'item115', RodLevel = 3, DrawWeight = 24 },
      { Id = 'item38', Bait = 'item115', RodLevel = 3, DrawWeight = 16 },
      { Id = 'item39', Bait = 0, RodLevel = 1, DrawWeight = 2 },
      { Id = 'item40', Bait = 'item115', RodLevel = 1, DrawWeight = 2 },
      { Id = 'item41', Bait = 'item115', RodLevel = 1, DrawWeight = 2 },
      { Id = 'item42', Bait = 'item115', RodLevel = 3, DrawWeight = 8 },
      { Id = 'item43', Bait = 'item115', RodLevel = 3, DrawWeight = 6 },
      { Id = 'item44', Bait = 'item115', RodLevel = 3, DrawWeight = 4 },
      { Id = 'fish23Elite', Bait = 'item115', RodLevel = 3, DrawWeight = 10 },
    }
    assert.are.equal(#expect, #rows)
    for index, row in ipairs(expect) do
      assert.are.equal(row.Id, rows[index].Id, '第 ' .. index .. ' 行鱼种')
      assert.are.equal(row.Bait, rows[index].Bait, row.Id .. ' 鱼饵')
      assert.are.equal(row.RodLevel, rows[index].RodLevel, row.Id .. ' 竿级')
      assert.are.equal(row.DrawWeight, rows[index].DrawWeight, row.Id .. ' 权重')
      assert.is_not_nil(cfg.Fish[row.Id], row.Id .. ' 不在鱼种表')
    end
    -- 保底与门槛：不挂饵只能出蟛蜞/极品蟛蜞；挂鲱鱼罐头竿 1 不出竿 3 的蟹
    local FishCatch = require('common.FishCatch')
    local function selectAll(rodLevel, baitId)
      local total = 0
      for _, row in ipairs(rows) do
        if row.RodLevel <= rodLevel and (row.Bait == 0 or row.Bait == baitId) then
          total = total + row.DrawWeight
        end
      end
      local found = {}
      for roll = 1, total do
        found[FishCatch.Select(rows, rodLevel, baitId, function() return roll end)] = true
      end
      return found
    end
    local noBait = selectAll(1, nil)
    assert.same({ item33 = true, item39 = true }, noBait)
    local baitRod1 = selectAll(1, 'item115')
    assert.same({ item33 = true, item34 = true, item35 = true,
      item39 = true, item40 = true, item41 = true }, baitRod1)
    local baitRod3 = selectAll(3, 'item115')
    assert.is_not_nil(baitRod3.item38)
    assert.is_not_nil(baitRod3.fish23Elite)
    -- 首领饵必出蟹老板（#88 口径：BossBait 键即首领饵物品 id）
    assert.are.equal('fish24Boss', cfg.Casting.BossBait.item122)
  end)

  -- 水区注册：Id 取内容层 WaterId，矩形 80×24，中心 (480,-44)，映射到 crabLake 钓鱼区
  it("test_crab_lake_water_zone_registered_and_disjoint", function()
    local water = crabWater(cfg)
    assert.is_not_nil(water, 'crabLake.water 未进 Water.Zones')
    assert.are.equal(480, water.Center.x)
    assert.are.equal(-44, water.Center.z)
    assert.are.equal(40, water.HalfX)
    assert.are.equal(12, water.HalfZ)
    assert.are.equal('number', type(water.SurfaceY))
    assert.are.equal('crabLake', water.ZoneId)
    assert.are.equal('crabLake', cfg.Water.ZoneIdByWater['crabLake.water'])
    for _, zone in ipairs(cfg.Water.Zones) do
      if zone.Id ~= 'crabLake.water' then
        local zx = zone.HalfX or zone.HalfXZ
        local zz = zone.HalfZ or zone.HalfXZ
        local dx = math.abs(zone.Center.x - water.Center.x)
        local dz = math.abs(zone.Center.z - water.Center.z)
        assert.is_true(dx > zx + water.HalfX or dz > zz + water.HalfZ,
          'crabLake.water 与 ' .. zone.Id .. ' 水平重叠')
      end
    end
  end)

  -- 蟹湖 14 行翻开 implemented 并配模型；帝王蟹 / 蟹老板带 Combat 与战斗参数表
  it("test_crab_species_implemented_with_models_and_combat", function()
    local fish = cfg.Fish
    local normals = { 'item33', 'item34', 'item35', 'item36', 'item37', 'item38',
      'item39', 'item40', 'item41', 'item42', 'item43', 'item44' }
    for _, id in ipairs(normals) do
      assert.is_true(fish[id].implemented, id .. ' 未翻开 implemented')
      assert.are.equal('7000554', fish[id].Model, id .. ' 复用官方螃蟹模型')
      assert.is_nil(fish[id].Combat, id .. ' 普通/极品蟹不走战斗路径')
    end
    assert.is_true(fish.fish23Elite.implemented)
    assert.are.equal('7000554', fish.fish23Elite.Model)
    assert.are.equal('kingCrab', fish.fish23Elite.Combat)
    assert.is_true(fish.fish24Boss.implemented)
    assert.are.equal('7000554', fish.fish24Boss.Model)
    assert.are.equal('crabBoss', fish.fish24Boss.Combat)
    -- 战斗参数表（数值来源 GameSpec §12 正文与钓鱼表）
    local king = cfg.FishCombat.kingCrab
    assert.is_not_nil(king, '缺 FishCombat.kingCrab')
    assert.are.equal(5, king.JabIntervalSec)
    assert.are.equal(3, king.JabsPerSide)
    assert.are.equal(0.2, king.JabStepSec)
    assert.are.equal(15, king.JabDamage)
    assert.are.equal(30, king.ActiveSec)
    assert.are.equal(5, king.StunSec)
    local boss = cfg.FishCombat.crabBoss
    assert.is_not_nil(boss, '缺 FishCombat.crabBoss')
    assert.are.equal(20, boss.PinchDamage)
    assert.are.equal(4, boss.PinchCooldownSec)
    assert.are.equal(30, boss.ChargeSec)
    assert.are.equal(25, boss.SpinSec)
    assert.are.equal(5, boss.SpinDurationSec)
    assert.are.equal(30, boss.SpinDamage)
    -- 蟹老板饵是首领饵：不走 Bait 计数库存，不可按只回收（沿用既有口径）
    local items = require('common.cfg.Items')
    assert.is_true(items.Definitions.item122.BossBait)
    assert.is_nil(items.Definitions.item122.Container)
    assert.is_nil(cfg.Interact.Fisherman.BaitPrice.item122)
  end)

  -- Z3_Shop 三级摊位：鲱鱼罐头 / 捕蟹竿 / 霰弹枪与 3 级升级行上架
  it("test_z3_shop_stand_level3_shelves_crab_goods", function()
    local stand
    for _, row in ipairs(cfg.Shop.Stands) do
      if row.AnchorName == 'Z3_Shop' then stand = row end
    end
    assert.is_not_nil(stand, '缺 Z3_Shop 摊位')
    assert.are.equal(3, stand.Level)
    local gear = {}
    for _, row in ipairs(cfg.Shop.ListForPage(3, '钓具')) do gear[row.ItemId] = row.Price end
    assert.are.equal(3, gear.item115)
    assert.are.equal(24, gear.crabRod)
    local weapons = {}
    for _, row in ipairs(cfg.Shop.ListForPage(3, '武器')) do weapons[row.ItemId] = row.Price end
    assert.are.equal(200, weapons.item138)
    local upgrades = {}
    for _, row in ipairs(cfg.Shop.ListForPage(3, '升级')) do upgrades[row.Name] = row.Price end
    assert.are.equal(500, upgrades['远程武器升级1'])
    assert.are.equal(400, upgrades['爆炸物升级1'])
    assert.are.equal(200, upgrades['近战武器升级3'])
    assert.are.equal(400, upgrades['背包升级3'])
    -- 一二区摊位买不到 3 级新品
    local pondGear = {}
    for _, row in ipairs(cfg.Shop.ListForPage(1, '钓具')) do pondGear[row.ItemId] = true end
    assert.is_nil(pondGear.item115)
    assert.is_nil(pondGear.crabRod)
  end)

  -- 烧烤锚点预置（#137 的接入点）：场景合同第三区暴露 Grill 实体
  it("test_zone3_scene_contract_exposes_grill_anchor", function()
    local scene = cfg.Zones[3].Scene
    assert.are.equal('Z3_Grill', scene.GrillName)
    local grill
    for _, entity in ipairs(scene.Entities) do
      if entity.Role == 'Grill' then grill = entity end
    end
    assert.is_not_nil(grill)
    assert.are.equal('Z3_Grill', grill.Name)
    assert.same({ x = 490, y = 5, z = 10 }, grill.Position)
  end)
end)

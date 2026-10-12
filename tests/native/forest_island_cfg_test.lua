-- #141 树林岛最小内容接线（GameSpec §5.4/§8/§12、钓鱼表 R44–R57、商店表 R8/9/17/22/31/38/41/49）：
-- 树林岛水区进 Water.Zones；抽鱼池按原表 13 行（海胆任意饵保底、比目鱼起用蚂蟥、翻车鲀起竿级 4）、
-- 剑鱼入池；首领饵 item123 必出三头鲨；14 鱼种翻开 implemented 并给剑鱼 / 三头鲨 Combat 与战斗参数；
-- Z4_Shop 四级摊位上架蚂蟥 / 普通鱼竿 / 冲锋枪与 4 级升级行；场景合同暴露 Z4_Grill 烧烤锚点；
-- 信物链 鱼剑→牛腿、三联鲨鱼头→沙滩岛船票；返程第 4 区 90 金。
-- 失败方式（先列后写）：
--   1. 树林岛水区没进 Water.Zones / ZoneIdByWater（抛竿选不到树林岛鱼表），或与其他水区水平重叠；
--   2. 抽鱼池行错：不挂饵出不了海胆保底、挂蚂蟥竿 1 能出竿 4 的鱼、漏极品行或剑鱼行、
--      权重 / 竿级 / 饵与原表不符，或行指向不存在的鱼种；
--   3. 首领饵 item123 没登记（必出三头鲨失效），或登记错鱼种；
--   4. 14 鱼种 implemented 未翻开、剑鱼 / 三头鲨缺 Combat 标签与战斗参数表（数值错）；
--   5. Z4_Shop 摊位缺失或 Level 不是 4：买不到蚂蟥 / 普通鱼竿 / 冲锋枪 / 4 级升级行；
--   6. 场景合同第四区缺烧烤锚点 Z4_Grill（#137 接入点）；
--   7. 信物链错（鱼剑→牛腿、三联鲨鱼头→沙滩岛船票）或返程票价不是 90 金。
-- 迁移自 tests/gameplay/forest_island_cfg_test.lua（#83）。旧 setUp 会把 GameCfg 从模块缓存摘下重装、
-- tearDown 装回，映射为逐例 before_each/after_each 以保留「setup 失败仍清理模块缓存」的行为；
-- it 的书写顺序沿用旧入口的方法名字典序，与迁移前逐条对账。
describe("TestForestIslandCfg", function()
  local cfg, savedCfg

  before_each(function()
    savedCfg = package.loaded['common.GameCfg']
    package.loaded['common.GameCfg'] = nil
    cfg = require('common.GameCfg')
  end)

  after_each(function()
    package.loaded['common.GameCfg'] = savedCfg
  end)

  local function forestWater(cfg)
    for _, zone in ipairs(cfg.Water.Zones) do
      if zone.Id == 'forestIsland.water' then return zone end
    end
  end

  -- 抽鱼池：13 行（普通 / 极品 12 + 剑鱼），数值逐行钉原表；首领鲨由 BossBait 接管不入池
  it("test_casting_zone_matches_source_table", function()
    local rows = cfg.Casting.Zones['forestIsland.water']
    assert.is_not_nil(rows, '树林岛抽鱼池缺失')
    local expect = {
      { Id = 'item49', Bait = 0, RodLevel = 1, DrawWeight = 8 },
      { Id = 'item50', Bait = 'item116', RodLevel = 1, DrawWeight = 8 },
      { Id = 'item51', Bait = 'item116', RodLevel = 1, DrawWeight = 8 },
      { Id = 'item52', Bait = 'item116', RodLevel = 4, DrawWeight = 32 },
      { Id = 'item53', Bait = 'item116', RodLevel = 4, DrawWeight = 24 },
      { Id = 'item54', Bait = 'item116', RodLevel = 4, DrawWeight = 16 },
      { Id = 'item55', Bait = 0, RodLevel = 1, DrawWeight = 2 },
      { Id = 'item56', Bait = 'item116', RodLevel = 1, DrawWeight = 2 },
      { Id = 'item57', Bait = 'item116', RodLevel = 1, DrawWeight = 2 },
      { Id = 'item58', Bait = 'item116', RodLevel = 4, DrawWeight = 8 },
      { Id = 'item59', Bait = 'item116', RodLevel = 4, DrawWeight = 6 },
      { Id = 'item60', Bait = 'item116', RodLevel = 4, DrawWeight = 4 },
      { Id = 'fish31Elite', Bait = 'item116', RodLevel = 4, DrawWeight = 10 },
    }
    assert.are.equal(#expect, #rows)
    for index, row in ipairs(expect) do
      assert.are.equal(row.Id, rows[index].Id, '第 ' .. index .. ' 行鱼种')
      assert.are.equal(row.Bait, rows[index].Bait, row.Id .. ' 鱼饵')
      assert.are.equal(row.RodLevel, rows[index].RodLevel, row.Id .. ' 竿级')
      assert.are.equal(row.DrawWeight, rows[index].DrawWeight, row.Id .. ' 权重')
      assert.is_not_nil(cfg.Fish[row.Id], row.Id .. ' 不在鱼种表')
    end
    -- 保底与门槛：不挂饵只能出海胆 / 极品海胆；挂蚂蟥竿 1 不出竿 4 的鱼
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
    assert.same({ item49 = true, item55 = true }, selectAll(1, nil))
    local baitRod1 = selectAll(1, 'item116')
    assert.same({ item49 = true, item50 = true, item51 = true,
      item55 = true, item56 = true, item57 = true }, baitRod1)
    local baitRod4 = selectAll(4, 'item116')
    assert.is_not_nil(baitRod4.item54)
    assert.is_not_nil(baitRod4.fish31Elite)
    -- 首领饵必出三头鲨（#88 口径：BossBait 键即首领饵物品 id）
    assert.are.equal('fish32Boss', cfg.Casting.BossBait.item123)
  end)

  -- 信物链与返程：鱼剑→牛腿、三联鲨鱼头→沙滩岛船票；第 4 区返程 90 金
  it("test_exchange_chain_and_return_price", function()
    local chain = cfg.Content.Exchanges[4]
    assert.are.equal('forestIsland', chain.ZoneId)
    assert.are.equal('item63', chain.EliteToken)
    assert.are.equal('item123', chain.BossBait)
    assert.are.equal('item64', chain.BossToken)
    assert.are.equal('item149', chain.Result)
    assert.same({ item63 = 'item123', item64 = 'item149' }, cfg.Interact.Fishermen[4].Exchange)
    local route
    for _, candidate in ipairs(cfg.Ferry.Routes) do
      if candidate.FromZoneId == 'crabLake' and candidate.ToZoneId == 'forestIsland' then route = candidate end
    end
    assert.is_not_nil(route, '缺 蟹湖→树林岛 航线')
    assert.are.equal(90, route.Return.Price)
    assert.are.equal('item148', route.Outbound.Ticket)
  end)

  -- 水区注册：Id 取内容层 WaterId，矩形 80×24，中心 (720,-44)，映射到 forestIsland 钓鱼区
  it("test_forest_island_water_zone_registered_and_disjoint", function()
    local water = forestWater(cfg)
    assert.is_not_nil(water, 'forestIsland.water 未进 Water.Zones')
    assert.are.equal(720, water.Center.x)
    assert.are.equal(-44, water.Center.z)
    assert.are.equal(40, water.HalfX)
    assert.are.equal(12, water.HalfZ)
    assert.are.equal('number', type(water.SurfaceY))
    assert.are.equal('forestIsland', water.ZoneId)
    assert.are.equal('forestIsland', cfg.Water.ZoneIdByWater['forestIsland.water'])
    for _, zone in ipairs(cfg.Water.Zones) do
      if zone.Id ~= 'forestIsland.water' then
        local zx = zone.HalfX or zone.HalfXZ
        local zz = zone.HalfZ or zone.HalfXZ
        local dx = math.abs(zone.Center.x - water.Center.x)
        local dz = math.abs(zone.Center.z - water.Center.z)
        assert.is_true(dx > zx + water.HalfX or dz > zz + water.HalfZ,
          'forestIsland.water 与 ' .. zone.Id .. ' 水平重叠')
      end
    end
  end)

  -- 树林岛 14 行翻开 implemented；剑鱼 / 三头鲨带 Combat 与战斗参数表（数值来源 GameSpec §12 / 钓鱼表）
  it("test_forest_species_implemented_with_combat", function()
    local fish = cfg.Fish
    local normals = { 'item49', 'item50', 'item51', 'item52', 'item53', 'item54',
      'item55', 'item56', 'item57', 'item58', 'item59', 'item60' }
    for _, id in ipairs(normals) do
      assert.is_true(fish[id].implemented, id .. ' 未翻开 implemented')
      assert.is_nil(fish[id].Combat, id .. ' 普通 / 极品鱼不走战斗路径')
    end
    assert.is_true(fish.fish31Elite.implemented)
    assert.are.equal('swordfish', fish.fish31Elite.Combat)
    assert.is_true(fish.fish32Boss.implemented)
    assert.are.equal('shark', fish.fish32Boss.Combat)
    -- 剑鱼：左右挥头按表基础攻击 20；跳跃周期按表 50 秒、随机 10 米外落点、5 米范围 100
    local sword = cfg.FishCombat.swordfish
    assert.is_not_nil(sword, '缺 FishCombat.swordfish')
    assert.are.equal(20, sword.SwingDamage)
    assert.is_true(sword.SwingCooldownSec > 0, '挥头节拍须显式配置细化')
    assert.are.equal(50, sword.JumpIntervalSec)
    assert.are.equal(10, sword.JumpDistance)
    assert.are.equal(5, sword.JumpRadius)
    assert.are.equal(100, sword.JumpDamage)
    -- 三头鲨：扫头按表 25、冷却 3 秒；正文每 20 秒跳跃、随机 15 米外、10 米范围 200；翻滚接触 25
    local shark = cfg.FishCombat.shark
    assert.is_not_nil(shark, '缺 FishCombat.shark')
    assert.are.equal(25, shark.SweepDamage)
    assert.are.equal(3, shark.SweepCooldownSec)
    assert.are.equal(20, shark.JumpIntervalSec)
    assert.are.equal(15, shark.JumpDistance)
    assert.are.equal(10, shark.JumpRadius)
    assert.are.equal(200, shark.JumpDamage)
    assert.are.equal(25, shark.RollDamage)
  end)

  -- Z4_Shop 四级摊位：蚂蟥 / 普通鱼竿 / 冲锋枪与 4 级升级行上架
  it("test_z4_shop_stand_level4_shelves_forest_goods", function()
    local stand
    for _, row in ipairs(cfg.Shop.Stands) do
      if row.AnchorName == 'Z4_Shop' then stand = row end
    end
    assert.is_not_nil(stand, '缺 Z4_Shop 摊位')
    assert.are.equal(4, stand.Level)
    local gear = {}
    for _, row in ipairs(cfg.Shop.ListForPage(4, '钓具')) do gear[row.ItemId] = row.Price end
    assert.are.equal(4, gear.item116)
    assert.are.equal(50, gear.normalRod)
    local weapons = {}
    for _, row in ipairs(cfg.Shop.ListForPage(4, '武器')) do weapons[row.ItemId] = row.Price end
    assert.are.equal(500, weapons.item139)
    assert.are.equal(50, weapons.item144)
    local upgrades = {}
    for _, row in ipairs(cfg.Shop.ListForPage(4, '升级')) do upgrades[row.Name] = row.Price end
    assert.are.equal(800, upgrades['背包升级4'])
    assert.are.equal(1000, upgrades['远程武器升级2'])
    assert.are.equal(800, upgrades['弹容量升级2'])
    assert.are.equal(400, upgrades['近战武器升级4'])
    -- 三区摊位买不到 4 级新品
    local crabGear = {}
    for _, row in ipairs(cfg.Shop.ListForPage(3, '钓具')) do crabGear[row.ItemId] = true end
    assert.is_nil(crabGear.normalRod)
  end)

  -- 烧烤锚点预置（#137 的接入点）：场景合同第四区暴露 Grill 实体
  it("test_zone4_scene_contract_exposes_grill_anchor", function()
    local scene = cfg.Zones[4].Scene
    assert.are.equal('Z4_Grill', scene.GrillName)
    local grill
    for _, entity in ipairs(scene.Entities) do
      if entity.Role == 'Grill' then grill = entity end
    end
    assert.is_not_nil(grill)
    assert.are.equal('Z4_Grill', grill.Name)
  end)
end)

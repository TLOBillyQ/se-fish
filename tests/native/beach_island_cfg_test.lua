-- #142 沙滩岛最小内容接线（GameSpec §5.5/§8/§12、钓鱼表 R58–R71、
-- 商店表 R6/R7/R21/R30/R37/R44/R48、#121 裁定）：
-- 沙滩岛水区进 Water.Zones（中心 720,364、80×24，与树林岛水区不相交）；
-- 抽鱼池按原表 13 行（海参任意饵保底、海狗起椰子饵 + 专业鱼竿 5、海象入池权重 10）；
-- 首领饵 item124（海豹）必出虎鲸；14 鱼种翻开 implemented，海象 / 虎鲸带 Combat 与
-- 官方模型号（注册表 7000544–7000563 内，不虚构）；FishCombat 海象=甩头 25 + 40 秒突击
-- 20 米 120，虎鲸=爪 30/2 秒 + 虎啸 10 秒远程 30（未给伤的独立基础披露细化）+ 甩尾 10 秒 160 +
-- 鲸跃 25 秒落 15 米外、10 米范围 240；Z5_Shop 五级摊位上架椰子 / 专业鱼竿 / 自动步枪与 5 级
-- 升级行，锚点名与场景合同 ShopName 一致（灰盒锚点真可用）；场景合同第五区暴露 Z5_Grill；
-- 信物链 海象尾→海豹、虎头→礁石岛船票；第五区返程 270 金。
-- 失败方式（先列后写）：
--   1. 沙滩岛水区没进 Water.Zones / ZoneIdByWater（抛竿选不到沙滩岛鱼表），或与其他水区水平重叠；
--   2. 抽鱼池行错：不挂饵出不了海参保底、椰子饵竿 1 能出竿 5 的鱼、漏极品 / 海象行、
--      权重 / 竿级 / 饵与原表不符，或行指向不存在的鱼种；
--   3. 首领饵 item124 没登记（必出虎鲸失效）或登记错鱼种；
--   4. 14 鱼种 implemented 未翻开、海象 / 虎鲸缺 Combat 标签、Model 缺失或是注册表外的虚构号；
--   5. FishCombat 数值错（海象 甩头25 / 周期40秒 / 20米 / 120；虎鲸 爪30间隔2秒 / 虎啸10秒远程30 /
--      甩尾10秒160 / 鲸跃25秒15米外10米范围240），或预警细化参数未显式配置；
--   6. Z5_Shop 摊位缺失、Level 不是 5 或锚点名与场景合同 ShopName 不一致：
--      买不到椰子 / 专业鱼竿 / 自动步枪 / 5 级升级行；
--   7. 场景合同第五区缺烧烤锚点 Z5_Grill；
--   8. 信物链错（海象尾→海豹、虎头→礁石岛船票）或第五区返程票价不是 270 金。
-- 迁移自 tests/gameplay/beach_island_cfg_test.lua（#83）。旧 setUp 会把 GameCfg 从模块缓存摘下重装、
-- tearDown 装回，映射为逐例 before_each/after_each 以保留「setup 失败仍清理模块缓存」的行为；
-- it 的书写顺序沿用旧入口的方法名字典序，与迁移前逐条对账。
describe("TestBeachIslandCfg", function()
  local cfg, savedCfg

  before_each(function()
    savedCfg = package.loaded['common.GameCfg']
    package.loaded['common.GameCfg'] = nil
    cfg = require('common.GameCfg')
  end)

  after_each(function()
    package.loaded['common.GameCfg'] = savedCfg
  end)

  local function beachWater(cfg)
    for _, zone in ipairs(cfg.Water.Zones) do
      if zone.Id == 'beachIsland.water' then return zone end
    end
  end

  -- 战斗参数：海象甩头 25 / 40 秒突击 20 米 120；虎鲸四并集招式互斥不丢
  it("test_beach_fish_combat_params", function()
    -- 海象（#121 裁定：甩头按表基础攻击 25；突击周期按表 40 秒，正文冲锋 20 米、命中 120）
    local walrus = cfg.FishCombat.walrus
    assert.is_not_nil(walrus, '缺 FishCombat.walrus')
    assert.are.equal(25, walrus.SwingDamage)
    assert.is_true(walrus.SwingCooldownSec > 0, '甩头节拍须显式配置细化')
    assert.are.equal(40, walrus.ChargeSec)
    assert.are.equal(120, walrus.ChargeDamage)
    assert.are.equal(20, walrus.ChargeDistance)
    assert.is_true(walrus.ChargeWindupSec > 0, '突击前摇须显式配置细化')
    assert.is_true(walrus.ChargeContactRange > 0, '突击接触距离须显式配置细化')
    -- 虎鲸（#121 裁定：爪击按表 30、间隔 2 秒；表内每 10 秒虎啸远程攻击——未给伤，按独立
    -- 基础 30 披露细化；正文每 10 秒甩尾 160；跳跃周期按表 25 秒、随机 15 米外落点、
    -- 10 米范围 240。四招并集互斥，均不得丢）
    local orca = cfg.FishCombat.orca
    assert.is_not_nil(orca, '缺 FishCombat.orca')
    assert.are.equal(30, orca.ClawDamage)
    assert.are.equal(2, orca.ClawCooldownSec)
    assert.is_true(orca.ClawWindupSec > 0, '爪击前摇须显式配置细化')
    assert.are.equal(10, orca.RoarSec)
    assert.are.equal(30, orca.RoarDamage)
    assert.is_true(orca.RoarWindupSec > 0, '虎啸前摇须显式配置细化')
    assert.are.equal(10, orca.TailSec)
    assert.are.equal(160, orca.TailDamage)
    assert.is_true(orca.TailWindupSec > 0, '甩尾前摇须显式配置细化')
    assert.are.equal(25, orca.JumpIntervalSec)
    assert.are.equal(15, orca.JumpDistance)
    assert.are.equal(10, orca.JumpRadius)
    assert.are.equal(240, orca.JumpDamage)
  end)

  -- 水区注册：Id 取内容层 WaterId，矩形 80×24，中心 (720,364)，映射到 beachIsland 钓鱼区
  it("test_beach_island_water_zone_registered_and_disjoint", function()
    local water = beachWater(cfg)
    assert.is_not_nil(water, 'beachIsland.water 未进 Water.Zones')
    assert.are.equal(720, water.Center.x)
    assert.are.equal(364, water.Center.z)
    assert.are.equal(40, water.HalfX)
    assert.are.equal(12, water.HalfZ)
    assert.are.equal('number', type(water.SurfaceY))
    assert.are.equal('beachIsland', water.ZoneId)
    assert.are.equal('beachIsland', cfg.Water.ZoneIdByWater['beachIsland.water'])
    for _, zone in ipairs(cfg.Water.Zones) do
      if zone.Id ~= 'beachIsland.water' then
        local zx = zone.HalfX or zone.HalfXZ
        local zz = zone.HalfZ or zone.HalfXZ
        local dx = math.abs(zone.Center.x - water.Center.x)
        local dz = math.abs(zone.Center.z - water.Center.z)
        assert.is_true(dx > zx + water.HalfX or dz > zz + water.HalfZ,
          'beachIsland.water 与 ' .. zone.Id .. ' 水平重叠')
      end
    end
  end)

  -- 沙滩岛 14 行翻开 implemented；海象 / 虎鲸带 Combat 与官方模型号（注册表内，不虚构）
  it("test_beach_species_implemented_with_combat_and_real_models", function()
    local fish = cfg.Fish
    local models = cfg.FishCarrier.Models
    local normals = { 'item65', 'item66', 'item67', 'item68', 'item69', 'item70',
      'item71', 'item72', 'item73', 'item74', 'item75', 'item76' }
    for _, id in ipairs(normals) do
      assert.is_true(fish[id].implemented, id .. ' 未翻开 implemented')
      assert.is_nil(fish[id].Combat, id .. ' 普通 / 极品鱼不走战斗路径')
      assert.is_not_nil(models[fish[id].Model], id .. ' 模型号 ' .. tostring(fish[id].Model) .. ' 不在官方注册表')
    end
    assert.is_true(fish.fish39Elite.implemented)
    assert.are.equal('walrus', fish.fish39Elite.Combat)
    assert.is_not_nil(models[fish.fish39Elite.Model],
      '海象模型号 ' .. tostring(fish.fish39Elite.Model) .. ' 不在官方注册表')
    assert.is_true(fish.fish40Boss.implemented)
    assert.are.equal('orca', fish.fish40Boss.Combat)
    assert.is_not_nil(models[fish.fish40Boss.Model],
      '虎鲸模型号 ' .. tostring(fish.fish40Boss.Model) .. ' 不在官方注册表')
  end)

  -- 抽鱼池：13 行（普通 / 极品 12 + 海象），数值逐行钉原表；虎鲸由 BossBait 接管不入池
  it("test_casting_zone_matches_source_table", function()
    local rows = cfg.Casting.Zones['beachIsland.water']
    assert.is_not_nil(rows, '沙滩岛抽鱼池缺失')
    local expect = {
      { Id = 'item65', Bait = 0, RodLevel = 1, DrawWeight = 8 },
      { Id = 'item66', Bait = 'item117', RodLevel = 1, DrawWeight = 8 },
      { Id = 'item67', Bait = 'item117', RodLevel = 1, DrawWeight = 8 },
      { Id = 'item68', Bait = 'item117', RodLevel = 5, DrawWeight = 32 },
      { Id = 'item69', Bait = 'item117', RodLevel = 5, DrawWeight = 24 },
      { Id = 'item70', Bait = 'item117', RodLevel = 5, DrawWeight = 16 },
      { Id = 'item71', Bait = 0, RodLevel = 1, DrawWeight = 2 },
      { Id = 'item72', Bait = 'item117', RodLevel = 1, DrawWeight = 2 },
      { Id = 'item73', Bait = 'item117', RodLevel = 1, DrawWeight = 2 },
      { Id = 'item74', Bait = 'item117', RodLevel = 5, DrawWeight = 8 },
      { Id = 'item75', Bait = 'item117', RodLevel = 5, DrawWeight = 6 },
      { Id = 'item76', Bait = 'item117', RodLevel = 5, DrawWeight = 4 },
      { Id = 'fish39Elite', Bait = 'item117', RodLevel = 5, DrawWeight = 10 },
    }
    assert.are.equal(#expect, #rows)
    for index, row in ipairs(expect) do
      assert.are.equal(row.Id, rows[index].Id, '第 ' .. index .. ' 行鱼种')
      assert.are.equal(row.Bait, rows[index].Bait, row.Id .. ' 鱼饵')
      assert.are.equal(row.RodLevel, rows[index].RodLevel, row.Id .. ' 竿级')
      assert.are.equal(row.DrawWeight, rows[index].DrawWeight, row.Id .. ' 权重')
      assert.is_not_nil(cfg.Fish[row.Id], row.Id .. ' 不在鱼种表')
    end
    -- 保底与门槛：不挂饵只能出海参 / 极品海参；挂椰子竿 1 不出竿 5 的鱼
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
    assert.same({ item65 = true, item71 = true }, selectAll(1, nil))
    local baitRod1 = selectAll(1, 'item117')
    assert.same({ item65 = true, item66 = true, item67 = true,
      item71 = true, item72 = true, item73 = true }, baitRod1)
    local baitRod5 = selectAll(5, 'item117')
    assert.is_not_nil(baitRod5.item70)
    assert.is_not_nil(baitRod5.fish39Elite)
    -- 首领饵必出虎鲸（#88 口径：BossBait 键即首领饵物品 id）
    assert.are.equal('fish40Boss', cfg.Casting.BossBait.item124)
  end)

  -- 信物链与返程：海象尾→海豹、虎头→礁石岛船票；第五区返程 270 金
  it("test_exchange_chain_and_return_price", function()
    local chain = cfg.Content.Exchanges[5]
    assert.are.equal('beachIsland', chain.ZoneId)
    assert.are.equal('item79', chain.EliteToken)
    assert.are.equal('item124', chain.BossBait)
    assert.are.equal('fish40Boss', chain.BossFish)
    assert.are.equal('item80', chain.BossToken)
    assert.are.equal('item150', chain.Result)
    assert.same({ item79 = 'item124', item80 = 'item150' }, cfg.Interact.Fishermen[5].Exchange)
    local route
    for _, candidate in ipairs(cfg.Ferry.Routes) do
      if candidate.FromZoneId == 'forestIsland' and candidate.ToZoneId == 'beachIsland' then route = candidate end
    end
    assert.is_not_nil(route, '缺 树林岛→沙滩岛 航线')
    assert.are.equal(270, route.Return.Price)
    assert.are.equal('item149', route.Outbound.Ticket)
  end)

  -- Z5_Shop 五级摊位：椰子 / 专业鱼竿 / 自动步枪与 5 级升级行上架，锚点名与场景合同一致
  it("test_z5_shop_stand_level5_shelves_beach_goods", function()
    local stand
    for _, row in ipairs(cfg.Shop.Stands) do
      if row.AnchorName == 'Z5_Shop' then stand = row end
    end
    assert.is_not_nil(stand, '缺 Z5_Shop 摊位')
    assert.are.equal(5, stand.Level)
    assert.are.equal(cfg.Zones[5].Scene.ShopName, stand.AnchorName, '摊位锚点名与场景合同 ShopName 不一致')
    local gear = {}
    for _, row in ipairs(cfg.Shop.ListForPage(5, '钓具')) do gear[row.ItemId] = row.Price end
    assert.are.equal(5, gear.item117)
    assert.are.equal(100, gear.proRod)
    local weapons = {}
    for _, row in ipairs(cfg.Shop.ListForPage(5, '武器')) do weapons[row.ItemId] = row.Price end
    assert.are.equal(1000, weapons.item140)
    local upgrades = {}
    for _, row in ipairs(cfg.Shop.ListForPage(5, '升级')) do upgrades[row.Name] = row.Price end
    assert.are.equal(1600, upgrades['背包升级5'])
    assert.are.equal(2000, upgrades['远程武器升级3'])
    assert.are.equal(1600, upgrades['爆炸物升级2'])
    assert.are.equal(800, upgrades['近战武器升级5'])
    -- 四区摊位买不到 5 级新品
    local forestGear = {}
    for _, row in ipairs(cfg.Shop.ListForPage(4, '钓具')) do forestGear[row.ItemId] = true end
    assert.is_nil(forestGear.item117)
    assert.is_nil(forestGear.proRod)
  end)

  -- 烧烤锚点预置（#137 的接入点）：场景合同第五区暴露 Grill 实体
  it("test_zone5_scene_contract_exposes_grill_anchor", function()
    local scene = cfg.Zones[5].Scene
    assert.are.equal('Z5_Grill', scene.GrillName)
    local grill
    for _, entity in ipairs(scene.Entities) do
      if entity.Role == 'Grill' then grill = entity end
    end
    assert.is_not_nil(grill)
    assert.are.equal('Z5_Grill', grill.Name)
  end)
end)

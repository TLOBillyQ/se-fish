-- #142 沙滩岛最小内容接线（GameSpec §5.5/§8/§12、钓鱼表 R58–R71、
-- 商店表 R6/R7/R21/R30/R37/R44/R48、#121 裁定）：
-- 沙滩岛水区进 Water.Zones（中心 660,144、80×24，与树林岛水区不相交）；
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
local lu = require('luaunit')

TestBeachIslandCfg = {}

function TestBeachIslandCfg:setUp()
    self.savedCfg = package.loaded['common.GameCfg']
    package.loaded['common.GameCfg'] = nil
    self.cfg = require('common.GameCfg')
end

function TestBeachIslandCfg:tearDown()
    package.loaded['common.GameCfg'] = self.savedCfg
end

local function beachWater(cfg)
    for _, zone in ipairs(cfg.Water.Zones) do
        if zone.Id == 'beachIsland.water' then return zone end
    end
end

-- 水区注册：Id 取内容层 WaterId，矩形 80×24，中心 (660,144)，映射到 beachIsland 钓鱼区
function TestBeachIslandCfg:test_beach_island_water_zone_registered_and_disjoint()
    local water = beachWater(self.cfg)
    lu.assertNotNil(water, 'beachIsland.water 未进 Water.Zones')
    lu.assertEquals(water.Center.x, 660)
    lu.assertEquals(water.Center.z, 144)
    lu.assertEquals(water.HalfX, 40)
    lu.assertEquals(water.HalfZ, 12)
    lu.assertEquals(type(water.SurfaceY), 'number')
    lu.assertEquals(water.ZoneId, 'beachIsland')
    lu.assertEquals(self.cfg.Water.ZoneIdByWater['beachIsland.water'], 'beachIsland')
    for _, zone in ipairs(self.cfg.Water.Zones) do
        if zone.Id ~= 'beachIsland.water' then
            local zx = zone.HalfX or zone.HalfXZ
            local zz = zone.HalfZ or zone.HalfXZ
            local dx = math.abs(zone.Center.x - water.Center.x)
            local dz = math.abs(zone.Center.z - water.Center.z)
            lu.assertTrue(dx > zx + water.HalfX or dz > zz + water.HalfZ,
                'beachIsland.water 与 ' .. zone.Id .. ' 水平重叠')
        end
    end
end

-- 抽鱼池：13 行（普通 / 极品 12 + 海象），数值逐行钉原表；虎鲸由 BossBait 接管不入池
function TestBeachIslandCfg:test_casting_zone_matches_source_table()
    local rows = self.cfg.Casting.Zones['beachIsland.water']
    lu.assertNotNil(rows, '沙滩岛抽鱼池缺失')
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
    lu.assertEquals(#rows, #expect)
    for index, row in ipairs(expect) do
        lu.assertEquals(rows[index].Id, row.Id, '第 ' .. index .. ' 行鱼种')
        lu.assertEquals(rows[index].Bait, row.Bait, row.Id .. ' 鱼饵')
        lu.assertEquals(rows[index].RodLevel, row.RodLevel, row.Id .. ' 竿级')
        lu.assertEquals(rows[index].DrawWeight, row.DrawWeight, row.Id .. ' 权重')
        lu.assertNotNil(self.cfg.Fish[row.Id], row.Id .. ' 不在鱼种表')
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
    lu.assertEquals(selectAll(1, nil), { item65 = true, item71 = true })
    local baitRod1 = selectAll(1, 'item117')
    lu.assertEquals(baitRod1, { item65 = true, item66 = true, item67 = true,
        item71 = true, item72 = true, item73 = true })
    local baitRod5 = selectAll(5, 'item117')
    lu.assertNotNil(baitRod5.item70)
    lu.assertNotNil(baitRod5.fish39Elite)
    -- 首领饵必出虎鲸（#88 口径：BossBait 键即首领饵物品 id）
    lu.assertEquals(self.cfg.Casting.BossBait.item124, 'fish40Boss')
end

-- 沙滩岛 14 行翻开 implemented；海象 / 虎鲸带 Combat 与官方模型号（注册表内，不虚构）
function TestBeachIslandCfg:test_beach_species_implemented_with_combat_and_real_models()
    local fish = self.cfg.Fish
    local models = self.cfg.FishCarrier.Models
    local normals = { 'item65', 'item66', 'item67', 'item68', 'item69', 'item70',
        'item71', 'item72', 'item73', 'item74', 'item75', 'item76' }
    for _, id in ipairs(normals) do
        lu.assertTrue(fish[id].implemented, id .. ' 未翻开 implemented')
        lu.assertNil(fish[id].Combat, id .. ' 普通 / 极品鱼不走战斗路径')
        lu.assertNotNil(models[fish[id].Model], id .. ' 模型号 ' .. tostring(fish[id].Model) .. ' 不在官方注册表')
    end
    lu.assertTrue(fish.fish39Elite.implemented)
    lu.assertEquals(fish.fish39Elite.Combat, 'walrus')
    lu.assertNotNil(models[fish.fish39Elite.Model],
        '海象模型号 ' .. tostring(fish.fish39Elite.Model) .. ' 不在官方注册表')
    lu.assertTrue(fish.fish40Boss.implemented)
    lu.assertEquals(fish.fish40Boss.Combat, 'orca')
    lu.assertNotNil(models[fish.fish40Boss.Model],
        '虎鲸模型号 ' .. tostring(fish.fish40Boss.Model) .. ' 不在官方注册表')
end

-- 战斗参数：海象甩头 25 / 40 秒突击 20 米 120；虎鲸四并集招式互斥不丢
function TestBeachIslandCfg:test_beach_fish_combat_params()
    -- 海象（#121 裁定：甩头按表基础攻击 25；突击周期按表 40 秒，正文冲锋 20 米、命中 120）
    local walrus = self.cfg.FishCombat.walrus
    lu.assertNotNil(walrus, '缺 FishCombat.walrus')
    lu.assertEquals(walrus.SwingDamage, 25)
    lu.assertTrue(walrus.SwingCooldownSec > 0, '甩头节拍须显式配置细化')
    lu.assertEquals(walrus.ChargeSec, 40)
    lu.assertEquals(walrus.ChargeDamage, 120)
    lu.assertEquals(walrus.ChargeDistance, 20)
    lu.assertTrue(walrus.ChargeWindupSec > 0, '突击前摇须显式配置细化')
    lu.assertTrue(walrus.ChargeContactRange > 0, '突击接触距离须显式配置细化')
    -- 虎鲸（#121 裁定：爪击按表 30、间隔 2 秒；表内每 10 秒虎啸远程攻击——未给伤，按独立
    -- 基础 30 披露细化；正文每 10 秒甩尾 160；跳跃周期按表 25 秒、随机 15 米外落点、
    -- 10 米范围 240。四招并集互斥，均不得丢）
    local orca = self.cfg.FishCombat.orca
    lu.assertNotNil(orca, '缺 FishCombat.orca')
    lu.assertEquals(orca.ClawDamage, 30)
    lu.assertEquals(orca.ClawCooldownSec, 2)
    lu.assertTrue(orca.ClawWindupSec > 0, '爪击前摇须显式配置细化')
    lu.assertEquals(orca.RoarSec, 10)
    lu.assertEquals(orca.RoarDamage, 30)
    lu.assertTrue(orca.RoarWindupSec > 0, '虎啸前摇须显式配置细化')
    lu.assertEquals(orca.TailSec, 10)
    lu.assertEquals(orca.TailDamage, 160)
    lu.assertTrue(orca.TailWindupSec > 0, '甩尾前摇须显式配置细化')
    lu.assertEquals(orca.JumpIntervalSec, 25)
    lu.assertEquals(orca.JumpDistance, 15)
    lu.assertEquals(orca.JumpRadius, 10)
    lu.assertEquals(orca.JumpDamage, 240)
end

-- Z5_Shop 五级摊位：椰子 / 专业鱼竿 / 自动步枪与 5 级升级行上架，锚点名与场景合同一致
function TestBeachIslandCfg:test_z5_shop_stand_level5_shelves_beach_goods()
    local stand
    for _, row in ipairs(self.cfg.Shop.Stands) do
        if row.AnchorName == 'Z5_Shop' then stand = row end
    end
    lu.assertNotNil(stand, '缺 Z5_Shop 摊位')
    lu.assertEquals(stand.Level, 5)
    lu.assertEquals(stand.AnchorName, self.cfg.Zones[5].Scene.ShopName, '摊位锚点名与场景合同 ShopName 不一致')
    local gear = {}
    for _, row in ipairs(self.cfg.Shop.ListForPage(5, '钓具')) do gear[row.ItemId] = row.Price end
    lu.assertEquals(gear.item117, 5)
    lu.assertEquals(gear.proRod, 100)
    local weapons = {}
    for _, row in ipairs(self.cfg.Shop.ListForPage(5, '武器')) do weapons[row.ItemId] = row.Price end
    lu.assertEquals(weapons.item140, 1000)
    local upgrades = {}
    for _, row in ipairs(self.cfg.Shop.ListForPage(5, '升级')) do upgrades[row.Name] = row.Price end
    lu.assertEquals(upgrades['背包升级5'], 1600)
    lu.assertEquals(upgrades['远程武器升级3'], 2000)
    lu.assertEquals(upgrades['爆炸物升级2'], 1600)
    lu.assertEquals(upgrades['近战武器升级5'], 800)
    -- 四区摊位买不到 5 级新品
    local forestGear = {}
    for _, row in ipairs(self.cfg.Shop.ListForPage(4, '钓具')) do forestGear[row.ItemId] = true end
    lu.assertNil(forestGear.item117)
    lu.assertNil(forestGear.proRod)
end

-- 烧烤锚点预置（#137 的接入点）：场景合同第五区暴露 Grill 实体
function TestBeachIslandCfg:test_zone5_scene_contract_exposes_grill_anchor()
    local scene = self.cfg.Zones[5].Scene
    lu.assertEquals(scene.GrillName, 'Z5_Grill')
    local grill
    for _, entity in ipairs(scene.Entities) do
        if entity.Role == 'Grill' then grill = entity end
    end
    lu.assertNotNil(grill)
    lu.assertEquals(grill.Name, 'Z5_Grill')
end

-- 信物链与返程：海象尾→海豹、虎头→礁石岛船票；第五区返程 270 金
function TestBeachIslandCfg:test_exchange_chain_and_return_price()
    local chain = self.cfg.Content.Exchanges[5]
    lu.assertEquals(chain.ZoneId, 'beachIsland')
    lu.assertEquals(chain.EliteToken, 'item79')
    lu.assertEquals(chain.BossBait, 'item124')
    lu.assertEquals(chain.BossFish, 'fish40Boss')
    lu.assertEquals(chain.BossToken, 'item80')
    lu.assertEquals(chain.Result, 'item150')
    lu.assertEquals(self.cfg.Interact.Fishermen[5].Exchange, { item79 = 'item124', item80 = 'item150' })
    local route
    for _, candidate in ipairs(self.cfg.Ferry.Routes) do
        if candidate.FromZoneId == 'forestIsland' and candidate.ToZoneId == 'beachIsland' then route = candidate end
    end
    lu.assertNotNil(route, '缺 树林岛→沙滩岛 航线')
    lu.assertEquals(route.Return.Price, 270)
    lu.assertEquals(route.Outbound.Ticket, 'item149')
end

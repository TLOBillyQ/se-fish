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
local lu = require('luaunit')

TestForestIslandCfg = {}

function TestForestIslandCfg:setUp()
    self.savedCfg = package.loaded['common.GameCfg']
    package.loaded['common.GameCfg'] = nil
    self.cfg = require('common.GameCfg')
end

function TestForestIslandCfg:tearDown()
    package.loaded['common.GameCfg'] = self.savedCfg
end

local function forestWater(cfg)
    for _, zone in ipairs(cfg.Water.Zones) do
        if zone.Id == 'forestIsland.water' then return zone end
    end
end

-- 水区注册：Id 取内容层 WaterId，矩形 80×24，中心 (460,144)，映射到 forestIsland 钓鱼区
function TestForestIslandCfg:test_forest_island_water_zone_registered_and_disjoint()
    local water = forestWater(self.cfg)
    lu.assertNotNil(water, 'forestIsland.water 未进 Water.Zones')
    lu.assertEquals(water.Center.x, 460)
    lu.assertEquals(water.Center.z, 144)
    lu.assertEquals(water.HalfX, 40)
    lu.assertEquals(water.HalfZ, 12)
    lu.assertEquals(type(water.SurfaceY), 'number')
    lu.assertEquals(water.ZoneId, 'forestIsland')
    lu.assertEquals(self.cfg.Water.ZoneIdByWater['forestIsland.water'], 'forestIsland')
    for _, zone in ipairs(self.cfg.Water.Zones) do
        if zone.Id ~= 'forestIsland.water' then
            local zx = zone.HalfX or zone.HalfXZ
            local zz = zone.HalfZ or zone.HalfXZ
            local dx = math.abs(zone.Center.x - water.Center.x)
            local dz = math.abs(zone.Center.z - water.Center.z)
            lu.assertTrue(dx > zx + water.HalfX or dz > zz + water.HalfZ,
                'forestIsland.water 与 ' .. zone.Id .. ' 水平重叠')
        end
    end
end

-- 抽鱼池：13 行（普通 / 极品 12 + 剑鱼），数值逐行钉原表；首领鲨由 BossBait 接管不入池
function TestForestIslandCfg:test_casting_zone_matches_source_table()
    local rows = self.cfg.Casting.Zones['forestIsland.water']
    lu.assertNotNil(rows, '树林岛抽鱼池缺失')
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
    lu.assertEquals(#rows, #expect)
    for index, row in ipairs(expect) do
        lu.assertEquals(rows[index].Id, row.Id, '第 ' .. index .. ' 行鱼种')
        lu.assertEquals(rows[index].Bait, row.Bait, row.Id .. ' 鱼饵')
        lu.assertEquals(rows[index].RodLevel, row.RodLevel, row.Id .. ' 竿级')
        lu.assertEquals(rows[index].DrawWeight, row.DrawWeight, row.Id .. ' 权重')
        lu.assertNotNil(self.cfg.Fish[row.Id], row.Id .. ' 不在鱼种表')
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
    lu.assertEquals(selectAll(1, nil), { item49 = true, item55 = true })
    local baitRod1 = selectAll(1, 'item116')
    lu.assertEquals(baitRod1, { item49 = true, item50 = true, item51 = true,
        item55 = true, item56 = true, item57 = true })
    local baitRod4 = selectAll(4, 'item116')
    lu.assertNotNil(baitRod4.item54)
    lu.assertNotNil(baitRod4.fish31Elite)
    -- 首领饵必出三头鲨（#88 口径：BossBait 键即首领饵物品 id）
    lu.assertEquals(self.cfg.Casting.BossBait.item123, 'fish32Boss')
end

-- 树林岛 14 行翻开 implemented；剑鱼 / 三头鲨带 Combat 与战斗参数表（数值来源 GameSpec §12 / 钓鱼表）
function TestForestIslandCfg:test_forest_species_implemented_with_combat()
    local fish = self.cfg.Fish
    local normals = { 'item49', 'item50', 'item51', 'item52', 'item53', 'item54',
        'item55', 'item56', 'item57', 'item58', 'item59', 'item60' }
    for _, id in ipairs(normals) do
        lu.assertTrue(fish[id].implemented, id .. ' 未翻开 implemented')
        lu.assertNil(fish[id].Combat, id .. ' 普通 / 极品鱼不走战斗路径')
    end
    lu.assertTrue(fish.fish31Elite.implemented)
    lu.assertEquals(fish.fish31Elite.Combat, 'swordfish')
    lu.assertTrue(fish.fish32Boss.implemented)
    lu.assertEquals(fish.fish32Boss.Combat, 'shark')
    -- 剑鱼：左右挥头按表基础攻击 20；跳跃周期按表 50 秒、随机 10 米外落点、5 米范围 100
    local sword = self.cfg.FishCombat.swordfish
    lu.assertNotNil(sword, '缺 FishCombat.swordfish')
    lu.assertEquals(sword.SwingDamage, 20)
    lu.assertTrue(sword.SwingCooldownSec > 0, '挥头节拍须显式配置细化')
    lu.assertEquals(sword.JumpIntervalSec, 50)
    lu.assertEquals(sword.JumpDistance, 10)
    lu.assertEquals(sword.JumpRadius, 5)
    lu.assertEquals(sword.JumpDamage, 100)
    -- 三头鲨：扫头按表 25、冷却 3 秒；正文每 20 秒跳跃、随机 15 米外、10 米范围 200；翻滚接触 25
    local shark = self.cfg.FishCombat.shark
    lu.assertNotNil(shark, '缺 FishCombat.shark')
    lu.assertEquals(shark.SweepDamage, 25)
    lu.assertEquals(shark.SweepCooldownSec, 3)
    lu.assertEquals(shark.JumpIntervalSec, 20)
    lu.assertEquals(shark.JumpDistance, 15)
    lu.assertEquals(shark.JumpRadius, 10)
    lu.assertEquals(shark.JumpDamage, 200)
    lu.assertEquals(shark.RollDamage, 25)
end

-- Z4_Shop 四级摊位：蚂蟥 / 普通鱼竿 / 冲锋枪与 4 级升级行上架
function TestForestIslandCfg:test_z4_shop_stand_level4_shelves_forest_goods()
    local stand
    for _, row in ipairs(self.cfg.Shop.Stands) do
        if row.AnchorName == 'Z4_Shop' then stand = row end
    end
    lu.assertNotNil(stand, '缺 Z4_Shop 摊位')
    lu.assertEquals(stand.Level, 4)
    local gear = {}
    for _, row in ipairs(self.cfg.Shop.ListForPage(4, '钓具')) do gear[row.ItemId] = row.Price end
    lu.assertEquals(gear.item116, 4)
    lu.assertEquals(gear.normalRod, 50)
    local weapons = {}
    for _, row in ipairs(self.cfg.Shop.ListForPage(4, '武器')) do weapons[row.ItemId] = row.Price end
    lu.assertEquals(weapons.item139, 500)
    lu.assertEquals(weapons.item144, 50)
    local upgrades = {}
    for _, row in ipairs(self.cfg.Shop.ListForPage(4, '升级')) do upgrades[row.Name] = row.Price end
    lu.assertEquals(upgrades['背包升级4'], 800)
    lu.assertEquals(upgrades['远程武器升级2'], 1000)
    lu.assertEquals(upgrades['弹容量升级2'], 800)
    lu.assertEquals(upgrades['近战武器升级4'], 400)
    -- 三区摊位买不到 4 级新品
    local crabGear = {}
    for _, row in ipairs(self.cfg.Shop.ListForPage(3, '钓具')) do crabGear[row.ItemId] = true end
    lu.assertNil(crabGear.normalRod)
end

-- 烧烤锚点预置（#137 的接入点）：场景合同第四区暴露 Grill 实体
function TestForestIslandCfg:test_zone4_scene_contract_exposes_grill_anchor()
    local scene = self.cfg.Zones[4].Scene
    lu.assertEquals(scene.GrillName, 'Z4_Grill')
    local grill
    for _, entity in ipairs(scene.Entities) do
        if entity.Role == 'Grill' then grill = entity end
    end
    lu.assertNotNil(grill)
    lu.assertEquals(grill.Name, 'Z4_Grill')
end

-- 信物链与返程：鱼剑→牛腿、三联鲨鱼头→沙滩岛船票；第 4 区返程 90 金
function TestForestIslandCfg:test_exchange_chain_and_return_price()
    local chain = self.cfg.Content.Exchanges[4]
    lu.assertEquals(chain.ZoneId, 'forestIsland')
    lu.assertEquals(chain.EliteToken, 'item63')
    lu.assertEquals(chain.BossBait, 'item123')
    lu.assertEquals(chain.BossToken, 'item64')
    lu.assertEquals(chain.Result, 'item149')
    lu.assertEquals(self.cfg.Interact.Fishermen[4].Exchange, { item63 = 'item123', item64 = 'item149' })
    local route
    for _, candidate in ipairs(self.cfg.Ferry.Routes) do
        if candidate.FromZoneId == 'crabLake' and candidate.ToZoneId == 'forestIsland' then route = candidate end
    end
    lu.assertNotNil(route, '缺 蟹湖→树林岛 航线')
    lu.assertEquals(route.Return.Price, 90)
    lu.assertEquals(route.Outbound.Ticket, 'item148')
end

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
local lu = require('luaunit')

TestCrabLakeCfg = {}

function TestCrabLakeCfg:setUp()
    self.savedCfg = package.loaded['common.GameCfg']
    package.loaded['common.GameCfg'] = nil
    self.cfg = require('common.GameCfg')
end

function TestCrabLakeCfg:tearDown()
    package.loaded['common.GameCfg'] = self.savedCfg
end

local function crabWater(cfg)
    for _, zone in ipairs(cfg.Water.Zones) do
        if zone.Id == 'crabLake.water' then return zone end
    end
end

-- 水区注册：Id 取内容层 WaterId，矩形 80×24，中心 (260,144)，映射到 crabLake 钓鱼区
function TestCrabLakeCfg:test_crab_lake_water_zone_registered_and_disjoint()
    local water = crabWater(self.cfg)
    lu.assertNotNil(water, 'crabLake.water 未进 Water.Zones')
    lu.assertEquals(water.Center.x, 260)
    lu.assertEquals(water.Center.z, 144)
    lu.assertEquals(water.HalfX, 40)
    lu.assertEquals(water.HalfZ, 12)
    lu.assertEquals(type(water.SurfaceY), 'number')
    lu.assertEquals(water.ZoneId, 'crabLake')
    lu.assertEquals(self.cfg.Water.ZoneIdByWater['crabLake.water'], 'crabLake')
    for _, zone in ipairs(self.cfg.Water.Zones) do
        if zone.Id ~= 'crabLake.water' then
            local zx = zone.HalfX or zone.HalfXZ
            local zz = zone.HalfZ or zone.HalfXZ
            local dx = math.abs(zone.Center.x - water.Center.x)
            local dz = math.abs(zone.Center.z - water.Center.z)
            lu.assertTrue(dx > zx + water.HalfX or dz > zz + water.HalfZ,
                'crabLake.water 与 ' .. zone.Id .. ' 水平重叠')
        end
    end
end

-- 抽鱼池：13 行（普通/极品 12 + 帝王蟹），数值逐行钉原表；首领饵由 BossBait 接管不入池
function TestCrabLakeCfg:test_casting_zone_matches_source_table()
    local rows = self.cfg.Casting.Zones['crabLake.water']
    lu.assertNotNil(rows, '蟹湖抽鱼池缺失')
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
    lu.assertEquals(#rows, #expect)
    for index, row in ipairs(expect) do
        lu.assertEquals(rows[index].Id, row.Id, '第 ' .. index .. ' 行鱼种')
        lu.assertEquals(rows[index].Bait, row.Bait, row.Id .. ' 鱼饵')
        lu.assertEquals(rows[index].RodLevel, row.RodLevel, row.Id .. ' 竿级')
        lu.assertEquals(rows[index].DrawWeight, row.DrawWeight, row.Id .. ' 权重')
        lu.assertNotNil(self.cfg.Fish[row.Id], row.Id .. ' 不在鱼种表')
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
    lu.assertEquals(noBait, { item33 = true, item39 = true })
    local baitRod1 = selectAll(1, 'item115')
    lu.assertEquals(baitRod1, { item33 = true, item34 = true, item35 = true,
        item39 = true, item40 = true, item41 = true })
    local baitRod3 = selectAll(3, 'item115')
    lu.assertNotNil(baitRod3.item38)
    lu.assertNotNil(baitRod3.fish23Elite)
    -- 首领饵必出蟹老板（#88 口径：BossBait 键即首领饵物品 id）
    lu.assertEquals(self.cfg.Casting.BossBait.item122, 'fish24Boss')
end

-- 蟹湖 14 行翻开 implemented 并配模型；帝王蟹 / 蟹老板带 Combat 与战斗参数表
function TestCrabLakeCfg:test_crab_species_implemented_with_models_and_combat()
    local fish = self.cfg.Fish
    local normals = { 'item33', 'item34', 'item35', 'item36', 'item37', 'item38',
        'item39', 'item40', 'item41', 'item42', 'item43', 'item44' }
    for _, id in ipairs(normals) do
        lu.assertTrue(fish[id].implemented, id .. ' 未翻开 implemented')
        lu.assertEquals(fish[id].Model, '7000554', id .. ' 复用官方螃蟹模型')
        lu.assertNil(fish[id].Combat, id .. ' 普通/极品蟹不走战斗路径')
    end
    lu.assertTrue(fish.fish23Elite.implemented)
    lu.assertEquals(fish.fish23Elite.Model, '7000554')
    lu.assertEquals(fish.fish23Elite.Combat, 'kingCrab')
    lu.assertTrue(fish.fish24Boss.implemented)
    lu.assertEquals(fish.fish24Boss.Model, '7000554')
    lu.assertEquals(fish.fish24Boss.Combat, 'crabBoss')
    -- 战斗参数表（数值来源 GameSpec §12 正文与钓鱼表）
    local king = self.cfg.FishCombat.kingCrab
    lu.assertNotNil(king, '缺 FishCombat.kingCrab')
    lu.assertEquals(king.JabIntervalSec, 5)
    lu.assertEquals(king.JabsPerSide, 3)
    lu.assertEquals(king.JabStepSec, 0.2)
    lu.assertEquals(king.JabDamage, 15)
    lu.assertEquals(king.ActiveSec, 30)
    lu.assertEquals(king.StunSec, 5)
    local boss = self.cfg.FishCombat.crabBoss
    lu.assertNotNil(boss, '缺 FishCombat.crabBoss')
    lu.assertEquals(boss.PinchDamage, 20)
    lu.assertEquals(boss.PinchCooldownSec, 4)
    lu.assertEquals(boss.ChargeSec, 30)
    lu.assertEquals(boss.SpinSec, 25)
    lu.assertEquals(boss.SpinDurationSec, 5)
    lu.assertEquals(boss.SpinDamage, 30)
    -- 蟹老板饵是首领饵：不走 Bait 计数库存，不可按只回收（沿用既有口径）
    local items = require('common.cfg.Items')
    lu.assertTrue(items.Definitions.item122.BossBait)
    lu.assertNil(items.Definitions.item122.Container)
    lu.assertNil(self.cfg.Interact.Fisherman.BaitPrice.item122)
end

-- Z3_Shop 三级摊位：鲱鱼罐头 / 捕蟹竿 / 霰弹枪与 3 级升级行上架
function TestCrabLakeCfg:test_z3_shop_stand_level3_shelves_crab_goods()
    local stand
    for _, row in ipairs(self.cfg.Shop.Stands) do
        if row.AnchorName == 'Z3_Shop' then stand = row end
    end
    lu.assertNotNil(stand, '缺 Z3_Shop 摊位')
    lu.assertEquals(stand.Level, 3)
    local gear = {}
    for _, row in ipairs(self.cfg.Shop.ListForPage(3, '钓具')) do gear[row.ItemId] = row.Price end
    lu.assertEquals(gear.item115, 3)
    lu.assertEquals(gear.crabRod, 24)
    local weapons = {}
    for _, row in ipairs(self.cfg.Shop.ListForPage(3, '武器')) do weapons[row.ItemId] = row.Price end
    lu.assertEquals(weapons.item138, 200)
    local upgrades = {}
    for _, row in ipairs(self.cfg.Shop.ListForPage(3, '升级')) do upgrades[row.Name] = row.Price end
    lu.assertEquals(upgrades['远程武器升级1'], 500)
    lu.assertEquals(upgrades['爆炸物升级1'], 400)
    lu.assertEquals(upgrades['近战武器升级3'], 200)
    lu.assertEquals(upgrades['背包升级3'], 400)
    -- 一二区摊位买不到 3 级新品
    local pondGear = {}
    for _, row in ipairs(self.cfg.Shop.ListForPage(1, '钓具')) do pondGear[row.ItemId] = true end
    lu.assertNil(pondGear.item115)
    lu.assertNil(pondGear.crabRod)
end

-- 烧烤锚点预置（#137 的接入点）：场景合同第三区暴露 Grill 实体
function TestCrabLakeCfg:test_zone3_scene_contract_exposes_grill_anchor()
    local scene = self.cfg.Zones[3].Scene
    lu.assertEquals(scene.GrillName, 'Z3_Grill')
    local grill
    for _, entity in ipairs(scene.Entities) do
        if entity.Role == 'Grill' then grill = entity end
    end
    lu.assertNotNil(grill)
    lu.assertEquals(grill.Name, 'Z3_Grill')
    lu.assertEquals(grill.Position, { x = 250, y = 5, z = 90 })
end

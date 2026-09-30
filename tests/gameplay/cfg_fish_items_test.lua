-- #122 配置公开返回值是本切片约定的测试接缝。
-- 失败方式（先列后写）：
--   1. 录入漏行，或普通/极品复用编号覆盖，图鉴与物品数量不足；
--   2. 稳定键、源表编号、来源行丢失，无法定位冲突或关联其他配置；
--   3. 鱼饵/掉落引用不存在、掉落数量无效，钓取或结算中途报错；
--   4. 旧 v1 ID 丢失或被改指向另一物品，旧存档财产无法恢复；
--   5. 自行纠正极品鲶鱼/鲈鱼/奶龙/蛇颈龙数值，或 Q10 改名误改售价；
--   6. 未实现内容冒充可用，负恢复鱼饵丢符号，非食物误进入普通食用。
local lu = require('luaunit')

TestCfgFishItems = {}

local function count(rows)
    local total = 0
    for _ in pairs(rows) do total = total + 1 end
    return total
end

function TestCfgFishItems:testItemCatalogPreservesEverySourceRow()
    local items = require('common.cfg.Items')
    lu.assertEquals(count(items.Definitions), 171)
    local seen = {}
    for id, row in pairs(items.Definitions) do
        lu.assertEquals(type(id), 'string')
        lu.assertNotNil(id:match('^[a-z][A-Za-z0-9]*$'))
        lu.assertEquals(row.Id, id)
        lu.assertIsNumber(row.SourceId)
        lu.assertNil(seen[row.SourceId], row.source)
        seen[row.SourceId] = true
        lu.assertEquals(row.source, '物品表!R' .. (row.SourceId + 1))
        lu.assertEquals(items.SourceIdMap[row.SourceId], id)
        lu.assertEquals(type(row.implemented), 'boolean')
    end
    for sourceId = 1, 171 do lu.assertTrue(seen[sourceId]) end
end

function TestCfgFishItems:testFishCatalogKeepsAllGradesWithoutOverwritingRepeatedNumbers()
    local fish = require('common.cfg.Fish')
    local items = require('common.cfg.Items')
    lu.assertEquals(count(fish.Definitions), 98)
    local sourceRows, sourceKeys, zones = {}, {}, {}
    local grades = { normal = 0, rare = 0, elite = 0, boss = 0 }
    for id, row in pairs(fish.Definitions) do
        lu.assertEquals(row.Id, id)
        lu.assertEquals(type(id), 'string')
        lu.assertNotNil(id:match('^[a-z][A-Za-z0-9]*$'))
        lu.assertNotNil(row.source:match('^钓鱼表!R%d+$'))
        lu.assertNil(sourceRows[row.source], row.source)
        sourceRows[row.source] = true
        local sourceKey = row.SourceId .. ':' .. row.Grade
        lu.assertNil(sourceKeys[sourceKey], row.source)
        sourceKeys[sourceKey] = true
        lu.assertEquals(fish.SourceIdMap[sourceKey], id)
        grades[row.Grade] = grades[row.Grade] + 1
        zones[row.ZoneId] = (zones[row.ZoneId] or 0) + 1
        lu.assertEquals(type(row.WaterId), 'string')
        lu.assertEquals(type(row.implemented), 'boolean')
        lu.assertTrue(row.Health > 0 and row.BaseWeight > 0, row.source)
        lu.assertTrue(row.DrawWeight > 0 and row.DrawWeight % 1 == 0, row.source)
        lu.assertTrue(row.RodLevel >= 1 and row.RodLevel <= 7, row.source)
        lu.assertTrue(row.Bait == 0 or items.Definitions[row.Bait] ~= nil, row.source)
        lu.assertTrue(#row.Drops > 0, row.source)
        for _, drop in ipairs(row.Drops) do
            lu.assertNotNil(items.Definitions[drop.ItemId], row.source)
            lu.assertTrue(drop.Count > 0 and drop.Count % 1 == 0, row.source)
        end
    end
    lu.assertEquals(grades, { normal = 42, rare = 42, elite = 7, boss = 7 })
    lu.assertEquals(count(zones), 7)
    for _, zoneCount in pairs(zones) do lu.assertEquals(zoneCount, 14) end
    for sourceRow = 2, 99 do lu.assertTrue(sourceRows['钓鱼表!R' .. sourceRow]) end
end

function TestCfgFishItems:testLegacyV1InventoryAndFishIdsStillResolve()
    local items = require('common.cfg.Items')
    local fish = require('common.cfg.Fish')
    -- 固定的 v1 存档样本；不能从新配置反推旧 ID，否则漏映射也会通过。
    local oldItemIds = {
        'tilapia', 'carp', 'knifeFish', 'bass', 'catfish', 'goldfish',
        'worm', 'sausage', 'starterRod', 'shrimp', 'riverShrimp', 'crayfish',
        'bostonLobster', 'aussieLobster', 'milkLobster', 'rareShrimp', 'rareRiverShrimp',
        'rareCrayfish', 'rareBostonLobster', 'rareAussieLobster', 'rareMilkLobster',
        'eelMeat', 'eelHead', 'garMeat', 'garHead', 'duck', 'shrimpTicket',
        'shrimpRod', 'crabRod', 'normalRod', 'proRod', 'airforceRod', 'unscientificRod',
    }
    for _, oldId in ipairs(oldItemIds) do
        lu.assertEquals(items.LegacyIdMap[oldId], oldId, oldId)
        lu.assertNotNil(items.Definitions[items.LegacyIdMap[oldId]], oldId)
    end
    local oldFishIds = {
        'tilapia', 'carp', 'knifeFish', 'bass', 'catfish', 'goldfish', 'eel', 'alligatorGar',
        'shrimp', 'riverShrimp', 'crayfish', 'bostonLobster', 'aussieLobster', 'milkLobster',
        'rareShrimp', 'rareRiverShrimp', 'rareCrayfish', 'rareBostonLobster', 'rareAussieLobster', 'rareMilkLobster',
    }
    for _, oldId in ipairs(oldFishIds) do
        lu.assertEquals(fish.LegacyIdMap[oldId], oldId, oldId)
        lu.assertNotNil(fish.Definitions[fish.LegacyIdMap[oldId]], oldId)
    end
end

function TestCfgFishItems:testConfirmedNamesAndUnusualSourceNumbersArePreserved()
    local fish = require('common.cfg.Fish')
    local items = require('common.cfg.Items')
    local catfish = fish.Definitions[fish.SourceIdMap['4:rare']]
    local bass = fish.Definitions[fish.SourceIdMap['5:rare']]
    lu.assertEquals({ catfish.Name, catfish.Health, catfish.BaseWeight, catfish.BasePrice }, { '极品鲶鱼', 20, 2, 6 })
    lu.assertEquals({ bass.Name, bass.Health, bass.BaseWeight, bass.BasePrice }, { '极品鲈鱼', 25, 5, 7 })
    lu.assertEquals(fish.Definitions.rareMilkLobster.BaseWeight, 50)
    lu.assertEquals(fish.Definitions[fish.SourceIdMap['53:rare']].BaseWeight, 10000)
    local renamed = {
        [64] = { '三联鲨鱼头', 500, 100 },
        [93] = { '鹰翅膀', 1000, 50 },
        [109] = { '沧龙翅', 2000, 50 },
        [111] = { '沧龙尾', 4000, 50 },
    }
    for sourceId, expected in pairs(renamed) do
        local row = items.Definitions[items.SourceIdMap[sourceId]]
        lu.assertEquals({ row.Name, row.BasePrice, row.EatPercent }, expected, row.source)
    end
    lu.assertEquals(items.Definitions.shrimpTicket.Name, '虾池船票')
    lu.assertEquals(items.Definitions[items.SourceIdMap[147]].Name, '蟹湖船票')
end

function TestCfgFishItems:testBossAndSameNameSpecialItemKeepSeparateIdentities()
    local fish = require('common.cfg.Fish')
    local items = require('common.cfg.Items')
    local bossId = fish.SourceIdMap['56:boss']
    local specialItemId = items.SourceIdMap[170]
    lu.assertNotEquals(bossId, specialItemId)
    lu.assertEquals(fish.Definitions[bossId].Grade, 'boss')
    lu.assertEquals(items.Definitions[specialItemId].Type, '特殊道具')
end

function TestCfgFishItems:testUnimplementedContentAndInventorySemanticsRemainExplicit()
    local fish = require('common.cfg.Fish')
    local items = require('common.cfg.Items')
    for _, row in pairs(fish.Definitions) do
        -- #136：蟹湖 14 行已随本单实装；其余未实装区与全部精英/首领仍保持 implemented=false
        if row.ZoneId ~= 'fishPond' and row.ZoneId ~= 'shrimpPond' and row.ZoneId ~= 'crabLake'
            or row.Grade == 'elite' or row.Grade == 'boss' then
            if row.Id ~= 'fish23Elite' and row.Id ~= 'fish24Boss' then
                lu.assertFalse(row.implemented, row.source)
            end
        end
    end
    for sourceId = 152, 171 do
        lu.assertFalse(items.Definitions[items.SourceIdMap[sourceId]].implemented)
    end
    for sourceId = 113, 119 do
        lu.assertEquals(items.Definitions[items.SourceIdMap[sourceId]].Container, 'bait')
    end
    for sourceId = 120, 126 do
        local row = items.Definitions[items.SourceIdMap[sourceId]]
        lu.assertTrue(row.BossBait)
        lu.assertNil(row.Container)
    end
    for sourceId, expected in pairs({ [119] = -20, [121] = -20, [122] = -10, [126] = -99 }) do
        lu.assertEquals(items.Definitions[items.SourceIdMap[sourceId]].EatPercent, expected)
    end
    for sourceId = 127, 171 do
        lu.assertNil(items.Definitions[items.SourceIdMap[sourceId]].EatPercent)
    end
    lu.assertEquals(items.Definitions.sausage.EatPercent, 5)
end

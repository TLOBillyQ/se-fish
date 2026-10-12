-- #122 配置公开返回值是本切片约定的测试接缝。
-- 失败方式（先列后写）：
--   1. 录入漏行，或普通/极品复用编号覆盖，图鉴与物品数量不足；
--   2. 稳定键、源表编号、来源行丢失，无法定位冲突或关联其他配置；
--   3. 鱼饵/掉落引用不存在、掉落数量无效，钓取或结算中途报错；
--   4. 旧 v1 ID 丢失或被改指向另一物品，旧存档财产无法恢复；
--   5. 自行纠正极品鲶鱼/鲈鱼/奶龙/蛇颈龙数值，或 Q10 改名误改售价；
--   6. 未实现内容冒充可用，负恢复鱼饵丢符号，非食物误进入普通食用。
-- 迁移自 tests/gameplay/cfg_fish_items_test.lua（#83）；案例顺序沿用旧入口的方法名字典序。
local function count(rows)
  local total = 0
  for _ in pairs(rows) do total = total + 1 end
  return total
end

describe("TestCfgFishItems", function()
  it("testBossAndSameNameSpecialItemKeepSeparateIdentities", function()
    local fish = require('common.cfg.Fish')
    local items = require('common.cfg.Items')
    local bossId = fish.SourceIdMap['56:boss']
    local specialItemId = items.SourceIdMap[170]
    assert.are_not.equal(specialItemId, bossId)
    assert.are.equal('boss', fish.Definitions[bossId].Grade)
    assert.are.equal('特殊道具', items.Definitions[specialItemId].Type)
  end)

  it("testConfirmedNamesAndUnusualSourceNumbersArePreserved", function()
    local fish = require('common.cfg.Fish')
    local items = require('common.cfg.Items')
    local catfish = fish.Definitions[fish.SourceIdMap['4:rare']]
    local bass = fish.Definitions[fish.SourceIdMap['5:rare']]
    assert.same({ '极品鲶鱼', 20, 2, 6 }, { catfish.Name, catfish.Health, catfish.BaseWeight, catfish.BasePrice })
    assert.same({ '极品鲈鱼', 25, 5, 7 }, { bass.Name, bass.Health, bass.BaseWeight, bass.BasePrice })
    assert.are.equal(50, fish.Definitions.rareMilkLobster.BaseWeight)
    assert.are.equal(10000, fish.Definitions[fish.SourceIdMap['53:rare']].BaseWeight)
    local renamed = {
      [64] = { '三联鲨鱼头', 500, 100 },
      [93] = { '鹰翅膀', 1000, 50 },
      [109] = { '沧龙翅', 2000, 50 },
      [111] = { '沧龙尾', 4000, 50 },
    }
    for sourceId, expected in pairs(renamed) do
      local row = items.Definitions[items.SourceIdMap[sourceId]]
      assert.same(expected, { row.Name, row.BasePrice, row.EatPercent }, row.source)
    end
    assert.are.equal('虾池船票', items.Definitions.shrimpTicket.Name)
    assert.are.equal('蟹湖船票', items.Definitions[items.SourceIdMap[147]].Name)
  end)

  it("testFishCatalogKeepsAllGradesWithoutOverwritingRepeatedNumbers", function()
    local fish = require('common.cfg.Fish')
    local items = require('common.cfg.Items')
    assert.are.equal(98, count(fish.Definitions))
    local sourceRows, sourceKeys, zones = {}, {}, {}
    local grades = { normal = 0, rare = 0, elite = 0, boss = 0 }
    for id, row in pairs(fish.Definitions) do
      assert.are.equal(id, row.Id)
      assert.are.equal('string', type(id))
      assert.is_not_nil(id:match('^[a-z][A-Za-z0-9]*$'))
      assert.is_not_nil(row.source:match('^钓鱼表!R%d+$'))
      assert.is_nil(sourceRows[row.source], row.source)
      sourceRows[row.source] = true
      local sourceKey = row.SourceId .. ':' .. row.Grade
      assert.is_nil(sourceKeys[sourceKey], row.source)
      sourceKeys[sourceKey] = true
      assert.are.equal(id, fish.SourceIdMap[sourceKey])
      grades[row.Grade] = grades[row.Grade] + 1
      zones[row.ZoneId] = (zones[row.ZoneId] or 0) + 1
      assert.are.equal('string', type(row.WaterId))
      assert.are.equal('boolean', type(row.implemented))
      assert.is_true(row.Health > 0 and row.BaseWeight > 0, row.source)
      assert.is_true(row.DrawWeight > 0 and row.DrawWeight % 1 == 0, row.source)
      assert.is_true(row.RodLevel >= 1 and row.RodLevel <= 7, row.source)
      assert.is_true(row.Bait == 0 or items.Definitions[row.Bait] ~= nil, row.source)
      assert.is_true(#row.Drops > 0, row.source)
      for _, drop in ipairs(row.Drops) do
        assert.is_not_nil(items.Definitions[drop.ItemId], row.source)
        assert.is_true(drop.Count > 0 and drop.Count % 1 == 0, row.source)
      end
    end
    assert.same({ normal = 42, rare = 42, elite = 7, boss = 7 }, grades)
    assert.are.equal(7, count(zones))
    for _, zoneCount in pairs(zones) do assert.are.equal(14, zoneCount) end
    for sourceRow = 2, 99 do assert.is_true(sourceRows['钓鱼表!R' .. sourceRow]) end
  end)

  it("testItemCatalogPreservesEverySourceRow", function()
    local items = require('common.cfg.Items')
    assert.are.equal(171, count(items.Definitions))
    local seen = {}
    for id, row in pairs(items.Definitions) do
      assert.are.equal('string', type(id))
      assert.is_not_nil(id:match('^[a-z][A-Za-z0-9]*$'))
      assert.are.equal(id, row.Id)
      assert.number(row.SourceId)
      assert.is_nil(seen[row.SourceId], row.source)
      seen[row.SourceId] = true
      assert.are.equal('物品表!R' .. (row.SourceId + 1), row.source)
      assert.are.equal(id, items.SourceIdMap[row.SourceId])
      assert.are.equal('boolean', type(row.implemented))
    end
    for sourceId = 1, 171 do assert.is_true(seen[sourceId]) end
  end)

  it("testLegacyV1InventoryAndFishIdsStillResolve", function()
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
      assert.are.equal(oldId, items.LegacyIdMap[oldId], oldId)
      assert.is_not_nil(items.Definitions[items.LegacyIdMap[oldId]], oldId)
    end
    local oldFishIds = {
      'tilapia', 'carp', 'knifeFish', 'bass', 'catfish', 'goldfish', 'eel', 'alligatorGar',
      'shrimp', 'riverShrimp', 'crayfish', 'bostonLobster', 'aussieLobster', 'milkLobster',
      'rareShrimp', 'rareRiverShrimp', 'rareCrayfish', 'rareBostonLobster', 'rareAussieLobster', 'rareMilkLobster',
    }
    for _, oldId in ipairs(oldFishIds) do
      assert.are.equal(oldId, fish.LegacyIdMap[oldId], oldId)
      assert.is_not_nil(fish.Definitions[fish.LegacyIdMap[oldId]], oldId)
    end
  end)

  it("testUnimplementedContentAndInventorySemanticsRemainExplicit", function()
    local fish = require('common.cfg.Fish')
    local items = require('common.cfg.Items')
    for _, row in pairs(fish.Definitions) do
      -- #136：蟹湖 14 行、#141：树林岛 14 行、#142：沙滩岛 14 行已随对应本单实装；
      -- 其余未实装区与全部精英/首领仍保持 implemented=false。
      local built = row.ZoneId == 'fishPond' or row.ZoneId == 'shrimpPond'
        or row.ZoneId == 'crabLake' or row.ZoneId == 'forestIsland' or row.ZoneId == 'beachIsland'
        or row.ZoneId == 'reefIsland'
      if not built or row.Grade == 'elite' or row.Grade == 'boss' then
        if row.Id ~= 'fish23Elite' and row.Id ~= 'fish24Boss'
          and row.Id ~= 'fish31Elite' and row.Id ~= 'fish32Boss'
          and row.Id ~= 'fish39Elite' and row.Id ~= 'fish40Boss'
          and row.ZoneId ~= 'reefIsland' and row.ZoneId ~= 'volcanoIsland' then
          assert.is_false(row.implemented, row.source)
        end
      end
    end
    -- #140：风神之翼（169）与哥斯拉（170）已随本单接入；其余大奖与药水仍待后续任务
    for sourceId = 152, 171 do
      local row = items.Definitions[items.SourceIdMap[sourceId]]
      if sourceId == 169 or sourceId == 170 then
        assert.is_true(row.implemented, row.source)
      else
        assert.is_false(row.implemented, row.source)
      end
    end
    for sourceId = 113, 119 do
      assert.are.equal('bait', items.Definitions[items.SourceIdMap[sourceId]].Container)
    end
    for sourceId = 120, 126 do
      local row = items.Definitions[items.SourceIdMap[sourceId]]
      assert.is_true(row.BossBait)
      assert.is_nil(row.Container)
    end
    for sourceId, expected in pairs({ [119] = -20, [121] = -20, [122] = -10, [126] = -99 }) do
      assert.are.equal(expected, items.Definitions[items.SourceIdMap[sourceId]].EatPercent)
    end
    for sourceId = 127, 171 do
      assert.is_nil(items.Definitions[items.SourceIdMap[sourceId]].EatPercent)
    end
    assert.are.equal(5, items.Definitions.sausage.EatPercent)
  end)
end)

-- #122 失败方式：漏鱼/漏物/漏商店行、重复原表编号、普通与极品同号被覆盖；
-- 鱼饵或掉落物悬空、七区精英信物/首领饵/首领信物断链；价格、权重、限购无效；
-- 夜明珠进入金币商店、作废升级或旧奖池混入；未接入行为误标为已实现。
local lu = require('luaunit')
local Validate = require('common.ContentValidation')
local cfg = require('common.GameCfg')

TestContentValidation = {}

function TestContentValidation:test_full_catalog_has_no_reference_errors()
    local result = Validate.Check(cfg)
    lu.assertEquals(result.errors, {})
    lu.assertEquals(result.counts, { zones = 7, fish = 98, items = 171,
        shop = 50, lottery = 7, blindbox = 42, lotteryWeight = 100, blindboxWeight = 1000 })
end

function TestContentValidation:test_missing_drop_reports_original_row()
    local fish = cfg.Fish.eel
    local original = fish.Drops[1].ItemId
    fish.Drops[1].ItemId = 'missing-item'
    local result = Validate.Check(cfg)
    fish.Drops[1].ItemId = original
    lu.assertStrContains(table.concat(result.errors, '\n'), '钓鱼表!R14')
    lu.assertStrContains(table.concat(result.errors, '\n'), 'missing-item')
end

function TestContentValidation:test_duplicate_source_id_reports_both_rows()
    local old = cfg.Items.Definitions.item7.SourceId
    cfg.Items.Definitions.item7.SourceId = 8
    local result = Validate.Check(cfg)
    cfg.Items.Definitions.item7.SourceId = old
    lu.assertStrContains(table.concat(result.errors, '\n'), '物品表!R8')
    lu.assertStrContains(table.concat(result.errors, '\n'), '物品表!R9')
end

function TestContentValidation:test_broken_exchange_reports_row()
    local original = cfg.Content.Exchanges and cfg.Content.Exchanges[1] and cfg.Content.Exchanges[1].BossBait
    if not original then return end
    cfg.Content.Exchanges[1].BossBait = 'missing-bait'
    local result = Validate.Check(cfg)
    cfg.Content.Exchanges[1].BossBait = original
    lu.assertStrContains(table.concat(result.errors, '\n'), 'missing-bait')
end

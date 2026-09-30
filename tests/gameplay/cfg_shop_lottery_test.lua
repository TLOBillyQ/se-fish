-- 失败方式：漏录/重复源行、作废售卖、金额和限购错位、抽奖返奖混淆、保底或货币错误、引用失效。
local lu = require('luaunit')

TestContentCfg = {}

function TestContentCfg:test_shop_rows_and_source_prices()
    local shop = require('common.cfg.Shop')
    lu.assertEquals(#shop.Goods, 50)
    lu.assertEquals(#shop.Excluded, 1)
    lu.assertEquals(shop.Excluded[1].number, 27)
    local seen = {}
    for _, goods in ipairs(shop.Goods) do
        lu.assertNotNil(goods.source:match('^商店表!R%d+$'))
        lu.assertNil(seen[goods.number], '重复编号 ' .. goods.number)
        seen[goods.number] = true
        lu.assertTrue(goods.price > 0 and goods.price % 1 == 0)
        lu.assertTrue(goods.purchaseLimit >= 0 and goods.purchaseLimit % 1 == 0)
        lu.assertTrue(goods.minShopLevel >= 1 and goods.minShopLevel <= 7)
        lu.assertNotEquals(goods.itemName, '夜明珠')
        lu.assertNotEquals(goods.itemName, '背包升级7')
        lu.assertEquals(goods.implemented, true, goods.source .. ' #130 起全量接入商店')
    end
    lu.assertNil(seen[27])
    lu.assertEquals(shop.Goods[14].itemName, '新手鱼竿')
    lu.assertEquals(shop.Goods[14].price, 5)
    lu.assertEquals(shop.Goods[14].source, '商店表!R15')
end

function TestContentCfg:test_upgrades_are_once_per_level()
    local goods = require('common.cfg.Shop').Goods
    local groups = { backpack = 6, melee = 7, ranged = 5, explosive = 3, magazine = 3 }
    local seen = {}
    for _, row in ipairs(goods) do
        if row.upgrade then
            local upgrade = row.upgrade
            lu.assertEquals(row.purchaseLimit, 1)
            lu.assertTrue(upgrade.level >= 1 and upgrade.level <= groups[upgrade.kind])
            local key = upgrade.kind .. upgrade.level
            lu.assertNil(seen[key], key)
            seen[key] = true
        end
    end
    for kind, maximum in pairs(groups) do
        for level = 1, maximum do lu.assertTrue(seen[kind .. level]) end
    end
    for _, row in ipairs(goods) do
        if row.upgrade and row.upgrade.kind == 'backpack' and row.upgrade.level == 6 then
            lu.assertEquals(row.description, '购买后，道具栏+1，背包格+5')
            lu.assertEquals(row.upgrade.backpackSlots, 40)
        end
    end
end

function TestContentCfg:test_lottery_has_seven_patterns_and_independent_prizes()
    local lottery = require('common.cfg.Lottery')
    lu.assertEquals(#lottery.Patterns, 7)
    local weight = 0
    for _, pattern in ipairs(lottery.Patterns) do
        weight = weight + pattern.weight
        lu.assertNotNil(pattern.source:match('^抽奖表!R%d+$'))
        lu.assertTrue(pattern.pairMultiplier > 0)
        lu.assertEquals(pattern.implemented, true, pattern.source .. ' #138 起接入抽奖机')
    end
    lu.assertEquals(weight, 100)
    lu.assertEquals(lottery.Patterns[1].pairMultiplier, 2)
    lu.assertEquals(lottery.Patterns[7].pairMultiplier, 20)
    lu.assertEquals(#lottery.Patterns[1].tripleReward.itemKeys, 5)
    lu.assertEquals(#lottery.Patterns[2].tripleReward.itemKeys, 5)
    lu.assertEquals(#lottery.Patterns[3].tripleReward.itemKeys, 5)
    lu.assertEquals(lottery.Patterns[4].tripleReward.itemName, '加速药水')
    lu.assertEquals(lottery.PairRule, 'exactlyTwo')
    lu.assertEquals(lottery.TripleRule, 'tripleFirst')
end

function TestContentCfg:test_blindbox_weight_pricing_and_pity()
    local box = require('common.cfg.Blindbox')
    lu.assertEquals(#box.Entries, 42)
    local weight, priceExpectation = 0, 0
    for _, entry in ipairs(box.Entries) do
        lu.assertNotNil(entry.source:match('^地图盲盒表!R%d+$'))
        lu.assertNotNil(entry.itemKey)
        lu.assertTrue(entry.weight > 0 and entry.weight % 1 == 0)
        lu.assertTrue(entry.basePrice > 0 and entry.basePrice % 1 == 0)
        lu.assertEquals(entry.multiplier, 1)
        lu.assertEquals(entry.implemented, false)
        weight = weight + entry.weight
        priceExpectation = priceExpectation + entry.weight * entry.basePrice / 1000
    end
    lu.assertEquals(weight, 1000)
    lu.assertAlmostEquals(priceExpectation, 166.075, 0.00001)
    lu.assertEquals(box.Currency, '金豆')
    lu.assertEquals(box.SinglePrice, 10)
    lu.assertEquals(box.TenPrice, 90)
    lu.assertEquals(box.Pity.afterMisses, 49)
    lu.assertEquals(box.Pity.guaranteedDraw, 50)
    lu.assertEquals(#box.Pity.prizeItemKeys, 2)
    lu.assertEquals(box.Entries[1].itemName, '极品美人鱼')
    lu.assertEquals(box.Entries[2].itemName, '极品蛇颈龙')
    lu.assertTrue(box.Entries[1].jackpot and box.Entries[2].jackpot)
end

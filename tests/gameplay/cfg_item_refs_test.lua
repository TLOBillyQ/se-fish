-- #122-B 源表交叉引用校验：借助同一目录 Items 的公开 Definitions，避免由盲盒重复另建名字映射。
local lu = require('luaunit')

TestCfgItemReferences = {}

function TestCfgItemReferences:test_shop_and_lottery_reference_catalog()
    local definitions = require('common.cfg.Items').Definitions
    for _, row in ipairs(require('common.cfg.Shop').Goods) do
        if row.itemKey then
            local item = definitions[row.itemKey]
            lu.assertNotNil(item, row.source .. ' 缺物品 ' .. row.itemKey)
            lu.assertEquals(item.Name, row.itemName, row.source)
        end
    end
    for _, row in ipairs(require('common.cfg.Lottery').Patterns) do
        local prize = row.tripleReward
        if prize.itemKey then
            lu.assertNotNil(definitions[prize.itemKey], row.source)
            lu.assertEquals(definitions[prize.itemKey].Name, prize.itemName, row.source)
        else
            for index, key in ipairs(prize.itemKeys) do
                lu.assertNotNil(definitions[key], row.source)
                lu.assertEquals(definitions[key].Name, prize.itemNames[index], row.source)
            end
        end
    end
end

function TestCfgItemReferences:test_blindbox_references_42_rare_catches_at_matching_prices()
    local definitions = require('common.cfg.Items').Definitions
    local box = require('common.cfg.Blindbox')
    local seen = {}
    for _, row in ipairs(box.Entries) do
        local item = definitions[row.itemKey]
        lu.assertNotNil(item, row.source .. ' 缺物品 ' .. row.itemKey)
        lu.assertEquals(item.Name, row.itemName, row.source)
        lu.assertEquals(item.Type, '极品食物', row.source)
        lu.assertEquals(item.BasePrice, row.basePrice, row.source)
        lu.assertNil(seen[row.itemKey], '重复鱼获 ' .. row.itemKey)
        seen[row.itemKey] = true
    end
    lu.assertEquals(box.Pity.prizeItemKeys, { box.Entries[1].itemKey, box.Entries[2].itemKey })
end

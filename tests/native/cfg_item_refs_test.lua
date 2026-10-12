-- #122-B 源表交叉引用校验：借助同一目录 Items 的公开 Definitions，避免由盲盒重复另建名字映射。
-- 迁移自 tests/gameplay/cfg_item_refs_test.lua（#83，LuaUnit → 原生 Busted）；
-- 案例顺序沿用旧入口的类名 + 方法名字典序，保证与迁移前后可逐条对账。
describe("TestCfgItemReferences", function()
  it("test_blindbox_references_42_rare_catches_at_matching_prices", function()
    local definitions = require('common.cfg.Items').Definitions
    local box = require('common.cfg.Blindbox')
    local seen = {}
    for _, row in ipairs(box.Entries) do
      local item = definitions[row.itemKey]
      assert.is_not_nil(item, row.source .. ' 缺物品 ' .. row.itemKey)
      assert.are.equal(row.itemName, item.Name, row.source)
      assert.are.equal('极品食物', item.Type, row.source)
      assert.are.equal(row.basePrice, item.BasePrice, row.source)
      assert.is_nil(seen[row.itemKey], '重复鱼获 ' .. row.itemKey)
      seen[row.itemKey] = true
    end
    assert.same({ box.Entries[1].itemKey, box.Entries[2].itemKey }, box.Pity.prizeItemKeys)
  end)

  it("test_shop_and_lottery_reference_catalog", function()
    local definitions = require('common.cfg.Items').Definitions
    for _, row in ipairs(require('common.cfg.Shop').Goods) do
      if row.itemKey then
        local item = definitions[row.itemKey]
        assert.is_not_nil(item, row.source .. ' 缺物品 ' .. row.itemKey)
        assert.are.equal(row.itemName, item.Name, row.source)
      end
    end
    for _, row in ipairs(require('common.cfg.Lottery').Patterns) do
      local prize = row.tripleReward
      if prize.itemKey then
        assert.is_not_nil(definitions[prize.itemKey], row.source)
        assert.are.equal(prize.itemName, definitions[prize.itemKey].Name, row.source)
      else
        for index, key in ipairs(prize.itemKeys) do
          assert.is_not_nil(definitions[key], row.source)
          assert.are.equal(prize.itemNames[index], definitions[key].Name, row.source)
        end
      end
    end
  end)
end)

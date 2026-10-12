-- #84 迁移：精英电鳗部位掉落（原 tests/gameplay/eel_loot_test.lua，1 例）。
-- 接缝：MgrLoot 的 Drops 多发掉落——数量与倍率、重复死亡不重复发放、他人可拾、拾取发成部位物品。
-- 沿用 tests/support/fish_loot 共享夹具；describe/it 名称保留旧类名与方法名。
local FishLoot = require('tests.support.fish_loot')

describe('TestEelLoot', function()
    local env

    before_each(function()
        env = setmetatable({}, { __index = FishLoot })
        env:setUp()
    end)
    after_each(function()
        env:tearDown()
    end)

    it('test_eel_drops_three_items_and_another_player_can_pick_them', function()
        local fish = env:land(env.player, 'eel', 1.7)
        env:kill(fish)
        env:kill(fish)
        local counts, loots = {}, {}
        for _, loot in pairs(env.loot.Loots) do
            counts[loot.ItemId] = (counts[loot.ItemId] or 0) + 1
            loots[#loots + 1] = loot
            assert.are.equal(1.7, loot.Mult)
        end
        assert.same({ eelMeat = 2, eelHead = 1 }, counts)
        for _, loot in ipairs(loots) do
            env.other.Character.Position = loot.Position
            assert.is_true(env.loot:Pickup(env.other, loot.Id))
            assert.is_false(env.loot:Pickup(env.player, loot.Id))
        end
        assert.same({}, env.loot:Snapshot())
        local snapshot = env.data[env.other.UserId]:GetItemBarSnapshot()
        counts = {}
        for _, slots in ipairs({ snapshot.slots, snapshot.backpack }) do
            for _, item in pairs(slots) do counts[item.itemId] = (counts[item.itemId] or 0) + 1 end
        end
        assert.are.equal(2, counts.eelMeat)
        assert.are.equal(1, counts.eelHead)
    end)
end)

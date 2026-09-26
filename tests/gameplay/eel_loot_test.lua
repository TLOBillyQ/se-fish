-- #86 失败方式：部位掉落丢数量/倍率、重复死亡重复发放、错误地限制拾取者、拾取发成 eel。
local lu = require('luaunit')
require('tests.gameplay.fish_loot_test')
TestEelLoot = {}
for _, name in ipairs({ 'setUp', 'tearDown', 'newPlayer', 'land', 'mounts', 'kill', 'bar' }) do
    TestEelLoot[name] = TestFishLoot[name]
end
function TestEelLoot:test_eel_drops_three_items_and_another_player_can_pick_them()
    local fish = self:land(self.player, 'eel', 1.7)
    self:kill(fish)
    self:kill(fish)
    local counts, loots = {}, {}
    for _, loot in pairs(self.loot.Loots) do
        counts[loot.ItemId] = (counts[loot.ItemId] or 0) + 1
        loots[#loots + 1] = loot
        lu.assertEquals(loot.Mult, 1.7)
    end
    lu.assertEquals(counts, { eelMeat = 2, eelHead = 1 })
    for _, loot in ipairs(loots) do
        self.other.Character.Position = loot.Position
        lu.assertTrue(self.loot:Pickup(self.other, loot.Id))
        lu.assertFalse(self.loot:Pickup(self.player, loot.Id))
    end
    lu.assertEquals(self.loot:Snapshot(), {})
    local snapshot = self.data[self.other.UserId]:GetItemBarSnapshot()
    counts = {}
    for _, slots in ipairs({ snapshot.slots, snapshot.backpack }) do
        for _, item in pairs(slots) do counts[item.itemId] = (counts[item.itemId] or 0) + 1 end
    end
    lu.assertEquals(counts.eelMeat, 2)
    lu.assertEquals(counts.eelHead, 1)
end

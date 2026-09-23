-- #51 新手任务前三步（拾 5 只蚯蚓 → 喂 5 只蚯蚓 → 买 1 把新手鱼竿）与正式拾饵点位。
-- 失败方式（先列后写）：
--   1. 同一事实（同一 eventId）重发被重复计数；
--   2. 用物品载荷去重：五次不同的蚯蚓喂食只记一次；
--   3. 非当前步骤的事件计数或推进（第 1 步就买竿推进、第 1 步的喂食记进第 2 步）；
--   4. 已推进后收到早期事件（买竿后再拾饵）回退或改动任务；
--   5. 物品不对也计数：第 2 步喂鱼获当成喂蚯蚓，第 3 步买蚯蚓当成买竿；
--   6. 没有 eventId 的通知被接受；
--   7. 进度在玩家之间共享，或一名玩家的事实推进了别人；
--   8. 玩法失败（余额不足 / 越距 / 没有可喂物 / 重放旧序号）也发出事实；成功的事实缺 eventId 或不同请求共用 eventId；
--   9. 任务推进时额外发奖励（金币 / 物品变动）；
--  10. 推进后不下发任务状态、不写玩家属性、不给完成提示，客户端无从显示步骤与计数；
--  11. 正式点位不走配置、少于 5 个（第 1 步只能等刷新），或丢了 2 米拾取 / 15 秒刷新的复用。
local lu = require('luaunit')

TestQuest = {}

local function newPlayer(id)
    local player = { UserId = id, Attrs = {}, Character = { Position = { x = 0, y = 0, z = 0 } } }
    function player:SetAttribute(k, v) self.Attrs[k] = v end
    return player
end

function TestQuest:setUp()
    local env = self
    self.cfg = require('common.GameCfg')
    self.savedDebug = self.cfg.Debug
    self.cfg.Debug = { Enabled = false }
    self.Steps = assert(loadfile('common/QuestSteps.lua'))()
    self.quest = assert(loadfile('server/Mgr/MgrQuest.lua'))()
    self.sent = {}
    self.quest.Send = function(_, player, state) env.sent[#env.sent + 1] = { player = player, state = state } end
    self.a, self.b = newPlayer(1), newPlayer(2)
    self.quest:OnPlayerAdded(self.a)
    self.quest:OnPlayerAdded(self.b)
end

function TestQuest:tearDown()
    self.cfg.Debug = self.savedDebug
end

function TestQuest:notify(player, kind, itemId, eventId)
    return self.quest:Notify(kind, player, { itemId = itemId, eventId = eventId })
end

function TestQuest:state(player)
    return self.quest:GetState(player)
end

function TestQuest:lastSent(player)
    for i = #self.sent, 1, -1 do
        if self.sent[i].player == player then return self.sent[i].state end
    end
end

-- 把 a 推进到第 3 步（买竿）
function TestQuest:toStep3(player)
    for i = 1, 5 do self:notify(player, 'PickBait', 'worm', 'loot:' .. i) end
    for i = 1, 5 do self:notify(player, 'Feed', 'worm', 'feed:' .. player.UserId .. ':' .. i) end
end

function TestQuest:test_config_three_steps_in_design_order()
    local steps = self.cfg.Quest.Steps
    lu.assertEquals(#steps >= 3, true)
    lu.assertEquals({ steps[1].Kind, steps[1].ItemId, steps[1].Need }, { 'PickBait', 'worm', 5 })
    lu.assertEquals({ steps[2].Kind, steps[2].ItemId, steps[2].Need }, { 'Feed', 'worm', 5 })
    lu.assertEquals({ steps[3].Kind, steps[3].ItemId, steps[3].Need }, { 'Buy', 'starterRod', 1 })
    for _, step in ipairs(steps) do lu.assertTrue(type(step.Text) == 'string' and step.Text ~= '') end
end

function TestQuest:test_same_event_id_counts_once()
    lu.assertTrue(self:notify(self.a, 'PickBait', 'worm', 'loot:1'))
    lu.assertFalse(self:notify(self.a, 'PickBait', 'worm', 'loot:1'))
    lu.assertEquals(self:state(self.a).count, 1)
end

function TestQuest:test_five_distinct_feeds_each_count()
    for i = 1, 5 do self:notify(self.a, 'PickBait', 'worm', 'loot:' .. i) end
    lu.assertEquals(self:state(self.a).step, 2)
    for i = 1, 4 do lu.assertTrue(self:notify(self.a, 'Feed', 'worm', 'feed:1:' .. i)) end
    lu.assertEquals(self:state(self.a).count, 4)
    self:notify(self.a, 'Feed', 'worm', 'feed:1:5')
    lu.assertEquals(self:state(self.a).step, 3)
    lu.assertEquals(self:state(self.a).count, 0)
end

function TestQuest:test_not_current_step_ignored()
    lu.assertFalse(self:notify(self.a, 'Buy', 'starterRod', 'shop:1:1'))
    lu.assertFalse(self:notify(self.a, 'Feed', 'worm', 'feed:1:1'))
    lu.assertEquals(self:state(self.a).step, 1)
    lu.assertEquals(self:state(self.a).count, 0)
end

function TestQuest:test_early_events_do_not_roll_back()
    self:toStep3(self.a)
    lu.assertEquals(self:state(self.a).step, 3)
    lu.assertFalse(self:notify(self.a, 'PickBait', 'worm', 'loot:99'))
    lu.assertFalse(self:notify(self.a, 'Feed', 'worm', 'feed:1:99'))
    lu.assertEquals(self:state(self.a).step, 3)
    lu.assertTrue(self:notify(self.a, 'Buy', 'starterRod', 'shop:1:1'))
    lu.assertEquals(self:state(self.a).step, 4)
    lu.assertFalse(self:notify(self.a, 'PickBait', 'worm', 'loot:100'))
    lu.assertEquals(self:state(self.a).step, 4)
end

function TestQuest:test_wrong_item_does_not_count()
    for i = 1, 5 do self:notify(self.a, 'PickBait', 'worm', 'loot:' .. i) end
    lu.assertFalse(self:notify(self.a, 'Feed', 'bass', 'feed:1:1'))
    lu.assertEquals(self:state(self.a).count, 0)
    for i = 2, 6 do self:notify(self.a, 'Feed', 'worm', 'feed:1:' .. i) end
    lu.assertFalse(self:notify(self.a, 'Buy', 'worm', 'shop:1:1'))
    lu.assertEquals(self:state(self.a).step, 3)
end

function TestQuest:test_missing_event_id_rejected()
    lu.assertFalse(self:notify(self.a, 'PickBait', 'worm', nil))
    lu.assertEquals(self:state(self.a).count, 0)
end

function TestQuest:test_players_independent()
    self:notify(self.a, 'PickBait', 'worm', 'loot:1')
    lu.assertEquals(self:state(self.a).count, 1)
    lu.assertEquals(self:state(self.b).count, 0)
    -- 同一个拾取 id 由 b 上报（不可能的重复）也只按 b 自己的进度记
    lu.assertTrue(self:notify(self.b, 'PickBait', 'worm', 'loot:2'))
    lu.assertEquals(self:state(self.b).count, 1)
    lu.assertEquals(self:state(self.a).count, 1)
end

function TestQuest:test_publish_attribute_and_notice()
    local first = self:lastSent(self.a)
    lu.assertEquals(first.step, 1)
    lu.assertEquals(first.need, 5)
    lu.assertTrue(first.text:find('拾取 5 只蚯蚓', 1, true) ~= nil)
    lu.assertEquals(self.a.Attrs.QuestStep, 1)
    self:notify(self.a, 'PickBait', 'worm', 'loot:1')
    local counted = self:lastSent(self.a)
    lu.assertEquals(counted.count, 1)
    lu.assertTrue(counted.text:find('1/5', 1, true) ~= nil)
    lu.assertNil(counted.notice)
    for i = 2, 5 do self:notify(self.a, 'PickBait', 'worm', 'loot:' .. i) end
    local advanced = self:lastSent(self.a)
    lu.assertEquals(advanced.step, 2)
    lu.assertTrue(advanced.notice:find('喂钓鱼佬吃 5 只蚯蚓', 1, true) ~= nil)
    lu.assertEquals(self.a.Attrs.QuestStep, 2)
    lu.assertEquals(self.a.Attrs.QuestText, advanced.text)
end

function TestQuest:test_removed_player_state_dropped()
    self.quest:OnPlayerRemoving(self.a)
    lu.assertNil(self:state(self.a))
    lu.assertFalse(self:notify(self.a, 'PickBait', 'worm', 'loot:1'))
end

-- 失败方式 8 / 9：商店、喂食、拾饵只在成功后发事实，eventId 随请求 / 拾取 id 变化，推进不发奖励
function TestQuest:spyQuest()
    local env = self
    env.facts = {}
    return { Notify = function(_, kind, player, payload)
        env.facts[#env.facts + 1] = { kind = kind, player = player, itemId = payload.itemId, eventId = payload.eventId }
        return true
    end }
end

function TestQuest:makeData(coin)
    local PlayerData = assert(loadfile('server/Data/PlayerData.lua'))()
    local data = PlayerData.New(self.a)
    data:Init()
    data.Data.FishCoin = coin or 0
    return data
end

function TestQuest:test_shop_notifies_only_on_success()
    local env = self
    local data = self:makeData(5)
    local shop = assert(loadfile('server/Mgr/MgrShop.lua'))()
    shop.PlayerData = { GetDataInst = function() return data end, SendItemBar = function() end }
    env.inRange = false
    shop.Interact = { InRange = function() return env.inRange end }
    shop.Reply = function() end
    shop.Quest = self:spyQuest()
    shop:Handle(self.a, { action = 'Buy', itemId = 'starterRod', seq = 1 })
    lu.assertEquals(#self.facts, 0)
    env.inRange = true
    lu.assertTrue(shop:Handle(self.a, { action = 'Buy', itemId = 'starterRod', seq = 2 }))
    lu.assertFalse(shop:Handle(self.a, { action = 'Buy', itemId = 'starterRod', seq = 2 }))
    lu.assertFalse(shop:Handle(self.a, { action = 'Buy', itemId = 'starterRod', seq = 3 })) -- 余额 0
    lu.assertEquals(#self.facts, 1)
    lu.assertEquals(self.facts[1].kind, 'Buy')
    lu.assertEquals(self.facts[1].itemId, 'starterRod')
    lu.assertNotNil(self.facts[1].eventId)
    data.Data.FishCoin = 1
    lu.assertTrue(shop:Handle(self.a, { action = 'Buy', itemId = 'worm', seq = 4 }))
    lu.assertNotEquals(self.facts[2].eventId, self.facts[1].eventId)
end

function TestQuest:test_feed_notifies_each_success_with_distinct_ids()
    local data = self:makeData(0)
    data.Data.Bait.worm = 2
    data:SelectBait('worm')
    local interact = assert(loadfile('server/Mgr/MgrInteract.lua'))()
    interact.PlayerData = { GetDataInst = function() return data end, SendItemBar = function() end }
    interact.InRange = function() return {} end
    interact.Reply = function() end
    interact.PlayEat = function() end
    interact.Quest = self:spyQuest()
    lu.assertTrue(interact:Handle(self.a, { target = 'fisherman', action = 'Feed', seq = 1 }))
    lu.assertFalse(interact:Handle(self.a, { target = 'fisherman', action = 'Feed', seq = 1 }))
    lu.assertTrue(interact:Handle(self.a, { target = 'fisherman', action = 'Feed', seq = 2 }))
    lu.assertFalse(interact:Handle(self.a, { target = 'fisherman', action = 'Feed', seq = 3 })) -- 没有可喂物
    lu.assertEquals(#self.facts, 2)
    lu.assertEquals({ self.facts[1].kind, self.facts[1].itemId }, { 'Feed', 'worm' })
    lu.assertNotNil(self.facts[1].eventId)
    lu.assertNotEquals(self.facts[1].eventId, self.facts[2].eventId)
    lu.assertEquals(data.Data.FishCoin, 2)
end

function TestQuest:test_bait_pickup_notifies_with_loot_id()
    local data = self:makeData(0)
    local loot = assert(loadfile('server/Mgr/MgrLoot.lua'))()
    loot.PlayerData = { SendItemBar = function() end }
    loot.Reply = function() end
    loot.Broadcast = function() end
    loot.Now = function() return 0 end
    loot.Quest = self:spyQuest()
    loot.Spots = { s = {} }
    local unit = { Destroy = function() end }
    lu.assertTrue(loot:GiveBait(self.a, data, { Id = 7, Kind = 'bait', ItemId = 'worm', Count = 1, SpotId = 's', Unit = unit }))
    lu.assertTrue(loot:GiveBait(self.a, data, { Id = 8, Kind = 'bait', ItemId = 'worm', Count = 1, SpotId = 's', Unit = unit }))
    lu.assertEquals(#self.facts, 2)
    lu.assertEquals({ self.facts[1].kind, self.facts[1].itemId }, { 'PickBait', 'worm' })
    lu.assertNotEquals(self.facts[1].eventId, self.facts[2].eventId)
    lu.assertEquals(data.Data.Bait.worm, 2)
end

function TestQuest:test_quest_grants_no_reward()
    local data = self:makeData(0)
    self.quest.PlayerData = { GetDataInst = function() return data end }
    self:toStep3(self.a)
    self:notify(self.a, 'Buy', 'starterRod', 'shop:1:1')
    lu.assertEquals(data.Data.FishCoin, 0)
    lu.assertEquals(data:GetItemBarSnapshot().slots, {})
    lu.assertEquals(data:GetItemBarSnapshot().bait, {})
end

function TestQuest:test_formal_bait_spots_configured()
    local fresh = assert(loadfile('common/GameCfg.lua'))()
    local spots = fresh.BaitSpots.Spots
    lu.assertTrue(#spots >= 5)
    local ids = {}
    for _, spot in ipairs(spots) do
        lu.assertNil(ids[spot.Id])
        ids[spot.Id] = true
        lu.assertEquals(spot.ItemId, 'worm')
        lu.assertTrue(type(spot.Position.x) == 'number' and type(spot.Position.z) == 'number')
    end
    lu.assertEquals(fresh.BaitSpots.RespawnSec, 15)
    lu.assertEquals(fresh.Loot.PickupRadius, 2)
end

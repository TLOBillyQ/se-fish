-- 原生 Busted（#87 迁移自 tests/gameplay/quest_test.lua 的 TestQuest）。
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
-- #52 第四至九步（挂饵 → 水边抛竿 → 收线上岸 → 岸上放下 → 打死 → 喂鱼获）：
--  12. 步骤表不是设计案的 9 步顺序，或文案不集中在配置；
--  13. 第 9 步被任意喂食（喂蚯蚓）完成，而不是喂鱼获；
--  14. 第 4 步时收到后面步骤的事实（上岸 / 放下 / 打死 / 喂鱼获）就计数或跳步；
--  15. 9 步走完没有收尾提示、任务条不显示完成，或完成后仍有事实被计数；
--  16. 任务系统反查玩法系统（require 了 server 下的玩法管理器）。
-- 各玩法侧的事实发送（挂饵 / 抛竿落水 / 上岸 / 岸上放下 / 击杀归属）分别在 item_bar_flow / landing /
-- fish_lift 的测试里。
-- 迁移说明：案例按旧 LuaUnit 实际执行序（方法名字典序）逐个 it 注册；
--   旧 setUp/tearDown 逐例映射为 before_each/after_each（Debug 开关逐案例还原，不看前例遗留）；
--   lu.assertNotEquals 是深不等，映射为 assert.are_not.same；lu.assertNotNil → is_not_nil。
local RandomGuard = require("tests.support.random_guard")

local function newPlayer(id)
  local player = { UserId = id, Attrs = {}, Character = { Position = { x = 0, y = 0, z = 0 } } }
  function player:SetAttribute(k, v)
    self.Attrs[k] = v
  end
  return player
end

--- 搭一次新手任务世界；调用方负责 cleanup()。
local function newWorld()
  local env = {}
  local owner = env

  function env:notify(player, kind, itemId, eventId, category)
    return self.quest:Notify(kind, player, { itemId = itemId, eventId = eventId, category = category })
  end

  function env:state(player)
    return self.quest:GetState(player)
  end

  function env:lastSent(player)
    for i = #self.sent, 1, -1 do
      if self.sent[i].player == player then
        return self.sent[i].state
      end
    end
  end

  -- 把 a 推进到第 3 步（买竿）
  function env:toStep3(player)
    for i = 1, 5 do
      self:notify(player, "PickBait", "worm", "loot:" .. i)
    end
    for i = 1, 5 do
      self:notify(player, "Feed", "worm", "feed:" .. player.UserId .. ":" .. i)
    end
  end

  -- 把玩家推进到第 9 步（喂鱼获）
  function env:toStep9(player)
    self:toStep3(player)
    local uid = player.UserId
    self:notify(player, "Buy", "starterRod", "shop:" .. uid .. ":1")
    self:notify(player, "EquipBait", "worm", "bait:" .. uid .. ":1")
    self:notify(player, "CastWater", nil, "cast:" .. uid .. ":1")
    self:notify(player, "Land", "bass", "reel:1:" .. uid)
    self:notify(player, "DropShore", "bass", "drop:" .. uid .. ":1")
    self:notify(player, "Kill", "bass", "kill:1")
  end

  -- 失败方式 8 / 9：商店、喂食、拾饵只在成功后发事实，eventId 随请求 / 拾取 id 变化，推进不发奖励
  function env:spyQuest()
    local sink = owner
    sink.facts = {}
    return {
      Notify = function(_, kind, player, payload)
        sink.facts[#sink.facts + 1] = {
          kind = kind, player = player, itemId = payload.itemId, eventId = payload.eventId,
        }
        return true
      end,
    }
  end

  function env:makeData(coin)
    local PlayerData = assert(loadfile("server/Data/PlayerData.lua"))()
    local data = PlayerData.New(self.a)
    data:Init()
    data.Data.FishCoin = coin or 0
    return data
  end

  function env:cleanup()
    self.cfg.Debug = self.savedDebug
  end

  env.cfg = require("common.GameCfg")
  env.savedDebug = env.cfg.Debug
  env.cfg.Debug = { Enabled = false }
  env.Steps = assert(loadfile("common/QuestSteps.lua"))()
  env.quest = assert(loadfile("server/Mgr/MgrQuest.lua"))()
  env.sent = {}
  env.quest.Send = function(_, player, state)
    env.sent[#env.sent + 1] = { player = player, state = state }
  end
  env.a, env.b = newPlayer(1), newPlayer(2)
  env.quest:OnPlayerAdded(env.a)
  env.quest:OnPlayerAdded(env.b)

  return env
end

describe("新手任务九步（MgrQuest × QuestSteps × 玩法事实）", function()
  local env
  before_each(function()
    env = newWorld()
  end)
  after_each(function()
    RandomGuard.restore()
    if env then
      env:cleanup()
      env = nil
    end
  end)

  it("test_bait_pickup_notifies_with_loot_id", function()
    local data = env:makeData(0)
    local loot = assert(loadfile("server/Mgr/MgrLoot.lua"))()
    loot.PlayerData = { SendItemBar = function() end }
    loot.Reply = function() end
    loot.Broadcast = function() end
    loot.Now = function()
      return 0
    end
    loot.Quest = env:spyQuest()
    loot.Spots = { s = {} }
    local unit = { Destroy = function() end }
    assert.is_true(loot:GiveBait(env.a, data,
      { Id = 7, Kind = "bait", ItemId = "worm", Count = 1, SpotId = "s", Unit = unit }))
    assert.is_true(loot:GiveBait(env.a, data,
      { Id = 8, Kind = "bait", ItemId = "worm", Count = 1, SpotId = "s", Unit = unit }))
    assert.same(2, #env.facts)
    assert.same({ "PickBait", "worm" }, { env.facts[1].kind, env.facts[1].itemId })
    assert.are_not.same(env.facts[2].eventId, env.facts[1].eventId)
    assert.same(2, data.Data.Bait.worm)
  end)

  it("test_config_nine_steps_in_design_order", function()
    local steps = env.cfg.Quest.Steps
    assert.same(9, #steps)
    local kinds = {}
    for i, step in ipairs(steps) do
      kinds[i] = step.Kind
    end
    assert.same({ "PickBait", "Feed", "Buy", "EquipBait", "CastWater", "Land", "DropShore", "Kill", "Feed" }, kinds)
    assert.same("worm", steps[4].ItemId)
    assert.same("fish", steps[9].Category)
    assert.is_nil(steps[9].ItemId)
    for i = 3, 9 do
      assert.same(1, steps[i].Need)
    end
  end)

  it("test_config_three_steps_in_design_order", function()
    local steps = env.cfg.Quest.Steps
    assert.same(true, #steps >= 3)
    assert.same({ "PickBait", "worm", 5 }, { steps[1].Kind, steps[1].ItemId, steps[1].Need })
    assert.same({ "Feed", "worm", 5 }, { steps[2].Kind, steps[2].ItemId, steps[2].Need })
    assert.same({ "Buy", "starterRod", 1 }, { steps[3].Kind, steps[3].ItemId, steps[3].Need })
    for _, step in ipairs(steps) do
      assert.is_true(type(step.Text) == "string" and step.Text ~= "")
    end
  end)

  it("test_early_events_do_not_roll_back", function()
    env:toStep3(env.a)
    assert.same(3, env:state(env.a).step)
    assert.is_false(env:notify(env.a, "PickBait", "worm", "loot:99"))
    assert.is_false(env:notify(env.a, "Feed", "worm", "feed:1:99"))
    assert.same(3, env:state(env.a).step)
    assert.is_true(env:notify(env.a, "Buy", "starterRod", "shop:1:1"))
    assert.same(4, env:state(env.a).step)
    assert.is_false(env:notify(env.a, "PickBait", "worm", "loot:100"))
    assert.same(4, env:state(env.a).step)
  end)

  it("test_feed_notifies_each_success_with_distinct_ids", function()
    local data = env:makeData(0)
    data.Data.Bait.worm = 2
    data:SelectBait("worm")
    local interact = assert(loadfile("server/Mgr/MgrInteract.lua"))()
    interact.PlayerData = {
      GetDataInst = function()
        return data
      end,
      SendItemBar = function() end,
    }
    interact.InRange = function()
      return {}
    end
    interact.Reply = function() end
    interact.PlayEat = function() end
    interact.Quest = env:spyQuest()
    assert.is_true(interact:Handle(env.a, { target = "fisherman", action = "Feed", seq = 1 }))
    assert.is_false(interact:Handle(env.a, { target = "fisherman", action = "Feed", seq = 1 }))
    assert.is_true(interact:Handle(env.a, { target = "fisherman", action = "Feed", seq = 2 }))
    assert.is_false(interact:Handle(env.a, { target = "fisherman", action = "Feed", seq = 3 })) -- 没有可喂物
    assert.same(2, #env.facts)
    assert.same({ "Feed", "worm" }, { env.facts[1].kind, env.facts[1].itemId })
    assert.is_not_nil(env.facts[1].eventId)
    assert.are_not.same(env.facts[2].eventId, env.facts[1].eventId)
    assert.same(2, data.Data.FishCoin)
  end)

  it("test_finish_gives_closing_notice_and_stops_counting", function()
    env:toStep9(env.a)
    env:notify(env.a, "Feed", "bass", "feed:1:60", "fish")
    local last = env:lastSent(env.a)
    assert.is_true(last.done)
    assert.same(env.cfg.Quest.DoneText, last.notice)
    assert.same(env.cfg.Quest.DoneText, last.text)
    assert.same(env.cfg.Quest.DoneText, env.a.Attrs.QuestText)
    assert.is_false(env:notify(env.a, "Feed", "bass", "feed:1:61", "fish"))
    assert.is_false(env:notify(env.a, "PickBait", "worm", "loot:61"))
    -- 另一名玩家不受影响
    assert.same(1, env:state(env.b).step)
  end)

  it("test_five_distinct_feeds_each_count", function()
    for i = 1, 5 do
      env:notify(env.a, "PickBait", "worm", "loot:" .. i)
    end
    assert.same(2, env:state(env.a).step)
    for i = 1, 4 do
      assert.is_true(env:notify(env.a, "Feed", "worm", "feed:1:" .. i))
    end
    assert.same(4, env:state(env.a).count)
    env:notify(env.a, "Feed", "worm", "feed:1:5")
    assert.same(3, env:state(env.a).step)
    assert.same(0, env:state(env.a).count)
  end)

  it("test_formal_bait_spots_configured", function()
    local fresh = assert(loadfile("common/GameCfg.lua"))()
    local spots = fresh.BaitSpots.Spots
    assert.is_true(#spots >= 5)
    local ids = {}
    for _, spot in ipairs(spots) do
      assert.is_nil(ids[spot.Id])
      ids[spot.Id] = true
      assert.same("worm", spot.ItemId)
      assert.is_true(type(spot.Position.x) == "number" and type(spot.Position.z) == "number")
    end
    assert.same(15, fresh.BaitSpots.RespawnSec)
    assert.same(2, fresh.Loot.PickupRadius)
  end)

  it("test_late_step_facts_ignored_at_step4", function()
    env:toStep3(env.a)
    env:notify(env.a, "Buy", "starterRod", "shop:1:1")
    assert.same(4, env:state(env.a).step)
    assert.is_false(env:notify(env.a, "Land", "bass", "reel:9:1"))
    assert.is_false(env:notify(env.a, "DropShore", "bass", "drop:1:9"))
    assert.is_false(env:notify(env.a, "Kill", "bass", "kill:9"))
    assert.is_false(env:notify(env.a, "Feed", "bass", "feed:1:9", "fish"))
    assert.is_false(env:notify(env.a, "EquipBait", "other", "bait:1:9"))
    assert.same(4, env:state(env.a).step)
    assert.same(0, env:state(env.a).count)
  end)

  it("test_missing_event_id_rejected", function()
    assert.is_false(env:notify(env.a, "PickBait", "worm", nil))
    assert.same(0, env:state(env.a).count)
  end)

  it("test_not_current_step_ignored", function()
    assert.is_false(env:notify(env.a, "Buy", "starterRod", "shop:1:1"))
    assert.is_false(env:notify(env.a, "Feed", "worm", "feed:1:1"))
    assert.same(1, env:state(env.a).step)
    assert.same(0, env:state(env.a).count)
  end)

  it("test_players_independent", function()
    env:notify(env.a, "PickBait", "worm", "loot:1")
    assert.same(1, env:state(env.a).count)
    assert.same(0, env:state(env.b).count)
    -- 同一个拾取 id 由 b 上报（不可能的重复）也只按 b 自己的进度记
    assert.is_true(env:notify(env.b, "PickBait", "worm", "loot:2"))
    assert.same(1, env:state(env.b).count)
    assert.same(1, env:state(env.a).count)
  end)

  it("test_publish_attribute_and_notice", function()
    local first = env:lastSent(env.a)
    assert.same(1, first.step)
    assert.same(5, first.need)
    assert.is_true(first.text:find("拾取 5 只蚯蚓", 1, true) ~= nil)
    assert.same(1, env.a.Attrs.QuestStep)
    env:notify(env.a, "PickBait", "worm", "loot:1")
    local counted = env:lastSent(env.a)
    assert.same(1, counted.count)
    assert.is_true(counted.text:find("1/5", 1, true) ~= nil)
    assert.is_nil(counted.notice)
    for i = 2, 5 do
      env:notify(env.a, "PickBait", "worm", "loot:" .. i)
    end
    local advanced = env:lastSent(env.a)
    assert.same(2, advanced.step)
    assert.is_true(advanced.notice:find("喂钓鱼佬吃 5 只蚯蚓", 1, true) ~= nil)
    assert.same(2, env.a.Attrs.QuestStep)
    assert.same(advanced.text, env.a.Attrs.QuestText)
  end)

  it("test_quest_does_not_require_gameplay_managers", function()
    local handle = assert(io.open("server/Mgr/MgrQuest.lua", "r"))
    local source = handle:read("a")
    handle:close()
    assert.is_nil(source:find("require%(%s*['\"]server%."))
  end)

  it("test_quest_grants_no_reward", function()
    local data = env:makeData(0)
    env.quest.PlayerData = {
      GetDataInst = function()
        return data
      end,
    }
    env:toStep3(env.a)
    env:notify(env.a, "Buy", "starterRod", "shop:1:1")
    assert.same(0, data.Data.FishCoin)
    assert.same({}, data:GetItemBarSnapshot().slots)
    assert.same({}, data:GetItemBarSnapshot().bait)
  end)

  it("test_removed_player_state_dropped", function()
    env.quest:OnPlayerRemoving(env.a)
    assert.is_nil(env:state(env.a))
    assert.is_false(env:notify(env.a, "PickBait", "worm", "loot:1"))
  end)

  it("test_same_event_id_counts_once", function()
    assert.is_true(env:notify(env.a, "PickBait", "worm", "loot:1"))
    assert.is_false(env:notify(env.a, "PickBait", "worm", "loot:1"))
    assert.same(1, env:state(env.a).count)
  end)

  it("test_shop_notifies_only_on_success", function()
    local data = env:makeData(5)
    local shop = assert(loadfile("server/Mgr/MgrShop.lua"))()
    shop.PlayerData = {
      GetDataInst = function()
        return data
      end,
      SendItemBar = function() end,
    }
    env.inRange = false
    shop.Interact = {
      InRange = function()
        return env.inRange
      end,
    }
    shop.Reply = function() end
    shop.Quest = env:spyQuest()
    shop:Handle(env.a, { action = "Buy", itemId = "starterRod", seq = 1 })
    assert.same(0, #env.facts)
    env.inRange = true
    assert.is_true(shop:Handle(env.a, { action = "Buy", itemId = "starterRod", seq = 2 }))
    assert.is_false(shop:Handle(env.a, { action = "Buy", itemId = "starterRod", seq = 2 }))
    assert.is_false(shop:Handle(env.a, { action = "Buy", itemId = "starterRod", seq = 3 })) -- 余额 0
    assert.same(1, #env.facts)
    assert.same("Buy", env.facts[1].kind)
    assert.same("starterRod", env.facts[1].itemId)
    assert.is_not_nil(env.facts[1].eventId)
    data.Data.FishCoin = 1
    assert.is_true(shop:Handle(env.a, { action = "Buy", itemId = "worm", seq = 4 }))
    assert.are_not.same(env.facts[2].eventId, env.facts[1].eventId)
  end)

  it("test_step9_needs_fish_feed_not_any_feed", function()
    env:toStep9(env.a)
    assert.same(9, env:state(env.a).step)
    assert.is_false(env:notify(env.a, "Feed", "worm", "feed:1:50", "bait"))
    assert.is_false(env:notify(env.a, "Feed", "bass", "feed:1:51"))
    assert.same(9, env:state(env.a).step)
    assert.is_true(env:notify(env.a, "Feed", "bass", "feed:1:52", "fish"))
    assert.same(10, env:state(env.a).step)
  end)

  it("test_wrong_item_does_not_count", function()
    for i = 1, 5 do
      env:notify(env.a, "PickBait", "worm", "loot:" .. i)
    end
    assert.is_false(env:notify(env.a, "Feed", "bass", "feed:1:1"))
    assert.same(0, env:state(env.a).count)
    for i = 2, 6 do
      env:notify(env.a, "Feed", "worm", "feed:1:" .. i)
    end
    assert.is_false(env:notify(env.a, "Buy", "worm", "shop:1:1"))
    assert.same(3, env:state(env.a).step)
  end)
end)

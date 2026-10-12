-- 迁移自 tests/gameplay/gm_coin_test.lua（#91）；行为契约原文见 #47、#28。
-- #47 GM 发放与金币唯一入口（真 PlayerData + 假玩家列表）。
-- 失败方式（先列后写）：
--   1. 扣币能把余额扣成负数、余额不足时部分扣除，或加 / 扣非正整数也生效；
--   2. 扣币失败时仍执行了附带的发货 / 扣物品回调（钱没扣货发了）；
--   3. GM 在调试开关关闭时仍能发放；
--   4. GM 目标解析错：默认不是自己、指定的 UserId 不存在时落到别人或自己身上；
--   5. GM 发的鱼竿进了鱼饵库存、蚯蚓占了道具栏格；未知物品 / 非法数量也能发；道具栏空格不够时发了一半；
--   6. GM 扣币不走同一入口（能扣成负数）；发放后不推送库存；
--   7. 库存快照不带金币，HUD 进界面时拿不到实际余额。
-- it 名字沿用旧方法名，注册顺序 = LuaUnit sortedPairs 的实际执行顺序。

local GameCfg = require('common.GameCfg')

describe('GM 发放与金币唯一入口（MgrGM × PlayerData）', function()
  local env
  local restore

  before_each(function()
    -- 快照先于任何改动：before_each 中途失败时 after_each 仍能还原已改项。
    -- helper 的根级 after_each 只恢复 GameCfg.Debug / Save.AcceptanceSlot 的引用，
    -- 本夹具把 Debug 换成新表，故这里再快照一次并按旧 tearDown 顺序显式还原。
    restore = {
      game = rawget(_G, 'game'),
      Debug = GameCfg.Debug,
    }
    env = { attrs = {}, synced = {}, replies = {}, players = {} }
    GameCfg.Debug = { Enabled = true, InitialGrants = restore.Debug.InitialGrants }
    local PlayerData = assert(loadfile('server/Data/PlayerData.lua'))()

    local function newPlayer(id)
      local player = { UserId = id, Name = 'p' .. id, SetAttribute = function(_, k, v)
        env.attrs[id] = env.attrs[id] or {}
        env.attrs[id][k] = v
      end }
      local data = PlayerData.New(player)
      data:Init()
      return player, data
    end
    env.me, env.myData = newPlayer(1)
    env.you, env.yourData = newPlayer(2)
    env.players = { env.me, env.you }
    rawset(_G, 'game', { GetService = function(_, name)
      if name == 'Players' then return { GetPlayers = function() return env.players end } end
    end })
    env.gm = assert(loadfile('server/Mgr/MgrGM.lua'))()
    env.gm.PlayerData = {
      GetDataInst = function(_, p)
        return p == env.me and env.myData or p == env.you and env.yourData or nil
      end,
      SendItemBar = function(_, p) env.synced[#env.synced + 1] = p end,
    }
    env.gm.Reply = function(_, player, result)
      env.replies[#env.replies + 1] = { player = player, result = result }
    end
  end)

  after_each(function()
    -- 顺序与旧 tearDown 一致：先还原 Debug，再送走 game 全局。
    if restore then
      GameCfg.Debug = restore.Debug
      rawset(_G, 'game', restore.game)
    end
    env = nil
    restore = nil
  end)

  it('test_coin_entry_never_goes_negative_and_rejects_bad_amounts', function()
    local d = env.myData
    assert.is_true(d:AddCoin(5, nil, 'test'))
    assert.same(5, d.Data.FishCoin)
    assert.is_false(d:SpendCoin(6, nil, 'test'))
    assert.same(5, d.Data.FishCoin)
    for _, bad in ipairs({ 0, -1, 1.5, 'x' }) do
      assert.is_false(d:AddCoin(bad, nil, 'test'))
      assert.is_false(d:SpendCoin(bad, nil, 'test'))
    end
    assert.is_true(d:SpendCoin(5, nil, 'test'))
    assert.same(0, d.Data.FishCoin)
    assert.same(0, env.attrs[1].FishCoin)
  end)

  it('test_failed_spend_does_not_run_its_callback', function()
    local ran = false
    assert.is_false(env.myData:SpendCoin(3, function() ran = true end, 'test'))
    assert.is_false(ran)
    env.myData:AddCoin(3, nil, 'test')
    assert.is_true(env.myData:SpendCoin(3, function() ran = true end, 'test'))
    assert.is_true(ran)
  end)

  it('test_gm_coin_targets_self_by_default_or_given_player', function()
    assert.is_true(env.gm:Handle(env.me, { action = 'Coin', amount = 10 }))
    assert.same(10, env.myData.Data.FishCoin)
    assert.is_true(env.gm:Handle(env.me, { action = 'Coin', amount = 7, target = 2 }))
    assert.same(7, env.yourData.Data.FishCoin)
    assert.same(10, env.myData.Data.FishCoin)
    assert.is_false(env.gm:Handle(env.me, { action = 'Coin', amount = 7, target = 99 }))
    assert.same(10, env.myData.Data.FishCoin)
    assert.same(7, env.yourData.Data.FishCoin)
    -- 扣币走同一入口：不够就不扣
    assert.is_false(env.gm:Handle(env.me, { action = 'Coin', amount = -11 }))
    assert.same(10, env.myData.Data.FishCoin)
    assert.is_true(env.gm:Handle(env.me, { action = 'Coin', amount = -4 }))
    assert.same(6, env.myData.Data.FishCoin)
    assert.is_false(env.gm:Handle(env.me, { action = 'Coin', amount = 0 }))
    assert.is_false(env.gm:Handle(env.me, { action = 'Coin', amount = 2.5 }))
    assert.is_false(env.gm:Handle(env.me, 'Coin'))
    assert.are.equal(env.me, env.synced[1])
    assert.are.equal(env.you, env.synced[2])
  end)

  it('test_gm_items_go_to_their_own_containers', function()
    local worms = env.yourData.Data.Bait.worm
    assert.is_true(env.gm:Handle(env.me, { action = 'Item', itemId = 'worm', count = 5, target = 2 }))
    assert.same(worms + 5, env.yourData.Data.Bait.worm)
    assert.is_true(env.gm:Handle(env.me, { action = 'Item', itemId = 'starterRod', count = 2 }))
    local slots = env.myData:GetItemBarSnapshot().slots
    assert.same('starterRod', slots[2].itemId)
    assert.same('starterRod', env.myData:GetItemBarSnapshot().backpack[1].itemId)
    assert.same(1, slots[2].count)
    assert.is_nil(env.myData.Data.Bait.starterRod)
    for _, bad in ipairs({ { itemId = 'gold', count = 1 }, { itemId = 'worm', count = 0 },
      { itemId = 'worm', count = 1.5 }, { itemId = 'worm', count = 1000 } }) do
      bad.action = 'Item'
      assert.is_false(env.gm:Handle(env.me, bad))
    end
  end)

  it('test_gm_rejects_when_debug_is_disabled', function()
    GameCfg.Debug = { Enabled = false }
    assert.is_false(env.gm:Handle(env.me, { action = 'Coin', amount = 10 }))
    assert.is_false(env.gm:Handle(env.me, { action = 'Item', itemId = 'starterRod', count = 1 }))
    assert.same(0, env.myData.Data.FishCoin)
    assert.same(2, #env.replies)
    assert.are.equal(env.me, env.replies[1].player)
    assert.same({ ok = false, action = 'Coin', reason = '调试开关已关闭' }, env.replies[1].result)
    assert.same(0, #env.synced)
  end)

  it('test_item_bar_grant_is_all_or_nothing', function()
    for _ = 1, 5 do env.myData:AddItem('carp', 1) end -- 已占 6 格，剩 1 格
    assert.is_false(env.gm:Handle(env.me, { action = 'Item', itemId = 'starterRod', count = 2 }))
    local used = 0
    for _ in pairs(env.myData:GetItemBarSnapshot().slots) do used = used + 1 end
    assert.same(2, used)
    assert.is_true(env.gm:Handle(env.me, { action = 'Item', itemId = 'starterRod', count = 1 }))
  end)

  it('test_next_fish_requires_debug_valid_fish_and_online_target', function()
    env.gm.Cast = { NextFish = {}, SetNextFish = function(cast, target, fishId)
      cast.NextFish[target.UserId] = { fishId = fishId }
    end }
    assert.is_true(env.gm:Handle(env.me, { action = 'NextFish', fishId = 'eel', target = 2 }))
    assert.same('eel', env.gm.Cast.NextFish[2].fishId)
    assert.is_nil(env.gm.Cast.NextFish[1])
    assert.same(0, #env.synced)
    assert.is_false(env.gm:Handle(env.me, { action = 'NextFish', fishId = 'unknown' }))
    assert.is_false(env.gm:Handle(env.me, { action = 'NextFish', fishId = 'bass', target = 999 }))
    GameCfg.Debug.Enabled = false
    assert.is_false(env.gm:Handle(env.me, { action = 'NextFish', fishId = 'bass', target = 2 }))
    assert.same('eel', env.gm.Cast.NextFish[2].fishId)
  end)

  it('test_snapshot_carries_coin_for_hud', function()
    env.myData:AddCoin(12, nil, 'test')
    assert.same(12, env.myData:GetItemBarSnapshot().coin)
  end)
end)

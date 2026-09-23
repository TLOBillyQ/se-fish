-- #47 GM 发放与金币唯一入口（真 PlayerData + 假玩家列表）。
-- 失败方式（先列后写）：
--   1. 扣币能把余额扣成负数、余额不足时部分扣除，或加 / 扣非正整数也生效；
--   2. 扣币失败时仍执行了附带的发货 / 扣物品回调（钱没扣货发了）；
--   3. GM 在调试开关关闭时仍能发放（默认必须关闭）；
--   4. GM 目标解析错：默认不是自己、指定的 UserId 不存在时落到别人或自己身上；
--   5. GM 发的鱼竿进了鱼饵库存、蚯蚓占了道具栏格；未知物品 / 非法数量也能发；道具栏空格不够时发了一半；
--   6. GM 扣币不走同一入口（能扣成负数）；发放后不推送库存；
--   7. 库存快照不带金币，HUD 进界面时拿不到实际余额。
local lu = require('luaunit')

TestGMCoin = {}

function TestGMCoin:setUp()
    local env = self
    self.savedGame = rawget(_G, 'game')
    self.cfg = require('common.GameCfg')
    self.savedDebug = self.cfg.Debug
    self.cfg.Debug = { Enabled = true, InitialGrants = self.savedDebug.InitialGrants }
    local PlayerData = assert(loadfile('server/Data/PlayerData.lua'))()
    self.attrs = {}
    local function newPlayer(id)
        local player = { UserId = id, Name = 'p' .. id, SetAttribute = function(_, k, v)
            env.attrs[id] = env.attrs[id] or {}
            env.attrs[id][k] = v
        end }
        local data = PlayerData.New(player)
        data:Init()
        return player, data
    end
    self.me, self.myData = newPlayer(1)
    self.you, self.yourData = newPlayer(2)
    self.players = { self.me, self.you }
    _G.game = { GetService = function(_, name)
        if name == 'Players' then return { GetPlayers = function() return env.players end } end
    end }
    self.synced = {}
    self.gm = assert(loadfile('server/Mgr/MgrGM.lua'))()
    self.gm.PlayerData = {
        GetDataInst = function(_, p)
            return p == env.me and env.myData or p == env.you and env.yourData or nil
        end,
        SendItemBar = function(_, p) env.synced[#env.synced + 1] = p end,
    }
    self.gm.Reply = function() end
end

function TestGMCoin:tearDown()
    self.cfg.Debug = self.savedDebug
    _G.game = self.savedGame
end

function TestGMCoin:test_coin_entry_never_goes_negative_and_rejects_bad_amounts()
    local d = self.myData
    lu.assertTrue(d:AddCoin(5, nil, 'test'))
    lu.assertEquals(d.Data.FishCoin, 5)
    lu.assertFalse(d:SpendCoin(6, nil, 'test'))
    lu.assertEquals(d.Data.FishCoin, 5)
    for _, bad in ipairs({ 0, -1, 1.5, 'x' }) do
        lu.assertFalse(d:AddCoin(bad, nil, 'test'))
        lu.assertFalse(d:SpendCoin(bad, nil, 'test'))
    end
    lu.assertTrue(d:SpendCoin(5, nil, 'test'))
    lu.assertEquals(d.Data.FishCoin, 0)
    lu.assertEquals(self.attrs[1].FishCoin, 0)
end

function TestGMCoin:test_failed_spend_does_not_run_its_callback()
    local ran = false
    lu.assertFalse(self.myData:SpendCoin(3, function() ran = true end, 'test'))
    lu.assertFalse(ran)
    self.myData:AddCoin(3, nil, 'test')
    lu.assertTrue(self.myData:SpendCoin(3, function() ran = true end, 'test'))
    lu.assertTrue(ran)
end

function TestGMCoin:test_gm_is_off_by_default()
    local fresh = assert(loadfile('common/GameCfg.lua'))()
    lu.assertFalse(fresh.Debug.Enabled)
    self.cfg.Debug = { Enabled = false }
    lu.assertFalse(self.gm:Handle(self.me, { action = 'Coin', amount = 10 }))
    lu.assertFalse(self.gm:Handle(self.me, { action = 'Item', itemId = 'starterRod', count = 1 }))
    lu.assertEquals(self.myData.Data.FishCoin, 0)
end

function TestGMCoin:test_gm_coin_targets_self_by_default_or_given_player()
    lu.assertTrue(self.gm:Handle(self.me, { action = 'Coin', amount = 10 }))
    lu.assertEquals(self.myData.Data.FishCoin, 10)
    lu.assertTrue(self.gm:Handle(self.me, { action = 'Coin', amount = 7, target = 2 }))
    lu.assertEquals(self.yourData.Data.FishCoin, 7)
    lu.assertEquals(self.myData.Data.FishCoin, 10)
    lu.assertFalse(self.gm:Handle(self.me, { action = 'Coin', amount = 7, target = 99 }))
    lu.assertEquals(self.myData.Data.FishCoin, 10)
    lu.assertEquals(self.yourData.Data.FishCoin, 7)
    -- 扣币走同一入口：不够就不扣
    lu.assertFalse(self.gm:Handle(self.me, { action = 'Coin', amount = -11 }))
    lu.assertEquals(self.myData.Data.FishCoin, 10)
    lu.assertTrue(self.gm:Handle(self.me, { action = 'Coin', amount = -4 }))
    lu.assertEquals(self.myData.Data.FishCoin, 6)
    lu.assertFalse(self.gm:Handle(self.me, { action = 'Coin', amount = 0 }))
    lu.assertFalse(self.gm:Handle(self.me, { action = 'Coin', amount = 2.5 }))
    lu.assertFalse(self.gm:Handle(self.me, 'Coin'))
    lu.assertEquals(self.synced[1], self.me)
    lu.assertEquals(self.synced[2], self.you)
end

function TestGMCoin:test_gm_items_go_to_their_own_containers()
    local worms = self.yourData.Data.Bait.worm
    lu.assertTrue(self.gm:Handle(self.me, { action = 'Item', itemId = 'worm', count = 5, target = 2 }))
    lu.assertEquals(self.yourData.Data.Bait.worm, worms + 5)
    lu.assertTrue(self.gm:Handle(self.me, { action = 'Item', itemId = 'starterRod', count = 2 }))
    local slots = self.myData:GetItemBarSnapshot().slots
    lu.assertEquals(slots[2].itemId, 'starterRod')
    lu.assertEquals(slots[3].itemId, 'starterRod')
    lu.assertEquals(slots[2].count, 1)
    lu.assertEquals(self.myData.Data.Bait.starterRod, nil)
    for _, bad in ipairs({ { itemId = 'gold', count = 1 }, { itemId = 'worm', count = 0 },
        { itemId = 'worm', count = 1.5 }, { itemId = 'worm', count = 1000 } }) do
        bad.action = 'Item'
        lu.assertFalse(self.gm:Handle(self.me, bad))
    end
end

function TestGMCoin:test_item_bar_grant_is_all_or_nothing()
    for _ = 1, 5 do self.myData:AddItem('carp', 1) end -- 已占 6 格，剩 2 格
    lu.assertFalse(self.gm:Handle(self.me, { action = 'Item', itemId = 'starterRod', count = 3 }))
    local used = 0
    for _ in pairs(self.myData:GetItemBarSnapshot().slots) do used = used + 1 end
    lu.assertEquals(used, 6)
    lu.assertTrue(self.gm:Handle(self.me, { action = 'Item', itemId = 'starterRod', count = 2 }))
end

function TestGMCoin:test_snapshot_carries_coin_for_hud()
    self.myData:AddCoin(12, nil, 'test')
    lu.assertEquals(self.myData:GetItemBarSnapshot().coin, 12)
end

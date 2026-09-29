-- #44 向钓鱼佬喂食换金币（真 PlayerData + 假钓鱼佬锚点单位）。
-- #127 起回收口径放宽：选中格里的**任何**有基础价的物品都按基础价 × 实例倍率回收（鱼竿、道具、船票同理），
-- 烤过的按烤熟价 ×1.5；「选中鱼竿也能换钱」不再是缺陷，「什么都没选」才是 'nothing'。
-- 失败方式（先列后写）：
--   1. 金币算错：四舍五入而不是 floor(基础售价 × 个体倍率)、倍率缺省不按 1、蚯蚓不是每只 1 金币、
--      用了商店买入价；
--   2. 扣错库存：鱼获不从选中格扣、扣了别的格或整格以外的东西；鱼饵不从 Bait 计数扣而另建库存；
--      空格 / 没选中时也能换钱；
--   3. 不复验：不在钓鱼佬 5 米内（按 x/z）、目标不是登记的交互点、动作不是喂食、玩家数据未就绪也能结算；
--   4. 重放：同一请求序号重复到达、旧序号回放各结算一次；
--   5. 扣除、入账、选中态归位不同步：扣了没加钱或加了没扣，选中格清空后仍指向空格，不推送库存；
--   6. 金币有第二个写入口，或 FishCoin 属性没随入账更新；
--   7. 吃动作失败（锚点没有动画）连带裁决失败。
local lu = require('luaunit')

TestFishFeed = {}

local function vec(x, y, z) return { x = x, y = y, z = z } end

function TestFishFeed:setUp()
    local env = self
    self.savedGame = _G.game
    self.savedCfg = package.loaded['common.GameCfg']
    package.loaded['common.GameCfg'] = nil
    self.cfg = require('common.GameCfg')
    -- #49：进图白送只在调试开关下发放，这里沿用它的起始库存（鱼竿在第 1 格、蚯蚓若干）
    self.cfg.Debug = { Enabled = true, InitialGrants = self.cfg.Debug.InitialGrants }
    local PlayerData = assert(loadfile('server/Data/PlayerData.lua'))()
    self.attrs = {}
    self.player = { UserId = 1, Character = { Position = vec(3, 1, 3) },
        SetAttribute = function(_, k, v) env.attrs[k] = v end }
    self.stranger = { UserId = 2, Character = { Position = vec(3, 1, 3) }, SetAttribute = function() end }
    self.data = PlayerData.New(self.player, function() env.published = (env.published or 0) + 1 end)
    self.data:Init()
    self.plays = {}
    self.anchor = { Name = 'TGUnitFish', Position = vec(0, 6, 0),
        PlayAnimation = function(_, name) env.plays[#env.plays + 1] = name end }
    self.synced = {}
    self.replies = {}
    self.mgr = assert(loadfile('server/Mgr/MgrInteract.lua'))()
    self.mgr.FindAnchor = function(_, name) return name == 'TGUnitFish' and env.anchor or nil end
    self.mgr.PlayerData = {
        GetDataInst = function(_, p) return p == env.player and env.data or nil end,
        SendItemBar = function(_, p) env.synced[#env.synced + 1] = p end,
    }
    self.mgr.Reply = function(_, p, payload) env.replies[#env.replies + 1] = { player = p, payload = payload } end
    self.seq = 0
end

function TestFishFeed:tearDown()
    package.loaded['common.GameCfg'] = self.savedCfg
    _G.game = self.savedGame
end

function TestFishFeed:feed(extra)
    self.seq = self.seq + 1
    local payload = { target = 'fisherman', action = 'Feed', seq = self.seq }
    for k, v in pairs(extra or {}) do payload[k] = v end
    return self.mgr:Handle(self.player, payload)
end

function TestFishFeed:give(itemId, mult)
    lu.assertTrue(self.data:AddItem(itemId, mult))
    local items = self.data.Data.Containers.itemBar
    for index = 1, 8 do
        if items[index] and items[index].itemId == itemId and items[index].mult == mult then return index end
    end
end

function TestFishFeed:test_fish_price_is_floor_of_base_times_mult_and_defaults_to_one()
    local FishCatch = assert(loadfile('common/FishCatch.lua'))()
    lu.assertEquals(FishCatch.Price(self.cfg.Fish.bass, 1.99), 11)   -- 6 × 1.99 = 11.94
    lu.assertEquals(FishCatch.Price(self.cfg.Fish.goldfish, 1.15), 9) -- 8 × 1.15 = 9.2
    lu.assertEquals(FishCatch.Price(self.cfg.Fish.tilapia, 1.5), 4)   -- 3 × 1.5 = 4.5
    lu.assertEquals(FishCatch.Price(self.cfg.Fish.carp, 1.1), 4)      -- 4 × 1.1 = 4.4，防浮点误差
    lu.assertEquals(FishCatch.Price(self.cfg.Fish.carp, nil), 4)
end

function TestFishFeed:test_feed_selected_fish_takes_that_slot_and_pays_once()
    self:give('carp', 1.1)
    lu.assertTrue(self.data:DiscardSlot(1))
    local slot = self:give('bass', 1.99)
    lu.assertTrue(self.data:SelectSlot(slot))
    lu.assertTrue(self:feed())
    lu.assertEquals(self.data.Data.FishCoin, 11)
    lu.assertEquals(self.attrs.FishCoin, 11)
    lu.assertNil(self.data.Data.Containers.itemBar[slot])
    lu.assertEquals(self.data.Data.Containers.itemBar[2].itemId, 'carp')
    lu.assertNil(self.data.Data.SelectedSlot)
    lu.assertEquals(self.data.Data.Bait.worm, self.cfg.Debug.InitialGrants[2].count)
    lu.assertEquals(self.synced, { self.player })
    lu.assertEquals(self.plays, { self.cfg.Interact.Fisherman.EatAnimation })
    lu.assertTrue(self.replies[#self.replies].payload.ok)
    lu.assertEquals(self.replies[#self.replies].payload.coins, 11)
end

function TestFishFeed:test_fish_without_mult_pays_base_price()
    local slot = self:give('goldfish', nil)
    self.data:SelectSlot(slot)
    lu.assertTrue(self:feed())
    lu.assertEquals(self.data.Data.FishCoin, 8)
end

function TestFishFeed:test_feed_selected_bait_takes_one_worm_for_one_coin()
    lu.assertTrue(self.data:SelectBait('worm'))
    local before = self.data.Data.Bait.worm
    lu.assertTrue(self:feed())
    lu.assertEquals(self.data.Data.Bait.worm, before - 1)
    lu.assertEquals(self.data.Data.FishCoin, 1)
    lu.assertEquals(self.attrs.FishCoin, 1)
    lu.assertNil(self.data.Data.Bait.bait)
    lu.assertNil(self.data.Data.Containers.bait)
end

function TestFishFeed:test_last_worm_clears_bait_selection()
    self.data.Data.Bait.worm = 1
    self.data:SelectBait('worm')
    lu.assertTrue(self:feed())
    lu.assertEquals(self.data.Data.Bait.worm, 0)
    lu.assertNil(self.data.Data.SelectedBait)
    lu.assertFalse(self:feed())
    lu.assertEquals(self.data.Data.FishCoin, 1)
end

function TestFishFeed:test_selected_fish_wins_over_selected_bait()
    local slot = self:give('tilapia', 1.5)
    self.data:SelectSlot(slot)
    self.data:SelectBait('worm')
    local worms = self.data.Data.Bait.worm
    lu.assertTrue(self:feed())
    lu.assertEquals(self.data.Data.FishCoin, 4)
    lu.assertEquals(self.data.Data.Bait.worm, worms)
end

-- 什么都不选（或选中格空）才是 'nothing'；选中鱼竿按物品表基础价回收（#127 取代 #44 的「不能卖竿」）
function TestFishFeed:test_nothing_selected_is_refused_and_plain_items_are_recycled()
    lu.assertFalse(self:feed())             -- 什么都没选
    lu.assertEquals(self.data.Data.FishCoin, 0)
    lu.assertEquals(self.plays, {})
    lu.assertEquals(self.replies[#self.replies].payload.reason, 'nothing')

    self.data:SelectSlot(1)                 -- 新手鱼竿（BasePrice = 3）
    lu.assertEquals(self.data.Data.SelectedSlot, 1)
    lu.assertTrue(self:feed())
    lu.assertEquals(self.data.Data.FishCoin, self.cfg.Items.SalePrice('starterRod'))
    lu.assertEquals(self.data.Data.Containers.itemBar[1], nil)
    lu.assertEquals(self.replies[#self.replies].payload.itemId, 'starterRod')
    lu.assertEquals(self.replies[#self.replies].payload.category, 'item')
end

function TestFishFeed:test_server_rechecks_distance_target_action_and_identity()
    self.data:SelectBait('worm')
    local r = self.cfg.Interact.Fisherman.Radius + self.cfg.Interact.Fisherman.Slack
    self.player.Character.Position = vec(r + 0.1, 1, 0)
    lu.assertFalse(self:feed())
    self.player.Character.Position = vec(r - 0.1, -50, 0) -- 只看 x/z
    lu.assertFalse(self:feed({ target = 'shopkeeper' }))
    lu.assertFalse(self:feed({ action = 'Steal' }))
    lu.assertFalse(self:feed({ target = false }))
    lu.assertFalse(self.mgr:Handle(self.stranger, { target = 'fisherman', action = 'Feed', seq = 99 }))
    lu.assertFalse(self.mgr:Handle(self.player, 'Feed'))
    lu.assertEquals(self.data.Data.FishCoin, 0)
    lu.assertTrue(self:feed())
    lu.assertEquals(self.data.Data.FishCoin, 1)
end

function TestFishFeed:test_replayed_or_stale_seq_settles_nothing()
    self.data:SelectBait('worm')
    lu.assertTrue(self.mgr:Handle(self.player, { target = 'fisherman', action = 'Feed', seq = 5 }))
    lu.assertFalse(self.mgr:Handle(self.player, { target = 'fisherman', action = 'Feed', seq = 5 }))
    lu.assertFalse(self.mgr:Handle(self.player, { target = 'fisherman', action = 'Feed', seq = 3 }))
    lu.assertFalse(self.mgr:Handle(self.player, { target = 'fisherman', action = 'Feed', seq = 5.5 }))
    lu.assertFalse(self.mgr:Handle(self.player, { target = 'fisherman', action = 'Feed' }))
    lu.assertEquals(self.data.Data.FishCoin, 1)
    lu.assertTrue(self.mgr:Handle(self.player, { target = 'fisherman', action = 'Feed', seq = 6 }))
    lu.assertEquals(self.data.Data.FishCoin, 2)
    -- 离线重进后序号重新从头算
    self.mgr:OnPlayerRemoving(self.player)
    lu.assertTrue(self.mgr:Handle(self.player, { target = 'fisherman', action = 'Feed', seq = 1 }))
end

function TestFishFeed:test_missing_animation_does_not_block_settlement()
    self.anchor.PlayAnimation = nil
    self.data:SelectBait('worm')
    lu.assertTrue(self:feed())
    lu.assertEquals(self.data.Data.FishCoin, 1)
    self.anchor.PlayAnimation = function() error('boom') end
    lu.assertTrue(self:feed())
    lu.assertEquals(self.data.Data.FishCoin, 2)
end

function TestFishFeed:test_fish_coin_has_single_write_entry()
    local writers = 0
    for _, path in ipairs({ 'server/Data/PlayerData.lua', 'server/Mgr/MgrInteract.lua',
        'server/Mgr/MgrPlayerData.lua', 'server/Mgr/MgrLoot.lua' }) do
        local file = assert(io.open(path, 'r'))
        local text = file:read('a')
        file:close()
        for _ in text:gmatch('[%.%s]FishCoin%s*=%s*[^=]') do writers = writers + 1 end
    end
    -- PlayerData:Init 的初值 + AddCoin 里的唯一一处累加 + ApplySave 的读档恢复（#92，不是运行时收支）
    lu.assertEquals(writers, 3)
end

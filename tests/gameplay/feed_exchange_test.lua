-- #87 信物兑换（GameSpec §8.1 已确认）：选中格是信物（电鳗头 / 鳄雀鳝鱼头）时喂钓鱼佬走 1:1 兑换，
-- 电鳗头 → 首领饵「鸭子」、鳄雀鳝鱼头 → 虾池船票，不给金币；背包与道具栏全满时拒绝、提示且不消耗信物。
-- #127 起：兑换按**交付后的容量**校验——先扣掉选中的信物（释放这一格）再发产物，
-- 所以道具栏 + 背包全满时仍能成交，产物落进刚释放的那一格；「使用本次交付释放的格位」是合法的。
-- 失败方式（先列后写）：
--   1. 选中信物却走了金币分支（按 BasePrice 入账），或穿过选中格掉进鱼饵分支扣了蚯蚓；
--   2. 产物发错：电鳗头没换鸭子、鳄雀鳝鱼头没换船票、数量不是 1、产物没进道具栏 / 背包；
--   3. 容量判定错：满格时拒绝兑换、产物没落进释放出的格，或尚有空位却被拒绝；
--   4. 扣除与发放不同步：信物扣了产物没发，或发了产物信物还在；金币被兑换改动；
--   5. 拒绝时缺提示（reason 不是 'full'），或成功回包缺兑换双方，客户端无法给兑换提示；
--   6. 兑换成功不播吃动作、不推送库存；未选中的信物被误当兑换物。
local lu = require('luaunit')

TestFeedExchange = {}

local function vec(x, y, z) return { x = x, y = y, z = z } end

function TestFeedExchange:setUp()
    local env = self
    self.savedGame = _G.game
    self.savedCfg = package.loaded['common.GameCfg']
    package.loaded['common.GameCfg'] = nil
    self.cfg = require('common.GameCfg')
    -- 关掉进图白送，库存完全由用例自己摆
    self.cfg.Debug = { Enabled = false }
    local PlayerData = assert(loadfile('server/Data/PlayerData.lua'))()
    self.attrs = {}
    self.player = { UserId = 1, Character = { Position = vec(3, 1, 3) },
        SetAttribute = function(_, k, v) env.attrs[k] = v end }
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

function TestFeedExchange:tearDown()
    package.loaded['common.GameCfg'] = self.savedCfg
    _G.game = self.savedGame
end

function TestFeedExchange:feed()
    self.seq = self.seq + 1
    return self.mgr:Handle(self.player, { target = 'fisherman', action = 'Feed', seq = self.seq })
end

function TestFeedExchange:give(itemId)
    lu.assertTrue(self.data:AddItem(itemId))
    local bar = self.data.Data.Containers.itemBar
    for index = 1, self.data:ItemBarCapacity() do
        if bar[index] and bar[index].itemId == itemId then return index, 'itemBar' end
    end
    local backpack = self.data.Data.Containers.backpack
    for index = 1, self.data:BackpackCapacity() do
        if backpack[index] and backpack[index].itemId == itemId then return index, 'backpack' end
    end
end

function TestFeedExchange:countItem(itemId)
    local total = 0
    for _, container in pairs(self.data.Data.Containers) do
        for _, entry in pairs(container) do
            if entry.itemId == itemId then total = total + entry.count end
        end
    end
    return total
end

function TestFeedExchange:fillExcept(keepSlot)
    -- 把道具栏与背包除 keepSlot 外全部填满（用无兑换关系的普通鱼获）
    local bar = self.data.Data.Containers.itemBar
    for index = 1, self.data:ItemBarCapacity() do
        if index ~= keepSlot and (not bar[index] or bar[index].count <= 0) then
            lu.assertTrue(self.data:AddItem('tilapia'))
        end
    end
    while self.data:AddItem('tilapia') do end
end

function TestFeedExchange:test_eel_head_exchanges_for_one_duck_without_coins()
    local slot = self:give('eelHead')
    lu.assertTrue(self.data:SelectSlot(slot))
    lu.assertTrue(self:feed())
    lu.assertEquals(self:countItem('eelHead'), 0)
    lu.assertEquals(self:countItem('duck'), 1)
    lu.assertEquals(self.data.Data.FishCoin, 0)
    lu.assertEquals(self.attrs.FishCoin, 0)
    lu.assertNil(self.data.Data.SelectedSlot)
    lu.assertEquals(self.synced, { self.player })
    lu.assertEquals(self.plays, { self.cfg.Interact.Fisherman.EatAnimation })
    local reply = self.replies[#self.replies].payload
    lu.assertTrue(reply.ok)
    lu.assertNil(reply.coins)
    lu.assertEquals(reply.exchange, { from = 'eelHead', to = 'duck' })
end

function TestFeedExchange:test_gar_head_exchanges_for_one_shrimp_ticket()
    local slot = self:give('garHead')
    lu.assertTrue(self.data:SelectSlot(slot))
    lu.assertTrue(self:feed())
    lu.assertEquals(self:countItem('garHead'), 0)
    lu.assertEquals(self:countItem('shrimpTicket'), 1)
    lu.assertEquals(self.data.Data.FishCoin, 0)
    lu.assertEquals(self.replies[#self.replies].payload.exchange, { from = 'garHead', to = 'shrimpTicket' })
end

-- #127 容量口径：先交付选中格、再校验交付后的容量，满格也能用释放出的格位成交
function TestFeedExchange:test_full_storage_exchanges_using_the_released_slot()
    local slot = self:give('eelHead')
    self:fillExcept(slot)
    lu.assertTrue(self.data:SelectSlot(slot))
    lu.assertTrue(self:feed())
    lu.assertEquals(self:countItem('eelHead'), 0)
    lu.assertEquals(self:countItem('duck'), 1)
    lu.assertEquals(self.data.Data.FishCoin, 0)
    lu.assertEquals(self.plays, { self.cfg.Interact.Fisherman.EatAnimation })
    local bar = self.data.Data.Containers.itemBar
    lu.assertEquals(bar[slot] and bar[slot].itemId, 'duck', '产物落进本次交付释放出的格')
    lu.assertEquals(self.replies[#self.replies].payload.exchange, { from = 'eelHead', to = 'duck' })
end

function TestFeedExchange:test_product_lands_in_first_free_slot()
    -- 信物扣掉后它自己的格就是第一个空格，产物落在那里（与 AddItem「优先填道具栏」一致）
    local slot = self:give('eelHead')
    lu.assertTrue(self.data:AddItem('tilapia')) -- 道具栏第二格占满
    lu.assertTrue(self.data:SelectSlot(slot))
    lu.assertTrue(self:feed())
    local bar = self.data.Data.Containers.itemBar
    lu.assertNotNil(bar[slot])
    lu.assertEquals(bar[slot].itemId, 'duck')
    lu.assertEquals(bar[slot].count, 1)
    lu.assertEquals(self:countItem('eelHead'), 0)
end

function TestFeedExchange:test_selected_token_wins_over_selected_bait()
    self.data.Data.Bait.worm = 5
    local slot = self:give('eelHead')
    lu.assertTrue(self.data:SelectSlot(slot))
    lu.assertTrue(self.data:SelectBait('worm'))
    lu.assertTrue(self:feed())
    lu.assertEquals(self:countItem('duck'), 1)
    lu.assertEquals(self.data.Data.Bait.worm, 5)
    lu.assertEquals(self.data.Data.FishCoin, 0)
end

function TestFeedExchange:test_unselected_token_does_not_block_normal_coin_feed()
    self:give('eelHead')
    local fishSlot = self:give('carp')
    lu.assertTrue(self.data:SelectSlot(fishSlot))
    lu.assertTrue(self:feed())
    lu.assertEquals(self.data.Data.FishCoin, self.cfg.Fish.carp.BasePrice)
    lu.assertEquals(self:countItem('eelHead'), 1)
    lu.assertEquals(self:countItem('duck'), 0)
end

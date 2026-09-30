-- #127 T06 七区兑换与回收（GameSpec §8.1 / 路线图 §8.1 已确认）：每区一个钓鱼佬，
-- 选中**未烤**的本区信物时按本区链 1:1 兑换（精英信物 → 首领饵，首领信物 → 本区产物/最终成就）；
-- 其余选中物品按物品表基础价 × 实例倍率回收金币；烤过的信物不再兑换，只按烤熟价（×1.5）售卖。
-- 容量：先交付选中格、再按交付后的容量校验，用本次交付释放的格位是合法的；最终容量不足时拒绝且不扣物品。
-- 失败方式（先列后写）：
--   1. 七区钓鱼佬缺区、锚点串区，或兑换链串区（第二区 NPC 用了第一区的链）；
--   2. 未烤信物不走本区链而按基础价卖金币；烤过的信物仍走兑换；
--   3. 满格时拒绝兑换（应释放选中格后成交），或产物没落进释放出的格；
--   4. 兑换扣了却没发 / 发了却没扣、动了金币、选中态没归位、没推库存；
--   5. 普通物品（鱼竿、道具、船票）不能回收，或忽略实例倍率、烤熟价没有 ×1.5、鱼获用了商店买入价；
--   6. 第七区最终成就没落进存档（Extra.achievements），或白占道具格；
--   7. 只在本区 NPC 才成交：站在别的区（含锚点范围外）也能用别区链兑换。
local lu = require('luaunit')

TestExchangeZones = {}

local function vec(x, y, z) return { x = x, y = y, z = z } end

-- 场景合同（#125）里的某个角色实体；钓鱼佬位置是唯一真源
local function sceneEntity(zone, role)
    for _, entity in ipairs(zone.Scene.Entities) do
        if entity.Role == role then return entity end
    end
end

function TestExchangeZones:setUp()
    local env = self
    self.savedGame = _G.game
    self.savedCfg = package.loaded['common.GameCfg']
    package.loaded['common.GameCfg'] = nil
    self.cfg = require('common.GameCfg')
    -- 关掉进图白送，库存完全由用例自己摆
    self.cfg.Debug = { Enabled = false }
    self.PlayerData = assert(loadfile('server/Data/PlayerData.lua'))()
    self.attrs = {}
    self.player = { UserId = 1, Character = { Position = vec(0, 0, 0) },
        SetAttribute = function(_, k, v) env.attrs[k] = v end }
    -- 七区钓鱼佬锚点：名字与位置都取 #125 场景合同
    self.anchors = {}
    self.plays = {}
    for index, zone in ipairs(self.cfg.Zones) do
        local entity = sceneEntity(zone, 'Fisherman')
        for _, name in ipairs(self.cfg.Interact.Fishermen[index].AnchorNames) do
            self.anchors[name] = { Name = name, Position = entity.Position,
                PlayAnimation = function(_, animation) env.plays[#env.plays + 1] = animation end }
        end
    end
    self.synced = {}
    self.replies = {}
    self.mgr = assert(loadfile('server/Mgr/MgrInteract.lua'))()
    self.mgr.FindAnchor = function(_, name) return env.anchors[name] end
    self.mgr.PlayerData = {
        GetDataInst = function(_, p) return p == env.player and env.data or nil end,
        SendItemBar = function(_, p) env.synced[#env.synced + 1] = p end,
    }
    self.mgr.Reply = function(_, p, payload) env.replies[#env.replies + 1] = { player = p, payload = payload } end
    self:resetInventory()
    self:standAt(1)
    self.seq = 0
end

function TestExchangeZones:tearDown()
    package.loaded['common.GameCfg'] = self.savedCfg
    _G.game = self.savedGame
end

-- 每个区的链路用例都从干净库存开始：道具栏只有 2 格，七个区的产物会挤掉后续信物的落点。
-- seq 不重置：同会话序号严格递增是客户端契约，重放/旧序号一律拒绝
function TestExchangeZones:resetInventory()
    self.data = self.PlayerData.New(self.player, function() end)
    self.data:Init()
    self.synced, self.replies, self.plays = {}, {}, {}
end

-- 站到第 zoneIndex 区钓鱼佬锚点上
function TestExchangeZones:standAt(zoneIndex)
    local name = self.cfg.Interact.Fishermen[zoneIndex].AnchorNames[1]
    local center = self.anchors[name].Position
    self.player.Character.Position = vec(center.x + 1, center.y, center.z)
end

function TestExchangeZones:feed()
    self.seq = self.seq + 1
    return self.mgr:Handle(self.player, { target = 'fisherman', action = 'Feed', seq = self.seq })
end

function TestExchangeZones:give(itemId, mult)
    lu.assertTrue(self.data:AddItem(itemId, mult))
    local bar = self.data.Data.Containers[self.cfg.Items.ContainerId.ItemBar]
    for index = 1, self.data:ItemBarCapacity() do
        if bar[index] and bar[index].itemId == itemId and bar[index].mult == mult then return index end
    end
end

function TestExchangeZones:countItem(itemId)
    local total = 0
    for _, container in pairs(self.data.Data.Containers) do
        for _, entry in pairs(container) do
            if entry.itemId == itemId then total = total + entry.count end
        end
    end
    return total
end

function TestExchangeZones:lastReply()
    return self.replies[#self.replies] and self.replies[#self.replies].payload
end

-- 配置：每区一个钓鱼佬，锚点与兑换链都按本区派生，共享表现参数仍在 Fisherman
function TestExchangeZones:test_fishermen_are_dispatched_per_zone_with_that_zone_chain()
    lu.assertEquals(#self.cfg.Interact.Fishermen, #self.cfg.Zones)
    lu.assertEquals(#self.cfg.Interact.Fishermen, 7)
    for index, chain in ipairs(self.cfg.Content.Exchanges) do
        local npc = self.cfg.Interact.Fishermen[index]
        lu.assertEquals(npc.ZoneId, chain.ZoneId)
        lu.assertEquals(npc.AnchorNames, { self.cfg.Zones[index].Scene.FishermanName })
        lu.assertEquals(npc.Exchange[chain.EliteToken], chain.BossBait)
        lu.assertEquals(npc.Exchange[chain.BossToken], chain.Result)
        -- 串区自检：本区链恰好两条，且不含别区信物
        local count = 0
        for _ in pairs(npc.Exchange) do count = count + 1 end
        lu.assertEquals(count, 2)
        for other, otherChain in ipairs(self.cfg.Content.Exchanges) do
            if other ~= index then
                lu.assertNil(npc.Exchange[otherChain.EliteToken])
                lu.assertNil(npc.Exchange[otherChain.BossToken])
            end
        end
    end
    lu.assertEquals(self.cfg.Interact.Fisherman.Radius, 5)
    lu.assertEquals(self.cfg.Interact.Fisherman.BaitPrice, { worm = 1 })
end

-- 回收价：鱼获走 FishCatch（含烤熟 ×1.5），其余物品走物品表 BasePrice；查不到的 id 不可回收
function TestExchangeZones:test_sale_price_covers_plain_items_fish_mult_and_cooking()
    local Items = self.cfg.Items
    lu.assertEquals(Items.SalePrice('starterRod'), 3)
    lu.assertEquals(Items.SalePrice('starterRod', nil, true), 4)   -- floor(3 × 1.5)
    lu.assertEquals(Items.SalePrice('item147'), 1)                 -- 蟹湖船票
    lu.assertEquals(Items.SalePrice('garHead'), 20)
    lu.assertEquals(Items.SalePrice('garHead', nil, true), 30)
    lu.assertEquals(Items.SalePrice('bass', 1.99), 11)             -- 与 FishCatch.Price 同源
    lu.assertEquals(Items.SalePrice('bass', 1.99, true), 17)       -- floor(6 × 1.99 × 1.5)
    lu.assertEquals(Items.SalePrice('tilapia'), 3)
    lu.assertNil(Items.SalePrice('notAnItem'))
    lu.assertNil(Items.SalePrice(nil))
end

-- 七区链：每区未烤精英信物 → 本区首领饵，未烤首领信物 → 本区产物（第七区是最终成就）
function TestExchangeZones:test_each_zone_chain_exchanges_in_that_zone()
    for index, chain in ipairs(self.cfg.Content.Exchanges) do
        self:resetInventory()
        self:standAt(index)
        local eliteSlot = self:give(chain.EliteToken)
        lu.assertTrue(self.data:SelectSlot(eliteSlot))
        lu.assertTrue(self:feed(), '第' .. index .. '区精英信物应兑换')
        lu.assertEquals(self:countItem(chain.EliteToken), 0)
        lu.assertEquals(self:countItem(chain.BossBait), 1)
        lu.assertEquals(self.data.Data.FishCoin, 0, '兑换不给金币')
        lu.assertNil(self.data.Data.SelectedSlot, '兑换后选中态要归位')
        lu.assertEquals(self:lastReply().exchange, { from = chain.EliteToken, to = chain.BossBait })
        lu.assertEquals(self.synced, { self.player }, '兑换成功后要推一次库存')

        local bossSlot = self:give(chain.BossToken)
        lu.assertTrue(self.data:SelectSlot(bossSlot))
        lu.assertTrue(self:feed(), '第' .. index .. '区首领信物应兑换')
        lu.assertEquals(self:countItem(chain.BossToken), 0)
        if chain.Result == 'achievement.final' then
            lu.assertTrue(self.data.Extra.achievements.final, '第七区要写最终成就')
            lu.assertEquals(self:lastReply().achievement, 'final')
        else
            lu.assertEquals(self:countItem(chain.Result), 1)
            lu.assertEquals(self:lastReply().exchange, { from = chain.BossToken, to = chain.Result })
        end
        lu.assertEquals(self.data.Data.FishCoin, 0)
        lu.assertEquals(self.plays, {}, '本用例没有配吃动作，不播也不影响结算')
    end
end

-- 只在本区成交：站在第二区 NPC 边用第一区信物，按普通物品回收而不是兑换
function TestExchangeZones:test_other_zone_token_is_recycled_not_exchanged()
    self:standAt(2)
    local slot = self:give('eelHead')
    lu.assertTrue(self.data:SelectSlot(slot))
    lu.assertTrue(self:feed())
    lu.assertEquals(self:countItem('eelHead'), 0)
    lu.assertEquals(self:countItem('duck'), 0, '别区信物不能换首领饵')
    lu.assertEquals(self.data.Data.FishCoin, self.cfg.Items.SalePrice('eelHead'))
    lu.assertNil(self:lastReply().exchange)
end

-- 烤过的信物只售卖：按烤熟价（基础价 × 倍率 × 1.5）结金币，不再走兑换
function TestExchangeZones:test_cooked_token_is_sold_only()
    local slot = self:give('garHead')
    self.data.Data.Containers.itemBar[slot].saved = { [self.cfg.Items.CookedFlag] = true }
    lu.assertTrue(self.data:SelectSlot(slot))
    lu.assertTrue(self:feed())
    lu.assertEquals(self:countItem('garHead'), 0)
    lu.assertEquals(self:countItem('shrimpTicket'), 0, '烤过的首领信物不能再换船票')
    lu.assertEquals(self.data.Data.FishCoin, 30) -- floor(20 × 1 × 1.5)
    lu.assertNil(self:lastReply().exchange)
end

-- 满格：先交付选中格再校验容量，产物落进释放出来的那一格
function TestExchangeZones:test_full_storage_exchanges_using_the_released_slot()
    local slot = self:give('garHead')
    lu.assertTrue(self.data:SelectSlot(slot))
    while self.data:AddItem('tilapia') do end
    lu.assertEquals(self.data:AddItem('tilapia'), false, '前置：道具栏与背包都满了')
    lu.assertTrue(self:feed())
    local bar = self.data.Data.Containers.itemBar
    lu.assertEquals(bar[slot] and bar[slot].itemId, 'shrimpTicket')
    lu.assertEquals(self:countItem('garHead'), 0)
    lu.assertEquals(self.data.Data.FishCoin, 0)
    lu.assertEquals(self:lastReply().exchange, { from = 'garHead', to = 'shrimpTicket' })
end

-- 普通物品回收：鱼竿、船票、鱼获都按基础价 × 实例倍率，烤过的按烤熟价
function TestExchangeZones:test_plain_items_are_recycled_at_base_price_times_mult()
    local rodSlot = self:give('normalRod')          -- 基础价 25、无倍率
    lu.assertTrue(self.data:SelectSlot(rodSlot))
    lu.assertTrue(self:feed())
    lu.assertEquals(self.data.Data.FishCoin, 25)
    lu.assertEquals(self:countItem('normalRod'), 0)

    local fishSlot = self:give('bass', 1.99)        -- 6 × 1.99 = 11
    lu.assertTrue(self.data:SelectSlot(fishSlot))
    lu.assertTrue(self:feed())
    lu.assertEquals(self.data.Data.FishCoin, 36)

    local cookedSlot = self:give('bass', 1.99)
    self.data.Data.Containers.itemBar[cookedSlot].saved = { [self.cfg.Items.CookedFlag] = true }
    lu.assertTrue(self.data:SelectSlot(cookedSlot))
    lu.assertTrue(self:feed())                      -- floor(6 × 1.99 × 1.5) = 17
    lu.assertEquals(self.data.Data.FishCoin, 53)

    local ticketSlot = self:give('item147')         -- 蟹湖船票，基础价 1
    lu.assertTrue(self.data:SelectSlot(ticketSlot))
    lu.assertTrue(self:feed())
    lu.assertEquals(self.data.Data.FishCoin, 54)
    lu.assertEquals(self:lastReply().category, 'item')
end

-- 超出范围（含站在别的区）不结算，也不误伤库存
function TestExchangeZones:test_out_of_range_never_settles()
    local slot = self:give('garHead')
    lu.assertTrue(self.data:SelectSlot(slot))
    self.player.Character.Position = vec(9999, 0, 9999)
    lu.assertFalse(self:feed())
    lu.assertEquals(self:countItem('garHead'), 1)
    lu.assertEquals(self.data.Data.FishCoin, 0)
    lu.assertEquals(self.replies, {})
end

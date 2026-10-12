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
-- 迁移自 tests/gameplay/exchange_zones_127_test.lua（#83）。旧 setUp 逐例装配夹具（含把 GameCfg
-- 从模块缓存摘下重装）并预置站位，旧 tearDown 装回缓存与 _G.game；映射为逐例 before_each/after_each，
-- 保留「setup 失败仍完成清理」的行为。it 顺序沿用旧入口的方法名字典序，与迁移前逐条对账。
-- 断言口径：旧 assertEquals 两侧同为 table 时是深比较 → assert.same；标量 → assert.are.equal。

local function vec(x, y, z) return { x = x, y = y, z = z } end

-- 场景合同（#125）里的某个角色实体；钓鱼佬位置是唯一真源
local function sceneEntity(zone, role)
  for _, entity in ipairs(zone.Scene.Entities) do
    if entity.Role == role then return entity end
  end
end

describe("TestExchangeZones", function()
  local t

  -- 旧类的 self:xxx 辅助方法（不以 test 开头，旧入口不会收集）在这里还原为闭包函数，
  -- 统一读 describe 级的 t；before_each 先装好 t 再调用它们。

  -- 每个区的链路用例都从干净库存开始：道具栏只有 2 格，七个区的产物会挤掉后续信物的落点。
  -- seq 不重置：同会话序号严格递增是客户端契约，重放/旧序号一律拒绝
  local function resetInventory()
    t.data = t.PlayerData.New(t.player, function() end)
    t.data:Init()
    t.synced, t.replies, t.plays = {}, {}, {}
  end

  -- 站到第 zoneIndex 区钓鱼佬锚点上
  local function standAt(zoneIndex)
    local name = t.cfg.Interact.Fishermen[zoneIndex].AnchorNames[1]
    local center = t.anchors[name].Position
    t.player.Character.Position = vec(center.x + 1, center.y, center.z)
  end

  local function feed()
    t.seq = t.seq + 1
    return t.mgr:Handle(t.player, { target = 'fisherman', action = 'Feed', seq = t.seq })
  end

  local function give(itemId, mult)
    assert.is_true(t.data:AddItem(itemId, mult))
    local bar = t.data.Data.Containers[t.cfg.Items.ContainerId.ItemBar]
    for index = 1, t.data:ItemBarCapacity() do
      if bar[index] and bar[index].itemId == itemId and bar[index].mult == mult then return index end
    end
  end

  local function countItem(itemId)
    local total = 0
    for _, container in pairs(t.data.Data.Containers) do
      for _, entry in pairs(container) do
        if entry.itemId == itemId then total = total + entry.count end
      end
    end
    return total
  end

  local function lastReply()
    return t.replies[#t.replies] and t.replies[#t.replies].payload
  end

  before_each(function()
    local env = {}
    t = env
    env.savedGame = rawget(_G, 'game')
    env.savedCfg = package.loaded['common.GameCfg']
    package.loaded['common.GameCfg'] = nil
    env.cfg = require('common.GameCfg')
    -- 关掉进图白送，库存完全由用例自己摆
    env.cfg.Debug = { Enabled = false }
    env.PlayerData = assert(loadfile('server/Data/PlayerData.lua'))()
    env.attrs = {}
    env.player = { UserId = 1, Character = { Position = vec(0, 0, 0) },
      SetAttribute = function(_, k, v) env.attrs[k] = v end }
    -- 七区钓鱼佬锚点：名字与位置都取 #125 场景合同
    env.anchors = {}
    env.plays = {}
    for index, zone in ipairs(env.cfg.Zones) do
      local entity = sceneEntity(zone, 'Fisherman')
      for _, name in ipairs(env.cfg.Interact.Fishermen[index].AnchorNames) do
        env.anchors[name] = { Name = name, Position = entity.Position,
          PlayAnimation = function(_, animation) env.plays[#env.plays + 1] = animation end }
      end
    end
    env.synced = {}
    env.replies = {}
    env.mgr = assert(loadfile('server/Mgr/MgrInteract.lua'))()
    env.mgr.FindAnchor = function(_, name) return env.anchors[name] end
    env.mgr.PlayerData = {
      GetDataInst = function(_, p) return p == env.player and env.data or nil end,
      SendItemBar = function(_, p) env.synced[#env.synced + 1] = p end,
    }
    env.mgr.Reply = function(_, p, payload) env.replies[#env.replies + 1] = { player = p, payload = payload } end
    resetInventory()
    standAt(1)
    env.seq = 0
  end)

  after_each(function()
    package.loaded['common.GameCfg'] = t.savedCfg
    _G.game = t.savedGame
    t = nil
  end)

  -- 烤过的信物只售卖：按烤熟价（基础价 × 倍率 × 1.5）结金币，不再走兑换
  it("test_cooked_token_is_sold_only", function()
    local slot = give('garHead')
    t.data.Data.Containers.itemBar[slot].saved = { [t.cfg.Items.CookedFlag] = true }
    assert.is_true(t.data:SelectSlot(slot))
    assert.is_true(feed())
    assert.are.equal(0, countItem('garHead'))
    assert.are.equal(0, countItem('shrimpTicket'), '烤过的首领信物不能再换船票')
    assert.are.equal(30, t.data.Data.FishCoin) -- floor(20 × 1 × 1.5)
    assert.is_nil(lastReply().exchange)
  end)

  -- 七区链：每区未烤精英信物 → 本区首领饵，未烤首领信物 → 本区产物（第七区是最终成就）
  it("test_each_zone_chain_exchanges_in_that_zone", function()
    for index, chain in ipairs(t.cfg.Content.Exchanges) do
      resetInventory()
      standAt(index)
      local eliteSlot = give(chain.EliteToken)
      assert.is_true(t.data:SelectSlot(eliteSlot))
      assert.is_true(feed(), '第' .. index .. '区精英信物应兑换')
      assert.are.equal(0, countItem(chain.EliteToken))
      assert.are.equal(1, countItem(chain.BossBait))
      assert.are.equal(0, t.data.Data.FishCoin, '兑换不给金币')
      assert.is_nil(t.data.Data.SelectedSlot, '兑换后选中态要归位')
      assert.same({ from = chain.EliteToken, to = chain.BossBait }, lastReply().exchange)
      assert.same({ t.player }, t.synced, '兑换成功后要推一次库存')

      local bossSlot = give(chain.BossToken)
      assert.is_true(t.data:SelectSlot(bossSlot))
      assert.is_true(feed(), '第' .. index .. '区首领信物应兑换')
      assert.are.equal(0, countItem(chain.BossToken))
      if chain.Result == 'achievement.final' then
        assert.is_true(t.data.Extra.achievements.final, '第七区要写最终成就')
        assert.are.equal('final', lastReply().achievement)
      else
        assert.are.equal(1, countItem(chain.Result))
        assert.same({ from = chain.BossToken, to = chain.Result }, lastReply().exchange)
      end
      assert.are.equal(0, t.data.Data.FishCoin)
      assert.same({}, t.plays, '本用例没有配吃动作，不播也不影响结算')
    end
  end)

  -- #38 失败方式：不同 operation 再交哥斯拉头又消耗；唯一性须随真实存档而非会话序号保存。
  it("test_final_achievement_refuses_another_head_without_consuming_it", function()
    standAt(7)
    local first = give('item112')
    t.data:SelectSlot(first)
    assert.is_true(feed())
    local second = give('item112')
    t.data:SelectSlot(second)
    assert.is_false(feed())
    assert.are.equal(1, countItem('item112'))
    assert.is_true(t.data.Extra.achievements.final)
    assert.are.equal('already-completed', lastReply().reason)
  end)

  -- 配置：每区一个钓鱼佬，锚点与兑换链都按本区派生，共享表现参数仍在 Fisherman
  it("test_fishermen_are_dispatched_per_zone_with_that_zone_chain", function()
    assert.are.equal(#t.cfg.Zones, #t.cfg.Interact.Fishermen)
    assert.are.equal(7, #t.cfg.Interact.Fishermen)
    for index, chain in ipairs(t.cfg.Content.Exchanges) do
      local npc = t.cfg.Interact.Fishermen[index]
      assert.are.equal(chain.ZoneId, npc.ZoneId)
      assert.same({ t.cfg.Zones[index].Scene.FishermanName }, npc.AnchorNames)
      assert.are.equal(chain.BossBait, npc.Exchange[chain.EliteToken])
      assert.are.equal(chain.Result, npc.Exchange[chain.BossToken])
      -- 串区自检：本区链恰好两条，且不含别区信物
      local count = 0
      for _ in pairs(npc.Exchange) do count = count + 1 end
      assert.are.equal(2, count)
      for other, otherChain in ipairs(t.cfg.Content.Exchanges) do
        if other ~= index then
          assert.is_nil(npc.Exchange[otherChain.EliteToken])
          assert.is_nil(npc.Exchange[otherChain.BossToken])
        end
      end
    end
    assert.are.equal(5, t.cfg.Interact.Fisherman.Radius)
    assert.same({ worm = 1 }, t.cfg.Interact.Fisherman.BaitPrice)
  end)

  -- 满格：先交付选中格再校验容量，产物落进释放出来的那一格
  it("test_full_storage_exchanges_using_the_released_slot", function()
    local slot = give('garHead')
    assert.is_true(t.data:SelectSlot(slot))
    while t.data:AddItem('tilapia') do end
    assert.is_false(t.data:AddItem('tilapia'), '前置：道具栏与背包都满了')
    assert.is_true(feed())
    local bar = t.data.Data.Containers.itemBar
    assert.are.equal('shrimpTicket', bar[slot] and bar[slot].itemId)
    assert.are.equal(0, countItem('garHead'))
    assert.are.equal(0, t.data.Data.FishCoin)
    assert.same({ from = 'garHead', to = 'shrimpTicket' }, lastReply().exchange)
  end)

  -- 只在本区成交：站在第二区 NPC 边用第一区信物，按普通物品回收而不是兑换
  it("test_other_zone_token_is_recycled_not_exchanged", function()
    standAt(2)
    local slot = give('eelHead')
    assert.is_true(t.data:SelectSlot(slot))
    assert.is_true(feed())
    assert.are.equal(0, countItem('eelHead'))
    assert.are.equal(0, countItem('duck'), '别区信物不能换首领饵')
    assert.are.equal(t.cfg.Items.SalePrice('eelHead'), t.data.Data.FishCoin)
    assert.is_nil(lastReply().exchange)
  end)

  -- 超出范围（含站在别的区）不结算，也不误伤库存
  it("test_out_of_range_never_settles", function()
    local slot = give('garHead')
    assert.is_true(t.data:SelectSlot(slot))
    t.player.Character.Position = vec(9999, 0, 9999)
    assert.is_false(feed())
    assert.are.equal(1, countItem('garHead'))
    assert.are.equal(0, t.data.Data.FishCoin)
    assert.same({}, t.replies)
  end)

  -- 普通物品回收：鱼竿、船票、鱼获都按基础价 × 实例倍率，烤过的按烤熟价
  it("test_plain_items_are_recycled_at_base_price_times_mult", function()
    local rodSlot = give('normalRod')          -- 基础价 25、无倍率
    assert.is_true(t.data:SelectSlot(rodSlot))
    assert.is_true(feed())
    assert.are.equal(25, t.data.Data.FishCoin)
    assert.are.equal(0, countItem('normalRod'))

    local fishSlot = give('bass', 1.99)        -- 6 × 1.99 = 11
    assert.is_true(t.data:SelectSlot(fishSlot))
    assert.is_true(feed())
    assert.are.equal(36, t.data.Data.FishCoin)

    local cookedSlot = give('bass', 1.99)
    t.data.Data.Containers.itemBar[cookedSlot].saved = { [t.cfg.Items.CookedFlag] = true }
    assert.is_true(t.data:SelectSlot(cookedSlot))
    assert.is_true(feed())                      -- floor(6 × 1.99 × 1.5) = 17
    assert.are.equal(53, t.data.Data.FishCoin)

    local ticketSlot = give('item147')         -- 蟹湖船票，基础价 1
    assert.is_true(t.data:SelectSlot(ticketSlot))
    assert.is_true(feed())
    assert.are.equal(54, t.data.Data.FishCoin)
    assert.are.equal('item', lastReply().category)
  end)

  -- 回收价：鱼获走 FishCatch（含烤熟 ×1.5），其余物品走物品表 BasePrice；查不到的 id 不可回收
  it("test_sale_price_covers_plain_items_fish_mult_and_cooking", function()
    local Items = t.cfg.Items
    assert.are.equal(3, Items.SalePrice('starterRod'))
    assert.are.equal(4, Items.SalePrice('starterRod', nil, true))   -- floor(3 × 1.5)
    assert.are.equal(1, Items.SalePrice('item147'))                 -- 蟹湖船票
    assert.are.equal(20, Items.SalePrice('garHead'))
    assert.are.equal(30, Items.SalePrice('garHead', nil, true))
    assert.are.equal(11, Items.SalePrice('bass', 1.99))             -- 与 FishCatch.Price 同源
    assert.are.equal(17, Items.SalePrice('bass', 1.99, true))       -- floor(6 × 1.99 × 1.5)
    assert.are.equal(3, Items.SalePrice('tilapia'))
    assert.is_nil(Items.SalePrice('notAnItem'))
    assert.is_nil(Items.SalePrice(nil))
  end)
end)

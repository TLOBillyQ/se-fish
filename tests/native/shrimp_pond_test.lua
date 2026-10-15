-- 迁移自 tests/gameplay/shrimp_pond_test.lua（#85）；行为契约原文见 #90、#127、#136、#141、#142、#84、#49。
-- #90 虾池最小内容：虾池水区与鱼表、香肠（饵）、虾池商店（2 级摊位）、虾池钓鱼佬（多锚点回收）。
-- 失败方式（先列后写）：
--   1. 香肠没配 Container='bait'：买了占道具栏格、不进 Bait 计数，挂饵挂不上；
--   2. 摊位等级用错：一区摊能买香肠 / 钓虾竿，或虾池摊买不到；价格不是 2 / 12；
--   3. 摊位范围复验丢失：不在任何摊位旁也能买，或玩家位置不影响按哪个摊位结算；
--   4. 虾池鱼表配错：新手竿（竿 1）能出波龙及以上、不挂饵出不了虾米保底、
--      挂香肠竿 1 能出竿 2 的虾，或鱼表行指向 GameCfg.Fish 里不存在的鱼种；
--   5. 虾池水区没进 Water.Zones（抛竿选不到虾池鱼表），或与一区水区重叠（在虾池抛竿出一区鱼）；
--   6. 钓鱼佬多锚点回归：一区钓鱼佬失效，或虾池钓鱼佬（TGUnitFishShrimp）旁喂食不结算；
--   7. 抛竿竿种门：选中的不是竿（无 Level）也能抛，或钓虾竿抛出去竿级按 1 算（抽不出波龙）。
--   8. 虾池迁移统一模板后残留小池几何、窄边界或旧设施落点，运行时水域与场景合同不一致。
-- it 名字沿用旧方法名，注册顺序 = LuaUnit sortedPairs 的实际执行顺序。

local function vec(x, y, z) return { x = x, y = y, z = z } end

-- 两个商店摊与两个钓鱼佬锚点的假位置；虾池侧与统一模板的场景合同一致。
local ANCHORS = {
  TGUnitShop = vec(0, 2, 0),
  TGUnitShopShrimp = vec(216, 6, 13),
  TGUnitFish = vec(0, 6, 10),
  TGUnitFishShrimp = vec(213, 6, -17),
}

local function newInteract()
  return {
    FindAnchor = function(_, name)
      local pos = ANCHORS[name]
      return pos and { Name = name, Position = pos } or nil
    end,
    InRange = function(_, player, point)
      local pos = player.Character and player.Character.Position
      local anchor = ANCHORS[point.AnchorName]
      if not pos or not anchor then return nil end
      local dx, dz = pos.x - anchor.x, pos.z - anchor.z
      if math.sqrt(dx * dx + dz * dz) > point.Radius + point.Slack then return nil end
      return { Name = point.AnchorName, Position = anchor }
    end,
  }
end

local function collectSelectable(rows, rodLevel, baitId)
  local FishCatch = require('common.FishCatch')
  local total = 0
  for _, row in ipairs(rows) do
    if row.RodLevel <= rodLevel and (row.Bait == 0 or row.Bait == baitId) then
      total = total + row.DrawWeight
    end
  end
  local found = {}
  for roll = 1, total do
    local id = FishCatch.Select(rows, rodLevel, baitId, function() return roll end)
    found[id] = true
  end
  return found
end

describe('虾池最小内容（水区 / 鱼表 / 商店 / 钓鱼佬 / 抛竿）', function()
  local env
  local restore

  before_each(function()
    -- 快照先于任何改动：before_each 中途失败时 after_each 仍能还原。
    restore = {
      game = rawget(_G, 'game'),
      GameCfg = package.loaded['common.GameCfg'],
      REUtil = package.loaded['common.REUtil'],
      MgrPlayerData = package.loaded['server.Mgr.MgrPlayerData'],
      MgrFishUnit = package.loaded['server.Mgr.MgrFishUnit'],
    }
    env = { replies = {}, sent = {}, seq = 0, now = 0 }
    package.loaded['common.GameCfg'] = nil
    env.cfg = require('common.GameCfg')
    -- 与 shop_test 同一口径：吃 #49 调试白送的起始库存（鱼竿第 1 格、蚯蚓若干）
    env.cfg.Debug = { Enabled = true, InitialGrants = env.cfg.Debug.InitialGrants }
    local PlayerData = assert(loadfile('server/Data/PlayerData.lua'))()
    env.me = { UserId = 1, Character = { Position = vec(0, 2, 2) }, SetAttribute = function() end }
    env.data = PlayerData.New(env.me)
    env.data:Init()
    env.shop = assert(loadfile('server/Mgr/MgrShop.lua'))()
    env.shop.PlayerData = {
      GetDataInst = function(_, p) return p == env.me and env.data or nil end,
      SendItemBar = function() end,
    }
    env.shop.Interact = newInteract()
    env.shop.Reply = function(_, _, result) env.replies[#env.replies + 1] = result end
    -- MgrCast 桩（与 boss_bait_test 同口径）：REUtil 记录下发，PlayerData/FishUnit 指向真数据
    env.me.Character.Rotation = { GetForward = function() return vec(0, 0, 1) end }
    package.loaded['common.REUtil'] = {
      GetRE = function(_, name)
        env.sent[name] = env.sent[name] or {}
        return { FireClient = function(_, _, payload)
          env.sent[name][#env.sent[name] + 1] = payload
        end }
      end,
      CheckRECD = function() return false end,
    }
    package.loaded['server.Mgr.MgrPlayerData'] = {
      GetDataInst = function(_, p) return p == env.me and env.data or nil end,
      SendItemBar = function() end,
    }
    package.loaded['server.Mgr.MgrFishUnit'] = {
      HeldInfo = function() return nil end,
      CanCast = function() return true end,
    }
    env.cast = assert(loadfile('server/Mgr/MgrCast.lua'))()
    env.cast.World = { GetServerTime = function() return env.now end }
    env.cast.ReelIn = { Begin = function() return true end }
  end)

  after_each(function()
    package.loaded['common.GameCfg'] = restore and restore.GameCfg
    package.loaded['common.REUtil'] = restore and restore.REUtil
    package.loaded['server.Mgr.MgrPlayerData'] = restore and restore.MgrPlayerData
    package.loaded['server.Mgr.MgrFishUnit'] = restore and restore.MgrFishUnit
    _G.game = restore and restore.game
    env = nil
    restore = nil
  end)

  local function buy(itemId)
    env.seq = env.seq + 1
    return env.shop:Handle(env.me, { action = 'Buy', itemId = itemId, seq = env.seq })
  end

  local function lastReason()
    local last = env.replies[#env.replies]
    return last and last.reason
  end

  local function moveTo(name)
    local anchor = ANCHORS[name]
    env.me.Character.Position = vec(anchor.x + 1, anchor.y, anchor.z)
  end

  -- 站在虾池岸上 z=-29 朝 -Z 抛 5 米，落点 (240,3,-34) 进入新水面。
  local function standAtPool()
    env.me.Character.Position = vec(240, 6, -29)
    env.me.Character.Rotation = { GetForward = function() return vec(0, 0, -1) end }
  end

  it('虾池套用统一模板并迁移运行时水域', function()
    local scene = env.cfg.Zones[2].Scene
    assert.same('planned', scene.State)
    assert.same({ MinX = 180, MaxX = 300, MinZ = -70, MaxZ = 50,
      BottomY = -30, TopY = 40, MaxFlightHeight = 20, CanClimb = false,
      EntityNames = scene.Boundary.EntityNames }, scene.Boundary)
    assert.same({ x = 240, y = 6, z = 30.5 }, scene.SafePoint)
    local positions = {}
    for _, entity in ipairs(scene.Entities) do positions[entity.Name] = entity.Position end
    assert.same({ x = 213, y = 6, z = -17 }, positions.TGUnitFishShrimp)
    assert.same({ x = 216, y = 6, z = 13 }, positions.TGUnitShopShrimp)
    assert.same({ x = 258, y = 6, z = -18 }, positions.Z2_Lottery)
    assert.same({ x = 188, y = 6, z = -24 }, positions.Z2_Bait1)
    assert.same({ x = 292, y = 6, z = -24 }, positions.Z2_Bait2)
    assert.same({ x = 215, y = 6, z = 40.5 }, positions.Z2_FerryOut)
    assert.same({ x = 265, y = 6, z = 40.5 }, positions.FerryReturn)
    assert.same('Z2_Land', scene.LandName)
    assert.same('Z2_Water', scene.Waters[1].EntityName)
    assert.same({ x = 240, y = 2, z = -44 }, scene.Waters[1].Center)
    assert.same(40, scene.Waters[1].HalfX)
    assert.same(12, scene.Waters[1].HalfZ)
    assert.same(3, scene.Waters[1].SurfaceY)
    assert.same('shrimpPond.water', scene.Waters[1].Id)
    assert.same('shrimpPond', env.cfg.Water.ZoneIdByWater['shrimpPond.water'])
    assert.is_not_nil(env.cfg.Casting.Zones['shrimpPond.water'])
    assert.is_nil(env.cfg.Casting.Zones.ShrimpPool)
    assert.is_nil(env.cfg.Water.ZoneIdByWater.ShrimpPool)
    local runtimeWater
    for _, water in ipairs(env.cfg.Water.Zones) do
      assert.is_not.equal('ShrimpPool', water.Id)
      if water.Id == 'shrimpPond.water' then runtimeWater = water end
    end
    assert.is_not_nil(runtimeWater)
    assert.same(scene.Waters[1].Center, runtimeWater.Center)
    assert.same(scene.SafePoint, env.cfg.Ferry.Routes[1].Outbound.Destination)
  end)

  it('test_buy_away_from_all_stands_rejected', function()
    -- 不在任何摊位旁：'range'，不扣钱
    env.me.Character.Position = vec(50, 2, 50)
    env.data:AddCoin(10, nil, 'test')
    assert.is_false(buy('worm'))
    assert.same('range', lastReason())
    assert.same(10, env.data.Data.FishCoin)
  end)

  it('test_buy_sausage_at_shrimp_stand_goes_to_bait_counter', function()
    -- 虾池摊买香肠：扣 2 金、进 Bait 计数、不占道具栏格
    moveTo('TGUnitShopShrimp')
    env.data:AddCoin(10, nil, 'test')
    assert.is_true(buy('sausage'))
    assert.same(8, env.data.Data.FishCoin)
    assert.same(1, env.data.Data.Bait.sausage)
    assert.is_nil(env.data:GetItemBarSnapshot().slots[2])
    assert.is_true(env.replies[#env.replies].ok)
    assert.same(2, env.replies[#env.replies].price)
  end)

  it('test_cast_with_non_rod_selected_rejected', function()
    -- 选中的不是竿（物品表无 Level）：抛竿不受理，不起会话（竿种门回归）
    standAtPool()
    assert.is_true(env.data:AddItem('carp'))
    assert.is_true(env.data:SelectSlot(2))
    env.cast:Cast(env.me, { slot = 2, itemId = 'carp' })
    assert.is_nil(env.cast.Sessions[1])
  end)

  it('test_cast_with_shrimp_rod_records_pool_zone_and_rod_level', function()
    -- 钓虾竿挂香肠抛虾池：会话记 zoneId=shrimpPond.water、竿级 2、饵 sausage。
    standAtPool()
    assert.is_true(env.data:AddItem('shrimpRod'))
    assert.is_true(env.data:SelectSlot(2))
    env.data.Data.Bait.sausage = 1
    assert.is_true(env.data:SelectBait('sausage'))
    env.cast:Cast(env.me, { slot = 2, itemId = 'shrimpRod' })
    local session = env.cast.Sessions[1] and env.cast.Sessions[1].session
    assert.is_not_nil(session)
    assert.same('shrimpPond.water', session.zoneId)
    assert.same({ x = 240, y = 3, z = -34 }, session.landing)
    assert.same(2, session.rodLevel)
    assert.same('sausage', session.baitId)
  end)

  it('test_fisherman_multi_anchor_feeds_at_shrimp_pond', function()
    -- 钓鱼佬按区分派（#127）：一区锚点 TGUnitFish、虾池锚点 TGUnitFishShrimp 各一个；
    -- 虾池钓鱼佬旁喂鱼获照价结算，一区钓鱼佬旁同样可用
    assert.same({ 'TGUnitFish' }, env.cfg.Interact.Fishermen[1].AnchorNames)
    assert.same('fishPond', env.cfg.Interact.Fishermen[1].ZoneId)
    assert.same({ 'TGUnitFishShrimp' }, env.cfg.Interact.Fishermen[2].AnchorNames)
    assert.same('shrimpPond', env.cfg.Interact.Fishermen[2].ZoneId)
    _G.game = { GetService = function() return {} end }
    local mgr = assert(loadfile('server/Mgr/MgrInteract.lua'))()
    mgr.FindAnchor = function(_, name)
      local pos = ANCHORS[name]
      return pos and { Name = name, Position = pos } or nil
    end
    local replies = {}
    mgr.PlayerData = {
      GetDataInst = function() return env.data end,
      SendItemBar = function() end,
    }
    mgr.Reply = function(_, _, payload) replies[#replies + 1] = payload end
    -- 站在虾池钓鱼佬旁：选中一格沼虾喂出 10 金（BasePrice × 倍率 1）
    moveTo('TGUnitFishShrimp')
    assert.is_true(env.data:AddItem('riverShrimp'))
    local slot
    for index = 1, 8 do
      local entry = env.data.Data.Containers.itemBar[index]
      if entry and entry.itemId == 'riverShrimp' then slot = index end
    end
    assert.is_true(env.data:SelectSlot(slot))
    assert.is_true(mgr:Handle(env.me, { target = 'fisherman', action = 'Feed', seq = 1 }))
    assert.same(10, env.data.Data.FishCoin)
    assert.is_true(replies[#replies].ok)
    -- 一区钓鱼佬旁同样可用（按区分派：各自只认本区锚点，互不借用）
    moveTo('TGUnitFish')
    assert.is_true(env.data:AddItem('carp'))
    for index = 1, 8 do
      local entry = env.data.Data.Containers.itemBar[index]
      if entry and entry.itemId == 'carp' then slot = index end
    end
    assert.is_true(env.data:SelectSlot(slot))
    assert.is_true(mgr:Handle(env.me, { target = 'fisherman', action = 'Feed', seq = 2 }))
    assert.same(14, env.data.Data.FishCoin)
  end)

  it('test_home_stand_cannot_sell_shrimp_goods', function()
    -- 一区摊买不到香肠与钓虾竿（'item' 且不扣钱）；两摊都能买蚯蚓
    moveTo('TGUnitShop')
    env.data:AddCoin(20, nil, 'test')
    assert.is_false(buy('sausage'))
    assert.same('item', lastReason())
    assert.is_false(buy('shrimpRod'))
    assert.same('item', lastReason())
    assert.same(20, env.data.Data.FishCoin)
    assert.is_true(buy('worm'))
    assert.same(19, env.data.Data.FishCoin)
  end)

  it('test_sausage_definition_and_shop_rows', function()
    -- 配置钉住：香肠是饵（Container='bait'）、商店 2 金 2 级起售；虾池摊 2 级、一区摊 1 级
    local sausage = env.cfg.Items.Definitions.sausage
    assert.is_not_nil(sausage)
    assert.same('bait', sausage.Container)
    assert.same('sausage', env.cfg.Items.Id.Sausage)
    local goods
    for _, g in ipairs(env.cfg.Shop.Goods) do
      if g.ItemId == 'sausage' then goods = g end
    end
    assert.is_not_nil(goods)
    assert.same(2, goods.Price)
    assert.same(2, goods.MinShopLevel)
    -- 摊位表：一区摊 1 级、虾池摊 2 级、蟹湖摊 3 级、树林岛摊 4 级、沙滩岛摊 5 级
    -- （等级语义：第 N 钓鱼区起售竿级 N，#84；蟹湖摊 #136、树林岛摊 #141、沙滩岛摊 #142 接入）
    local stands = {}
    for _, stand in ipairs(env.cfg.Shop.Stands) do stands[stand.AnchorName] = stand.Level end
    assert.same({ TGUnitShop = 1, TGUnitShopShrimp = 2, Z3_Shop = 3, Z4_Shop = 4,
      Z5_Shop = 5, Z6_Shop = 6, Z7_Shop = 7 }, stands)
  end)

  it('test_shrimp_pool_cast_table_gating', function()
    -- 虾池鱼表：竿 1 不挂饵只有虾米保底（含极品）；竿 1 挂香肠不出竿 2 的虾；
    -- 竿 2 挂香肠六种全可出；每行 Id 都在 GameCfg.Fish
    local rows = env.cfg.Casting.Zones['shrimpPond.water']
    assert.is_not_nil(rows)
    assert.same(13, #rows)
    for _, row in ipairs(rows) do
      assert.message(row.Id .. ' 不在 GameCfg.Fish').is_not_nil(env.cfg.Fish[row.Id])
    end
    assert.same({ shrimp = true, rareShrimp = true }, collectSelectable(rows, 1, nil))
    local rod1 = collectSelectable(rows, 1, 'sausage')
    assert.is_true(rod1.riverShrimp)
    assert.is_true(rod1.crayfish)
    assert.is_nil(rod1.bostonLobster)
    assert.is_nil(rod1.aussieLobster)
    assert.is_nil(rod1.milkLobster)
    local rod2 = collectSelectable(rows, 2, 'sausage')
    for _, id in ipairs({ 'shrimp', 'riverShrimp', 'crayfish', 'bostonLobster', 'aussieLobster', 'milkLobster',
      'rareShrimp', 'rareRiverShrimp', 'rareCrayfish', 'rareBostonLobster', 'rareAussieLobster', 'rareMilkLobster', 'fish15Elite' }) do
      assert.message(id .. ' 竿 2 挂香肠应可出').is_true(rod2[id])
    end
    -- 权重钉住（钓鱼表）：普通 8/8/8/32/24/16，极品 2/2/2/8/6/4
    local weights = {}
    for _, row in ipairs(rows) do weights[row.Id] = row.DrawWeight end
    assert.same({ shrimp = 8, riverShrimp = 8, crayfish = 8,
      bostonLobster = 32, aussieLobster = 24, milkLobster = 16,
      rareShrimp = 2, rareRiverShrimp = 2, rareCrayfish = 2,
      rareBostonLobster = 8, rareAussieLobster = 6, rareMilkLobster = 4, fish15Elite = 10 }, weights)
  end)

  it('test_shrimp_pool_water_zone_registered_and_disjoint', function()
    -- 虾池水区进 Water.Zones 且与一区水区不相交（否则抛竿先命中一区鱼表）
    local pool
    for _, zone in ipairs(env.cfg.Water.Zones) do
      if zone.Id == 'shrimpPond.water' then pool = zone end
    end
    assert.is_not_nil(pool)
    assert.same({ x = 240, y = 2, z = -44 }, pool.Center)
    assert.same(40, pool.HalfX)
    assert.same(12, pool.HalfZ)
    for _, zone in ipairs(env.cfg.Water.Zones) do
      if zone.Id ~= 'shrimpPond.water' then
        local dx = math.abs(zone.Center.x - pool.Center.x)
        local dz = math.abs(zone.Center.z - pool.Center.z)
        -- #136 起蟹湖水区是长方形（HalfX/HalfZ），与正方形 HalfXZ 同口径比较
        local zx = zone.HalfXZ or zone.HalfX
        local zz = zone.HalfXZ or zone.HalfZ
        assert.message('shrimpPond.water 与 ' .. zone.Id .. ' 水平重叠')
          .is_true(dx > zx + pool.HalfX or dz > zz + pool.HalfZ)
      end
    end
  end)

  it('test_shrimp_stand_sells_shrimp_rod_at_level_two', function()
    -- 虾池摊买钓虾竿 12 金进道具栏；等级语义沿用 FindGoods(itemId, level)
    moveTo('TGUnitShopShrimp')
    env.data:AddCoin(12, nil, 'test')
    assert.is_true(buy('shrimpRod'))
    assert.same(0, env.data.Data.FishCoin)
    assert.same('shrimpRod', env.data:GetItemBarSnapshot().slots[2].itemId)
    assert.is_not_nil(env.shop:FindGoods('shrimpRod', 2))
    assert.is_nil(env.shop:FindGoods('shrimpRod', 1))
    assert.is_nil(env.shop:FindGoods('sausage', 1))
  end)

  it('test_starter_rod_without_bait_only_hooks_shrimp', function()
    -- 新手竿不挂饵抛虾池：上钩只可能是虾米保底（含极品），出不了香肠行的虾
    standAtPool()
    assert.is_true(env.data:SelectSlot(1))
    env.cast:Cast(env.me, { slot = 1, itemId = 'starterRod' })
    local current = env.cast.Sessions[1]
    assert.is_not_nil(current)
    assert.same('shrimpPond.water', current.session.zoneId)
    assert.same(1, current.session.rodLevel)
    env.now = 10
    env.cast:Update()
    assert.same('hooked', current.session.phase)
    assert.message('竿 1 不挂饵应只出虾米，实际 ' .. tostring(current.session.fishId))
      .is_true(current.session.fishId == 'shrimp' or current.session.fishId == 'rareShrimp')
  end)
end)

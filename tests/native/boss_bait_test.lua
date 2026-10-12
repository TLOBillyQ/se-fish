-- 迁移自 tests/gameplay/boss_bait_test.lua（#85）；行为契约原文见 #88、#38、#141、#142。
-- #88 首领饵「鸭子」挂饵与必出首领（GameSpec §12 已确认链路）。
-- 设计（本文件即口径）：鸭子占道具栏/背包格、不进 Bait 计数；挂饵走既有 SelectBait 通道，
-- 抛竿时从道具栏（优先）或背包扣 1 只；钓出首领后消耗，脱钩 / 逃脱不返还（消耗发生在抛竿一刻）。
-- 挂首领饵在任意水区抛竿必出对应首领：无视抽签权重、鱼饵-鱼种匹配与竿级。
-- 失败方式（先列后写）：
--   1. 没鸭子也能挂、或挂了鸭子却不消耗 / 消耗错容器（该扣道具栏却扣了背包、一次扣两只）；
--   2. 最后一只鸭子被消耗后选中态残留，或快照 bait 表不带鸭子数量（客户端按钮画不出）；
--   3. 挂鸭子仍按权重抽签、被竿级 / 匹配表挡住，或只在配了行的水区才出首领；
--   4. 首领饵被当成普通鱼饵参与 FishCatch.Select 或喂钓鱼佬入账；
--   5. 收竿 / 脱钩 / 逃脱把鸭子退回库存；
--   6. 蚯蚓等普通鱼饵的既有行为被改坏。
-- it 名字沿用旧方法名，注册顺序 = LuaUnit sortedPairs 的实际执行顺序。

local function vec(x, y, z) return { x = x, y = y, z = z } end

local function signal()
  local slots = {}
  return {
    Connect = function(_, fn)
      slots[#slots + 1] = fn
      return { Disconnect = function() end }
    end,
    Fire = function(_, ...) for _, fn in ipairs(slots) do fn(...) end end,
  }
end

describe('首领饵必出首领（PlayerData × MgrCast）', function()
  local env
  local restore

  before_each(function()
    -- 快照先于任何改动：before_each 中途失败时 after_each 仍能还原。
    restore = {
      game = _G.game,
      GameCfg = package.loaded['common.GameCfg'],
      RE = package.loaded['common.REUtil'],
      PlayerData = package.loaded['server.Mgr.MgrPlayerData'],
      FishUnit = package.loaded['server.Mgr.MgrFishUnit'],
    }
    env = { now = 0, sent = {} }
    package.loaded['common.GameCfg'] = nil
    env.cfg = require('common.GameCfg')
    env.cfg.Debug = { Enabled = false }
    local PlayerData = assert(loadfile('server/Data/PlayerData.lua'))()
    env.player = { UserId = 1, Character = {
      Position = vec(-11.75, 2.183, -17.25),
      Rotation = { GetForward = function() return vec(0, 0, 1) end } },
      SetAttribute = function() end }
    env.data = PlayerData.New(env.player, function() end)
    env.data:Init()
    -- MgrCast 桩：REUtil 记录下发，MgrPlayerData 指向真数据，MgrFishUnit 只读持有
    package.loaded['common.REUtil'] = {
      GetRE = function(_, name)
        env.sent[name] = env.sent[name] or {}
        return { OnServerEvent = signal(), FireClient = function(_, player, payload)
          env.sent[name][#env.sent[name] + 1] = payload
        end }
      end,
      CheckRECD = function() return false end,
    }
    package.loaded['server.Mgr.MgrPlayerData'] = {
      GetDataInst = function(_, p) return p == env.player and env.data or nil end,
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
    package.loaded['common.REUtil'] = restore and restore.RE
    package.loaded['server.Mgr.MgrPlayerData'] = restore and restore.PlayerData
    package.loaded['server.Mgr.MgrFishUnit'] = restore and restore.FishUnit
    _G.game = restore and restore.game
    env = nil
    restore = nil
  end)

  local function hookSession(baitId, zoneId)
    local session = { phase = 'cast', landing = vec(0, 2, 0), zoneId = zoneId,
      baitId = baitId, slot = 1, rodLevel = 1, hookAt = 0 }
    env.cast.Sessions[1] = { player = env.player, session = session }
    env.now = 10
    env.cast:Update()
    return session
  end

  it('test_cast_consumes_duck_and_never_returns_it', function()
    assert.is_true(env.data:AddItem('starterRod'))
    assert.is_true(env.data:AddItem('duck'))
    assert.is_true(env.data:SelectSlot(1))
    assert.is_true(env.data:SelectBait('duck'))
    env.cast:Cast(env.player, { slot = 1, itemId = 'starterRod' })
    local current = env.cast.Sessions[1]
    assert.is_not_nil(current)
    assert.same('duck', current.session.baitId)
    assert.same(0, env.data:ItemCount('duck'))
    assert.is_nil(env.data.Data.SelectedBait)
    -- 收竿（未上钩放弃）：鸭子不退
    env.cast:Reel(env.player)
    assert.is_nil(env.cast.Sessions[1])
    assert.same(0, env.data:ItemCount('duck'))
  end)

  it('test_config_pins', function()
    -- 配置钉住：首领饵映射与首领近战占位参数
    -- #141：树林岛首领饵 item123 必出三头鲨；#142：沙滩岛首领饵 item124 必出虎鲸
    -- （#88 口径：BossBait 键即首领饵物品 id）
    assert.same({ duck = 'alligatorGar', item121 = 'fish16Boss', item122 = 'fish24Boss', item123 = 'fish32Boss',
      item124 = 'fish40Boss', item125 = 'fish48Boss', item126 = 'fish56Boss' }, env.cfg.Casting.BossBait)
    assert.same('gar', env.cfg.Fish.alligatorGar.Combat)
    assert.is_not_nil(env.cfg.FishCombat.gar.BiteRange)
    assert.is_not_nil(env.cfg.FishCombat.gar.BiteCooldownSec)
    assert.same({ { ItemId = 'garMeat', Count = 2 }, { ItemId = 'garHead', Count = 1 } },
      env.cfg.Fish.alligatorGar.Drops)
  end)

  it('test_consume_duck_takes_itembar_before_backpack', function()
    assert.is_true(env.data:AddItem('duck'))
    assert.is_true(env.data:AddItem('duck'))
    assert.is_true(env.data:AddItem('duck')) -- 道具栏 2 格满，第三只进背包
    assert.is_true(env.data:SelectBait('duck'))
    local ok, baitId = env.data:ConsumeSelectedBait()
    assert.is_true(ok)
    assert.same('duck', baitId)
    local bar = env.data.Data.Containers.itemBar
    local barDucks = 0
    for index = 1, env.data:ItemBarCapacity() do
      if bar[index] and bar[index].itemId == 'duck' then barDucks = barDucks + 1 end
    end
    assert.same(1, barDucks)
    assert.same('duck', env.data.Data.Containers.backpack[1].itemId)
  end)

  it('test_duck_hook_always_alligator_gar_ignoring_table_and_rod', function()
    local session = hookSession('duck', 'WaterCircle2')
    assert.same('hooked', session.phase)
    assert.same('alligatorGar', session.fishId)
    assert.is_not_nil(session.mult)
    assert.same('alligatorGar', env.sent.CastState[#env.sent.CastState].fishId)
  end)

  it('test_duck_hook_works_in_zone_without_rows', function()
    local session = hookSession('duck', 'WaterCircle1')
    assert.same('alligatorGar', session.fishId)
    -- 对照：同水区挂蚯蚓没有配置行，抽不出鱼
    local worm = hookSession('worm', 'WaterCircle1')
    assert.is_nil(worm.fishId)
    assert.same('cast', worm.phase)
  end)

  it('test_final_baits_hook_in_every_water_and_volcano_draw_pool_is_live', function()
    -- #38 失败方式：羊/核废料桶仅有目录、换到其他水域不出首领；火山鱼只有目录未进入抽取池。
    for _, zone in ipairs(env.cfg.Zones) do
      assert.same('fish48Boss', hookSession('item125', zone.WaterId).fishId)
      assert.same('fish56Boss', hookSession('item126', zone.WaterId).fishId)
    end
    local FishCatch = require('common.FishCatch')
    assert.same('item97', FishCatch.Select(env.cfg.Casting.Zones['volcanoIsland.water'], 1, nil,
      function() return 0 end))
    assert.is_true(env.cfg.Fish.fish56Boss.implemented)
  end)

  it('test_last_duck_consumed_clears_selection', function()
    assert.is_true(env.data:AddItem('duck'))
    assert.is_true(env.data:SelectBait('duck'))
    assert.is_true(env.data:ConsumeSelectedBait())
    assert.is_nil(env.data.Data.SelectedBait)
    local ok, baitId = env.data:ConsumeSelectedBait()
    assert.is_true(ok) -- 没挂饵是合法抛竿（不挂饵），不算失败
    assert.is_nil(baitId)
  end)

  it('test_pearl_hooks_dragon_in_every_water_and_abort_does_not_refund', function()
    assert.is_true(env.data:AddItem('starterRod'))
    assert.is_true(env.data:AddItem('item121'))
    assert.is_true(env.data:SelectSlot(1))
    assert.is_true(env.data:SelectBait('item121'))
    env.cast:Cast(env.player, { slot = 1, itemId = 'starterRod' })
    assert.same(0, env.data:ItemCount('item121'))
    env.cast:Abort(env.player)
    assert.same(0, env.data:ItemCount('item121'))
    for _, zone in ipairs(env.cfg.Water.Zones) do
      local session = hookSession('item121', zone.Id)
      assert.message(zone.Id).same('fish16Boss', session.fishId)
    end
  end)

  it('test_select_duck_requires_duck_in_storage', function()
    assert.is_false(env.data:SelectBait('duck'))
    assert.is_nil(env.data.Data.SelectedBait)
    assert.is_true(env.data:AddItem('duck'))
    assert.is_true(env.data:SelectBait('duck'))
    assert.same('duck', env.data.Data.SelectedBait)
  end)

  it('test_snapshot_lists_duck_count_alongside_worm', function()
    env.data.Data.Bait.worm = 3
    assert.is_true(env.data:AddItem('duck'))
    assert.is_true(env.data:AddItem('duck'))
    local bait = env.data:GetItemBarSnapshot().bait
    assert.same(3, bait.worm)
    assert.same(2, bait.duck)
  end)

  it('test_worm_hook_still_draws_from_zone_table', function()
    local session = hookSession('worm', 'WaterCircle2')
    assert.is_not_nil(session.fishId)
    assert.not_same('alligatorGar', session.fishId)
  end)
end)

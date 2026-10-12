-- 迁移自 tests/gameplay/gm_state_test.lua（#91）；行为契约原文见 #115。
-- #115 外部接缝：GM 请求、玩家快照、存档键值及异步结果。
-- 失败方式：局部补丁误清字段、非法输入部分落地、缩容吞物品、临时状态被自动写入、
-- 在途旧写乱序、手动保存失败误恢复、空槽读取清档、待切槽跨玩家串线或当局热切换。
-- it 名字沿用旧方法名，注册顺序 = LuaUnit sortedPairs 的实际执行顺序。

local GameCfg = require('common.GameCfg')

describe('GM 状态与存档接缝（MgrGM × MgrSave × PlayerData）', function()
  local env
  local restore

  local function drain()
    while #env.spawns > 0 do table.remove(env.spawns, 1)() end
  end

  before_each(function()
    -- 快照先于任何改动：夹具中途失败时 after_each 仍能还原已改项。
    -- helper 的根级 after_each 只还原 GameCfg.Debug 的引用，本夹具把它换成新表，故显式再还原一次。
    restore = { game = rawget(_G, 'game'), Debug = GameCfg.Debug }
    GameCfg.Debug = { Enabled = true, InitialGrants = restore.Debug.InitialGrants }
    env = { values = {}, players = {}, spawns = {}, replies = {}, data = {} }
    env.failGet, env.failSet = false, false
    local store = {
      GetAsync = function(_, key)
        if env.failGet then error('read unavailable') end
        return env.values[key]
      end,
      SetAsync = function(_, key, value)
        if env.failSet then error('write unavailable') end
        env.values[key] = value
      end,
      UpdateAsync = function(_, key, fn)
        if env.failSet then error('write unavailable') end
        local value = fn(env.values[key])
        if value then env.values[key] = value end
        return value
      end,
    }
    rawset(_G, 'game', { GetService = function(_, name)
      if name == 'Task' then return {
        Spawn = function(_, fn) env.spawns[#env.spawns + 1] = fn end,
        Wait = function() end,
      } end
      if name == 'DataStoreService' then return { GetDataStore = function() return store end } end
      if name == 'Players' then return { GetPlayers = function() return env.players end } end
    end })
    env.save = assert(loadfile('server/Mgr/MgrSave.lua'))()
    env.gm = assert(loadfile('server/Mgr/MgrGM.lua'))()
    local PlayerData = assert(loadfile('server/Data/PlayerData.lua'))()
    env.gm.Save = env.save
    env.gm.PlayerData = {
      GetDataInst = function(_, player) return env.data[player] end,
      SendItemBar = function() end,
    }
    env.gm.Reply = function(_, _, result) env.replies[#env.replies + 1] = result end
    local function add(id)
      local player = { UserId = id, SetAttribute = function() end }
      local data = PlayerData.New(player)
      data:Init()
      env.players[#env.players + 1] = player
      env.data[player] = data
      return player, data
    end
    env.me, env.mine = add(1)
    env.you, env.yours = add(2)
    env.save:LoadInto(env.me, env.mine)
    env.save:LoadInto(env.you, env.yours)
    drain()
  end)

  after_each(function()
    -- 顺序与旧 tearDown 一致：先还原 Debug 开关，再还原 game 全局。
    if restore then
      GameCfg.Debug = restore.Debug
      rawset(_G, 'game', restore.game)
    end
    env = nil
    restore = nil
  end)

  it('test_explicit_save_confirms_persistence_and_failure_keeps_pause', function()
    assert.is_true(env.gm:Handle(env.me, { action = 'ApplyState', coin = 101 }))
    env.failSet = true
    assert.is_true(env.gm:Handle(env.me, { action = 'SaveState' }))
    drain()
    assert.is_false(env.replies[#env.replies].ok)
    assert.is_true(env.replies[#env.replies].status.autosavePaused)
    assert.same(0, env.values.u1.coin)
    env.failSet = false
    assert.is_true(env.gm:Handle(env.me, { action = 'SaveState' }))
    drain()
    assert.is_true(env.replies[#env.replies].ok)
    assert.is_false(env.replies[#env.replies].status.autosavePaused)
    assert.same(101, env.values.u1.coin)
  end)

  it('test_in_flight_write_finishes_before_temporary_patch_and_all_automatic_paths_pause', function()
    assert.is_true(env.save:Save(1, env.mine:Serialize(), 'old'))
    assert.is_true(env.gm:Handle(env.me, { action = 'ApplyState', coin = 777 }))
    assert.same(0, env.mine.Data.FishCoin)
    drain()
    assert.same(0, env.values.u1.coin)
    assert.same(777, env.mine.Data.FishCoin)
    assert.is_true(env.save:Status(1).autosavePaused)
    assert.is_false(env.save:Save(1, env.mine:Serialize(), 'autosave'))
    assert.is_false(env.save:Commit(1, env.mine:Serialize(), 'ferry:ticket'))
    env.save:SaveLeaving(env.me, env.mine)
    assert.same(0, env.values.u1.coin)
  end)

  it('test_named_slot_is_per_player_and_only_switches_on_rejoin', function()
    env.gm:Handle(env.me, { action = 'GetState' })
    assert.same('', env.replies[#env.replies].status.currentSlot)
    assert.is_true(env.gm:Handle(env.me, { action = 'SelectSaveSlot', slot = 'qa-one' }))
    drain()
    assert.same('u1', env.save:Key(1))
    assert.same('qa-one', env.save:Status(1).nextSlot)
    assert.same('', env.save:Status(2).nextSlot)
    assert.same('qa-one', env.values['u1:gm-slot'])
    assert.is_false(env.gm:Handle(env.me, { action = 'SelectSaveSlot', slot = '../bad' }))
    env.save:LoadInto(env.me, env.mine)
    drain()
    assert.same('u1:qa:qa-one', env.save:Key(1))
  end)

  it('test_partial_patch_keeps_other_fields_and_rejects_bad_requests_atomically', function()
    assert.is_true(env.gm:Handle(env.me, { action = 'ApplyState', coin = 0 }))
    drain()
    assert.same(0, env.mine.Data.FishCoin)
    assert.same(0, env.mine.Data.UpgradeLevel)
    assert.same('starterRod', env.mine:GetItemBarSnapshot().slots[1].itemId)
    assert.is_false(env.gm:Handle(env.me, { action = 'ApplyState', coin = 7, upgradeLevel = 99 }))
    assert.same(0, env.mine.Data.FishCoin)
  end)

  it('test_read_empty_or_invalid_retains_state_and_valid_read_replaces_it', function()
    assert.is_true(env.gm:Handle(env.me, { action = 'ApplyState', coin = 91 }))
    env.values.u1 = nil
    assert.is_true(env.gm:Handle(env.me, { action = 'ReadState' }))
    drain()
    assert.is_false(env.replies[#env.replies].ok)
    assert.same(91, env.mine.Data.FishCoin)
    env.values.u1 = { invalid = true }
    assert.is_true(env.gm:Handle(env.me, { action = 'ReadState' }))
    drain()
    assert.is_false(env.replies[#env.replies].ok)
    assert.same(91, env.mine.Data.FishCoin)
    local saved = env.mine:Serialize()
    saved.coin = 55
    env.values.u1 = saved
    assert.is_true(env.gm:Handle(env.me, { action = 'ReadState' }))
    drain()
    assert.is_true(env.replies[#env.replies].ok)
    assert.same(55, env.mine.Data.FishCoin)
    assert.is_true(env.save:Status(1).autosavePaused)
  end)

  it('test_slots_capacity_and_invalid_patch_are_all_or_nothing', function()
    assert.is_true(env.gm:Handle(env.me, { action = 'ApplyState', upgradeLevel = 6,
      slots = { { container = 'backpack', index = 40, itemId = 'tilapia', count = 1, mult = 1.5 } } }))
    assert.same(1.5, env.mine:GetItemBarSnapshot().backpack[40].mult)
    local prior = env.mine:Serialize()
    for _, bad in ipairs({
      { coin = -1 }, { upgradeLevel = 7 },
      { slots = { { container = 'backpack', index = 41, clear = true } } },
      { slots = { { container = 'itemBar', index = 2, itemId = 'worm', count = 1 } } },
      { slots = { { container = 'itemBar', index = 2, itemId = 'carp', count = 2 } } },
      { slots = { { container = 'itemBar', index = 2, itemId = 'carp', count = 1, mult = 2.1 } } },
      { upgradeLevel = 0, coin = 99 },
    }) do
      bad.action = 'ApplyState'
      assert.is_false(env.gm:Handle(env.me, bad))
      assert.same(prior, env.mine:Serialize())
    end
    assert.is_true(env.gm:Handle(env.me, { action = 'ApplyState', upgradeLevel = 0,
      slots = { { container = 'backpack', index = 40, clear = true } } }))
    assert.is_nil(env.mine:GetItemBarSnapshot().backpack[40])
  end)
end)

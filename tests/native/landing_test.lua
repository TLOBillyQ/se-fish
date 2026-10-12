-- 迁移自 tests/gameplay/landing_test.lua（#85）；行为契约原文见 #37、#52、#128、#133。
-- #37 上岸结算：收线到 100% 后只生成一条待举起的活鱼，交给活鱼单位管理器。
-- 失败方式（先列后写）：
--   1. 上岸不生成鱼，或重复批次 / 迟到消息 / 结束收线 / 再次结算生成第二条；
--   2. 脱钩、收竿也生成鱼；
--   3. 鱼种或个体倍率与上钩时不同，或鱼不在玩家正前方；
--   4. 重量 / 售价存成快照、或不是「基础值 × 倍率」；
--   5. 上岸后卡在 landed 不回 idle，上岸 / 脱钩后不回到选中鱼竿；
--   6. 上岸加金币，旧等级字段、旧鱼管理链仍在；
--   7. 鱼生成失败或玩家离线时会话残留。
-- it 名字沿用旧方法名，注册顺序 = LuaUnit sortedPairs 的实际执行顺序。
-- 旧文件里的第二个类 TestLandingRetired 没有 setUp/tearDown，映射为独立的平铺 describe。

local GameCfg = require('common.GameCfg')

local function signal()
  local callbacks = {}
  return {
    Connect = function(_, fn)
      callbacks[#callbacks + 1] = fn
      return { Disconnect = function() end }
    end,
    Fire = function(_, ...) for _, fn in ipairs(callbacks) do fn(...) end end,
  }
end

local function vec(x, y, z)
  return { x = x, y = y, z = z }
end

local moduleNames = { 'common.REUtil', 'server.Mgr.MgrPlayerData',
  'server.Mgr.MgrFishCarrier', 'server.Mgr.MgrFishUnit' }

describe('上岸结算（MgrCast × MgrFishUnit × MgrFishCarrier）', function()
  local env
  local restore

  before_each(function()
    -- 快照先于任何改动：before_each 中途失败时 after_each 仍能还原。
    restore = { game = rawget(_G, 'game'), Vector3 = rawget(_G, 'Vector3') }
    for _, name in ipairs(moduleNames) do
      restore[name] = package.loaded[name]
    end
    env = { now = 0, events = {}, spawned = {}, despawned = {}, played = {}, restored = {}, sentBars = 0 }
    _G.Vector3 = { New = vec }
    _G.game = { GetService = function(_, name)
      if name == 'World' then return { GetServerTime = function() return env.now end } end
    end }
    package.loaded['common.REUtil'] = {
      GetRE = function(_, name)
        if not env.events[name] then
          env.events[name] = { OnServerEvent = signal(), FireClient = function(_, player, value)
            player.messages[#player.messages + 1] = { name = name, value = value }
          end }
        end
        return env.events[name]
      end,
      CheckRECD = function() return false end,
    }
    env.data = { Data = { SelectedSlot = 1, FishCoin = 0, Bait = { worm = 3 }, SelectedBait = 'worm',
      Containers = { itemBar = { [1] = { itemId = 'starterRod', count = 1, containerId = 'itemBar' } } } } }
    function env.data:ConsumeSelectedBait() return true, 'worm' end
    function env.data:RestoreSlot(index)
      env.restored[#env.restored + 1] = index
      self.Data.SelectedSlot = index
      return true
    end
    package.loaded['server.Mgr.MgrPlayerData'] = {
      GetDataInst = function(_, player) return player == env.player and env.data or nil end,
      SendItemBar = function() env.sentBars = env.sentBars + 1 end,
    }
    env.carrierOk = true
    package.loaded['server.Mgr.MgrFishCarrier'] = {
      Spawn = function(_, opts)
        if not env.carrierOk then return nil, 'body-create-failed' end
        local carrier = { Opts = opts, Body = { UnitId = #env.spawned + 1 } }
        env.spawned[#env.spawned + 1] = carrier
        return carrier
      end,
      Despawn = function(_, carrier) env.despawned[#env.despawned + 1] = carrier end,
    }
    package.loaded['server.Mgr.MgrFishUnit'] = nil
    env.fishUnit = assert(loadfile('server/Mgr/MgrFishUnit.lua'))()
    package.loaded['server.Mgr.MgrFishUnit'] = env.fishUnit
    env.reel = assert(loadfile('server/Mgr/MgrReelIn.lua'))()
    env.cast = assert(loadfile('server/Mgr/MgrCast.lua'))()
    env.cast.ReelIn = env.reel
    env.cast.FishUnit = env.fishUnit
    env.reel.Cast = env.cast
    env.reel:Start()
    env.cast:Start()
    local animator = { LoadAnimation = function(_, uri)
      return { Play = function() env.played[#env.played + 1] = uri end }
    end }
    env.player = { UserId = 7, messages = {}, CharacterAdded = signal(), CharacterRemoving = signal(),
      Character = { Position = vec(10, 2, -20), Animator = animator,
        Rotation = { GetForward = function() return vec(0, 0, 1) end } } }
    env.reel:OnPlayerAdded(env.player)
  end)

  after_each(function()
    if env then
      if env.reel then env.reel:Stop() end
      if env.cast then env.cast:Stop() end
    end
    for _, name in ipairs(moduleNames) do
      package.loaded[name] = restore[name]
    end
    _G.game = restore.game
    _G.Vector3 = restore.Vector3
    env = nil
    restore = nil
  end)

  -- 直接摆一个已上钩的会话，省掉抛竿与选鱼的随机
  local function hook(fishId, mult)
    local id = 'r' .. tostring(#env.spawned) .. ':' .. tostring(env.now)
    env.cast.Sessions[env.player.UserId] = { player = env.player, session = {
      phase = 'hooked', fishId = fishId, mult = mult, reelSession = id, slot = 1,
    } }
    assert.is_true(env.reel:Begin(env.player, id, env.now))
    return id
  end

  local function reelIn(id, n, q)
    env.events.ReelInRE.OnServerEvent:Fire(env.player, { s = id, n = n, q = q })
  end

  local function lastState()
    local last
    for _, message in ipairs(env.player.messages) do
      if message.name == 'CastState' then last = message.value end
    end
    return last
  end

  -- #52 新手任务事实（失败方式 8. 陆地抛竿冒充「水边抛竿」、每次落水不带唯一 eventId；
  --   9. 脱钩 / 收竿也报「上岸」，或一次上岸报两次）
  local function spyQuest()
    env.facts = {}
    env.cast.Quest = { Notify = function(_, kind, player, payload)
      env.facts[#env.facts + 1] = { kind = kind, player = player, itemId = payload.itemId, eventId = payload.eventId }
      return true
    end }
  end

  -- #133 图鉴接线：上岸才记一次（带幂等键），脱钩 / 收竿 / 二次结算都不记
  local function spyCompendium()
    env.landings = {}
    env.cast.Compendium = { RecordLanding = function(_, player, event)
      env.landings[#env.landings + 1] = { player = player, fishId = event.fishId,
        mult = event.mult, reelSerial = event.reelSerial }
      return true
    end }
  end

  it('test_downed_player_cannot_cast', function()
    -- #128 动作互斥：濒死（不能行动）的玩家不能发起抛竿，服务端直接拒绝，不依赖客户端界面
    env.cast.Vitals = { CanAct = function() return false end }
    env.player.Character.Position = vec(-11.75, 2, -17.25)
    env.cast:Cast(env.player, { slot = 1, itemId = 'starterRod' })
    assert.is_nil(env.cast.Sessions[env.player.UserId])
    assert.same('cannotAct', lastState().result.reason)
  end)

  it('test_fish_lands_in_front_of_player', function()
    local id = hook('carp', 1.5)
    reelIn(id, 10, 1)
    local pos = env.spawned[1].Opts.Position
    assert.near(10, pos.x, 1e-6)
    assert.is_true(pos.z > -20 and pos.z <= -17.5)
    assert.is_true(pos.y >= 2)
  end)

  it('test_landed_notifies_land_once_and_unhook_does_not', function()
    spyQuest()
    local lost = hook('carp', 1.1)
    env.now = 30
    env.reel:Update()
    assert.same(0, #env.facts)
    local id = hook('bass', 1.2)
    reelIn(id, 10, 1)
    env.cast:FinishReel(env.player, id, 'landed')
    assert.same(1, #env.facts)
    assert.same('Land', env.facts[1].kind)
    assert.same('bass', env.facts[1].itemId)
    assert.are.equal(env.player, env.facts[1].player)
    assert.is_not_nil(env.facts[1].eventId)
    assert.is_true(tostring(env.facts[1].eventId):find(id, 1, true) ~= nil)
    assert.not_same(id, lost)
  end)

  it('test_landed_records_compendium_and_unhook_does_not', function()
    spyCompendium()
    env.player.Character.Position = vec(-11.75, 2, -17.25)

    -- 走真实流程抛竿 → 上钩，拿到服务端分配的收线会话序号
    env.cast:Cast(env.player, { slot = 1, itemId = 'starterRod' })
    env.now = GameCfg.Casting.HookDelaySec + 0.1
    env.cast:Update()
    local landed = env.cast.Sessions[env.player.UserId].session
    assert.same('hooked', landed.phase)
    assert.is_not_nil(landed.reelSerial)
    reelIn(landed.reelSession, 10, 1)
    assert.same(1, #env.landings)
    assert.are.equal(env.player, env.landings[1].player)
    assert.same(landed.fishId, env.landings[1].fishId)
    assert.same(landed.mult, env.landings[1].mult)
    assert.same(landed.reelSerial, env.landings[1].reelSerial)

    -- 同一次上岸的重复结算与迟到批次不再记
    env.cast:FinishReel(env.player, landed.reelSession, 'landed')
    reelIn(landed.reelSession, 5, 2)
    assert.same(1, #env.landings)

    -- 脱钩（线还在水里）与随后的收竿都不算上岸
    env.now = env.now + GameCfg.Casting.LandedHoldSec + 1
    env.cast:Update()
    env.cast:Cast(env.player, { slot = 1, itemId = 'starterRod' })
    env.now = env.now + GameCfg.Casting.HookDelaySec + 0.1
    env.cast:Update()
    assert.same('hooked', env.cast.Sessions[env.player.UserId].session.phase)
    env.now = env.now + 30
    env.reel:Update()
    assert.same('unhooked', lastState().phase)
    env.events.CastAction.OnServerEvent:Fire(env.player, { action = 'Reel' })
    assert.same(1, #env.landings)
  end)

  it('test_landed_returns_to_idle_with_rod_selected_after_hold', function()
    local id = hook('goldfish', 2)
    env.data.Data.SelectedSlot = nil
    reelIn(id, 10, 1)
    env.now = 0.5
    env.cast:Update()
    assert.same('landed', lastState().phase)
    env.now = 5
    env.cast:Update()
    assert.same('idle', lastState().phase)
    assert.is_nil(env.cast.Sessions[env.player.UserId])
    assert.same(1, env.data.Data.SelectedSlot)
    assert.is_true(env.sentBars >= 1)
    env.cast:Update()
    assert.same(1, #env.spawned)
  end)

  it('test_landing_does_not_pay_coins', function()
    local id = hook('catfish', 1.9)
    reelIn(id, 10, 1)
    env.now = 5
    env.cast:Update()
    assert.same(0, env.data.Data.FishCoin)
  end)

  it('test_landing_spawns_exactly_one_fish_with_hooked_parameters', function()
    local id = hook('bass', 1.37)
    reelIn(id, 10, 1)
    assert.same(1, #env.spawned)
    local opts = env.spawned[1].Opts
    assert.same('bass', opts.FishId)
    assert.are.equal(env.player, opts.Player)
    assert.same(20, opts.MaxHealth)
    assert.same('landed', lastState().phase)
    local fish = env.fishUnit:GetFish(env.player)
    assert.same(1, #fish)
    assert.same('bass', fish[1].FishId)
    assert.same(1.37, fish[1].Mult)
    assert.same('awaitLift', fish[1].State)
    assert.same({ 'official://animation/24450' }, env.played)
  end)

  it('test_offline_during_landed_hold_clears_session_and_waiting_fish', function()
    local id = hook('bass', 1.2)
    reelIn(id, 10, 1)
    env.cast:OnPlayerRemoving(env.player)
    env.fishUnit:OnPlayerRemoving(env.player)
    assert.is_nil(env.cast.Sessions[env.player.UserId])
    assert.same(0, #env.fishUnit:GetFish(env.player))
    assert.same(1, #env.despawned)
    env.now = 5
    env.cast:Update()
  end)

  it('test_only_valid_water_cast_notifies_quest', function()
    spyQuest()
    env.player.Character.Position = vec(10, 2, -20)
    env.cast:Cast(env.player, { slot = 1, itemId = 'starterRod' })
    assert.is_nil(env.cast.Sessions[env.player.UserId])
    assert.same('invalidLanding', lastState().result.reason)
    assert.same(0, #env.facts)
    env.player.Character.Position = vec(-11.75, 2, -17.25)
    env.cast:Cast(env.player, { slot = 1, itemId = 'starterRod' })
    assert.is_not_nil(env.cast.Sessions[env.player.UserId].session.zoneId)
    env.cast:Reel(env.player)
    env.cast:Cast(env.player, { slot = 1, itemId = 'starterRod' })
    assert.same(2, #env.facts)
    assert.same('CastWater', env.facts[1].kind)
    assert.are.equal(env.player, env.facts[1].player)
    assert.is_not_nil(env.facts[1].eventId)
    assert.not_same(env.facts[2].eventId, env.facts[1].eventId)
  end)

  it('test_repeated_batches_late_close_and_second_finish_do_not_spawn_again', function()
    local id = hook('bass', 1.2)
    reelIn(id, 10, 1)
    reelIn(id, 10, 2)
    env.now = 0.3
    reelIn(id, 5, 3)
    env.reel:Close(env.player, { session = id })
    env.cast:FinishReel(env.player, id, 'landed')
    env.reel:Update()
    env.cast:Update()
    assert.same(1, #env.spawned)
  end)

  it('test_spawn_failure_still_ends_session', function()
    env.carrierOk = false
    local id = hook('bass', 1.2)
    reelIn(id, 10, 1)
    assert.same(0, #env.fishUnit:GetFish(env.player))
    env.now = 5
    env.cast:Update()
    assert.is_nil(env.cast.Sessions[env.player.UserId])
    assert.same('idle', lastState().phase)
  end)

  it('test_unhook_and_manual_reel_spawn_nothing', function()
    local id = hook('bass', 1.2)
    env.now = 30
    env.reel:Update()
    -- #133：脱钩不再直接回 idle，而是停在 unhooked（线还在水里）等玩家收竿
    assert.same('unhooked', lastState().phase)
    assert.same(0, #env.spawned)
    local closed = hook('carp', 1.1)
    env.reel:Close(env.player, { session = closed })
    assert.same(0, #env.spawned)
  end)

  it('test_unhook_keeps_rod_until_player_reels_back', function()
    -- #133：脱钩时线还在水里，鱼竿仍被占着；按「收竿」才归位到抛竿时选中的鱼竿
    hook('bass', 1.2)
    env.data.Data.SelectedSlot = nil
    env.now = 30
    env.reel:Update()
    assert.is_nil(env.data.Data.SelectedSlot)
    env.events.CastAction.OnServerEvent:Fire(env.player, { action = 'Reel' })
    assert.same(1, env.data.Data.SelectedSlot)
  end)

  it('test_weight_and_price_derive_from_species_and_multiplier', function()
    local id = hook('goldfish', 1.15)
    reelIn(id, 10, 1)
    local fish = env.fishUnit:GetFish(env.player)[1]
    assert.is_nil(fish.Weight)
    assert.is_nil(fish.Price)
    assert.same(0.12, env.fishUnit:Weight(fish))
    assert.same(9, env.fishUnit:Price(fish))
    fish.Mult = 2
    assert.same(0.2, env.fishUnit:Weight(fish))
    assert.same(16, env.fishUnit:Price(fish))
  end)
end)

-- 旧文件里的第二个类：只读源码/配置做接线钉子，不需要运行时夹具。
local function read(path)
  local file = io.open(path, 'r')
  if not file then return nil end
  local text = file:read('*a')
  file:close()
  return text
end

describe('管理器接线（server/main.lua 与配置）', function()
  it('test_compendium_is_registered_and_wired_to_cast', function()
    -- #133：图鉴管理器注册进 MgrMap，且只有 MgrCast 拿到它（击杀与掉落不经此路）
    local main = read('server/main.lua')
    assert.matches('MgrCompendium = require', main, 1, true)
    assert.matches('MgrMap.MgrCompendium.Save = MgrMap.MgrSave', main, 1, true)
    assert.matches('MgrMap.MgrCompendium.PlayerData = MgrMap.MgrPlayerData', main, 1, true)
    assert.matches('MgrMap.MgrCast.Compendium = MgrMap.MgrCompendium', main, 1, true)
  end)

  it('test_every_catchable_fish_has_species_values', function()
    local cfg = assert(loadfile('common/GameCfg.lua'))()
    for zone, rows in pairs(cfg.Casting.Zones) do
      for _, row in ipairs(rows) do
        local species = cfg.Fish[row.Id]
        assert.message(zone .. ' 的 ' .. row.Id .. ' 没有鱼种配置').is_not_nil(species)
        assert.message(row.Id).is_true(species.BaseWeight > 0 and species.Health > 0)
        assert.message(row.Id).is_true(species.BasePrice > 0 or species.Drops ~= nil)
        assert.message(row.Id .. ' 的模型号不在鱼载体表里').is_not_nil(cfg.FishCarrier.Models[species.Model])
      end
    end
    assert.same(1, cfg.Items.Definitions.starterRod.Level)
  end)

  it('test_fish_unit_is_registered', function()
    assert.matches('MgrFishUnit = require', read('server/main.lua'), 1, true)
  end)
end)

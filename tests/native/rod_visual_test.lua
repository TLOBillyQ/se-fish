-- 迁移自 tests/gameplay/rod_visual_test.lua（#85）。
-- 被测接缝：server.Mgr.MgrPlayerData 选中鱼竿时服务端挂载物（鱼竿外观）的生成与清理。
-- it 名字沿用旧方法名，注册顺序 = LuaUnit sortedPairs 的实际执行顺序。

local GameCfg = require('common.GameCfg')
local Mgr = require('server.Mgr.MgrPlayerData')

local function signal()
  local callbacks = {}
  return {
    Connect = function(_, fn)
      callbacks[#callbacks + 1] = fn
      return { Disconnect = function() for i, cb in ipairs(callbacks) do
        if cb == fn then callbacks[i] = nil end
      end end }
    end,
    Fire = function(_, ...) for _, cb in ipairs(callbacks) do cb(...) end end,
  }
end

describe('鱼竿外观挂载（MgrPlayerData）', function()
  local env
  local restore

  before_each(function()
    -- #49：进图白送只在调试开关下发放，这些用例沿用它的起始库存（鱼竿在第 1 格、蚯蚓若干）
    -- 快照先于任何改动，夹具中途失败时 after_each 仍能还原。
    restore = {
      GrantDebug = require('common.GameCfg').Debug,
      game = _G.game,
      Vector3 = _G.Vector3,
      Color = _G.Color,
      REUtil = _G.REUtil,
    }
    env = { failKind = nil, created = {}, events = {} }
    require('common.GameCfg').Debug = { Enabled = true, InitialGrants = restore.GrantDebug.InitialGrants }
    local world = { CreateUnit = function(_, kind, props)
      if env.failKind == kind then return nil end
      local unit = { Kind = kind, Destroyed = false }
      for key, value in pairs(props) do unit[key] = value end
      function unit:Destroy() self.Destroyed = true end
      env.created[#env.created + 1] = unit
      return unit
    end }
    _G.game = { GetService = function(_, name) if name == 'World' then return world end end }
    _G.Vector3 = { New = function(x, y, z) return { x = x, y = y, z = z } end }
    -- 鱼竿模型带 ModelColor1，服务端要 Color.New；原生逐例隔离后不能再蹭别的套件的残留全局。
    _G.Color = { New = function(...) return { ... } end }
    _G.REUtil = { CheckRECD = function() return false end, GetRE = function(_, name)
      if not env.events[name] then
        env.events[name] = {
          OnServerEvent = signal(),
          FireClient = function(_, player, state) player.lastState = state end,
        }
      end
      return env.events[name]
    end }
    env.player = { UserId = 34001, Character = { Name = 'Eggy' },
      CharacterAdded = signal(), CharacterRemoving = signal() }
    function env.player:SetAttribute() end
    Mgr:Start()
    Mgr:OnPlayerAdded(env.player)
  end)

  after_each(function()
    -- 顺序与旧 tearDown 一致：先还原 Debug 开关，再送走玩家，最后还原全局。
    if restore then
      require('common.GameCfg').Debug = restore.GrantDebug
    end
    if env and env.player then
      Mgr:OnPlayerRemoving(env.player)
    end
    if restore then
      _G.game = restore.game
      _G.Vector3 = restore.Vector3
      _G.Color = restore.Color
      _G.REUtil = restore.REUtil
    end
    env = nil
    restore = nil
  end)

  local function select(index)
    env.events.ItemBarAction.OnServerEvent:Fire(env.player, { action = 'SelectSlot', value = index })
  end

  it('test_disconnect_and_partial_spawn_failure_cleanup', function()
    select(1)
    local mount, model = env.created[1], env.created[2]
    Mgr:OnPlayerRemoving(env.player)
    assert.is_true(mount.Destroyed)
    assert.is_true(model.Destroyed)
    env.player.CharacterAdded:Fire({ Name = 'late' })
    assert.same(2, #env.created)
    Mgr:OnPlayerAdded(env.player)
    env.failKind = 'WorldUnit'
    select(1)
    assert.is_true(env.created[3].Destroyed)
    assert.same(3, #env.created)
    env.failKind = nil
    Mgr:SendItemBar(env.player)
    assert.same(5, #env.created)
    assert.is_false(env.created[4].Destroyed)
    assert.is_false(env.created[5].Destroyed)
  end)

  it('test_empty_slot_discard_and_external_depletion_cleanup', function()
    select(1)
    local mount, model = env.created[1], env.created[2]
    select(2)
    assert.is_true(mount.Destroyed)
    assert.is_true(model.Destroyed)
    select(1)
    env.events.ItemBarAction.OnServerEvent:Fire(env.player, { action = 'DiscardSlot', value = 1 })
    assert.is_true(env.created[3].Destroyed)
    assert.is_true(env.created[4].Destroyed)
    assert.is_nil(env.player.lastState.selectedSlot)
  end)

  it('test_external_depletion_and_respawn_cleanup', function()
    select(1)
    local firstMount = env.created[1]
    local oldCharacter = env.player.Character
    env.player.CharacterRemoving:Fire(oldCharacter)
    assert.is_true(firstMount.Destroyed)
    env.player.Character = { Name = 'Respawn' }
    env.player.CharacterAdded:Fire(env.player.Character)
    assert.same(4, #env.created)
    assert.are.equal(env.player.Character, env.created[3].Parent)
    Mgr:GetDataInst(env.player):UpdateData(function(data)
      data.Containers[GameCfg.Items.ContainerId.ItemBar][1].count = 0
    end, true)
    assert.is_true(env.created[3].Destroyed)
    assert.is_true(env.created[4].Destroyed)
    assert.is_nil(env.player.lastState.selectedSlot)
  end)

  it('test_players_hold_independent_rods', function()
    local other = { UserId = 34002, Character = { Name = 'Other' },
      CharacterAdded = signal(), CharacterRemoving = signal() }
    function other:SetAttribute() end
    Mgr:OnPlayerAdded(other)
    select(1)
    env.events.ItemBarAction.OnServerEvent:Fire(other, { action = 'SelectSlot', value = 1 })
    assert.same(4, #env.created)
    assert.are.equal(env.player.Character, env.created[1].Parent)
    assert.are.equal(other.Character, env.created[3].Parent)
    select(1)
    assert.is_true(env.created[1].Destroyed)
    assert.is_false(env.created[3].Destroyed)
    Mgr:OnPlayerRemoving(other)
    assert.is_true(env.created[3].Destroyed)
  end)

  it('test_selected_before_character_spawns_on_character_added', function()
    env.player.Character = nil
    select(1)
    assert.same(0, #env.created)
    assert.same(1, env.player.lastState.selectedSlot)
    env.player.Character = { Name = 'Late' }
    env.player.CharacterAdded:Fire(env.player.Character)
    assert.same(2, #env.created)
    assert.are.equal(env.player.Character, env.created[1].Parent)
  end)

  it('test_selection_spawns_server_mount_and_idempotent_refresh', function()
    select(1)
    assert.same(2, #env.created)
    local mount, model = env.created[1], env.created[2]
    assert.same('SkeletalSocketMount', mount.Kind)
    assert.are.equal(env.player.Character, mount.Parent)
    assert.same('l_weapon', mount.SocketName)
    assert.same('WorldUnit', model.Kind)
    assert.are.equal(mount, model.Parent)
    assert.same('official://mesh/50450', model.RenderMeshId)
    assert.same({ x = 0.2, y = 0.25, z = 0.2 }, model.Scale)
    assert.is_false(model.PhysicsActive)
    assert.is_false(model.CanCollide)
    Mgr:SendItemBar(env.player)
    assert.same(2, #env.created)
    select(1)
    assert.is_true(mount.Destroyed)
    assert.is_true(model.Destroyed)
  end)
end)

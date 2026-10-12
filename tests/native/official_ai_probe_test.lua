-- #50：真实 Lua 执行未修改 AI vendor；Task、单位、向量是引擎边界替身，并非试玩实测。
-- 迁移自 tests/tooling/official_ai_probe_test.lua（#92，LuaUnit → 原生 Busted）；
-- 案例顺序沿用旧入口的类名 + 方法名字典序。Runtime 夹具每次 loadAi() 建立独立模块环境。
local Probe = require('tools.probes.official_ai_probe')
local GameCfg = require('common.GameCfg')

describe("TestOfficialAiProbe", function()
  it("test_ability_bridge_reaches_real_ability_api_boundary", function()
    local Runtime = require('tests.tooling.official_ai_vendor_runtime')
    local ai, env = Runtime.loadAi()
    local unit = env.newUnit(1)
    local manager = { UnitId = 900, attrs = {}, abilities = {}, children = {} }
    function manager:GetChildren() return self.children end
    function manager:GetComponent() return nil end
    function manager:SetAttribute(key, value) self.attrs[key] = value end
    function manager:GetAttribute(key) return self.attrs[key] end
    env.registry._luaTags[manager.UnitId] = { 'AbilityManager' }
    env.registry.registerManager(manager, {
      getAbility = function(slot)
        local script = manager.abilities[slot]
        return script and { getScript = function() return script end,
          startCast = function(point, direction, target)
            env.lastCast = { slot = slot, point = point, direction = direction, target = target }
            return true
          end,
          breakCast = function() env.lastBreak = slot end,
          startAccumulate = function() env.lastAccumulate = slot return true end,
        }
      end,
      getAbilities = function()
        local scripts = {}
        for _, script in pairs(manager.abilities) do scripts[#scripts + 1] = script end
        return scripts
      end,
      addAbility = function(script, slot)
        manager.abilities[slot] = script
        env.lastAdded = { key = script.assetId, slot = slot, script = script }
        script.attrs.AbilityPresetKey = script.assetId
        return true
      end,
    }, unit)
    unit.children[1] = manager
    ai.AddAbilityToSlot(unit, 2, 'probe-ability')
    assert.is_not_nil(env.lastAdded)
    assert.are.equal('probe-ability', env.lastAdded.key)
    assert.are.equal(2, env.lastAdded.slot)
    env.lastAdded = nil
    ai.CastAbilityByKey(unit, 'probe-ability', 0, nil)
    assert.is_nil(env.lastAdded, '已有技能不重复添加')
    assert.is_not_nil(env.lastCast)
    assert.are.equal(2, env.lastCast.slot)
    local target = env.newUnit(3, env.Vector(4, 0, 0))
    env.players.list = { { Character = target } }
    env.lastCast = nil
    local report = Probe.Run({ ai = ai, isolated = true, evidence = 'offline',
      isIsolated = function(u) return u == unit or u == target end,
      createUnit = function() return unit end, destroyUnit = function(u) u:Destroy() end,
      target = target, players = function() return env.players.list end,
      now = function() return env.time.value end, wait = function(s) env.task:pump(s) end,
      vector = env.Vector, abilityKey = 'probe-ability',
      observe = function(u)
        local last = u.Controller.moves[#u.Controller.moves]
        return { moving = env.vecLen(last) > 0, stopped = env.vecLen(last) == 0,
          jumps = u.Controller.jumps, castObserved = env.lastCast ~= nil }
      end,
    })
    assert.is_true(report.ok, table.concat(report.errors, '; '))
    assert.are.equal(target.UnitId, env.lastCast.target)
    local found = false
    for _, evidence in ipairs(report.evidence) do
      if evidence.name == '技能指令' then found = evidence.passed end
    end
    assert.is_true(found)
  end)

  it("test_all_species_are_mapped_without_a_fixed_limit", function()
    local rows = Probe.monsterMappings(GameCfg)
    local seen = {}
    for _, row in ipairs(rows) do
      assert.is_nil(seen[row.id])
      seen[row.id] = true
      assert.is_not_nil(row.official)
      assert.is_not_nil(row.retained)
      assert.are.equal('待试玩验证', row.status)
    end
    for id in pairs(GameCfg.Fish) do assert.is_true(seen[id], id) end
    for _, id in ipairs({ 'fish47Elite', 'fish48Boss', 'fish55Elite', 'fish56Boss' }) do
      assert.is_true(seen[id], id)
    end
    local extra = { Fish = { newcomer = { Id = 'newcomer', Name = '新鱼', Grade = 'elite' } }, Ability = {} }
    assert.are.equal('未登记行为', Probe.monsterMappings(extra)[1].behavior)
  end)

  it("test_disconnected_signal_does_not_fire_after_cleanup", function()
    local Runtime = require('tests.tooling.official_ai_vendor_runtime')
    local _, env = Runtime.loadAi()
    local unit, calls = env.newUnit(91), 0
    local conn = unit.Destroying:Connect(function() calls = calls + 1 end)
    unit.Destroying:Fire()
    conn:Disconnect()
    conn:Disconnect()
    unit.Destroying:Fire()
    assert.are.equal(1, calls)
  end)

  it("test_finished_vendor_move_disconnects_collision_callback", function()
    local ai, env = require('tests.tooling.official_ai_vendor_runtime').loadAi()
    local unit = env.newUnit(19)
    ai.MoveDirection(unit, env.Vector(1, 0, 0), 0.2, 1)
    env.task:pump(0.1)
    unit.Controller.OnCollisionEnter:Fire()
    assert.are.equal(1, unit.Controller.jumps)
    env.task:pump(0.7)
    unit.Controller.OnCollisionEnter:Fire()
    assert.are.equal(1, unit.Controller.jumps, '完成后的碰撞连接应已断开')
    unit:Destroy()
  end)

  it("test_handoff_rejects_old_writers_and_duplicate_hits", function()
    local stopped, writes, damage = 0, 0, 0
    local starts = 0
    local ai = { StopAI = function() stopped = stopped + 1 end,
      StartAI = function() starts = starts + 1 end }
    local gate = Probe.newHandoff(ai, {}, function() writes = writes + 1 end,
      function() damage = damage + 1 end, function() end)
    local old = gate:Switch('official')
    local active = gate:Switch('custom')
    assert.is_false(gate:Write(old, {}))
    assert.is_true(gate:Write(active, {}))
    assert.is_true(gate:Hit(active, 'dive:1:player7', 30))
    assert.is_false(gate:Hit(active, 'dive:1:player7', 30))
    local controlled = gate:Switch('controlled')
    assert.is_false(gate:Write(active, {}))
    assert.is_false(gate:Hit(controlled, 'controlled:hit', 30))
    local restored = gate:Switch('official')
    assert.is_true(gate:Hit(restored, 'dive:1:player7', 30), '新代次允许新的同名攻击')
    assert.is_false(gate:IsActive({ generation = restored.generation, mode = 'official' }), '伪造同代次 token 不得获得所有权')
    assert.same({ 4, 2, 1, 2 }, { stopped, starts, writes, damage })
  end)

  it("test_real_vendor_handoff_restores_new_commands_and_cancels_old_mode", function()
    local ai, env = require('tests.tooling.official_ai_vendor_runtime').loadAi()
    local unit = env.newUnit(31)
    local gate = Probe.newHandoff(ai, unit, function(p) unit:SetPosition(p) end, function() end, function() end)
    local official = gate:Switch('official')
    ai.MoveDirection(unit, env.Vector(1, 0, 0), 0, 0)
    env.task:pump(0.1)
    local custom = gate:Switch('custom')
    assert.are.equal(0, env.vecLen(unit.Controller.moves[#unit.Controller.moves]))
    local count = #unit.Controller.moves
    env.task:pump(0.5)
    assert.are.equal(count, #unit.Controller.moves, '旧移动任务必须取消')
    assert.is_false(gate:Write(official, env.Vector()))
    assert.is_true(gate:Write(custom, env.Vector(0, 5, 0)))
    gate:Switch('controlled')
    assert.is_false(gate:Hit(custom, 'hit', 20))
    gate:Switch('official')
    ai.MoveDirection(unit, env.Vector(0, 0, 1), 0.2, 0)
    env.task:pump(0.1)
    assert.are.equal(1, unit.Controller.moves[#unit.Controller.moves].z)
    unit:Destroy()
    count = #unit.Controller.moves
    env.task:pump(1)
    assert.are.equal(count, #unit.Controller.moves, '销毁后任务不能继续写控制器')
  end)

  it("test_reserved_priority_and_move_threshold_are_inert", function()
    local Runtime = require('tests.tooling.official_ai_vendor_runtime')
    local ai, env = Runtime.loadAi()
    local unit = env.newUnit(1)
    local far = env.newUnit(2, env.Vector(4, 0, 0))
    local near = env.newUnit(3, env.Vector(2, 0, 0))
    env.players.list = { { Character = far }, { Character = near } }
    ai.SetSearchEnemyPriorityValue(unit, far, 999)
    ai.SetSearchEnemyFocusTarget(unit, far)
    ai.SetMoveThreshold(unit, 99)
    ai.SearchEnemy(unit, 10, 0, {}, {}, 0.5, ai.Configs.CMD_RUSH)
    env.task:pump(1.1)
    assert.is_true(#unit.Controller.moves >= 2)
    assert.near(1, unit.Controller.moves[2].x, 1e-9)
  end)

  it("test_run_collects_public_vendor_observations_and_marks_missing_engine_evidence", function()
    local ai, env = require('tests.tooling.official_ai_vendor_runtime').loadAi()
    local unit, target = env.newUnit(41), env.newUnit(42, env.Vector(4, 0, 0))
    env.players.list = { { Character = target } }
    local context = {
      ai = ai, isolated = true, evidence = 'offline',
      isIsolated = function(u) return u == unit or u == target end,
      createUnit = function() return unit end, destroyUnit = function(u) u:Destroy() end,
      target = target, players = function() return env.players.list end,
      now = function() return env.time.value end, wait = function(s) env.task:pump(s) end,
      vector = env.Vector, logger = function() end,
      observe = function(u)
        local last = u.Controller.moves[#u.Controller.moves]
        return { moving = env.vecLen(last) > 0, stopped = env.vecLen(last) == 0,
          jumps = u.Controller.jumps }
      end,
    }
    local report = Probe.Run(context)
    assert.is_true(report.ok, table.concat(report.errors, '; '))
    assert.is_true(report.cleaned)
    assert.is_true(#report.evidence >= 7)
    assert.is_true(#report.missing >= 2, 'Nav和技能未配置必须缺证')
    assert.is_true(unit.destroyed)
  end)

  it("test_run_requires_isolated_units_and_explicit_cleanup", function()
    local context = {
      logger = function() end,
      ai = {}, isolated = true, isIsolated = function() return true end,
      evidence = 'offline', wait = function() end, vector = function() return {} end,
      createUnit = function() return { UnitId = 1 } end,
      destroyUnit = function() error('模拟清理失败') end,
      players = function() return {} end,
      now = function() return 0 end,
    }
    -- 不用 assert.error_matches：Luassert 会先剥掉错误原文开头的 `^.-:%d+: `，而这里的期望子串正坐在
    -- 被剥的那一段里（探针把内层 error 的 `文件:行号: ` 拼在自己前缀后面），剥完只剩「模拟清理失败」，
    -- 断言就变成检查内层消息了。改取 pcall 原文做整体子串匹配，等价旧 assertErrorMsgContains。
    local ok, err = pcall(Probe.Run, context)
    assert.is_false(ok, '清理失败必须抛出错误')
    assert.matches('official_ai_probe 清理失败', tostring(err), 1, true)
    assert.is_nil(context.unit)
  end)

  it("test_vendor_move_direction_stop_and_resume_boundaries", function()
    local Runtime = require('tests.tooling.official_ai_vendor_runtime')
    local ai, env = Runtime.loadAi()
    local unit = env.newUnit(1)
    ai.MoveDirection(unit, env.Vector(1, 0, 0), 0.2, 0)
    env.task:pump(0.1)
    assert.is_true(env.vecLen(unit.Controller.moves[#unit.Controller.moves]) == 1)
    ai.StopMove(unit, 1)
    env.task:pump(0.1)
    assert.are.equal(0, env.vecLen(unit.Controller.moves[#unit.Controller.moves]))
    ai.StopAI(unit)
    ai.StartAI(unit)
    env.task:pump(0.2)
    assert.are.equal(0, env.vecLen(unit.Controller.moves[#unit.Controller.moves]))
    local near = env.newUnit(2, env.Vector(1, 0, 0))
    env.players.list[1] = { Character = near }
    ai.SearchEnemy(unit, 3, 0, {}, {}, 1, ai.Configs.CMD_JUMP)
    env.task:pump(1.1)
    assert.is_true(unit.Controller.jumps >= 1)
  end)
end)

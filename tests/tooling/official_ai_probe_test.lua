-- #50：真实 Lua 执行未修改 AI vendor；Task、单位、向量是引擎边界替身，并非试玩实测。
local lu = require('luaunit')
local Probe = require('tools.probes.official_ai_probe')
local GameCfg = require('common.GameCfg')

TestOfficialAiProbe = {}

function TestOfficialAiProbe:test_vendor_move_direction_stop_and_resume_boundaries()
    local Runtime = require('tests.tooling.official_ai_vendor_runtime')
    local ai, env = Runtime.loadAi()
    local unit = env.newUnit(1)
    ai.MoveDirection(unit, env.Vector(1, 0, 0), 0.2, 0)
    env.task:pump(0.1)
    lu.assertTrue(env.vecLen(unit.Controller.moves[#unit.Controller.moves]) == 1)
    ai.StopMove(unit, 1)
    env.task:pump(0.1)
    lu.assertEquals(env.vecLen(unit.Controller.moves[#unit.Controller.moves]), 0)
    ai.StopAI(unit)
    ai.StartAI(unit)
    env.task:pump(0.2)
    lu.assertEquals(env.vecLen(unit.Controller.moves[#unit.Controller.moves]), 0)
    local near = env.newUnit(2, env.Vector(1, 0, 0))
    env.players.list[1] = { Character = near }
    ai.SearchEnemy(unit, 3, 0, {}, {}, 1, ai.Configs.CMD_JUMP)
    env.task:pump(1.1)
    lu.assertTrue(unit.Controller.jumps >= 1)
end

function TestOfficialAiProbe:test_reserved_priority_and_move_threshold_are_inert()
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
    lu.assertTrue(#unit.Controller.moves >= 2)
    lu.assertAlmostEquals(unit.Controller.moves[2].x, 1, 1e-9)
end

function TestOfficialAiProbe:test_ability_bridge_reaches_real_ability_api_boundary()
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
    lu.assertNotNil(env.lastAdded)
    lu.assertEquals(env.lastAdded.key, 'probe-ability')
    lu.assertEquals(env.lastAdded.slot, 2)
    env.lastAdded = nil
    ai.CastAbilityByKey(unit, 'probe-ability', 0, nil)
    lu.assertNil(env.lastAdded, '已有技能不重复添加')
    lu.assertNotNil(env.lastCast)
    lu.assertEquals(env.lastCast.slot, 2)
end

function TestOfficialAiProbe:test_run_requires_isolated_units_and_explicit_cleanup()
    local context = {
        logger = function() end,
        ai = {},
        createUnit = function() return { UnitId = 1 } end,
        destroyUnit = function() error('模拟清理失败') end,
        players = function() return {} end,
        now = function() return 0 end,
    }
    lu.assertErrorMsgContains('official_ai_probe 清理失败', function() Probe.Run(context) end)
    lu.assertNil(context.unit)
end

function TestOfficialAiProbe:test_handoff_rejects_old_writers_and_duplicate_hits()
    local stopped, writes, damage = 0, 0, 0
    local ai = { StopAI = function() stopped = stopped + 1 end }
    local gate = Probe.newHandoff(ai, {}, function() writes = writes + 1 end,
        function() damage = damage + 1 end, function() end)
    local old = gate:Switch('official')
    local active = gate:Switch('custom')
    lu.assertFalse(gate:Write(old, {}))
    lu.assertTrue(gate:Write(active, {}))
    lu.assertTrue(gate:Hit(active, 'dive:1:player7', 30))
    lu.assertFalse(gate:Hit(active, 'dive:1:player7', 30))
    gate:Switch('controlled')
    lu.assertFalse(gate:Write(active, {}))
    lu.assertEquals({ stopped, writes, damage }, { 3, 1, 1 })
end

function TestOfficialAiProbe:test_all_species_are_mapped_without_a_fixed_limit()
    local rows = Probe.monsterMappings(GameCfg)
    local seen = {}
    for _, row in ipairs(rows) do
        lu.assertNil(seen[row.id])
        seen[row.id] = true
        lu.assertNotNil(row.official)
        lu.assertNotNil(row.retained)
        lu.assertEquals(row.status, '待试玩验证')
    end
    for id in pairs(GameCfg.Fish) do lu.assertTrue(seen[id], id) end
    for _, id in ipairs({ 'fish47Elite', 'fish48Boss', 'fish55Elite', 'fish56Boss' }) do
        lu.assertTrue(seen[id], id)
    end
    local extra = { Fish = { newcomer = { Id = 'newcomer', Name = '新鱼', Grade = 'elite' } }, Ability = {} }
    lu.assertEquals(Probe.monsterMappings(extra)[1].behavior, '未登记行为')
end

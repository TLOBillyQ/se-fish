-- #84 迁移：电鳗技能与战斗状态字标签（原 tests/gameplay/eel_combat_test.lua，12 + 3 例）。
-- 接缝：MgrFishUnit 的 eel 状态机——5 次放电每秒一次、施法被拒不计数不入睡、5 次满才睡 10 秒、
-- 逃跑时限到停施法并移除技能；客户端 FishCombatLabel 纯函数按服务端载荷出字，坏载荷不建节点。
-- TestEelCombat 沿用 tests/support/fish_escape 夹具（不需要 Vitals），TestFishCombatLabel 直接 loadfile 客户端模块。
-- Busted 案例体在沙箱 _ENV 中，写业务可见的全局（Quaternion）必须用 _G.Quaternion。
-- describe/it 名称保留旧类名与方法名，并按方法名字典序注册以保持旧套件执行顺序。
local GameCfg = require('common.GameCfg')
local FishEscape = require('tests.support.fish_escape')

-- 放下一条电鳗；castOk 决定每次施法结果，返回鱼与计数表
local function droppedEel(env, castOk)
    env:prepare()
    local log = { casts = 0, removed = 0, published = {} }
    env.castOk = castOk or function() return true end
    env.mgr.Ability = {
        EquipFish = function() return true end,
        CastFish = function()
            if not env.castOk() then return false end
            log.casts = log.casts + 1
            return true
        end,
        RemoveFish = function() log.removed = log.removed + 1 end,
    }
    env.mgr.CombatPublisher = function(payload) log.published[#log.published + 1] = payload end
    local fish = env:heldFish(env.player, 'eel')
    env.mgr:Drop(env.player)
    return fish, log
end

local function at(env, now, times)
    env.now = now
    for _ = 1, times or 1 do env.mgr:Update() end
end

describe('TestEelCombat', function()
    local env

    before_each(function()
        env = setmetatable({}, { __index = FishEscape })
        env:setUp()
    end)
    after_each(function()
        env:tearDown()
    end)

    it('test_client_snapshots_follow_state_changes', function()
        local fish, log = droppedEel(env)
        local first = log.published[1]
        assert.same({ 'combat', 180, 180, 0, 5 },
            { first.state, first.fleeAt, first.escapeSec, first.discharges, first.dischargeCount })
        assert.are.equal('eel', first.fishId)
        assert.is_not.is_nil(first.position)
        for t = 0, 5 do at(env, t) end
        local states = {}
        for i = 2, #log.published do
            local p = log.published[i]
            states[#states + 1] = p.state .. ':' .. p.discharges
        end
        assert.same({ 'attacking:1', 'attacking:2', 'attacking:3', 'attacking:4', 'attacking:5', 'sleeping:5' }, states)
        assert.are.equal(15, log.published[#log.published].wakeAt)
        at(env, 15)
        assert.are.equal('combat', log.published[#log.published - 1].state)
        assert.are.equal('attacking', log.published[#log.published].state)
        assert.is_true(fish.CombatPublished)
    end)

    it('test_combat_fish_is_not_counted_as_escaping', function()
        -- 再放普通鱼不能提前清掉尚未到逃跑时限的精英鱼。
        env:prepare()
        local eel = env:heldFish(env.player, 'eel')
        env.mgr:Drop(env.player)
        env.now = 1
        local normal = env:heldFish(env.player, 'bass')
        env.mgr:Drop(env.player)
        assert.same(eel, env.mgr.Fish[eel.Id])
        assert.same({ normal }, env.mgr:Escaping())
    end)

    it('test_escape_goes_straight_and_vanishes_in_water', function()
        local fish = droppedEel(env)
        at(env, 180)
        assert.are.equal('escaping', fish.State)
        local heading = fish.Heading
        env.hits = { { Instance = { Name = 'Wall' }, Distance = 1 } }
        at(env, 184)
        assert.same(heading, fish.Heading)
        fish.Carrier.Body.Position = Vector3.New(-11.75, 5, -12.25)
        env.mgr:Update()
        assert.is_nil(env.mgr.Fish[fish.Id])
    end)

    it('test_five_discharges_one_second_apart_then_sleeps_ten_seconds', function()
        local fish, log = droppedEel(env)
        assert.are.equal('combat', fish.State)
        for i = 0, 4 do
            at(env, i)
            assert.are.equal(i + 1, log.casts)
            assert.are.equal('attacking', fish.State)
            at(env, i + 0.5)
            assert.are.equal(i + 1, log.casts)
        end
        at(env, 4.99)
        assert.are.equal('attacking', fish.State)
        at(env, 5)
        assert.are.equal('sleeping', fish.State)
        assert.are.equal(15, fish.WakeAt)
        at(env, 14.99)
        assert.are.equal(5, log.casts)
        assert.are.equal('sleeping', fish.State)
        at(env, 15)
        assert.are.equal(6, log.casts)
        assert.are.equal('attacking', fish.State)
        assert.are.equal(1, fish.Discharges)
    end)

    it('test_flee_deadline_mid_attack_stops_casting_and_removes_skill', function()
        local fish, log = droppedEel(env)
        at(env, 0)
        at(env, 5)
        at(env, 177.5)
        assert.are.equal('attacking', fish.State)
        local casts = log.casts
        at(env, 180)
        assert.are.equal('escaping', fish.State)
        assert.are.equal(1, log.removed)
        at(env, 181)
        assert.are.equal(casts, log.casts)
        assert.are.equal('escaping', log.published[#log.published].state)
    end)

    it('test_killed_mid_attack_stops_and_label_disappears', function()
        local fish, log = droppedEel(env)
        at(env, 0)
        at(env, 1)
        assert.is_not.is_nil(env.mgr:TakeKilled(fish))
        assert.are.equal(1, log.removed)
        assert.same({ id = fish.Id, state = 'gone' }, log.published[#log.published])
        at(env, 2)
        assert.are.equal(2, log.casts)
        assert.is_nil(env.mgr:TakeKilled(fish))
    end)

    it('test_large_dt_neither_bursts_nor_swallows_sleep', function()
        local fish, log = droppedEel(env)
        at(env, 0)
        at(env, 3.7)
        assert.are.equal(2, log.casts)
        at(env, 3.7, 2)
        assert.are.equal(2, log.casts)
        at(env, 4.69)
        assert.are.equal(2, log.casts)
        at(env, 20)
        at(env, 21)
        at(env, 22)
        assert.are.equal(5, log.casts)
        at(env, 60)
        assert.are.equal('sleeping', fish.State)
        assert.are.equal(70, fish.WakeAt)
        at(env, 69.9)
        assert.are.equal(5, log.casts)
        at(env, 70)
        assert.are.equal(6, log.casts)
    end)

    it('test_moving_elite_shares_flee_bar_with_throttled_refresh', function()
        -- 逃跑时限条与鳄雀鳝共用：会移动的精英按限频补发坐标，不带放电字段，逃跑时标签收起。
        env:prepare()
        local published = {}
        env.mgr.Ability = { EquipFish = function() return true end, CastFish = function() return true end,
            RemoveFish = function() end }
        env.mgr.CombatPublisher = function(payload) published[#published + 1] = payload end
        local fish = env:heldFish(env.player, 'alligatorGar')
        env.mgr:Drop(env.player)
        local escapeSec = GameCfg.Fish.alligatorGar.EscapeSec
        assert.same({ 'combat', escapeSec, escapeSec }, { published[1].state, published[1].fleeAt, published[1].escapeSec })
        assert.is_nil(published[1].dischargeCount)
        local refresh = GameCfg.FishCombatLabel.MovingRefreshSec
        at(env, 0, 3)
        local count = #published
        at(env, refresh / 2)
        assert.are.equal(count, #published)
        at(env, refresh)
        assert.are.equal(count + 1, #published)
        at(env, escapeSec)
        assert.are.equal('escaping', fish.State)
        assert.are.equal('escaping', published[#published].state)
    end)

    it('test_rejected_cast_is_not_counted_and_retried', function()
        -- 打断：施法被技能包拒绝（InCast 未清 / 技能未就绪）不计数、不入睡，下帧重试
        local accept = false
        local fish, log = droppedEel(env, function() return accept end)
        at(env, 0)
        at(env, 3)
        assert.are.equal('combat', fish.State)
        assert.are.equal(0, log.casts)
        accept = true
        at(env, 3.1)
        assert.are.equal('attacking', fish.State)
        accept = false
        at(env, 4.1)
        at(env, 4.2)
        assert.are.equal(1, fish.Discharges)
        assert.are.equal('attacking', fish.State)
        accept = true
        at(env, 4.3)
        assert.are.equal(2, fish.Discharges)
        assert.are.equal(5.3, fish.NextDischargeAt)
    end)

    it('test_repeated_updates_at_same_time_discharge_once', function()
        local fish, log = droppedEel(env)
        at(env, 0, 3)
        assert.are.equal(1, log.casts)
        at(env, 1, 3)
        assert.are.equal(2, log.casts)
        assert.are.equal(2, fish.Discharges)
    end)

    it('test_skill_numbers_live_in_ability_cfg', function()
        local eel = GameCfg.Ability.FishAbilities.eel
        assert.same({ 5, 10, 5, 1, 10 },
            { eel.Radius, eel.Damage, eel.DischargeCount, eel.DischargeIntervalSec, eel.SleepSec })
        assert.is_true(eel.CastSec < eel.DischargeIntervalSec)
        assert.are.equal(180, GameCfg.Fish.eel.EscapeSec)
    end)

    it('test_sleep_lies_sideways_and_waking_restores_rotation', function()
        env:prepare()
        local oldQuaternion = _G.Quaternion
        local rotation = setmetatable({}, { __mul = function(_, value) return value end })
        -- Busted 案例体在沙箱 _ENV：业务模块读的是真 _G，必须写 _G.Quaternion
        _G.Quaternion = { FromEulerAngles = function(x, y, z) return { x = x, y = y, z = z } end }
        env.mgr.Ability = { EquipFish = function() end, CastFish = function() return true end }
        local fish = env:heldFish(env.player, 'eel')
        fish.Carrier.Body.Rotation = rotation
        env.mgr:Drop(env.player)
        for t = 0, 5 do at(env, t) end
        local sleepRotation = fish.Carrier.Body.Rotation
        at(env, 15)
        local wakeRotation = fish.Carrier.Body.Rotation
        _G.Quaternion = oldQuaternion
        assert.are.equal('attacking', fish.State)
        assert.are.equal(GameCfg.Ability.FishAbilities.eel.SleepRollRadians, sleepRotation.z)
        assert.are_not.equal(sleepRotation.z, wakeRotation.z)
    end)
end)

-- 客户端状态字：纯函数按服务端时间出字，坏载荷不建节点
local function with(base, extra)
    local t = {}
    for k, v in pairs(base) do t[k] = v end
    for k, v in pairs(extra) do t[k] = v end
    return t
end

describe('TestFishCombatLabel', function()
    local env

    before_each(function()
        env = {}
        env.label = assert(loadfile('client/FishCombatLabel.lua'))()
        env.base = { id = 1, fishId = 'eel', fleeAt = 180, escapeSec = 180, discharges = 3, dischargeCount = 5,
            position = { x = 0, y = 0, z = 0 } }
    end)
    after_each(function()
        env = nil
    end)

    it('test_crab_move_names_render_chinese_labels', function()
        -- #136 蟹类招式中文名：帝王蟹乱刺 / 蟹老板双击、冲撞、旋转
        for move, name in pairs({ jab = '蟹钳乱刺', pinch = '蟹钳双击', charge = '冲撞', spin = '旋转' }) do
            local text, kind = env.label.Text(with(env.base, { fishId = 'fish24Boss', state = 'combat', move = move }), 90)
            assert.are.equal('attack', kind)
            assert.matches(name, text, nil, true)
        end
    end)

    it('test_text_shows_discharges_sleep_and_flee_bar', function()
        local text, kind = env.label.Text(with(env.base, { state = 'attacking' }), 90)
        assert.are.equal('attack', kind)
        assert.matches('电鳗 放电 3/5', text, nil, true)
        assert.matches('逃跑时限 [=====-----] 90 秒', text, nil, true)
        text, kind = env.label.Text(with(env.base, { state = 'sleeping', wakeAt = 97.2 }), 90)
        assert.are.equal('sleep', kind)
        assert.matches('睡眠 8 秒', text, nil, true)
        assert.is_nil(env.label.Text(with(env.base, { state = 'combat' }), 180))
        text, kind = env.label.Text(with(env.base, { fishId = 'alligatorGar', state = 'attacking' }), 90)
        assert.are.equal('idle', kind)
        assert.is_nil(text:find('放电', 1, true))
    end)

    it('test_valid_rejects_malformed_payloads', function()
        assert.is_true(env.label.Valid(with(env.base, { state = 'attacking' })))
        assert.is_true(env.label.Valid({ id = 1, state = 'gone' }))
        assert.is_false(env.label.Valid(with(env.base, { state = 'attacking', fleeAt = 0 / 0 })))
        assert.is_false(env.label.Valid(with(env.base, { state = 'attacking', escapeSec = 0 })))
        assert.is_false(env.label.Valid(with(env.base, { state = 'attacking', position = 'x' })))
        assert.is_false(env.label.Valid({ state = 'gone' }))
    end)
end)

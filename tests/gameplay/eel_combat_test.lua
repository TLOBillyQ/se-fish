-- #86 失败方式：举鱼提前攻击、施法失败也睡眠、睡眠反复攻击、180秒仍睡眠、直线逃脱被普通鱼转向覆盖、移除残留技能。
-- #134 正式行为失败方式（先列后写）：
--   1. 一轮放电不是 5 次：施法被拒/打断也计数，或重复 Update、同一时刻连放；
--   2. 间隔不是 1 秒：大 dt 后补发连击，或按帧而不是按时刻放电；
--   3. 5 次未满就睡、睡眠不足 10 秒（大 dt 吞掉睡眠窗口）、睡眠中仍放电；
--   4. 攻击中到逃跑时限仍施法，或逃跑后技能残留；
--   5. 被打死后仍放电，或客户端状态字不消失；
--   6. 客户端看不到放电次数 / 睡眠倒计时 / 逃跑时限（只有日志）；
--   7. 放电范围不是 5 米、伤害不是 10、技能数值不在 GameCfg.Ability。
local lu = require('luaunit')
local GameCfg = require('common.GameCfg')
require('tests.gameplay.fish_escape_test')
TestEelCombat = {}
for _, name in ipairs({ 'setUp', 'tearDown', 'newPlayer', 'land', 'mounts', 'prepare', 'heldFish' }) do
    TestEelCombat[name] = TestFishEscape[name]
end

-- 放下一条电鳗；castOk 决定每次施法结果，返回鱼与计数表
function TestEelCombat:droppedEel(castOk)
    self:prepare()
    local log = { casts = 0, removed = 0, published = {} }
    self.castOk = castOk or function() return true end
    local env = self
    self.mgr.Ability = {
        EquipFish = function() return true end,
        CastFish = function()
            if not env.castOk() then return false end
            log.casts = log.casts + 1
            return true
        end,
        RemoveFish = function() log.removed = log.removed + 1 end,
    }
    self.mgr.CombatPublisher = function(payload) log.published[#log.published + 1] = payload end
    local fish = self:heldFish(self.player, 'eel')
    self.mgr:Drop(self.player)
    return fish, log
end

function TestEelCombat:at(now, times)
    self.now = now
    for _ = 1, times or 1 do self.mgr:Update() end
end

function TestEelCombat:test_skill_numbers_live_in_ability_cfg()
    local eel = GameCfg.Ability.FishAbilities.eel
    lu.assertEquals({ eel.Radius, eel.Damage, eel.DischargeCount, eel.DischargeIntervalSec, eel.SleepSec },
        { 5, 10, 5, 1, 10 })
    lu.assertTrue(eel.CastSec < eel.DischargeIntervalSec)
    lu.assertEquals(GameCfg.Fish.eel.EscapeSec, 180)
end

function TestEelCombat:test_five_discharges_one_second_apart_then_sleeps_ten_seconds()
    local fish, log = self:droppedEel()
    lu.assertEquals(fish.State, 'combat')
    for i = 0, 4 do
        self:at(i)
        lu.assertEquals(log.casts, i + 1)
        lu.assertEquals(fish.State, 'attacking')
        self:at(i + 0.5)
        lu.assertEquals(log.casts, i + 1)
    end
    self:at(4.99)
    lu.assertEquals(fish.State, 'attacking')
    self:at(5)
    lu.assertEquals(fish.State, 'sleeping')
    lu.assertEquals(fish.WakeAt, 15)
    self:at(14.99)
    lu.assertEquals(log.casts, 5)
    lu.assertEquals(fish.State, 'sleeping')
    self:at(15)
    lu.assertEquals(log.casts, 6)
    lu.assertEquals(fish.State, 'attacking')
    lu.assertEquals(fish.Discharges, 1)
end

function TestEelCombat:test_repeated_updates_at_same_time_discharge_once()
    local fish, log = self:droppedEel()
    self:at(0, 3)
    lu.assertEquals(log.casts, 1)
    self:at(1, 3)
    lu.assertEquals(log.casts, 2)
    lu.assertEquals(fish.Discharges, 2)
end

function TestEelCombat:test_large_dt_neither_bursts_nor_swallows_sleep()
    local fish, log = self:droppedEel()
    self:at(0)
    self:at(3.7)
    lu.assertEquals(log.casts, 2)
    self:at(3.7, 2)
    lu.assertEquals(log.casts, 2)
    self:at(4.69)
    lu.assertEquals(log.casts, 2)
    self:at(20)
    self:at(21)
    self:at(22)
    lu.assertEquals(log.casts, 5)
    self:at(60)
    lu.assertEquals(fish.State, 'sleeping')
    lu.assertEquals(fish.WakeAt, 70)
    self:at(69.9)
    lu.assertEquals(log.casts, 5)
    self:at(70)
    lu.assertEquals(log.casts, 6)
end

-- 打断：施法被技能包拒绝（InCast 未清 / 技能未就绪）不计数、不入睡，下帧重试
function TestEelCombat:test_rejected_cast_is_not_counted_and_retried()
    local accept = false
    local fish, log = self:droppedEel(function() return accept end)
    self:at(0)
    self:at(3)
    lu.assertEquals(fish.State, 'combat')
    lu.assertEquals(log.casts, 0)
    accept = true
    self:at(3.1)
    lu.assertEquals(fish.State, 'attacking')
    accept = false
    self:at(4.1)
    self:at(4.2)
    lu.assertEquals(fish.Discharges, 1)
    lu.assertEquals(fish.State, 'attacking')
    accept = true
    self:at(4.3)
    lu.assertEquals(fish.Discharges, 2)
    lu.assertEquals(fish.NextDischargeAt, 5.3)
end

function TestEelCombat:test_flee_deadline_mid_attack_stops_casting_and_removes_skill()
    local fish, log = self:droppedEel()
    self:at(0)
    self:at(5)
    self:at(177.5)
    lu.assertEquals(fish.State, 'attacking')
    local casts = log.casts
    self:at(180)
    lu.assertEquals(fish.State, 'escaping')
    lu.assertEquals(log.removed, 1)
    self:at(181)
    lu.assertEquals(log.casts, casts)
    lu.assertEquals(log.published[#log.published].state, 'escaping')
end

function TestEelCombat:test_killed_mid_attack_stops_and_label_disappears()
    local fish, log = self:droppedEel()
    self:at(0)
    self:at(1)
    lu.assertNotNil(self.mgr:TakeKilled(fish))
    lu.assertEquals(log.removed, 1)
    lu.assertEquals(log.published[#log.published], { id = fish.Id, state = 'gone' })
    self:at(2)
    lu.assertEquals(log.casts, 2)
    lu.assertNil(self.mgr:TakeKilled(fish))
end

function TestEelCombat:test_client_snapshots_follow_state_changes()
    local fish, log = self:droppedEel()
    local first = log.published[1]
    lu.assertEquals({ first.state, first.fleeAt, first.escapeSec, first.discharges, first.dischargeCount },
        { 'combat', 180, 180, 0, 5 })
    lu.assertEquals(first.fishId, 'eel')
    lu.assertNotNil(first.position)
    for t = 0, 5 do self:at(t) end
    local states = {}
    for i = 2, #log.published do
        local p = log.published[i]
        states[#states + 1] = p.state .. ':' .. p.discharges
    end
    lu.assertEquals(states, { 'attacking:1', 'attacking:2', 'attacking:3', 'attacking:4', 'attacking:5', 'sleeping:5' })
    lu.assertEquals(log.published[#log.published].wakeAt, 15)
    self:at(15)
    lu.assertEquals(log.published[#log.published - 1].state, 'combat')
    lu.assertEquals(log.published[#log.published].state, 'attacking')
    lu.assertTrue(fish.CombatPublished)
end

-- 逃跑时限条与鳄雀鳝共用：会移动的精英按限频补发坐标，不带放电字段，逃跑时标签收起。
function TestEelCombat:test_moving_elite_shares_flee_bar_with_throttled_refresh()
    self:prepare()
    local published = {}
    self.mgr.Ability = { EquipFish = function() return true end, CastFish = function() return true end,
        RemoveFish = function() end }
    self.mgr.CombatPublisher = function(payload) published[#published + 1] = payload end
    local fish = self:heldFish(self.player, 'alligatorGar')
    self.mgr:Drop(self.player)
    local escapeSec = GameCfg.Fish.alligatorGar.EscapeSec
    lu.assertEquals({ published[1].state, published[1].fleeAt, published[1].escapeSec }, { 'combat', escapeSec, escapeSec })
    lu.assertNil(published[1].dischargeCount)
    local refresh = GameCfg.FishCombatLabel.MovingRefreshSec
    self:at(0, 3)
    local count = #published
    self:at(refresh / 2)
    lu.assertEquals(#published, count)
    self:at(refresh)
    lu.assertEquals(#published, count + 1)
    self:at(escapeSec)
    lu.assertEquals(fish.State, 'escaping')
    lu.assertEquals(published[#published].state, 'escaping')
end

-- 再放普通鱼不能提前清掉尚未到逃跑时限的精英鱼。
function TestEelCombat:test_combat_fish_is_not_counted_as_escaping()
    self:prepare()
    local eel = self:heldFish(self.player, 'eel')
    self.mgr:Drop(self.player)
    self.now = 1
    local normal = self:heldFish(self.player, 'bass')
    self.mgr:Drop(self.player)
    lu.assertEquals(self.mgr.Fish[eel.Id], eel)
    lu.assertEquals(self.mgr:Escaping(), { normal })
end

function TestEelCombat:test_escape_goes_straight_and_vanishes_in_water()
    local fish = self:droppedEel()
    self:at(180)
    lu.assertEquals(fish.State, 'escaping')
    local heading = fish.Heading
    self.hits = { { Instance = { Name = 'Wall' }, Distance = 1 } }
    self:at(184)
    lu.assertEquals(fish.Heading, heading)
    fish.Carrier.Body.Position = Vector3.New(-11.75, 5, 27.75)
    self.mgr:Update()
    lu.assertNil(self.mgr.Fish[fish.Id])
end

function TestEelCombat:test_sleep_lies_sideways_and_waking_restores_rotation()
    self:prepare()
    local oldQuaternion = Quaternion
    local rotation = setmetatable({}, { __mul = function(_, value) return value end })
    Quaternion = { FromEulerAngles = function(x, y, z) return { x = x, y = y, z = z } end }
    self.mgr.Ability = { EquipFish = function() end, CastFish = function() return true end }
    local fish = self:heldFish(self.player, 'eel')
    fish.Carrier.Body.Rotation = rotation
    self.mgr:Drop(self.player)
    for t = 0, 5 do self:at(t) end
    local sleepRotation = fish.Carrier.Body.Rotation
    self:at(15)
    local wakeRotation = fish.Carrier.Body.Rotation
    Quaternion = oldQuaternion
    lu.assertEquals(fish.State, 'attacking')
    lu.assertEquals(sleepRotation.z, GameCfg.Ability.FishAbilities.eel.SleepRollRadians)
    lu.assertNotEquals(wakeRotation.z, sleepRotation.z)
end

-- 客户端状态字：纯函数按服务端时间出字，坏载荷不建节点
TestFishCombatLabel = {}
function TestFishCombatLabel:setUp()
    self.label = assert(loadfile('client/FishCombatLabel.lua'))()
    self.base = { id = 1, fishId = 'eel', fleeAt = 180, escapeSec = 180, discharges = 3, dischargeCount = 5,
        position = { x = 0, y = 0, z = 0 } }
end
local function with(base, extra)
    local t = {}
    for k, v in pairs(base) do t[k] = v end
    for k, v in pairs(extra) do t[k] = v end
    return t
end
function TestFishCombatLabel:test_text_shows_discharges_sleep_and_flee_bar()
    local text, kind = self.label.Text(with(self.base, { state = 'attacking' }), 90)
    lu.assertEquals(kind, 'attack')
    lu.assertStrContains(text, '电鳗 放电 3/5')
    lu.assertStrContains(text, '逃跑时限 [=====-----] 90 秒')
    text, kind = self.label.Text(with(self.base, { state = 'sleeping', wakeAt = 97.2 }), 90)
    lu.assertEquals(kind, 'sleep')
    lu.assertStrContains(text, '睡眠 8 秒')
    lu.assertNil(self.label.Text(with(self.base, { state = 'combat' }), 180))
    text, kind = self.label.Text(with(self.base, { fishId = 'alligatorGar', state = 'attacking' }), 90)
    lu.assertEquals(kind, 'idle')
    lu.assertNil(text:find('放电', 1, true))
end
-- #136 蟹类招式中文名：帝王蟹乱刺 / 蟹老板双击、冲撞、旋转
function TestFishCombatLabel:test_crab_move_names_render_chinese_labels()
    for move, name in pairs({ jab = '蟹钳乱刺', pinch = '蟹钳双击', charge = '冲撞', spin = '旋转' }) do
        local text, kind = self.label.Text(with(self.base, { fishId = 'fish24Boss', state = 'combat', move = move }), 90)
        lu.assertEquals(kind, 'attack')
        lu.assertStrContains(text, name)
    end
end
function TestFishCombatLabel:test_valid_rejects_malformed_payloads()
    lu.assertTrue(self.label.Valid(with(self.base, { state = 'attacking' })))
    lu.assertTrue(self.label.Valid({ id = 1, state = 'gone' }))
    lu.assertFalse(self.label.Valid(with(self.base, { state = 'attacking', fleeAt = 0 / 0 })))
    lu.assertFalse(self.label.Valid(with(self.base, { state = 'attacking', escapeSec = 0 })))
    lu.assertFalse(self.label.Valid(with(self.base, { state = 'attacking', position = 'x' })))
    lu.assertFalse(self.label.Valid({ state = 'gone' }))
end

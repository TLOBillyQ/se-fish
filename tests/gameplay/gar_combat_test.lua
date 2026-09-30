-- #88 鳄雀鳝首领战（占位）：上岸放下后主动追咬最近的活着的玩家，600HP / 攻 30 / 逃跑时限 300 秒，
-- 头伤 / 身后弱点判定后补（任务说明：占位即可）。
-- 失败方式（先列后写）：
--   1. 放下后不进入战斗（当普通鱼逃了），或不动 / 不追最近的玩家；
--   2. 追错了：追死玩家、追更远的玩家；追咬速度不取鱼种 Speed；
--   3. 咬不合约：超出咬距也咬、没有冷却连咬、伤害不取鱼种 Attack；
--   4. 逃跑时限耗尽不走精英直线逃脱；
--   5. 首领战走了电鳗的技能装配 / 睡眠路径，或反过来电鳗被追咬路径截胡。
-- #134 头部攻击与绕后（先列后写）：
--   6. 咬不看朝向：身后 / 正侧面仍被咬，绕后无效；或正前方头部区内反而不咬；
--   7. 咬距边界错：恰好 BiteRange 不咬、超出一点仍咬；与鱼中点重合时方向未定义出 NaN / 报错；
--   8. 预警期间鱼跟着目标转头（锁定失效），绕后仍被咬；咬空后不重新对准、或立刻补咬（冷却失效）；
--   9. 预警中目标走出咬距、濒死、离线仍结算伤害，或锁定不释放导致鱼原地发呆不追；
--  10. 鱼被移除（死亡 / 清场）或逃跑时限到时，预警残留：仍结算伤害，或客户端预警不收起；
--  11. 朝向不可辨识：追击 / 锁定不写 body.Rotation，或缺 Quaternion 时报错；预警广播字段缺失或推送失败把追咬打断。
local lu = require('luaunit')
require('tests.gameplay.fish_escape_test')

TestGarCombat = {}
for _, name in ipairs({ 'setUp', 'tearDown', 'newPlayer', 'land', 'mounts', 'prepare', 'heldFish' }) do
    TestGarCombat[name] = TestFishEscape[name]
end

local function vec(x, y, z) return { x = x, y = y, z = z } end

local function armPlayer(player, health)
    local damages = {}
    player.Character.Controller.Health = health
    player.Character.Controller.TakeDamage = function(_, d) damages[#damages + 1] = d end
    return damages
end

local function armVitals(self)
    self.vitalsCalls = {}
    self.downed = {}
    self.mgr.Vitals = {
        NewHit = function(_, source, category) return { source = source, category = category } end,
        ApplyHit = function(_, hit, player, amount)
            self.vitalsCalls[#self.vitalsCalls + 1] = { hit, player, amount }
            player.Character.Controller:TakeDamage(amount)
            return true, amount
        end,
        CanTakeDamage = function(_, player)
            return not self.downed[player] and (player.Character.Controller.Health or 0) > 0
        end,
    }
end

local baseSetUp = TestFishEscape.setUp
local baseTearDown = TestFishEscape.tearDown
function TestGarCombat:setUp()
    baseSetUp(self)
    armVitals(self)
    self.savedQuaternion = rawget(_G, 'Quaternion')
    self.notices = {}
    local env = self
    self.mgr.PublishBite = function(_, payload) env.notices[#env.notices + 1] = payload end
end

function TestGarCombat:tearDown()
    _G.Quaternion = self.savedQuaternion
    baseTearDown(self)
end

function TestGarCombat:test_drop_enters_combat_and_chases_nearest_living_player()
    self:prepare()
    armPlayer(self.player, 300)
    armPlayer(self.other, 300)
    local equipped = 0
    self.mgr.Ability = { EquipFish = function() equipped = equipped + 1 end }
    local fish = self:heldFish(self.player, 'alligatorGar')
    self.mgr:Drop(self.player)
    lu.assertEquals(fish.State, 'combat')
    lu.assertNotNil(fish.FleeAt)
    -- 放下后玩家走开：鱼追最近的 self.player（+z 方向），速度取鱼种 Speed=6；不走技能装配
    self.player.Character.Position = vec(10, 2, 40)
    self.mgr:Update()
    local v = fish.Carrier.Body.LinearVelocity
    lu.assertAlmostEquals(v.x, 0, 1e-6)
    lu.assertAlmostEquals(v.z, 6, 1e-6)
    lu.assertEquals(equipped, 0)
    -- self.player 倒下后改追 self.other（-x 方向）
    self.player.Character.Controller.Health = 0
    self.mgr:Update()
    v = fish.Carrier.Body.LinearVelocity
    lu.assertTrue(v.x > 0)
    lu.assertAlmostEquals(math.sqrt(v.x * v.x + v.z * v.z), 6, 1e-6)
end

function TestGarCombat:test_bite_only_in_range_with_cooldown_and_species_attack()
    self:prepare()
    local damages = armPlayer(self.player, 300)
    local fish = self:heldFish(self.player, 'alligatorGar')
    self.mgr:Drop(self.player)
    local body = fish.Carrier.Body
    -- 站进咬距：首个冷却期是起手预警，不立刻咬
    self.player.Character.Position = vec(body.Position.x, 2, body.Position.z)
    self.mgr:Update()
    lu.assertEquals(damages, {})
    lu.assertAlmostEquals(body.LinearVelocity.x, 0, 1e-6)
    lu.assertAlmostEquals(body.LinearVelocity.z, 0, 1e-6)
    local cd = require('common.GameCfg').FishCombat.gar.BiteCooldownSec
    self.now = cd
    self.mgr:Update()
    lu.assertEquals(damages, { 30 })
    lu.assertEquals(#self.vitalsCalls, 1)
    lu.assertEquals(self.vitalsCalls[1][1].source, fish)
    lu.assertEquals(self.vitalsCalls[1][1].category, 'fishAttack')
    lu.assertEquals(self.vitalsCalls[1][2], self.player)
    self.now = cd + 0.1
    self.mgr:Update()
    lu.assertEquals(damages, { 30 })
    self.now = cd * 2
    self.mgr:Update()
    lu.assertEquals(damages, { 30, 30 })
    -- 走出咬距：不咬，恢复追击
    self.player.Character.Position = vec(body.Position.x + 10, 2, body.Position.z)
    self.now = cd * 3
    self.mgr:Update()
    lu.assertEquals(damages, { 30, 30 })
    lu.assertTrue(body.LinearVelocity.x > 0)
end

function TestGarCombat:test_threat_target_and_override_reselect_legal_targets()
    self:prepare()
    armPlayer(self.player, 300)
    armPlayer(self.other, 300)
    local fish = self:heldFish(self.player, 'alligatorGar')
    self.mgr:Drop(self.player)
    local body = fish.Carrier.Body
    self.mgr:NoteDamage(fish, self.player, 30)
    self.mgr:NoteDamage(fish, self.other, 10)
    -- other 更近，但累计有效伤害更高的 player 优先
    self.other.Character.Position = vec(body.Position.x, 2, body.Position.z + 10)
    self.player.Character.Position = vec(body.Position.x + 10, 2, body.Position.z)
    self.mgr:Update()
    lu.assertTrue(body.LinearVelocity.x > 0)
    -- 特殊招式目标优先于仇恨
    self.mgr:SetTargetOverride(fish, self.other)
    self.mgr:Update()
    lu.assertTrue(body.LinearVelocity.z > 0)
    -- 指定目标失效即清理，回到最高仇恨；最高仇恨失效后重选合法目标
    self.downed[self.other] = true
    self.mgr:Update()
    lu.assertTrue(body.LinearVelocity.x > 0)
    lu.assertNil(fish.TargetOverride)
    self.downed[self.player] = true
    self.downed[self.other] = false
    self.mgr:Update()
    lu.assertTrue(body.LinearVelocity.z > 0)
    lu.assertNil(fish.Threat[self.player])
end

function TestGarCombat:test_bite_is_skipped_when_vitals_entry_is_not_wired()
    -- #128 健壮性：Vitals 未接线（如独立测试或接线遗漏）时追咬不得报错，只停住不咬
    self:prepare()
    armPlayer(self.player, 300)
    local fish = self:heldFish(self.player, 'alligatorGar')
    self.mgr:Drop(self.player)
    self.mgr.Vitals = nil
    local body = fish.Carrier.Body
    self.player.Character.Position = vec(body.Position.x, 2, body.Position.z)
    local cd = require('common.GameCfg').FishCombat.gar.BiteCooldownSec
    self.now = cd
    self.mgr:Update()
    lu.assertEquals(self.player.Character.Controller.Health, 300)
end

function TestGarCombat:test_flee_deadline_switches_to_straight_escape()
    self:prepare()
    armPlayer(self.player, 300)
    local fish = self:heldFish(self.player, 'alligatorGar')
    self.mgr:Drop(self.player)
    self.player.Character.Position = vec(10, 2, 40)
    self.now = 299
    self.mgr:Update()
    lu.assertEquals(fish.State, 'combat')
    self.now = 300
    self.mgr:Update()
    lu.assertEquals(fish.State, 'escaping')
    lu.assertTrue(fish.StraightEscape)
    -- 直线逃脱朝最近的拼接水区 PondSouth_7_1（中心 11.5, 13.5），从 (10, 22) 朝南。
    lu.assertTrue(fish.Carrier.Body.LinearVelocity.z < 0)
end

-- ===== #134 头部攻击与绕后 =====
local function gar() return require('common.GameCfg').FishCombat.gar end

local function lastNotice(self, kind)
    for i = #self.notices, 1, -1 do
        if self.notices[i].kind == kind then return self.notices[i] end
    end
end

-- 放下后把玩家摆到鱼身 (dx,dz) 处；返回鱼、鱼身位置、伤害记录
local function dropNear(self, dx, dz)
    self:prepare()
    local damages = armPlayer(self.player, 300)
    local fish = self:heldFish(self.player, 'alligatorGar')
    self.mgr:Drop(self.player)
    local p = fish.Carrier.Body.Position
    self.player.Character.Position = vec(p.x + dx, 2, p.z + dz)
    return fish, p, damages
end

function TestGarCombat:test_head_zone_geometry_and_range_boundary()
    local params = gar()
    local pos, facing = vec(0, 0, 0), { x = 0, z = 1 }
    local head = self.mgr.InHeadZone
    lu.assertTrue(head(pos, facing, vec(0, 0, params.BiteRange), params))        -- 正前方恰好咬距
    lu.assertFalse(head(pos, facing, vec(0, 0, params.BiteRange + 0.01), params)) -- 超出一点
    lu.assertTrue(head(pos, facing, vec(1, 0, 0.2), params))                     -- 斜前方
    lu.assertFalse(head(pos, facing, vec(1, 0, 0), params))                      -- 正侧面算后身
    lu.assertFalse(head(pos, facing, vec(0, 0, -1), params))                     -- 身后
    lu.assertFalse(head(pos, facing, vec(-0.5, 0, -2), params))                  -- 后身斜后
    lu.assertTrue(head(pos, facing, vec(0, 0, 0), params))                       -- 与中点重合无方向，按贴脸算
end

function TestGarCombat:test_windup_locks_facing_so_circling_behind_misses_then_reaims()
    local fish, p, damages = dropNear(self, 0, 2)
    local cd = gar().BiteCooldownSec
    self.mgr:Update()
    lu.assertNotNil(fish.BiteAim)
    lu.assertAlmostEquals(fish.Facing.z, 1, 1e-9)
    local lock = lastNotice(self, 'lock')
    lu.assertEquals(lock.fishId, fish.Id)
    lu.assertAlmostEquals(lock.yaw, 0, 1e-9)
    lu.assertEquals(lock.range, gar().BiteRange)
    lu.assertAlmostEquals(lock.duration, cd, 1e-9)
    -- 预警中绕到身后（仍在咬距内）：鱼不跟着转头
    self.player.Character.Position = vec(p.x, 2, p.z - 2)
    self.now = cd / 2
    self.mgr:Update()
    lu.assertAlmostEquals(fish.Facing.z, 1, 1e-9)
    self.now = cd
    self.mgr:Update()
    lu.assertEquals(damages, {})
    lu.assertEquals(lastNotice(self, 'clear').reason, 'miss')
    -- 咬空后按冷却重新对准身后的目标，不立刻补咬
    lu.assertAlmostEquals(fish.Facing.z, -1, 1e-9)
    self.now = cd + 0.1
    self.mgr:Update()
    lu.assertEquals(damages, {})
    self.now = cd * 2
    self.mgr:Update()
    lu.assertEquals(damages, { 30 })
    lu.assertEquals(lastNotice(self, 'clear').reason, 'bite')
end

function TestGarCombat:test_side_step_during_windup_counts_as_rear()
    local fish, p, damages = dropNear(self, 0, 2)
    self.mgr:Update()
    self.player.Character.Position = vec(p.x + 2, 2, p.z)
    self.now = gar().BiteCooldownSec
    self.mgr:Update()
    lu.assertEquals(damages, {})
    lu.assertNotNil(fish.BiteAim) -- 仍在咬距内：重新起咬
end

function TestGarCombat:test_target_downed_or_leaving_during_windup_cancels_bite()
    local fish, p, damages = dropNear(self, 0, 2)
    armPlayer(self.other, 300)
    self.other.Character.Position = vec(p.x + 40, 2, p.z)
    self.mgr:Update()
    self.downed[self.player] = true
    self.now = 0.5
    self.mgr:Update()
    lu.assertEquals(lastNotice(self, 'clear').reason, 'cancel')
    -- 取消后改追另一名合法玩家，不原地发呆
    lu.assertTrue(fish.Carrier.Body.LinearVelocity.x > 0)
    lu.assertNil(fish.BiteAim)
    self.now = gar().BiteCooldownSec
    self.mgr:Update()
    lu.assertEquals(damages, {})
    lu.assertEquals(#self.vitalsCalls, 0)
end

function TestGarCombat:test_fish_removed_or_fleeing_during_windup_never_bites()
    local fish, _, damages = dropNear(self, 0, 2)
    self.mgr:Update()
    lu.assertNotNil(self.mgr:TakeKilled(fish)) -- 被打死走统一 Remove
    lu.assertEquals(lastNotice(self, 'clear').reason, 'gone')
    self.now = gar().BiteCooldownSec
    self.mgr:Update()
    lu.assertEquals(damages, {})
    -- 逃跑时限在预警中到期：转逃脱并收起预警
    self.notices = {}
    local fish2 = self:heldFish(self.player, 'alligatorGar')
    self.mgr:Drop(self.player)
    local p2 = fish2.Carrier.Body.Position
    self.player.Character.Position = vec(p2.x, 2, p2.z + 2)
    self.now = fish2.FleeAt - 0.5
    self.mgr:Update()
    lu.assertNotNil(fish2.BiteAim)
    self.now = fish2.FleeAt
    self.mgr:Update()
    lu.assertEquals(fish2.State, 'escaping')
    lu.assertNil(fish2.BiteAim)
    lu.assertEquals(lastNotice(self, 'clear').reason, 'gone')
    lu.assertEquals(damages, {})
end

function TestGarCombat:test_body_rotation_follows_chase_and_locked_facing()
    local yaws = {}
    _G.Quaternion = { FromEulerAngles = function(x, y, z)
        yaws[#yaws + 1] = y
        return { x = x, y = y, z = z }
    end }
    local fish, p = dropNear(self, 10, 0)
    self.mgr:Update()
    local body = fish.Carrier.Body
    lu.assertAlmostEquals(body.Rotation.y, math.pi / 2 + gar().ModelYawOffset, 1e-9) -- 朝 +x 追
    self.player.Character.Position = vec(p.x, 2, p.z + 2)
    self.mgr:Update()
    lu.assertAlmostEquals(body.Rotation.y, gar().ModelYawOffset, 1e-9) -- 锁定朝 +z
    lu.assertTrue(#yaws >= 2)
end

function TestGarCombat:test_missing_quaternion_or_failed_publish_does_not_break_bite()
    _G.Quaternion = nil
    local _, _, damages = dropNear(self, 0, 2)
    self.mgr.PublishBite = function() error('re-down') end
    self.mgr:Update()
    self.now = gar().BiteCooldownSec
    self.mgr:Update()
    lu.assertEquals(damages, { 30 })
end

function TestGarCombat:test_notice_protocol_validation()
    local N = require('common.GarBiteNotice')
    local lock = N.Lock(3, vec(1, 2, 3), 1, 0, 2.5, 90, 1.5)
    lu.assertTrue(N.Valid(lock))
    lu.assertAlmostEquals(lock.yaw, math.pi / 2, 1e-9)
    lu.assertTrue(N.Valid(N.Clear(3, 'miss')))
    lu.assertFalse(N.Valid(nil))
    lu.assertFalse(N.Valid({ kind = 'lock', fishId = 3 }))
    lu.assertFalse(N.Valid(N.Lock(3, vec(0 / 0, 0, 0), 1, 0, 2.5, 90, 1.5)))
    lu.assertFalse(N.Valid(N.Lock(3, vec(0, 0, 0), 1, 0, 0, 90, 1.5)))
    lu.assertFalse(N.Valid({ kind = 'boom', fishId = 3 }))
end

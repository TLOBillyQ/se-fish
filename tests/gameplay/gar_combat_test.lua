-- #88 鳄雀鳝首领战（占位）：上岸放下后主动追咬最近的活着的玩家，600HP / 攻 30 / 逃跑时限 300 秒，
-- 头伤 / 身后弱点判定后补（任务说明：占位即可）。
-- 失败方式（先列后写）：
--   1. 放下后不进入战斗（当普通鱼逃了），或不动 / 不追最近的玩家；
--   2. 追错了：追死玩家、追更远的玩家；追咬速度不取鱼种 Speed；
--   3. 咬不合约：超出咬距也咬、没有冷却连咬、伤害不取鱼种 Attack；
--   4. 逃跑时限耗尽不走精英直线逃脱；
--   5. 首领战走了电鳗的技能装配 / 睡眠路径，或反过来电鳗被追咬路径截胡。
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
function TestGarCombat:setUp()
    baseSetUp(self)
    armVitals(self)
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

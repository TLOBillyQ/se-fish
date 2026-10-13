-- #84 迁移：鳄雀鳝首领战与头部攻击绕后（原 tests/gameplay/gar_combat_test.lua，13 例）。
-- 接缝：MgrFishUnit 的战斗状态机——放下进入 combat、追最近的活人、咬合约（咬距/冷却/鱼种攻击）、
-- 预警锁定朝向、目标失效即取消、逃跑时限转直线逃脱、预警协议校验。
-- 沿用 tests/support/fish_combat 共享夹具（含 Quaternion / math.random 的保存与还原）。
-- describe/it 名称保留旧类名与方法名，并按方法名字典序注册以保持旧套件执行顺序。
local FishCombat = require('tests.support.fish_combat')
local GameCfg = require('common.GameCfg')

local function vec(x, y, z) return { x = x, y = y, z = z } end

local function armPlayer(player, health)
    local damages = {}
    player.Character.Controller.Health = health
    player.Character.Controller.TakeDamage = function(_, d) damages[#damages + 1] = d end
    return damages
end

local function gar() return GameCfg.FishCombat.gar end

local function lastNotice(env, kind)
    for i = #env.notices, 1, -1 do
        if env.notices[i].kind == kind then return env.notices[i] end
    end
end

-- 放下后把玩家摆到鱼身 (dx,dz) 处；返回鱼、鱼身位置、伤害记录
local function dropNear(env, dx, dz)
    env:prepare()
    local damages = armPlayer(env.player, 300)
    local fish = env:heldFish(env.player, 'alligatorGar')
    env.mgr:Drop(env.player)
    local p = fish.Carrier.Body.Position
    env.player.Character.Position = vec(p.x + dx, 2, p.z + dz)
    return fish, p, damages
end

describe('TestGarCombat', function()
    local env

    before_each(function()
        env = FishCombat.new()
        env:setUp()
    end)
    after_each(function()
        env:tearDown()
    end)

    it('test_bite_is_skipped_when_vitals_entry_is_not_wired', function()
        -- #128 健壮性：Vitals 未接线（如独立测试或接线遗漏）时追咬不得报错，只停住不咬
        env:prepare()
        armPlayer(env.player, 300)
        local fish = env:heldFish(env.player, 'alligatorGar')
        env.mgr:Drop(env.player)
        env.mgr.Vitals = nil
        local body = fish.Carrier.Body
        env.player.Character.Position = vec(body.Position.x, 2, body.Position.z)
        local cd = GameCfg.FishCombat.gar.BiteCooldownSec
        env.now = cd
        env.mgr:Update()
        assert.are.equal(300, env.player.Character.Controller.Health)
    end)

    it('test_bite_only_in_range_with_cooldown_and_species_attack', function()
        env:prepare()
        local damages = armPlayer(env.player, 300)
        local fish = env:heldFish(env.player, 'alligatorGar')
        env.mgr:Drop(env.player)
        local body = fish.Carrier.Body
        -- 站进咬距：首个冷却期是起手预警，不立刻咬
        env.player.Character.Position = vec(body.Position.x, 2, body.Position.z)
        env.mgr:Update()
        assert.same({}, damages)
        assert.near(0, body.LinearVelocity.x, 1e-6)
        assert.near(0, body.LinearVelocity.z, 1e-6)
        local cd = GameCfg.FishCombat.gar.BiteCooldownSec
        env.now = cd
        env.mgr:Update()
        assert.same({ 30 }, damages)
        assert.are.equal(1, #env.vitalsCalls)
        assert.same(fish, env.vitalsCalls[1][1].source)
        assert.are.equal('fishAttack', env.vitalsCalls[1][1].category)
        assert.same(env.player, env.vitalsCalls[1][2])
        env.now = cd + 0.1
        env.mgr:Update()
        assert.same({ 30 }, damages)
        env.now = cd * 2
        env.mgr:Update()
        assert.same({ 30, 30 }, damages)
        -- 走出咬距：不咬，恢复追击
        env.player.Character.Position = vec(body.Position.x + 10, 2, body.Position.z)
        env.now = cd * 3
        env.mgr:Update()
        assert.same({ 30, 30 }, damages)
        assert.is_true(body.LinearVelocity.x > 0)
    end)

    it('test_body_rotation_follows_chase_and_locked_facing', function()
        local yaws = {}
        _G.Quaternion = { FromEulerAngles = function(x, y, z)
            yaws[#yaws + 1] = y
            return { x = x, y = y, z = z }
        end }
        local fish, p = dropNear(env, 10, 0)
        env.mgr:Update()
        local body = fish.Carrier.Body
        assert.near(math.pi / 2 + gar().ModelYawOffset, body.Rotation.y, 1e-9) -- 朝 +x 追
        env.player.Character.Position = vec(p.x, 2, p.z + 2)
        env.mgr:Update()
        assert.near(gar().ModelYawOffset, body.Rotation.y, 1e-9) -- 锁定朝 +z
        assert.is_true(#yaws >= 2)
    end)

    it('test_drop_enters_combat_and_chases_nearest_living_player', function()
        env:prepare()
        armPlayer(env.player, 300)
        armPlayer(env.other, 300)
        local equipped = 0
        env.mgr.Ability = { EquipFish = function() equipped = equipped + 1 end }
        local fish = env:heldFish(env.player, 'alligatorGar')
        env.mgr:Drop(env.player)
        assert.are.equal('combat', fish.State)
        assert.is_not.is_nil(fish.FleeAt)
        -- 放下后玩家走开：鱼追最近的 env.player（+z 方向），速度取鱼种 Speed=6；不走技能装配
        env.player.Character.Position = vec(10, 2, 0)
        env.mgr:Update()
        local v = fish.Carrier.Body.LinearVelocity
        assert.near(0, v.x, 1e-6)
        assert.near(6, v.z, 1e-6)
        assert.are.equal(0, equipped)
        -- env.player 倒下后改追 env.other（-x 方向）
        env.player.Character.Controller.Health = 0
        env.mgr:Update()
        v = fish.Carrier.Body.LinearVelocity
        assert.is_true(v.x > 0)
        assert.near(6, math.sqrt(v.x * v.x + v.z * v.z), 1e-6)
    end)

    it('test_fish_removed_or_fleeing_during_windup_never_bites', function()
        local fish, _, damages = dropNear(env, 0, 2)
        env.mgr:Update()
        assert.is_not.is_nil(env.mgr:TakeKilled(fish)) -- 被打死走统一 Remove
        assert.are.equal('gone', lastNotice(env, 'clear').reason)
        env.now = gar().BiteCooldownSec
        env.mgr:Update()
        assert.same({}, damages)
        -- 逃跑时限在预警中到期：转逃脱并收起预警
        env.notices = {}
        local fish2 = env:heldFish(env.player, 'alligatorGar')
        env.mgr:Drop(env.player)
        local p2 = fish2.Carrier.Body.Position
        env.player.Character.Position = vec(p2.x, 2, p2.z + 2)
        env.now = fish2.FleeAt - 0.5
        env.mgr:Update()
        assert.is_not.is_nil(fish2.BiteAim)
        env.now = fish2.FleeAt
        env.mgr:Update()
        assert.are.equal('escaping', fish2.State)
        assert.is_nil(fish2.BiteAim)
        assert.are.equal('gone', lastNotice(env, 'clear').reason)
        assert.same({}, damages)
    end)

    it('test_flee_deadline_switches_to_straight_escape', function()
        env:prepare()
        armPlayer(env.player, 300)
        local fish = env:heldFish(env.player, 'alligatorGar')
        env.mgr:Drop(env.player)
        env.player.Character.Position = vec(10, 2, 0)
        env.now = 299
        env.mgr:Update()
        assert.are.equal('combat', fish.State)
        env.now = 300
        env.mgr:Update()
        assert.are.equal('escaping', fish.State)
        assert.is_true(fish.StraightEscape)
        -- 直线逃脱朝最近的拼接水区 PondSouth_7_1（中心 11.5,-26.5），从 (10,-18) 朝南。
        assert.is_true(fish.Carrier.Body.LinearVelocity.z < 0)
    end)

    it('test_head_zone_geometry_and_range_boundary', function()
        local params = gar()
        local pos, facing = vec(0, 0, 0), { x = 0, z = 1 }
        local head = env.mgr.InHeadZone
        assert.is_true(head(pos, facing, vec(0, 0, params.BiteRange), params))        -- 正前方恰好咬距
        assert.is_false(head(pos, facing, vec(0, 0, params.BiteRange + 0.01), params)) -- 超出一点
        assert.is_true(head(pos, facing, vec(1, 0, 0.2), params))                     -- 斜前方
        assert.is_false(head(pos, facing, vec(1, 0, 0), params))                      -- 正侧面算后身
        assert.is_false(head(pos, facing, vec(0, 0, -1), params))                     -- 身后
        assert.is_false(head(pos, facing, vec(-0.5, 0, -2), params))                  -- 后身斜后
        assert.is_true(head(pos, facing, vec(0, 0, 0), params))                       -- 与中点重合无方向，按贴脸算
    end)

    it('test_missing_quaternion_or_failed_publish_does_not_break_bite', function()
        _G.Quaternion = nil
        local _, _, damages = dropNear(env, 0, 2)
        env.mgr.PublishBite = function() error('re-down') end
        env.mgr:Update()
        env.now = gar().BiteCooldownSec
        env.mgr:Update()
        assert.same({ 30 }, damages)
    end)

    it('test_notice_protocol_validation', function()
        local N = require('common.GarBiteNotice')
        local lock = N.Lock(3, vec(1, 2, 3), 1, 0, 2.5, 90, 1.5)
        assert.is_true(N.Valid(lock))
        assert.near(math.pi / 2, lock.yaw, 1e-9)
        assert.is_true(N.Valid(N.Clear(3, 'miss')))
        assert.is_false(N.Valid(nil))
        assert.is_false(N.Valid({ kind = 'lock', fishId = 3 }))
        assert.is_false(N.Valid(N.Lock(3, vec(0 / 0, 0, 0), 1, 0, 2.5, 90, 1.5)))
        assert.is_false(N.Valid(N.Lock(3, vec(0, 0, 0), 1, 0, 0, 90, 1.5)))
        assert.is_false(N.Valid({ kind = 'boom', fishId = 3 }))
    end)

    it('test_side_step_during_windup_counts_as_rear', function()
        local fish, p, damages = dropNear(env, 0, 2)
        env.mgr:Update()
        env.player.Character.Position = vec(p.x + 2, 2, p.z)
        env.now = gar().BiteCooldownSec
        env.mgr:Update()
        assert.same({}, damages)
        assert.is_not.is_nil(fish.BiteAim) -- 仍在咬距内：重新起咬
    end)

    it('test_target_downed_or_leaving_during_windup_cancels_bite', function()
        local fish, p, damages = dropNear(env, 0, 2)
        armPlayer(env.other, 300)
        env.other.Character.Position = vec(p.x + 40, 2, p.z)
        env.mgr:Update()
        env.downed[env.player] = true
        env.now = 0.5
        env.mgr:Update()
        assert.are.equal('cancel', lastNotice(env, 'clear').reason)
        -- 取消后改追另一名合法玩家，不原地发呆
        assert.is_true(fish.Carrier.Body.LinearVelocity.x > 0)
        assert.is_nil(fish.BiteAim)
        env.now = gar().BiteCooldownSec
        env.mgr:Update()
        assert.same({}, damages)
        assert.are.equal(0, #env.vitalsCalls)
    end)

    it('test_threat_target_and_override_reselect_legal_targets', function()
        env:prepare()
        armPlayer(env.player, 300)
        armPlayer(env.other, 300)
        local fish = env:heldFish(env.player, 'alligatorGar')
        env.mgr:Drop(env.player)
        local body = fish.Carrier.Body
        env.mgr:NoteDamage(fish, env.player, 30)
        env.mgr:NoteDamage(fish, env.other, 10)
        -- other 更近，但累计有效伤害更高的 player 优先
        env.other.Character.Position = vec(body.Position.x, 2, body.Position.z + 10)
        env.player.Character.Position = vec(body.Position.x + 10, 2, body.Position.z)
        env.mgr:Update()
        assert.is_true(body.LinearVelocity.x > 0)
        -- 特殊招式目标优先于仇恨
        env.mgr:SetTargetOverride(fish, env.other)
        env.mgr:Update()
        assert.is_true(body.LinearVelocity.z > 0)
        -- 指定目标失效即清理，回到最高仇恨；最高仇恨失效后重选合法目标
        env.downed[env.other] = true
        env.mgr:Update()
        assert.is_true(body.LinearVelocity.x > 0)
        assert.is_nil(fish.TargetOverride)
        env.downed[env.player] = true
        env.downed[env.other] = false
        env.mgr:Update()
        assert.is_true(body.LinearVelocity.z > 0)
        assert.is_nil(fish.Threat[env.player])
    end)

    it('test_windup_locks_facing_so_circling_behind_misses_then_reaims', function()
        local fish, p, damages = dropNear(env, 0, 2)
        local cd = gar().BiteCooldownSec
        env.mgr:Update()
        assert.is_not.is_nil(fish.BiteAim)
        assert.near(1, fish.Facing.z, 1e-9)
        local lock = lastNotice(env, 'lock')
        assert.are.equal(fish.Id, lock.fishId)
        assert.near(0, lock.yaw, 1e-9)
        assert.are.equal(gar().BiteRange, lock.range)
        assert.near(cd, lock.duration, 1e-9)
        -- 预警中绕到身后（仍在咬距内）：鱼不跟着转头
        env.player.Character.Position = vec(p.x, 2, p.z - 2)
        env.now = cd / 2
        env.mgr:Update()
        assert.near(1, fish.Facing.z, 1e-9)
        env.now = cd
        env.mgr:Update()
        assert.same({}, damages)
        assert.are.equal('miss', lastNotice(env, 'clear').reason)
        -- 咬空后按冷却重新对准身后的目标，不立刻补咬
        assert.near(-1, fish.Facing.z, 1e-9)
        env.now = cd + 0.1
        env.mgr:Update()
        assert.same({}, damages)
        env.now = cd * 2
        env.mgr:Update()
        assert.same({ 30 }, damages)
        assert.are.equal('bite', lastNotice(env, 'clear').reason)
    end)
end)

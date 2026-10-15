-- #90 迁移：武器系统（原 tests/gameplay/weapon_system_test.lua，9 类 40 例）。
-- describe / it 名沿用旧类名与方法名；注册顺序 = 旧套件实际执行顺序
-- （LuaUnit 按 `类名.方法名` 字节字典序收集全局类与方法，故
--  TestAbilitySwingRegistry → TestMainWeaponWiring → TestMgrFishUnitBlastFish → TestMgrWeapon →
--  TestMgrWeaponThrow → TestMgrWeaponUpgrade → TestPressGesture → TestWeaponConfig → TestWeaponPersistence）。
-- #129 失败方式先列：见 .scratch/129/progress.md。
-- 验收锁定：数值与商店表/票面一致（空手 5/0.5/2，不再 25）；挥砍登记驱动命中盒与伤害；
-- 服务端射速/弹量/换弹（2 秒）权威，切枪与重连不绕过；霰弹 5×20、火箭筒 500+5 米 100；
-- 投掷一发一件走 #123 协议（重放不重复扣）、20 米钳制、落水 3–5 条当地 1 级普通鱼后算伤害、
-- 5 米爆炸、普通投掷召唤不出首领；装备/选中重进恢复、弹匣按满匣恢复。
--
-- vendor 接缝处理（迁移期必修）：旧 TestAbilitySwingRegistry.setUp 给
-- server.packages.ability_system.api 装的 preload 桩只有 CastAbility 一个函数，
-- 而 common/AbilityAPIBase.build 按 SERVER_API 全名单校验、缺名即 error。旧套件能跑通
-- 完全依赖别处先把「真包模块」灌进 package.loaded，让那个 preload 永不被调用；
-- 旧 ability_seams 被迁走后这条残留断了，本文件 4 个案例直接报错（AddAbility 缺失）。
-- 现改用 tests/support/ability_package_stub.lua 按名单建齐桩，并在 after_each 把 preload
-- 与两份模块缓存放回快照，因此不再依赖任何别处的残留（详见 issue-90-mapping.md）。
local lu_stub = require('tests.support.ability_package_stub')
local Weapon = require('tests.support.weapon_world')
local GameCfg = require('common.GameCfg')
local PlayerData = require('server.Data.PlayerData')
local VENDOR = 'server.packages.ability_system.api'

-- ===== 挥砍登记（AbilityAPI） =====
describe('TestAbilitySwingRegistry', function()
    local ctx
    local saved
    before_each(function()
        saved = { game = rawget(_G, 'game'), preload = package.preload[VENDOR],
            vendor = package.loaded[VENDOR], api = package.loaded['server.AbilityAPI'] }
        package.preload[VENDOR] = function() return lu_stub.packageApi({ CastAbility = function() return true end }) end
        package.loaded[VENDOR] = nil
        ctx = { now = 1000 }
        _G.game = { GetService = function(_, name)
            if name == 'World' then return { GetServerTime = function() return ctx.now end } end
            return nil
        end }
        ctx.api = assert(loadfile('server/AbilityAPI.lua'))()
    end)
    after_each(function()
        _G.game = saved.game
        package.preload[VENDOR] = saved.preload
        package.loaded[VENDOR] = saved.vendor
        package.loaded['server.AbilityAPI'] = saved.api
    end)

    it('test_add_cast_guard_chains_after_base_guard', function()
        local baseCalls, extraCalls = 0, 0
        ctx.api.SetCastGuard(function() baseCalls = baseCalls + 1 return true end)
        ctx.api.AddCastGuard(function(unit, index)
            extraCalls = extraCalls + 1
            return index ~= 2 -- 近战槽无登记时拒绝
        end)
        assert.is_true(ctx.api.CastAbility({}, 0))  -- 非近战槽不受追加守卫影响
        assert.is_false(ctx.api.CastAbility({}, 2)) -- 追加守卫拒绝
        assert.same({ 2, 2 }, { baseCalls, extraCalls })
    end)

    it('test_expired_or_future_swing_rejected', function()
        ctx.api.StageSwing(7, { damage = 5, range = 2 })  -- at=1000
        ctx.now = 1000 + 1.6                              -- TTL 1.5 秒
        assert.is_nil(ctx.api.PeekSwing(7))
        assert.is_nil(ctx.api.TakeSwing(7))
        ctx.now = 1000
        ctx.api.StageSwing(8, { damage = 5, range = 2 })
        ctx.now = 500                                     -- 登记在未来（时钟回拨）视为过期
        assert.is_nil(ctx.api.TakeSwing(8))
    end)

    it('test_stage_take_once_and_overwrite', function()
        assert.is_true(ctx.api.StageSwing(7, { damage = 5, range = 2 }))
        assert.same(5, ctx.api.PeekSwing(7).damage)
        assert.same({ damage = 5, range = 2, at = 1000 }, ctx.api.TakeSwing(7))
        assert.is_nil(ctx.api.TakeSwing(7))
        -- 重复登记覆盖旧的（换武器不串档）
        ctx.api.StageSwing(7, { damage = 40, range = 4 })
        ctx.api.StageSwing(7, { damage = 10, range = 2 })
        assert.same(10, ctx.api.TakeSwing(7).damage)
    end)
end)

-- ===== main.lua 接线守卫 =====
describe('TestMainWeaponWiring', function()
    local function readSource(path)
        local parts = {}
        for line in io.lines(path) do parts[#parts + 1] = line end
        return table.concat(parts, '\n')
    end

    it('test_main_registers_and_wires_mgr_weapon', function()
        local src = readSource('server/main.lua')
        assert.matches('MgrWeapon = require("server.Mgr.MgrWeapon")', src, nil, true)
        assert.matches('MgrMap.MgrWeapon.Vitals = MgrMap.MgrVitals', src, nil, true)
        assert.matches('MgrMap.MgrWeapon.PlayerData = MgrMap.MgrPlayerData', src, nil, true)
        assert.matches('MgrMap.MgrWeapon.FishUnit = MgrMap.MgrFishUnit', src, nil, true)
    end)
end)

-- ===== 爆炸保底鱼（MgrFishUnit Wild 状态） =====
describe('TestMgrFishUnitBlastFish', function()
    local ctx
    local saved
    before_each(function()
        saved = { game = rawget(_G, 'game'), carrier = package.loaded['server.Mgr.MgrFishCarrier'] }
        ctx = { now = 3000, despawned = {}, spawnOpts = {} }
        package.loaded['server.Mgr.MgrFishCarrier'] = {
            Spawn = function(_, opts)
                ctx.spawnOpts[#ctx.spawnOpts + 1] = opts
                return { Body = { Position = opts.Position }, Receiver = { Controller = {} } }, nil
            end,
            Despawn = function(_, carrier) ctx.despawned[#ctx.despawned + 1] = carrier end,
            Attach = function() end,
        }
        _G.game = { GetService = function(_, name)
            if name == 'World' then return { GetServerTime = function() return ctx.now end } end
            if name == 'Players' then return { GetPlayers = function() return {} end } end
            return nil
        end }
        ctx.mgr = assert(loadfile('server/Mgr/MgrFishUnit.lua'))()
        ctx.owner = { UserId = 55 }
    end)
    after_each(function()
        _G.game = saved.game
        package.loaded['server.Mgr.MgrFishCarrier'] = saved.carrier
    end)

    it('test_spawn_wild_fish_with_ttl_and_owner', function()
        local fish = ctx.mgr:SpawnBlastFish('tilapia', 1, { x = 1, y = 2, z = 3 }, ctx.owner)
        assert.is_not_nil(fish)
        assert.same(ctx.mgr.State.Wild, fish.State)
        assert.same(ctx.owner, fish.Owner)
        assert.same(3000 + GameCfg.Ability.Throw.FishTtlSec, fish.WildUntil)
        assert.same(fish, ctx.mgr.Fish[fish.Id])
        assert.same('tilapia', ctx.spawnOpts[1].FishId)
        assert.same({ x = 1, y = 2, z = 3 }, ctx.spawnOpts[1].Position)
        assert.same(GameCfg.Fish.tilapia.Health, ctx.spawnOpts[1].MaxHealth)
        -- Wild 鱼不接抓举：不会发起 Lift（没有 Conns/RequestLift 副作用）
        assert.is_nil(fish.Conns)
    end)

    it('test_wild_fish_can_be_killed_for_loot', function()
        local fish = ctx.mgr:SpawnBlastFish('bass', 1, { x = 0, y = 2, z = 0 }, ctx.owner)
        local killed = ctx.mgr:TakeKilled(fish)
        assert.same('bass', killed.fishId)
        assert.same(1, killed.mult)
        assert.is_nil(ctx.mgr.Fish[fish.Id]) -- 只会成功一次
        assert.is_nil(ctx.mgr:TakeKilled(fish))
    end)

    it('test_wild_fish_expire_after_ttl', function()
        local fish = ctx.mgr:SpawnBlastFish('carp', 2, { x = 0, y = 2, z = 0 }, ctx.owner)
        ctx.now = 3000 + GameCfg.Ability.Throw.FishTtlSec - 1
        ctx.mgr:Update()
        assert.same(fish, ctx.mgr.Fish[fish.Id]) -- 未到期保留
        ctx.now = 3000 + GameCfg.Ability.Throw.FishTtlSec
        ctx.mgr:Update()
        assert.is_nil(ctx.mgr.Fish[fish.Id])     -- 到期移除
        assert.same(1, #ctx.despawned)
    end)
end)

-- ===== MgrWeapon：空手 / 近战 / 枪械 =====
describe('TestMgrWeapon', function()
    local ctx
    before_each(function()
        ctx = Weapon.new()
        ctx:setUp()
    end)
    after_each(function()
        ctx:tearDown()
    end)

    -- #37 失败方式：客户端俯仰丢失；方向尺度扩大射程；NaN/inf/零向量消耗弹药；
    -- 客户端声称命中绕过墙；正常攻击按钮/武器栏入口未带相机瞄准。
    it('test_attack_payload_aims_up_with_authoritative_origin_and_range', function()
        ctx.data:GrantWeapon('item141', 1); ctx.data:HoldWeapon('item141')
        ctx.mgr:Start()
        ctx.reHandler(ctx.player, { action = 'attack', aim = { x = 0, y = 30, z = 40 } })
        assert.near(GameCfg.Ability.GunShared.Range * 0.6, ctx.lastRay.d.y, 1e-6)
        assert.near(GameCfg.Ability.GunShared.Range * 0.8, ctx.lastRay.d.z, 1e-6)
        assert.same({ x = 0, y = 3, z = 0 }, ctx.lastRay.o)
        -- 首命中墙，客户端的伪造目标不会绕过它；已发一枪仍只扣票面一发。
        ctx.now = ctx.now + 2
        ctx.rayHit = { Instance = {}, Position = { x = 0, y = 4, z = 2 } }
        ctx.reHandler(ctx.player, { action = 'attack', aim = { x = 0, y = 3, z = 4 }, target = ctx.other })
        assert.same(0, #ctx.applied)
        local ammo = ctx.mgr:GetState(ctx.player.UserId).mags.item141.ammo
        for _, bad in ipairs({ false, {}, { x = 0, y = 0, z = 0 }, { x = 0, y = 0 / 0, z = 1 },
            { x = 0, y = math.huge, z = 1 }, { x = '0', y = 1, z = 1 }, { x = 1e308, y = 1, z = 1 } }) do
            ctx.now = ctx.now + 2
            ctx.reHandler(ctx.player, { action = 'attack', aim = bad })
            assert.same('bad-aim', Weapon.lastReply(ctx).reason)
            assert.same(ammo, ctx.mgr:GetState(ctx.player.UserId).mags.item141.ammo)
        end
    end)

    it('test_camera_aim_payload_uses_normalized_viewport_center', function()
        local prior = _G.game
        _G.game = { GetService = function(_, name)
            if name == 'CameraService' then return { ViewportPointToRay = function(_, x, y)
                assert.same({ 0.5, 0.5 }, { x, y })
                return { Direction = { x = 0, y = 0.6, z = 0.8 } }
            end } end
        end }
        local ok, payload = pcall(function() return require('client.WeaponAim'):AttackPayload() end)
        _G.game = prior
        assert.is_true(ok, tostring(payload))
        assert.same({ action = 'attack', aim = { x = 0, y = 0.6, z = 0.8 } }, payload)
    end)

    it('test_cast_guard_requires_staged_swing_for_melee_only', function()
        ctx.mgr:Start() -- 注册 AddCastGuard 与 WeaponAction 通道
        assert.is_not_nil(ctx.castGuard)
        ctx.swingStaged[42] = { damage = 5, range = 2 }
        assert.is_true(ctx.castGuard(ctx.player.Character, 1))  -- 已登记放行
        ctx.swingStaged[42] = nil
        assert.is_false(ctx.castGuard(ctx.player.Character, 1)) -- 近战槽无登记拒绝
        assert.is_true(ctx.castGuard(ctx.player.Character, 0))  -- 其它槽位不受影响
        assert.is_true(ctx.castGuard({ UnitId = 5 }, 1))        -- 非玩家单位（鱼施法）不受影响
    end)

    it('test_fire_rate_enforced_server_side', function()
        ctx.data:GrantWeapon('item139', 1) -- 冲锋枪 0.15s
        ctx.data:HoldWeapon('item139')
        ctx.now = 1000
        assert.is_true(ctx.mgr:Attack(ctx.player).ok)
        ctx.now = 1000.1 -- 客户端加速：0.1 < 0.15 拒绝
        assert.same('cooldown', ctx.mgr:Attack(ctx.player).reason)
        ctx.now = 1000.16 -- 0.16 ≥ 0.15 放行（0.15 恰为浮点边界，避开）
        assert.is_true(ctx.mgr:Attack(ctx.player).ok)
    end)

    it('test_gun_magazine_empties_then_auto_reload_two_seconds', function()
        ctx.data:GrantWeapon('item137', 1) -- 手枪 10 发
        ctx.data:HoldWeapon('item137')
        for i = 1, 10 do
            ctx.now = 1000 + i -- 间隔 1 秒，打光 10 发
            assert.is_true(ctx.mgr:Attack(ctx.player).ok)
        end
        assert.same(0, Weapon.lastReply(ctx).ammo)
        ctx.now = 1011
        local reply = ctx.mgr:Attack(ctx.player)
        assert.is_false(reply.ok)
        assert.same('empty', reply.reason)
        assert.is_true(reply.autoReload)
        assert.is_true(ctx.mgr:GetState(42).mags.item137.reloadUntil > 1011)
        -- 换弹中发射被拒
        assert.same('reloading', ctx.mgr:Attack(ctx.player).reason)
        -- 手动换弹不重置/不叠加
        assert.same('reloading', ctx.mgr:Reload(ctx.player).reason)
        -- 2 秒到期惰性补满；备弹无限（再打 10 发仍合法）
        ctx.now = 1013.01
        assert.is_true(ctx.mgr:Attack(ctx.player).ok)
        assert.same(9, Weapon.lastReply(ctx).ammo)
        assert.is_true(ctx.mgr:GetState(42).mags.item137.ammo >= 0)
    end)

    it('test_gun_ray_miss_applies_nothing', function()
        ctx.data:GrantWeapon('item137', 1)
        ctx.data:HoldWeapon('item137')
        ctx.rayHit = nil -- 未命中任何物体
        assert.is_true(ctx.mgr:Attack(ctx.player).ok)
        assert.same(0, #ctx.applied)
        ctx.rayHit = { Instance = { UnitId = 999, UnitType = 'WorldUnit', PhysicsActive = true },
            Position = { x = 0, y = 2, z = 3 } } -- 墙：不解析出玩家/鱼
        ctx.now = 1001 -- 过射速间隔再打一发
        assert.is_true(ctx.mgr:Attack(ctx.player).ok)
        assert.same(0, #ctx.applied)
    end)

    it('test_manual_reload_two_seconds_not_bypassed_by_switching', function()
        ctx.data:GrantWeapon('item137', 1)
        ctx.data:GrantWeapon('item141', 1) -- 狙击 5 发
        ctx.data:HoldWeapon('item137')
        ctx.now = 1000
        ctx.mgr:Attack(ctx.player)
        assert.is_true(ctx.mgr:Reload(ctx.player).ok)
        assert.same('reloading', ctx.mgr:Reload(ctx.player).reason)
        -- 切到狙击打一发再切回：手枪仍在换弹
        ctx.data:HoldWeapon('item141')
        ctx.now = 1001
        assert.is_true(ctx.mgr:Attack(ctx.player).ok)
        ctx.data:HoldWeapon('item137')
        assert.same('reloading', ctx.mgr:Attack(ctx.player).reason)
        ctx.now = 1002.01 -- 手枪 2 秒换弹完成
        assert.is_true(ctx.mgr:Attack(ctx.player).ok)
        assert.same(9, Weapon.lastReply(ctx).ammo)
    end)

    it('test_melee_interval_enforced_per_weapon_and_switching', function()
        ctx.data:GrantWeapon('item136', 1) -- 斧头 40 / 1.0s / 4m
        ctx.data:GrantWeapon('item135', 1) -- 匕首 15 / 0.5s / 3m
        ctx.data:HoldWeapon('item136')
        ctx.mgr:Attack(ctx.player)
        assert.same(40, ctx.swingStaged[42].damage)
        ctx.mgr:Attack(ctx.player) -- 间隔内连点：拒绝且不重复登记/施法
        assert.same('cooldown', Weapon.lastReply(ctx).reason)
        assert.same(1, #ctx.casts)
        ctx.now = 1000.5
        ctx.data:HoldWeapon('item135') -- 切武器不绕冷却：匕首自己的时间线
        ctx.mgr:Attack(ctx.player)
        assert.same(15, ctx.swingStaged[42].damage)
        assert.same(2, #ctx.casts)
        ctx.data:HoldWeapon('item136') -- 换回斧头：仍在 1 秒冷却内
        ctx.mgr:Attack(ctx.player)
        assert.same('cooldown', Weapon.lastReply(ctx).reason)
        ctx.now = 1001.01
        ctx.mgr:Attack(ctx.player)
        assert.same(3, #ctx.casts)
    end)

    it('test_rocket_direct_500_and_splash_5m_excludes_shooter', function()
        ctx.data:GrantWeapon('item142', 1)
        ctx.data:HoldWeapon('item142')
        ctx.other.Character.Position = { x = 0, y = 2, z = 4 }   -- 落点 5 米内
        ctx.rayHit = { Instance = ctx.other.Character, Position = { x = 0, y = 2, z = 4 } }
        ctx.mgr:Attack(ctx.player)
        local direct, splash = 0, {}
        for _, a in ipairs(ctx.applied) do
            if a.amount == 500 then direct = direct + 1 else splash[#splash + 1] = a end
        end
        assert.same(1, direct) -- 直伤一次
        -- 直伤目标被溅射跳过（不双算），投掷者不炸自己
        for _, a in ipairs(splash) do
            assert.same(100, a.amount)
            assert.is_not.same(ctx.other, a.target)
            assert.is_not.same(ctx.player, a.target)
        end
        assert.same(0, Weapon.lastReply(ctx).ammo) -- 1 发弹匣
    end)

    it('test_shotgun_five_pellets_one_shell', function()
        ctx.data:GrantWeapon('item138', 1) -- 霰弹 2 发 × 5×20
        ctx.data:HoldWeapon('item138')
        ctx.rayHit = { Instance = ctx.other.Character, Position = { x = 0, y = 2, z = 5 } }
        ctx.mgr:Attack(ctx.player)
        assert.same(5, #ctx.applied)
        for _, a in ipairs(ctx.applied) do assert.same(20, a.amount) end
        assert.same(ctx.other, ctx.applied[1].target)
        assert.same(1, Weapon.lastReply(ctx).ammo) -- 一发一壳
    end)

    it('test_unarmed_attack_stages_cfg_swing_and_casts_melee', function()
        ctx.mgr:Attack(ctx.player)
        assert.same({ damage = 5, range = 2 }, ctx.swingStaged[42])
        assert.same(1, #ctx.casts)
        assert.same(1, ctx.casts[1].index) -- GameCfg 挥砍槽位
        assert.same(ctx.player.Character, ctx.casts[1].unit)
        assert.is_true(Weapon.lastReply(ctx).ok)
    end)
end)

-- ===== 投掷 / 爆炸 =====
describe('TestMgrWeaponThrow', function()
    local ctx
    local saved
    local function throwPlayer(id)
        return { UserId = id, Character = { Position = { x = 0, y = 2, z = 0 },
            Rotation = { GetForward = function() return { x = 0, y = 0, z = 1 } end } } }
    end
    before_each(function()
        saved = { game = rawget(_G, 'game'), re = rawget(_G, 'REUtil'),
            api = package.loaded['server.AbilityAPI'] }
        ctx = { now = 2000, replies = {}, applied = {}, spawnedFish = {}, order = 0, launches = {} }
        ctx.player = throwPlayer(77)
        ctx.other = throwPlayer(78)
        package.loaded['server.AbilityAPI'] = { StageSwing = function() end,
            PeekSwing = function() return nil end, TakeSwing = function() return nil end,
            CastAbility = function() return true end, AddCastGuard = function() end }
        _G.REUtil = { GetRE = function(_, name)
            return { OnServerEvent = { Connect = function() end },
                FireClient = function(_, player, payload)
                    ctx.replies[#ctx.replies + 1] = payload end }
            end, CheckRECD = function() return nil end }
        _G.game = { GetService = function(_, name)
            if name == 'World' then return { GetServerTime = function() return ctx.now end,
                CreateUnit = function() return { Destroy = function() end, Position = { x = 0, y = 0, z = 0 } } end } end
            if name == 'Players' then return { GetPlayers = function() return { ctx.player, ctx.other } end,
                GetPlayerFromCharacter = function() return nil end } end
            return nil
        end }
        ctx.mgr = assert(loadfile('server/Mgr/MgrWeapon.lua'))()
        ctx.data = PlayerData.New({ UserId = 77, SetAttribute = function() end })
        ctx.data:Init()
        ctx.mgr.PlayerData = { GetDataInst = function() return ctx.data end,
            SendItemBar = function() end }
        ctx.mgr.Attr = require('tests.support.attr_runtime').New(ctx.mgr.PlayerData)
        ctx.mgr.Vitals = {
            CanAct = function() return true end,
            NewHit = function(_, source, category)
                ctx.order = ctx.order + 1
                return { id = ctx.order, source = source, category = category } end,
            ApplyHit = function(_, hit, target, amount)
                ctx.order = ctx.order + 1
                ctx.applied[#ctx.applied + 1] = { order = ctx.order, target = target, amount = amount }
                return true, amount end,
        }
        ctx.mgr.FishUnit = { Fish = {}, SpawnBlastFish = function(_, fishId, mult, pos, owner)
            ctx.order = ctx.order + 1
            ctx.spawnedFish[#ctx.spawnedFish + 1] = { order = ctx.order,
                fishId = fishId, mult = mult, pos = pos, owner = owner }
            -- 真实 MgrFishUnit 会把鱼登记进 Fish 表：爆炸结算能看到刚生成的保底鱼
            local id = 1000 + #ctx.spawnedFish
            ctx.mgr.FishUnit.Fish[id] = { Id = id, Carrier = { Body = { Position = pos } } }
            return { Id = id } end }
        ctx.mgr.FishCarrier = { ResolveCarrier = function() return nil end }
        local realLaunch = ctx.mgr.Launch
        ctx.mgr.Launch = function(m, player, itemId, target)
            ctx.launches[#ctx.launches + 1] = { itemId = itemId, target = target }
            return realLaunch(m, player, itemId, target)
        end
    end)
    after_each(function()
        _G.game = saved.game
        _G.REUtil = saved.re
        package.loaded['server.AbilityAPI'] = saved.api
    end)

    local function giveExplosive(data, itemId, count)
        -- AddItem 一次添一件（mult 是倍率元数据，不是数量）；每格一件不堆叠
        for _ = 1, count do assert.is_true(data:AddItem(itemId)) end
    end

    -- 道具栏初始有新手鱼竿占 1 号位（容量 2）：按实际落格找槽位
    local function barSlotOf(data, itemId)
        local snap = data:GetItemBarSnapshot()
        for index, entry in pairs(snap.slots) do
            if entry.itemId == itemId then return index end
        end
        return nil
    end

    it('test_blast_candidates_exclude_boss_elite_rare_and_high_rod', function()
        local pondRows = GameCfg.Casting.Zones.WaterCircle2
        for _, c in ipairs(ctx.mgr:BlastCandidates(pondRows)) do
            assert.same('normal', GameCfg.Fish[c.id].Grade)
        end
        local shrimpRows = GameCfg.Casting.Zones['shrimpPond.water']
        local picked = ctx.mgr:BlastCandidates(shrimpRows)
        for _, c in ipairs(picked) do
            assert.same('normal', GameCfg.Fish[c.id].Grade)
            assert.same(1, GameCfg.Fish[c.id].RodLevel)
        end
        assert.is_false((function()
            for _, c in ipairs(picked) do
                if c.id:match('rare') or c.id:match('Lobster') then return true end
            end
            return false
        end)())
    end)

    it('test_land_detonation_5m_radius_no_fish_skips_thrower', function()
        local landing = { x = 0, y = 2, z = 10 }
        ctx.other.Character.Position = { x = 0, y = 2, z = 14.9 }  -- 4.9 米内
        local far = throwPlayer(79)
        far.Character.Position = { x = 0, y = 2, z = 16.1 }        -- 6.1 米外
        local oldGet = _G.game.GetService
        _G.game.GetService = function(_, name)
            if name == 'Players' then return { GetPlayers = function()
                return { ctx.player, ctx.other, far } end,
                GetPlayerFromCharacter = function() return nil end } end
            return oldGet(_, name)
        end
        ctx.mgr:Detonate(ctx.player, 'item144', landing, nil)
        assert.same(0, #ctx.spawnedFish)
        local hitNear, hitFar, hitSelf = false, false, false
        for _, a in ipairs(ctx.applied) do
            assert.same(100, a.amount)
            if a.target == ctx.other then hitNear = true end
            if a.target == far then hitFar = true end
            if a.target == ctx.player then hitSelf = true end
        end
        assert.is_true(hitNear)
        assert.is_false(hitFar)
        assert.is_false(hitSelf)
    end)

    it('test_projectile_flies_then_detonates_in_water', function()
        giveExplosive(ctx.data, 'item143', 1)
        -- 20 米钳制是票面规则：站近水边投，选点才够得到 WaterCircle2 中心
        ctx.player.Character.Position = { x = -11.75, y = 2, z = -28 }
        local waterLanding = { x = -11.75, y = 2.183, z = -12.25 }
        ctx.mgr.Random = function(a, b) if a and b then return a end return 0.5 end -- 数量 3
        ctx.mgr:Launch(ctx.player, 'item143', waterLanding)
        assert.same(1, #ctx.mgr.Flying)
        ctx.now = 2000 + GameCfg.Ability.Throw.FlightSec + 0.01
        ctx.mgr:Update()
        assert.same(0, #ctx.mgr.Flying)
        assert.same(3, #ctx.spawnedFish) -- 落水保底鱼
        assert.same(1, ctx.data:ItemCount('item143')) -- Launch 不经存档协议，本用例直接发射不扣
    end)

    it('test_target_clamped_to_20m', function()
        local landing, zone = ctx.mgr:ResolveTarget(ctx.player, { x = 0, y = 2, z = 100 })
        assert.is_nil(zone)
        assert.near(20, landing.z, 0.01) -- 直接投掷钳到 20 米
        assert.same(0, landing.x)
    end)

    it('test_throw_consumes_exactly_one_without_save', function()
        giveExplosive(ctx.data, 'item143', 2)
        local slot = barSlotOf(ctx.data, 'item143')
        assert.is_not_nil(slot)
        assert.is_true(ctx.mgr:Handle(ctx.player, { action = 'throw', slot = slot, seq = 1 }))
        assert.same(1, ctx.data:ItemCount('item143'))
        assert.same(1, #ctx.launches)
        assert.same('item143', ctx.launches[1].itemId)
    end)

    it('test_throw_rejects_non_explosive_and_bad_slot', function()
        giveExplosive(ctx.data, 'item143', 1)
        assert.is_true(ctx.mgr:Handle(ctx.player, { action = 'throw', slot = 9, seq = 1 }))
        assert.same('bad-slot', ctx.replies[#ctx.replies].reason)
        -- 非爆炸物用初始道具栏里的新手鱼竿验证（鱼会进背包，占不到道具栏格）
        local rodSlot = barSlotOf(ctx.data, GameCfg.Items.Id.StarterRod)
        assert.is_not_nil(rodSlot)
        assert.is_true(ctx.mgr:Handle(ctx.player, { action = 'throw', slot = rodSlot, seq = 2 }))
        assert.same('bad-throwable', ctx.replies[#ctx.replies].reason)
        assert.same(1, ctx.data:ItemCount('item143'))
    end)

    it('test_throw_replay_does_not_consume_or_launch_again', function()
        -- 模拟 MgrSave 协议：同 requestId 第二次返回 replay，只回历史结果
        local executions = 0
        ctx.mgr.Save = {
            ResolveRequest = function(_, player, data, kind, requestId)
                assert.same('throw', kind)
                if requestId == 7 and ctx.replayed then
                    return { id = '77:1', sequence = 1, kind = 'throw', requestKey = 'k' }, 'replay'
                end
                return { id = '77:1', sequence = 1, kind = 'throw', requestKey = 'k' }, 'new'
            end,
            Execute = function(_, player, data, operation, transform, done)
                if ctx.replayed then
                    done(true, { ok = true, op = 'throw', itemId = 'item143', slot = 1 })
                    return true
                end
                local draft = PlayerData.New({ UserId = 77, SetAttribute = function() end })
                draft:Init(); draft:ApplySave(data:Serialize())
                local result = transform(draft)
                if result then
                    data:ApplySave(draft:Serialize()) -- 模拟真实 Execute 的写回
                    done(true, result)
                else
                    done(false, 'rejected')
                end
                executions = executions + 1
                return true
            end,
        }
        giveExplosive(ctx.data, 'item143', 2)
        local slot = barSlotOf(ctx.data, 'item143')
        ctx.mgr:Handle(ctx.player, { action = 'throw', slot = slot, seq = 7 })
        assert.same(1, ctx.data:ItemCount('item143'))
        assert.same(1, #ctx.launches)
        ctx.replayed = true
        ctx.mgr:Handle(ctx.player, { action = 'throw', slot = slot, seq = 7 }) -- 同 seq 重放
        assert.same(1, ctx.data:ItemCount('item143')) -- 不重复扣
        assert.same(1, #ctx.launches)                -- 不再发射
        assert.same(1, executions)                   -- 新结算只一次
    end)

    it('test_water_detonation_spawns_3_to_5_fish_before_damage', function()
        -- WaterCircle2 中心 (-11.75, 27.75) HalfXZ=6，SurfaceY=2.183
        local zone = { Id = 'WaterCircle2', Center = { x = -11.75, y = 1.05, z = 27.75 },
            HalfXZ = 6.0, SurfaceY = 2.183 }
        local landing = { x = -11.75, y = 2.183, z = 27.75 }
        ctx.mgr.Random = function(a, b)
            if a and b then return b end -- 数量取上限，候选取最后一个（确定性）
            return 0.999
        end
        ctx.mgr:Detonate(ctx.player, 'item143', landing, zone)
        assert.same(GameCfg.Ability.Throw.FishMax, #ctx.spawnedFish)
        assert.is_true(#ctx.spawnedFish >= GameCfg.Ability.Throw.FishMin)
        for _, f in ipairs(ctx.spawnedFish) do
            assert.same(ctx.player, f.owner)
            assert.same(1, f.mult)
            local species = GameCfg.Fish[f.fishId]
            assert.same('normal', species.Grade) -- 普通投掷召唤不出首领/精英/极品
            assert.same(1, species.RodLevel)
            -- 保底鱼在伤害之前生成
            for _, a in ipairs(ctx.applied) do assert.is_true(a.order > f.order) end
        end
        assert.is_true(#ctx.applied > 0) -- 随后按 5 米半径结算爆炸
    end)
end)

-- ===== #130 强化加成消费 =====
-- 失败方式：加成买了不生效/生效错对象（火箭筒溅射双加成、空手被加成）、
-- 弹容没向上取整、按复利算。
describe('TestMgrWeaponUpgrade', function()
    -- 旧文件这里是 `TestMgrWeaponUpgrade.setUp = function(self) TestMgrWeapon.setUp(self) end`，
    -- 直接复用武器世界夹具；Busted 下改为各案例自己 open/close 同一份 support 模块。
    local ctx
    before_each(function()
        ctx = Weapon.new()
        ctx:setUp()
    end)
    after_each(function()
        ctx:tearDown()
    end)

    it('test_explosive_max_level_scales_detonation', function()
        ctx.data.Extra.growth.upgrades.explosive = 3
        local landing = { x = 0, y = 2, z = 10 }
        ctx.other.Character.Position = { x = 0, y = 2, z = 14.9 }
        ctx.mgr:Detonate(ctx.player, 'item144', landing, nil)
        assert.is_true(#ctx.applied >= 1)
        for _, a in ipairs(ctx.applied) do
            assert.near(160, a.amount, 1e-9)
        end
    end)

    -- 弹容满级 +150% 向上取整：狙击 5→13（7.5→8 逐级验证在配置层），第 14 发才空匣
    it('test_magazine_max_level_rounds_up_and_extends_ammo', function()
        ctx.data.Extra.growth.upgrades.magazine = 3
        ctx.data:GrantWeapon('item141', 1) -- 狙击 5 发
        ctx.data:HoldWeapon('item141')
        for i = 1, 13 do
            ctx.now = 1000 + i * 2 -- 间隔 1.5 秒
            assert.is_true(ctx.mgr:Attack(ctx.player).ok)
        end
        assert.same(0, Weapon.lastReply(ctx).ammo)
        ctx.now = 1000 + 14 * 2
        local reply = ctx.mgr:Attack(ctx.player)
        assert.same('empty', reply.reason) -- 第 14 发才触发空匣换弹
        assert.is_true(reply.autoReload)
    end)

    -- 近战满级 +70%：斧头 40→68 登记进挥砍；空手不吃武器加成
    it('test_melee_max_level_scales_staged_swing', function()
        ctx.data.Extra.growth.upgrades.melee = 7
        ctx.data:GrantWeapon('item136', 1)
        ctx.data:HoldWeapon('item136')
        ctx.mgr:Attack(ctx.player)
        assert.near(68, ctx.swingStaged[42].damage, 1e-9)
        assert.same(4, ctx.swingStaged[42].range)
        ctx.data.Extra.inventory.selection.held = { kind = nil, id = nil, slot = nil } -- 回到空手
        ctx.data.Extra.inventory.selection.weapon = nil
        ctx.now = 1002 -- 过冷却
        ctx.mgr:Attack(ctx.player)
        assert.same(5, ctx.swingStaged[42].damage) -- 空手不加成
    end)

    -- 远程满级 +50%：每发弹丸乘算（霰弹 20→30）
    it('test_ranged_max_level_scales_each_pellet', function()
        ctx.data.Extra.growth.upgrades.ranged = 5
        ctx.data:GrantWeapon('item138', 1)
        ctx.data:HoldWeapon('item138')
        ctx.rayHit = { Instance = ctx.other.Character, Position = { x = 0, y = 2, z = 5 } }
        ctx.mgr:Attack(ctx.player)
        assert.same(5, #ctx.applied)
        for _, a in ipairs(ctx.applied) do assert.near(30, a.amount, 1e-9) end
    end)

    -- 火箭筒两段只归远程：直击 500→750；溅射 100→150，且不吃爆炸物加成（不双加成）
    it('test_rocket_two_stages_only_ranged_no_double_bonus', function()
        ctx.data.Extra.growth.upgrades.ranged = 5
        ctx.data.Extra.growth.upgrades.explosive = 3
        ctx.data:GrantWeapon('item142', 1)
        ctx.data:HoldWeapon('item142')
        ctx.other.Character.Position = { x = 0, y = 2, z = 4 }
        ctx.rayHit = { Instance = ctx.other.Character, Position = { x = 0, y = 2, z = 4 } }
        ctx.mgr:Attack(ctx.player)
        local direct = 0
        for _, a in ipairs(ctx.applied) do
            if a.target == ctx.other then
                direct = direct + 1
                assert.near(750, a.amount, 1e-9) -- 直击只吃远程
            else
                assert.near(150, a.amount, 1e-9) -- 溅射只吃远程：100×1.5，不乘爆炸物 1.6
                assert.is_not.same(ctx.player, a.target)
            end
        end
        assert.same(1, direct)
    end)

    -- 无强化时行为与 #129 基线完全一致（0 级不加成、弹容取基础值）
    it('test_zero_level_matches_129_baseline', function()
        ctx.data:GrantWeapon('item136', 1)
        ctx.data:HoldWeapon('item136')
        ctx.mgr:Attack(ctx.player)
        assert.same(40, ctx.swingStaged[42].damage)
        ctx.data:GrantWeapon('item141', 1)
        ctx.data:HoldWeapon('item141')
        ctx.now = 1002
        assert.is_true(ctx.mgr:Attack(ctx.player).ok)
        assert.same(4, Weapon.lastReply(ctx).ammo) -- 5 发基础弹匣
    end)
end)

-- ===== 客户端手势状态机 =====
describe('TestPressGesture', function()
    it('test_tap_and_long_press_and_move_cancel', function()
        local Gesture = require('client.PressGesture')
        local g = Gesture.New({ LongPressSec = 0.35 })
        g:Begin(10, { x = 100, y = 100 })
        assert.same('tap', g:End(10.1, { x = 103, y = 101 }))
        g:Begin(20, { x = 100, y = 100 })
        assert.is_false(g:Update(20.2))
        assert.is_true(g:Update(20.4)) -- 长按触发选点
        assert.same('long', g:End(20.5, { x = 300, y = 300 }))
        g:Begin(30, { x = 100, y = 100 })
        assert.is_nil(g:End(30.1, { x = 200, y = 100 })) -- 滑出容差：既不是点按也不是长按
    end)
end)

-- ===== 数值与表一致性 =====
describe('TestWeaponConfig', function()
    it('test_gun_shared_reload_two_seconds', function()
        assert.same(2, GameCfg.Ability.GunShared.ReloadSec)
        assert.is_true(GameCfg.Ability.GunShared.Range > 0)
    end)

    -- 商店表 R24—R19：手枪 10/1s/10、霰弹 5×20/1.5s/2、冲锋 13/0.15s/30、
    -- 自动步枪 20/0.2s/30、狙击 200/1.5s/5、火箭筒 500/1 发/周围 5 米 100
    it('test_guns_match_shop_table', function()
        local g = GameCfg.Ability.Guns
        assert.same({ Damage = 10, IntervalSec = 1.0, Magazine = 10 }, g.item137)
        assert.same({ Damage = 20, Pellets = 5, IntervalSec = 1.5, Magazine = 2 }, g.item138)
        assert.same({ Damage = 13, IntervalSec = 0.15, Magazine = 30, Auto = true }, g.item139)
        assert.same({ Damage = 20, IntervalSec = 0.2, Magazine = 30, Auto = true }, g.item140)
        assert.same({ Damage = 200, IntervalSec = 1.5, Magazine = 5 }, g.item141)
        assert.same({ Damage = 500, IntervalSec = 2.0, Magazine = 1,
            Splash = { Damage = 100, Radius = 5 } }, g.item142)
    end)

    -- 商店表 R27/R26/R25：指虎 10/0.5、匕首 15/0.5、斧头 40/1.0；#129 票面射程 2/3/4 米
    it('test_melee_weapons_match_design_table', function()
        local m = GameCfg.Ability.MeleeWeapons
        assert.same({ Damage = 10, IntervalSec = 0.5, Range = 2 }, m.item134)
        assert.same({ Damage = 15, IntervalSec = 0.5, Range = 3 }, m.item135)
        assert.same({ Damage = 40, IntervalSec = 1.0, Range = 4 }, m.item136)
    end)

    -- 商店表 R18/R17/R16：鞭炮 50、手雷 100、炸药 150；票面：直接 20 米、5 米爆炸、保底 3–5 条
    it('test_throwables_and_throw_ticket', function()
        local e = GameCfg.Ability.Explosives
        assert.same(50, e.item143.Damage)
        assert.same(100, e.item144.Damage)
        assert.same(150, e.item145.Damage)
        local t = GameCfg.Ability.Throw
        assert.same(20, t.Range)
        assert.same(5, t.ExplosionRadius)
        assert.same(3, t.FishMin)
        assert.same(5, t.FishMax)
    end)

    it('test_unarmed_uses_ticket_values_not_25', function()
        local u = GameCfg.Ability.Unarmed
        assert.is_not_nil(u)
        assert.same(5, u.Damage)
        assert.same(0.5, u.IntervalSec)
        assert.same(2, u.Range)
        assert.is_not.same(25, u.Damage)
    end)

    -- 全量商品表（GameCfg.Shop.Goods 是已接入白名单，武器购买归 #130）
    -- #139 起武器来源不止商店：抽奖武器大奖（weaponChoice 组）也进同两张表，
    -- 口径改为「每件武器要么在商店武器页、要么是抽奖大奖」，且物品表分类正确。
    it('test_weapon_ids_registered_in_shop_and_items', function()
        local shopGoods = {}
        for _, goods in ipairs(GameCfg.Content.Shop.Goods) do
            if goods.page == '武器' and goods.itemKey then shopGoods[goods.itemKey] = true end
        end
        local lotteryPrizes = {}
        for _, entry in ipairs(GameCfg.Content.Lottery.Patterns) do
            if entry.tripleReward and entry.tripleReward.kind == 'weaponChoice' then
                for _, itemKey in ipairs(entry.tripleReward.itemKeys) do lotteryPrizes[itemKey] = true end
            end
        end
        local function checkSource(id, wantType)
            assert.is_true(shopGoods[id] or lotteryPrizes[id], id .. ' 既不在商店武器页也不是抽奖大奖')
            assert.same(wantType, GameCfg.Items.Definitions[id].Type)
        end
        for id, _ in pairs(GameCfg.Ability.MeleeWeapons) do checkSource(id, '近战武器') end
        for id, _ in pairs(GameCfg.Ability.Guns) do checkSource(id, '远程武器') end
        for id, _ in pairs(GameCfg.Ability.Explosives) do
            assert.is_true(shopGoods[id], id .. ' 不在商店武器页')
            assert.same('爆炸物', GameCfg.Items.Definitions[id].Type)
        end
    end)
end)

-- ===== 重进恢复 =====
describe('TestWeaponPersistence', function()
    -- 旧类没有 setUp，但 loadfile('server/Mgr/MgrWeapon.lua') 会经 server.AbilityAPI 摸到技能包；
    -- 旧套件里它一直是「蹭前一个类的模块缓存」跑通的，缓存断了就报 AddAbility 缺失。
    -- 这里显式装上按 SERVER_API 名单建齐的包桩，并在案例后恢复缓存与 preload。
    local saved
    before_each(function()
        saved = { preload = package.preload[VENDOR], vendor = package.loaded[VENDOR],
            api = package.loaded['server.AbilityAPI'] }
        package.preload[VENDOR] = function() return lu_stub.packageApi({ CastAbility = function() return true end }) end
        package.loaded[VENDOR] = nil
        package.loaded['server.AbilityAPI'] = nil
    end)
    after_each(function()
        package.preload[VENDOR] = saved.preload
        package.loaded[VENDOR] = saved.vendor
        package.loaded['server.AbilityAPI'] = saved.api
    end)

    it('test_rejoin_restores_equipment_and_full_magazine', function()
        local data = PlayerData.New({ UserId = 129, SetAttribute = function() end })
        data:Init()
        assert.is_true(data:GrantWeapon('item137', 1))
        assert.is_true(data:SelectWeapon('item137'))
        local snapshot = data:Serialize()
        local re = PlayerData.New({ UserId = 129, SetAttribute = function() end })
        re:Init()
        assert.is_true(re:ApplySave(snapshot))
        local mgr = assert(loadfile('server/Mgr/MgrWeapon.lua'))()
        mgr.PlayerData = { GetDataInst = function() return re end }
        assert.same('item137', mgr:EquippedWeapon(re)) -- 选中武器重进恢复
        local mag = mgr:MagState(mgr:GetState(129), 'item137', GameCfg.Ability.Guns.item137.Magazine)
        assert.same(GameCfg.Ability.Guns.item137.Magazine, mag.ammo) -- 弹匣按满匣恢复（不进 #123 快照）
        local saved2 = re:Serialize()
        assert.is_nil(saved2.ammo) -- 快照 schema 未被动过：没有弹匣字段
        assert.same(1, re:WeaponCount('item137'))
    end)
end)

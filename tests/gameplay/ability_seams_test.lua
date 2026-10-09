-- #132 T11 原型：服务端接缝（AbilityAPI 的 SetScale / 挂点，MgrFishUnit 的飞行 / 叼人 / 阶段首领）。
-- 纯逻辑各有自己的用例（tests/gameplay/ability_proto_test.lua）；这里只测「接缝有没有被正确驱动」。
--
-- 失败方式（先列后写）：
--   1. 体型接缝把 NaN/非法倍率写进单位，或单位不支持 SetScale 时直接抛错把调用方打断；
--   2. 挂点接缝建出来的位移没净空（挂件陷进宿主）；无挂点名也能建；销毁失败还返回成功；
--   3. 飞行驱动不写回引擎，或写回时越过本区围栏（借飞行跨区）；
--   4. 空中受击不改变索敌：被打的鱼不找打它的玩家，只按最近挑人；
--   5. 阶段首领的招式不结算伤害、咬中不叼人；携带跟随不写回玩家位置、超时不放下。
local lu = require('luaunit')

local GameCfg = require('common.GameCfg')

local function vec(x, y, z)
    return { x = x, y = y, z = z }
end

-- 真实 AbilityAPI（懒加载接缝），加载期需要 RunService:IsServer()
TestAbilitySeams = {}

function TestAbilitySeams:setUp()
    self.saved = { Vector3 = rawget(_G, 'Vector3'), Quaternion = rawget(_G, 'Quaternion'),
        game = rawget(_G, 'game'), api = package.loaded['server.AbilityAPI'] }
    self.created = {}
    _G.Vector3 = { New = vec }
    _G.Quaternion = { New = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end }
    self.world = {
        CreateUnit = function(_, unitType, options)
            local unit = { UnitType = unitType, Destroyed = false }
            for k, v in pairs(options) do unit[k] = v end
            function unit:Destroy() self.Destroyed = true end
            self.created[#self.created + 1] = unit
            return unit
        end,
    }
    _G.game = { GetService = function(_, name)
        if name == 'RunService' then return { IsServer = function() return false end } end
        if name == 'World' then return self.world end
        return {}
    end }
    package.loaded['server.AbilityAPI'] = nil
    self.api = require('server.AbilityAPI')
end

function TestAbilitySeams:tearDown()
    _G.Vector3 = self.saved.Vector3
    _G.Quaternion = self.saved.Quaternion
    _G.game = self.saved.game
    package.loaded['server.AbilityAPI'] = self.saved.api
end

function TestAbilitySeams:test_set_body_scale_sanitizes_and_writes_a_uniform_scale()
    local written = nil
    local unit = { SetScale = function(_, scale) written = scale end }
    local applied = self.api.SetBodyScale(unit, 3)
    lu.assertTrue(applied.Ok)
    lu.assertEquals(applied.Scale, 3)
    lu.assertEquals(written, vec(3, 3, 3))
    lu.assertEquals(applied.Derived.CapsuleHeight, 6) -- 胶囊高随倍率放大
    -- 非法倍率净化成 1 倍，绝不把 NaN 写进单位
    for _, bad in ipairs({ 0 / 0, math.huge, -1, 0, 'x', nil }) do
        written = nil
        local result = self.api.SetBodyScale(unit, bad)
        lu.assertTrue(result.Ok, tostring(bad))
        lu.assertEquals(written, vec(1, 1, 1), tostring(bad))
    end
end

function TestAbilitySeams:test_set_body_scale_reports_failure_instead_of_throwing()
    lu.assertEquals(self.api.SetBodyScale(nil, 2).Error, 'no-unit')
    local noScale = self.api.SetBodyScale({}, 2)
    lu.assertFalse(noScale.Ok)
    lu.assertEquals(noScale.Error, 'no-set-scale')
    local broken = self.api.SetBodyScale({ SetScale = function() error('引擎拒绝') end }, 2)
    lu.assertFalse(broken.Ok)
    lu.assertEquals(broken.Scale, 2)
end

function TestAbilitySeams:test_attach_to_socket_creates_a_cleared_mount()
    local host = { Name = 'fish56Boss' }
    local attached = self.api.AttachToSocket(self.world, nil, host, 'LiftSocket', vec(0, 0.1, 0.1))
    lu.assertTrue(attached.Ok)
    lu.assertEquals(attached.Mount.UnitType, 'SkeletalSocketMount')
    lu.assertEquals(attached.Mount.Parent, host)
    lu.assertEquals(attached.Mount.SocketName, 'LiftSocket')
    -- 贴脸位移必须被推出去（挂点不穿出）
    lu.assertTrue(attached.Offset.z >= 0.1)
    lu.assertTrue(attached.Mount.SocketOffset.x == 0)
    -- 无挂点名 / 无宿主一律拒绝，不建孤儿单位
    lu.assertEquals(self.api.AttachToSocket(self.world, nil, host, nil, nil).Error, 'no-socket')
    lu.assertEquals(self.api.AttachToSocket(self.world, nil, nil, 'LiftSocket', nil).Error, 'no-host')
    lu.assertEquals(#self.created, 1)
end

function TestAbilitySeams:test_detach_destroys_the_mount_only_once()
    local attached = self.api.AttachToSocket(self.world, nil, { Name = 'boss' }, 'LiftSocket', vec(0, 2, 0))
    lu.assertTrue(self.api.DetachFromSocket(attached.Mount))
    lu.assertTrue(attached.Mount.Destroyed)
    lu.assertFalse(self.api.DetachFromSocket(nil))
end

-- MgrFishUnit 的驱动：假引擎（World/Players/Vitals/AbilityAPI 全桩），只验证接缝行为
TestFishAbilitySeams = {}

local function newFish(id, fishId, position)
    local body = { UnitId = id, Position = vec(position.x, position.y, position.z), BodyType = 4,
        Parent = nil, LinearVelocity = vec(0, 0, 0), Rotation = nil }
    return { Id = id, FishId = fishId, Owner = nil, Anchor = vec(position.x, position.y, position.z),
        Carrier = { Body = body, Health = GameCfg.Fish[fishId].Health,
            MaxHealth = GameCfg.Fish[fishId].Health, Dead = false }, Threat = {} }
end

local function newPlayer(userId, position)
    return { UserId = userId, Character = { Position = vec(position.x, position.y, position.z),
        Controller = { Health = 100, MaxHealth = 100 } } }
end

function TestFishAbilitySeams:setUp()
    local env = self
    self.saved = { Vector3 = rawget(_G, 'Vector3'), Quaternion = rawget(_G, 'Quaternion'),
        RaycastParams = rawget(_G, 'RaycastParams'), game = rawget(_G, 'game'),
        carrier = package.loaded['server.Mgr.MgrFishCarrier'],
        ability = package.loaded['server.Mgr.MgrFishUnit'],
        api = package.loaded['server.AbilityAPI'] }
    self.now = 100
    self.players = {}
    self.hits = {}
    self.mounts = {}
    self.detached = {}
    _G.Vector3 = { New = vec }
    _G.Quaternion = { New = function() return {} end, FromEulerAngles = function() return {} end }
    _G.RaycastParams = { new = function() return {} end }
    _G.game = { GetService = function(_, name)
        if name == 'World' then return { GetServerTime = function() return env.now end } end
        if name == 'Players' then return { GetPlayers = function() return env.players end } end
        return {}
    end }
    package.loaded['server.Mgr.MgrFishCarrier'] = { Spawn = function() return nil end, Despawn = function() end,
        SyncPosition = function() end }
    package.loaded['server.AbilityAPI'] = {
        AttachToSocket = function(_, unit, host, socketName, offset)
            local mount = { UnitType = 'SkeletalSocketMount', Parent = host, SocketName = socketName,
                SocketOffset = offset, Destroyed = false }
            function mount:Destroy() self.Destroyed = true end
            env.mounts[#env.mounts + 1] = mount
            return { Ok = true, Mount = mount, Offset = offset }
        end,
        DetachFromSocket = function(mount)
            env.detached[#env.detached + 1] = mount
            return true
        end,
    }
    package.loaded['server.Mgr.MgrFishUnit'] = nil
    self.mgr = assert(loadfile('server/Mgr/MgrFishUnit.lua'))()
    self.mgr.World = _G.game:GetService('World')
    self.mgr.Vitals = {
        CanTakeDamage = function() return true end,
        NewHit = function(_, source, category) return { source = source, category = category, targets = {} } end,
        ApplyHit = function(_, hit, target, amount)
            env.hits[#env.hits + 1] = { target = target, amount = amount, category = hit.category }
            return true
        end,
    }
end

function TestFishAbilitySeams:tearDown()
    _G.Vector3 = self.saved.Vector3
    _G.Quaternion = self.saved.Quaternion
    _G.RaycastParams = self.saved.RaycastParams
    _G.game = self.saved.game
    package.loaded['server.Mgr.MgrFishCarrier'] = self.saved.carrier
    package.loaded['server.Mgr.MgrFishUnit'] = self.saved.ability
    package.loaded['server.AbilityAPI'] = self.saved.api
end

function TestFishAbilitySeams:test_species_registry_routes_flight_and_boss()
    lu.assertEquals(self.mgr:FlightProfile('fish47Elite').DiveIntervalSec, 20)
    lu.assertEquals(self.mgr:FlightProfile('fish55Elite').Mode, 'leap')
    lu.assertEquals(self.mgr:FlightProfile('fish48Boss').DiveDamage, 260)
    lu.assertEquals(self.mgr:FlightProfile('eel'), nil)
    lu.assertTrue(self.mgr:BossPhaseEnabled('fish56Boss'))
    lu.assertFalse(self.mgr:BossPhaseEnabled('fish47Elite'))
end

function TestFishAbilitySeams:test_flight_bounds_come_from_the_zone_scene_then_the_fallback()
    local zone = nil
    for _, entry in ipairs(GameCfg.Zones) do
        if entry.Id == 'reefIsland' then zone = entry.Scene end
    end
    local bounds = self.mgr:FlightBounds('fish47Elite')
    lu.assertEquals(bounds.MinX, zone.Boundary.MinX)
    lu.assertEquals(bounds.CeilingY, zone.SafePoint.y + GameCfg.Ability.Flight.MaxHeight)
    -- 未知鱼种用兜底围栏，仍然是有限边界
    local fallback = self.mgr:FlightBounds('noSuchFish')
    lu.assertEquals(fallback.MaxX, GameCfg.Ability.Flight.FallbackBounds.MaxX)
    lu.assertNotEquals(fallback.CeilingY, math.huge)
end

function TestFishAbilitySeams:test_flying_writes_back_a_position_inside_the_fence()
    local fish = newFish(1, 'fish47Elite', { x = 0, y = 14, z = 0 })
    self.mgr.Fish[fish.Id] = fish
    local bounds = self.mgr:FlightBounds(fish.FishId)
    -- 起点故意放到围栏外：驱动一帧必须把它夹回本区
    fish.Carrier.Body.Position = vec(bounds.MaxX + 200, bounds.CeilingY + 50, bounds.MaxZ + 200)
    lu.assertTrue(self.mgr:StartFlight(fish, self.now))
    lu.assertEquals(fish.State, 'flying')
    for step = 1, 60 do
        self.now = self.now + 0.05
        self.mgr:UpdateFlying(fish, self.now)
    end
    local pos = fish.Carrier.Body.Position
    lu.assertTrue(pos.x <= bounds.MaxX and pos.x >= bounds.MinX, 'x ' .. tostring(pos.x))
    lu.assertTrue(pos.z <= bounds.MaxZ and pos.z >= bounds.MinZ, 'z ' .. tostring(pos.z))
    lu.assertTrue(pos.y <= bounds.CeilingY, 'y ' .. tostring(pos.y))
    lu.assertTrue(fish.Flight.Stats.Clamps > 0, '越界必须被钳制并计数')
    lu.assertTrue(#fish.Flight.ClampLog > 0)
end

function TestFishAbilitySeams:test_air_strike_focuses_the_attacker_then_the_nearest_one()
    local fish = newFish(2, 'fish47Elite', { x = 0, y = 14, z = 0 })
    self.mgr.Fish[fish.Id] = fish
    local far = newPlayer(1, { x = 40, y = 0, z = 0 })
    local near = newPlayer(2, { x = 1, y = 0, z = 0 })
    self.players = { far, near }
    local pos = fish.Carrier.Body.Position
    -- 没被打过：取最近的
    local target = self.mgr:ChooseTarget(fish, pos, { AggroRange = 60 })
    lu.assertEquals(target, near)
    -- 空中被远处的玩家打中：威胁优先，改盯打它的人
    self.mgr:NoteDamage(fish, far, 500)
    target = self.mgr:ChooseTarget(fish, pos, { AggroRange = 60 })
    lu.assertEquals(target, far, '空中受击后应改盯攻击者')
    -- 攻击者死亡：仇恨立即失效，回落最近目标
    far.Character.Controller.Health = 0
    target = self.mgr:ChooseTarget(fish, pos, { AggroRange = 60 })
    lu.assertEquals(target, near)
    lu.assertEquals(fish.Threat[far], nil, '失效目标要从仇恨表里清掉')
end

function TestFishAbilitySeams:test_boss_phase_bite_lands_damage_and_grabs_the_player()
    local safe = GameCfg.Zones[7].Scene.SafePoint
    local fish = newFish(3, 'fish56Boss', { x = safe.x, y = safe.y, z = safe.z })
    self.mgr.Fish[fish.Id] = fish
    local player = newPlayer(9, { x = safe.x + 1, y = safe.y, z = safe.z })
    self.players = { player }
    -- 50%：入水阶段（咬中 1000）
    fish.Carrier.Health, fish.Carrier.MaxHealth = 5000, 10000
    fish.Phase = require('common.BossPhase').New(GameCfg.Ability.BossPhase, self.now, fish.Carrier.Body.Position)
    fish.PhaseAt = self.now
    fish.Yaw = 0
    for step = 1, 355 do -- #38 正文沧龙式：15秒跃起，1秒预警+1.5秒腾空后咬中
        self.now = self.now + 0.05
        self.mgr:UpdateBossPhase(fish, self.now, fish.Carrier.Body.Position)
    end
    lu.assertEquals(fish.Phase.Phase, 'water')
    lu.assertEquals(#self.hits, 2)
    lu.assertEquals(self.hits[1].amount, 35)
    lu.assertEquals(self.hits[2].amount, 1000)
    lu.assertEquals(self.hits[2].category, 'fishAttack')
    lu.assertEquals(self.hits[2].target, player)
    -- 咬中即叼走：挂点建出来了，玩家归到携带态
    lu.assertNotNil(fish.Carry)
    lu.assertNotNil(fish.CarryMount)
    lu.assertEquals(fish.CarryMount.SocketName, GameCfg.Ability.Carry.Socket)
    lu.assertEquals(fish.Carry.TargetPlayer, player)
end

function TestFishAbilitySeams:test_carry_follows_snaps_and_releases_with_the_mount()
    local fish = newFish(4, 'fish56Boss', { x = 0, y = 0, z = 0 })
    self.mgr.Fish[fish.Id] = fish
    local player = newPlayer(9, { x = 1, y = 0, z = 0 })
    self.players = { player }
    local CarryMount = require('common.CarryMount')
    local cfg = GameCfg.Ability.Carry
    fish.Carry = CarryMount.New(cfg, { x = 0, y = 0, z = 0 }, 0, self.now)
    fish.Carry.GroundY = 2
    fish.Carry.TargetPlayer = player
    fish.Carry.LastStepAt = self.now
    lu.assertTrue(CarryMount.Attach(fish.Carry, { x = 1, y = 0, z = 0 }, self.now).Ok)
    fish.CarryMount = self.mounts[#self.mounts + 1] or { Destroyed = false, Destroy = function() end }
    -- 容差内不写回（避免每帧纠正抖动）
    local before = vec(player.Character.Position.x, player.Character.Position.y, player.Character.Position.z)
    self.mgr:UpdateCarry(fish, self.now + 0.05)
    lu.assertEquals(player.Character.Position.x, before.x)
    -- 被甩开：整段钳回挂点坐标
    player.Character.Position = vec(999, 0, 999)
    self.mgr:UpdateCarry(fish, self.now + 0.1)
    local mount = CarryMount.MountPoint(fish.Carry.Host, fish.Carry.Offset, 0)
    lu.assertAlmostEquals(player.Character.Position.x, mount.x, 1e-9)
    lu.assertAlmostEquals(player.Character.Position.z, mount.z, 1e-9)
    lu.assertEquals(fish.Carry.Stats.Snaps, 1)
    -- 超时：放下玩家、销毁挂点、清携带态
    self.mgr:UpdateCarry(fish, self.now + cfg.MaxCarrySec + 1)
    lu.assertEquals(fish.Carry, nil)
    lu.assertEquals(fish.CarryMount, nil)
    lu.assertEquals(#self.detached, 1)
    lu.assertAlmostEquals(player.Character.Position.y, 2 + cfg.DropHeight, 1e-9)
    lu.assertAlmostEquals(player.Character.Position.z, cfg.DropForward, 1e-9)
end

function TestFishAbilitySeams:test_remove_drops_a_carried_player_before_clearing_the_fish()
    local fish = newFish(5, 'fish56Boss', { x = 0, y = 0, z = 0 })
    self.mgr.Fish[fish.Id] = fish
    local player = newPlayer(9, { x = 1, y = 0, z = 0 })
    local CarryMount = require('common.CarryMount')
    fish.Carry = CarryMount.New(GameCfg.Ability.Carry, { x = 0, y = 0, z = 0 }, 0, self.now)
    fish.Carry.GroundY = 2
    fish.Carry.TargetPlayer = player
    CarryMount.Attach(fish.Carry, { x = 1, y = 0, z = 0 }, self.now)
    self.mgr:Remove(fish)
    lu.assertEquals(fish.Carry, nil)
    lu.assertEquals(self.mgr.Fish[fish.Id], nil)
    lu.assertAlmostEquals(player.Character.Position.y, 2 + GameCfg.Ability.Carry.DropHeight, 1e-9)
end

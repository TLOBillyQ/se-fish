-- #132 T11 验收步骤：把能力原型的纯逻辑契约写成可执行的 Gherkin。
-- 与 tests/probes/ability_proto.lua 同源（探针打印关键量，这里只做断言）；
-- world 由 acceptance4lua 的 harness 提供，步骤间用它传状态。
local GameCfg = require('common.GameCfg')
local BodyScale = require('common.BodyScale')
local FlightPath = require('common.FlightPath')
local CarryMount = require('common.CarryMount')
local BossPhase = require('common.BossPhase')

local function zoneScene(id)
    for _, entry in ipairs(GameCfg.Zones) do
        if entry.Id == id then return entry.Scene end
    end
    return nil
end

return { patterns = {
    { '^首领分阶段配置起手于 (%d+) 血$', function(world, maxHealth)
        world.bossCfg = GameCfg.Ability.BossPhase
        world.maxHealth = tonumber(maxHealth)
        world.boss = BossPhase.New(world.bossCfg, 0, { x = 0, y = 0, z = 0 })
    end },

    { '^首领血量一帧掉到 (%d+)%%$', function(world, percent)
        local health = world.maxHealth * tonumber(percent) / 100
        world.events = BossPhase.Update(world.boss, 0.05, 0.05, {
            Health = health, MaxHealth = world.maxHealth, Alive = true,
            Target = { x = 1, y = 0, z = 0 }, Pos = { x = 0, y = 0, z = 0 },
        })
    end },

    { '^首领进入 (%a+) 阶段并跳过 (%a+) 阶段$', function(world, phase, skipped)
        assert(world.events and world.events.PhaseChanged, '没有发生阶段切换')
        assert(world.events.To == phase, '实际阶段=' .. tostring(world.events.To))
        assert(table.concat(world.events.Skipped, ',') == skipped,
            '实际跳过=' .. table.concat(world.events.Skipped, ','))
        assert(world.boss.Phase == phase)
    end },

    { '^白头鹰在礁岛围栏外$', function(world)
        world.bounds = FlightPath.BoundsOf(zoneScene('reefIsland'), GameCfg.Ability.Flight)
        assert(world.bounds, '礁岛场景没有围栏')
        local b = world.bounds
        -- 起点就在围栏外（例如被顶飞后重新接管）：驱动一帧必须夹回本区，
        -- 所以起点同时是 Last，不会走「漂移回滚」分支（那条分支另有探针覆盖）。
        world.fly = FlightPath.New(b, GameCfg.Ability.Flight,
            GameCfg.Ability.Flight.Species.fish47Elite,
            { x = b.MaxX + 100, y = b.CeilingY + 100, z = b.MaxZ + 100 }, 0)
        world.clampsBefore = world.fly.Stats.Clamps
    end },

    { '^飞行推进一帧$', function(world)
        world.flyEvents = FlightPath.Step(world.fly, 0.05, 0.05)
    end },

    { '^白头鹰坐标仍在围栏内$', function(world)
        local b, p = world.bounds, world.fly.Pos
        assert(p.x <= b.MaxX and p.x >= b.MinX, 'x 越界: ' .. tostring(p.x))
        assert(p.z <= b.MaxZ and p.z >= b.MinZ, 'z 越界: ' .. tostring(p.z))
        assert(p.y <= b.CeilingY, 'y 越界: ' .. tostring(p.y))
        assert(world.fly.Stats.Clamps > world.clampsBefore, '越界没有被钳制')
    end },

    { '^宿主朝 %+x 且挂点位移为基准值$', function(world)
        world.host = { x = 100, y = 2, z = 50 }
        world.yaw = math.pi / 2
        world.base = {
            CapsuleHeight = GameCfg.Ability.BodyScale.CapsuleHeight,
            CameraDistance = GameCfg.Ability.BodyScale.CameraDistance,
            InteractRange = GameCfg.Ability.BodyScale.InteractRange,
            SocketOffset = GameCfg.Ability.Carry.Offset,
        }
        world.delta1 = nil
    end },

    { '^体型为 (%d+) 倍$', function(world, scale)
        local derived = BodyScale.Derive(tonumber(scale), world.base)
        local point = CarryMount.MountPoint(world.host, derived.SocketOffset, world.yaw)
        world.delta = { x = point.x - world.host.x, y = point.y - world.host.y, z = point.z - world.host.z }
        if not world.delta1 then
            local basePoint = CarryMount.MountPoint(world.host,
                BodyScale.Derive(1, world.base).SocketOffset, world.yaw)
            world.delta1 = { x = basePoint.x - world.host.x, y = basePoint.y - world.host.y,
                z = basePoint.z - world.host.z }
        end
    end },

    { '^挂点相对宿主的位移是 1 倍时的 (%d+) 倍$', function(world, factor)
        local k = tonumber(factor)
        assert(math.abs(world.delta.x - world.delta1.x * k) < 1e-9, 'x 不同比')
        assert(math.abs(world.delta.y - world.delta1.y * k) < 1e-9, 'y 不同比')
        assert(math.abs(world.delta.z - world.delta1.z * k) < 1e-9, 'z 不同比')
    end },

    { '^沧龙在原点朝 %+x 叼住 (%d+) 米内的玩家$', function(world, distance)
        local carry = GameCfg.Ability.Carry
        world.carryCfg = carry
        world.hostPos = { x = 0, y = 0, z = 0 }
        world.yaw = 0
        world.carry = CarryMount.New(carry, world.hostPos, world.yaw, 0)
        world.carried = { x = 0, y = 0, z = tonumber(distance) }
        local grabbed = CarryMount.Attach(world.carry, world.carried, 0)
        assert(grabbed.Ok, '叼人失败: ' .. tostring(grabbed.Reason))
        assert(grabbed.Damage == carry.GrabDamage)
    end },

    { '^玩家被甩到 (%d+) 米外$', function(world, distance)
        local far = { x = tonumber(distance), y = 0, z = tonumber(distance) }
        world.follow = CarryMount.Follow(world.carry, far, 0.1, 0.05)
    end },

    { '^玩家坐标被钳回挂点坐标$', function(world)
        assert(world.follow and world.follow.Snapped, '没有被钳回')
        local expected = CarryMount.MountPoint(world.carry.Host, world.carry.Offset, world.yaw)
        local got = world.follow.Position
        assert(math.abs(got.x - expected.x) < 1e-9 and math.abs(got.y - expected.y) < 1e-9
            and math.abs(got.z - expected.z) < 1e-9, '钳回坐标不等于挂点坐标')
        assert(world.carry.Stats.Snaps == 1)
    end },
} }

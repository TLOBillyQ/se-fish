-- #141 树林岛闭环验收的 Gherkin 步骤（只做断言；关键量由 tests/probes/forest_island.lua 打印）。
-- 业务用真实模块：common/GameCfg（抽鱼池 / 战斗数值 / 商店 / 兑换 / 摆渡）、
-- server/Mgr/MgrFishUnit（剑鱼 / 三头鲨状态机）。引擎边界是假的（载体、Vitals、RE）。
-- world 由 acceptance4lua 的 harness 提供，步骤间用它传状态；每个场景结束的「那么」步骤恢复全局。
if not package.path:find('./tests/lib/?.lua', 1, true) then
    package.path = './tests/lib/?.lua;' .. package.path
end
local GameCfg = require('common.GameCfg')
local FishCatch = require('common.FishCatch')

-- ===== 战斗世界：真实 MgrFishUnit（tests/support/combat_world，复用 fish_escape 测试的假引擎）=====
local CombatWorld = require('tests.support.combat_world')

local function combatWorld(world)
    world.combat = CombatWorld.new()
end

local function closeCombat(world)
    local env = world.combat
    if not env then return end
    CombatWorld.close(env)
    world.combat, world.fish = nil, nil
end

local at = CombatWorld.at

-- 放下一条树林岛鱼并把目标玩家摆到鱼身 (0, dz) 处
local function dropFish(world, fishId, dz)
    world.fish = CombatWorld.drop(world.combat, fishId, dz)
    return world.fish
end

local function pinRandom(world)
    CombatWorld.pinRandom(world.combat)
end

local function dropAt(world, fishId, awayMeters)
    combatWorld(world)
    pinRandom(world)
    dropFish(world, fishId, awayMeters)
    at(world.combat, 0)
end

local function selectAll(rows, rodLevel, baitId)
    local total = 0
    for _, row in ipairs(rows) do
        if row.RodLevel <= rodLevel and (row.Bait == 0 or row.Bait == baitId) then
            total = total + row.DrawWeight
        end
    end
    local found = {}
    for roll = 1, total do
        found[FishCatch.Select(rows, rodLevel, baitId, function() return roll end)] = true
    end
    return found
end

return { patterns = {
    -- ===== 水区与抽鱼池 =====
    { '^树林岛水区已接入抛竿区，抽鱼池 (%d+) 行$', function(world, count)
        local rows = GameCfg.Casting.Zones[GameCfg.Zones[4].WaterId]
        assert(rows, '树林岛水区没进活跃抽鱼池')
        assert(#rows == tonumber(count), '抽鱼池行数 ' .. #rows .. ' ≠ ' .. count)
        world.rows = rows
    end },

    { '^不挂饵抛竿只会出普通海胆或极品海胆$', function(world)
        local found = selectAll(world.rows, 1, nil)
        local ok = found.item49 and found.item55 and not found.item50 and not found.fish31Elite
        assert(ok, '无饵保底不清：' .. tostring(next(found)))
    end },

    { '^树林岛首领饵已登记$', function()
        assert(GameCfg.Casting.BossBait.item123 == 'fish32Boss',
            'item123 未登记为三头鲨首领饵: ' .. tostring(GameCfg.Casting.BossBait.item123))
    end },

    { '^挂 item(%d+) 必出三头鲨$', function(_, baitId)
        assert(GameCfg.Casting.BossBait['item' .. baitId] == 'fish32Boss', '首领饵映射错')
    end },

    -- ===== 剑鱼：挥头 =====
    { '^剑鱼上岸放下，玩家站在它正前方咬距内$', function(world)
        combatWorld(world)
        dropFish(world, 'fish31Elite', 2)
        at(world.combat, 0)
        assert(world.fish.Move and world.fish.Move.Name == 'swing', '正前方没有起挥头')
    end },

    { '^挥头预警过 (%d+) 秒结算$', function(world, sec)
        at(world.combat, tonumber(sec))
    end },

    { '^玩家受到一次 (%d+) 点伤害$', function(world, amount)
        local hits = world.combat.hits
        local ok = #hits == 1 and hits[1].amount == tonumber(amount)
        local detail = 'hits=' .. #hits
        closeCombat(world)
        assert(ok, detail)
    end },

    -- ===== 剑鱼 / 三头鲨：高跃 =====
    { '^剑鱼上岸放下，玩家站在 (%d+) 米外$', function(world, away)
        dropAt(world, 'fish31Elite', tonumber(away))
    end },

    { '^过 (%d+) 秒后起跳$', function(world, sec)
        local env, fish = world.combat, world.fish
        at(env, tonumber(sec))
        assert(fish.Move and fish.Move.Name == 'jump', '到点没有起跳')
        local dest = fish.Move.Destination
        world.dest = dest
        env.player.Character.Position = Vector3.New(dest.x, 2, dest.z)
    end },

    { '^剑鱼跳到 (%d+) 米外且落地 (%d+) 米内的玩家受一次 (%d+) 点伤害$', function(world, dist, radius, amount)
        local env, fish = world.combat, world.fish
        local body = fish.Carrier.Body
        local jump = GameCfg.FishCombat.swordfish
        local dx = world.dest.x - body.Position.x
        assert(math.abs(math.abs(dx) - tonumber(dist)) < 1e-6, '落点距离 ' .. dx .. ' ≠ ' .. dist)
        at(env, fish.Move.At + jump.JumpSec)
        local hits = env.hits
        local ok = #hits == 1 and hits[1].amount == tonumber(amount) and jump.JumpRadius == tonumber(radius)
        local detail = 'hits=' .. #hits .. ' radius=' .. tostring(jump.JumpRadius)
        closeCombat(world)
        assert(ok, detail)
    end },

    -- ===== 三头鲨：扫头 =====
    { '^三头鲨上岸放下，玩家站在它正前方咬距内$', function(world)
        combatWorld(world)
        dropFish(world, 'fish32Boss', 2)
        at(world.combat, 0)
        assert(world.fish.Move and world.fish.Move.Name == 'sweep', '正前方没有起扫头')
    end },

    { '^扫头预警过 (%d+) 秒结算$', function(world, sec)
        at(world.combat, tonumber(sec))
    end },

    -- ===== 三头鲨：翻滚接触去重 =====
    { '^三头鲨上岸放下，贴身玩家不在仇恨目标上$', function(world)
        combatWorld(world)
        local fish = dropFish(world, 'fish32Boss', 20)
        local env = world.combat
        env.other.Character.Controller.Health = 5000
        env.mgr:NoteDamage(fish, env.player, 30) -- 远处玩家仇恨最高，贴身玩家被“滚到”
        local bp = fish.Carrier.Body.Position
        env.other.Character.Position = Vector3.New(bp.x, 2, bp.z + 2)
        at(env, 0)
    end },

    { '^翻滚同一秒内连续两帧，再进入下一秒$', function(world)
        local env, fish = world.combat, world.fish
        at(env, 0.1) -- 必须实际滚动；静止首帧不算接触
        at(env, 0.2) -- 同秒第二帧不得重复扣血
        local bp = fish.Carrier.Body.Position
        env.other.Character.Position = Vector3.New(bp.x, 2, bp.z + 2)
        at(env, 1)
    end },

    { '^贴身玩家在第一秒只被滚到一次 (%d+)，第二秒再结算一次$', function(world, amount)
        local hits = world.combat.hits
        local ok = #hits == 2 and hits[1].amount == tonumber(amount) and hits[2].amount == tonumber(amount)
        local detail = 'hits=' .. #hits
        closeCombat(world)
        assert(ok, detail)
    end },

    { '^三头鲨上岸放下，玩家站在 (%d+) 米外$', function(world, away)
        dropAt(world, 'fish32Boss', tonumber(away))
    end },

    { '^三头鲨跳到 (%d+) 米外且落地 (%d+) 米内的玩家受一次 (%d+) 点伤害$', function(world, dist, radius, amount)
        local env, fish = world.combat, world.fish
        local body = fish.Carrier.Body
        local jump = GameCfg.FishCombat.shark
        local dx = world.dest.x - body.Position.x
        assert(math.abs(math.abs(dx) - tonumber(dist)) < 1e-6, '落点距离 ' .. dx .. ' ≠ ' .. dist)
        at(env, fish.Move.At + jump.JumpSec)
        local ok = #env.hits == 1 and env.hits[1].amount == tonumber(amount) and jump.JumpRadius == tonumber(radius)
        local detail = 'hits=' .. #env.hits .. ' radius=' .. tostring(jump.JumpRadius)
        closeCombat(world)
        assert(ok, detail)
    end },

    -- ===== 逃跑时限 =====
    { '^过 (%d+) 秒$', function(world, sec)
        at(world.combat, tonumber(sec))
    end },

    { '^剑鱼转入逃脱且不再结算伤害$', function(world)
        local env, fish = world.combat, world.fish
        local ok = fish.State == 'escaping' and #env.hits == 0
        local detail = 'state=' .. tostring(fish.State) .. ' hits=' .. #env.hits
        closeCombat(world)
        assert(ok, detail)
    end },

    -- ===== 商店 / 兑换 / 摆渡 =====
    { '^树林岛内容已接入$', function()
        assert(GameCfg.Fish.item49.implemented and GameCfg.Fish.fish32Boss.implemented, '树林岛鱼种未翻开')
        assert(GameCfg.FishCombat.swordfish and GameCfg.FishCombat.shark, '缺树林岛战斗参数')
    end },

    { '^四区买得到普通鱼竿 (%d+) 金，鱼剑换牛腿，三联鲨鱼头换沙滩岛船票，第四区返程 (%d+) 金$',
        function(_, rodPrice, returnPrice)
            local gear = {}
            for _, row in ipairs(GameCfg.Shop.ListForPage(4, '钓具')) do gear[row.ItemId] = row.Price end
            assert(gear.normalRod == tonumber(rodPrice), '四区普通鱼竿价 ' .. tostring(gear.normalRod))
            local chain = GameCfg.Content.Exchanges[4]
            assert(chain.EliteToken == 'item63' and chain.BossToken == 'item64', '树林岛信物链不对')
            local exchange = GameCfg.Interact.Fishermen[4].Exchange
            assert(exchange.item63 == 'item123', '鱼剑没有换牛腿')
            assert(exchange.item64 == 'item149', '三联鲨鱼头没有换沙滩岛船票')
            local route
            for _, candidate in ipairs(GameCfg.Ferry.Routes) do
                if candidate.FromZoneId == 'crabLake' and candidate.ToZoneId == 'forestIsland' then
                    route = candidate
                end
            end
            assert(route and route.Return.Price == tonumber(returnPrice),
                '第四区返程价 ' .. tostring(route and route.Return.Price))
        end },
} }

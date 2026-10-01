-- #142 沙滩岛闭环验收的 Gherkin 步骤（只做断言；关键量由 tests/probes/beach_island.lua 打印）。
-- 业务用真实模块：common/GameCfg（抽鱼池 / 战斗数值 / 商店 / 兑换 / 摆渡）、
-- server/Mgr/MgrFishUnit（海象 / 虎鲸状态机）。引擎边界是假的（载体、Vitals、RE）。
-- world 由 acceptance4lua 的 harness 提供，步骤间用它传状态；每个场景结束的「那么」步骤恢复全局。
-- 数值来源：钓鱼表 R58–R71、商店表 R6/R7/R21、#121 裁定（虎啸未给伤按独立基础 30 披露细化）。
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

-- 放下一条沙滩岛鱼并把目标玩家摆到鱼身 (0, dz) 处
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

-- 推进到 40 秒突击节拍（等预警起手，做有界等待），返回起手时的鱼身位置
local function startCharge(world)
    local env, fish = world.combat, world.fish
    for t = 0.5, 39.5, 0.5 do at(env, t) end
    at(env, 40)
    local guard = 0
    while (not fish.Move or fish.Move.Name ~= 'charge') and guard < 50 do
        env.now = env.now + 0.1
        env.mgr:Update()
        guard = guard + 1
    end
    assert(fish.Move and fish.Move.Name == 'charge', '到点没有起突击')
    world.chargeFrom = { x = fish.Carrier.Body.Position.x, z = fish.Carrier.Body.Position.z }
end

return { patterns = {
    -- ===== 水区与抽鱼池 =====
    { '^沙滩岛水区已接入抛竿区，抽鱼池 (%d+) 行$', function(world, count)
        local rows = GameCfg.Casting.Zones[GameCfg.Zones[5].WaterId]
        assert(rows, '沙滩岛水区没进活跃抽鱼池')
        assert(#rows == tonumber(count), '抽鱼池行数 ' .. #rows .. ' ≠ ' .. count)
        world.rows = rows
    end },

    { '^不挂饵抛竿只会出普通海参或极品海参$', function(world)
        local found = selectAll(world.rows, 1, nil)
        local ok = found.item65 and found.item71 and not found.item66 and not found.fish40Boss
        assert(ok, '无饵保底不清：' .. tostring(next(found)))
    end },

    { '^沙滩岛首领饵已登记$', function()
        assert(GameCfg.Casting.BossBait.item124 == 'fish40Boss',
            'item124 未登记为虎鲸首领饵: ' .. tostring(GameCfg.Casting.BossBait.item124))
    end },

    { '^挂 item(%d+) 必出虎鲸$', function(_, baitId)
        assert(GameCfg.Casting.BossBait['item' .. baitId] == 'fish40Boss', '首领饵映射错')
    end },

    -- ===== 海象：甩头 =====
    { '^海象上岸放下，玩家站在它正前方咬距内$', function(world)
        combatWorld(world)
        dropFish(world, 'fish39Elite', 2)
        at(world.combat, 0)
        assert(world.fish.Move and world.fish.Move.Name == 'swing', '正前方没有起甩头')
    end },

    { '^甩头预警过 (%d+) 秒结算$', function(world, sec)
        at(world.combat, tonumber(sec))
    end },

    -- 「玩家受到一次 (%d+) 点伤害」复用 forest_island_steps 的通用步骤（首个命中生效）。

    -- ===== 海象：突击 =====
    { '^海象上岸放下，玩家站在 (%d+) 米外$', function(world, away)
        dropAt(world, 'fish39Elite', tonumber(away))
    end },

    { '^过 (%d+) 秒后突击且玩家站在冲锋路径上$', function(world, sec)
        local env = world.combat
        at(env, tonumber(sec) - 0.5)
        startCharge(world)
        -- 预警期间把玩家摆上冲锋直线（起点正前方 10 米），锁头朝向已在起手时定死
        local from = world.chargeFrom
        env.player.Character.Position = Vector3.New(from.x, 2, from.z + 10)
        env.hits = {} -- 贴身甩头的结算不算进突击判定
    end },

    { '^玩家被冲锋撞到一次 (%d+) 点伤害且海象冲出 (%d+) 米$', function(world, amount, dist)
        local env, fish = world.combat, world.fish
        local params = GameCfg.FishCombat.walrus
        at(env, fish.Move.StrikeAt + 0.1)
        local traveled = math.abs(fish.Carrier.Body.Position.z - world.chargeFrom.z)
        local hits = env.hits
        local ok = #hits == 1 and hits[1].amount == tonumber(amount)
            and math.abs(traveled - tonumber(dist)) < 1e-6
        local detail = 'hits=' .. #hits .. ' traveled=' .. tostring(traveled)
        closeCombat(world)
        assert(ok, detail)
    end },

    -- ===== 虎鲸：爪击 =====
    { '^虎鲸上岸放下，玩家站在它正前方咬距内$', function(world)
        combatWorld(world)
        dropFish(world, 'fish40Boss', 2)
        at(world.combat, 0)
        assert(world.fish.Move and world.fish.Move.Name == 'claw', '正前方没有起爪击')
    end },

    { '^爪击预警过 (%d+) 秒结算$', function(world, sec)
        at(world.combat, tonumber(sec))
    end },

    -- ===== 虎鲸：虎啸（远程，咬距外也结算）=====
    { '^虎鲸上岸放下，玩家站在 (%d+) 米外$', function(world, away)
        dropAt(world, 'fish40Boss', tonumber(away))
    end },

    { '^虎啸到点预警并结算$', function(world)
        local env, fish = world.combat, world.fish
        for t = 0.5, 9.5, 0.5 do at(env, t) end
        -- 虎啸到点前把玩家挪到咬距外（12 米）、虎啸射程（15 米）内
        local bp = fish.Carrier.Body.Position
        env.player.Character.Position = Vector3.New(bp.x, 2, bp.z + 12)
        local guard = 0
        while (not fish.Move or fish.Move.Name ~= 'roar') and guard < 50 do
            env.now = env.now + 0.1
            env.mgr:Update()
            guard = guard + 1
        end
        assert(fish.Move and fish.Move.Name == 'roar', '到点没有起虎啸')
        env.hits = {} -- 此前贴身爪击的结算不算进本步断言
        at(env, fish.Move.StrikeAt + 0.1)
    end },

    -- ===== 虎鲸：甩尾（只打身后）=====
    { '^虎鲸上岸放下，身前目标身后 4 米有另一名玩家$', function(world)
        combatWorld(world)
        local fish = dropFish(world, 'fish40Boss', 2)
        local bp = fish.Carrier.Body.Position
        world.combat.other.Character.Position = Vector3.New(bp.x, 2, bp.z - 4)
    end },

    { '^虎啸过后甩尾结算$', function(world)
        local env, fish = world.combat, world.fish
        for t = 0.5, 9.5, 0.5 do at(env, t) end
        at(env, 10) -- 虎啸与甩尾同为 10 秒节拍，优先级压住甩尾
        assert(fish.Move and fish.Move.Name == 'roar', '同点没有先起虎啸')
        local guard = 0
        while (not fish.Move or fish.Move.Name ~= 'tail') and guard < 50 do
            env.now = env.now + 0.1
            env.mgr:Update()
            guard = guard + 1
        end
        assert(fish.Move and fish.Move.Name == 'tail', '虎啸后没有接甩尾')
        env.hits = {} -- 虎啸对身前目标的结算不算进甩尾判定
        at(env, fish.Move.StrikeAt + 0.1)
    end },

    { '^身后玩家受到一次 (%d+) 点伤害且身前目标不沾$', function(world, amount)
        local env = world.combat
        local hits = env.hits
        local ok = #hits == 1 and hits[1].amount == tonumber(amount) and hits[1].player == env.other
        local detail = 'hits=' .. #hits
        closeCombat(world)
        assert(ok, detail)
    end },

    -- ===== 虎鲸：鲸跃 =====
    -- 「过 (%d+) 秒后起跳」复用 forest_island_steps 的通用步骤（跳到落点并把玩家摆过去）。

    { '^虎鲸跳到 (%d+) 米外且落地 (%d+) 米内的玩家受一次 (%d+) 点伤害$', function(world, dist, radius, amount)
        local env, fish = world.combat, world.fish
        local body = fish.Carrier.Body
        local jump = GameCfg.FishCombat.orca
        local dx = world.dest.x - body.Position.x
        assert(math.abs(math.abs(dx) - tonumber(dist)) < 1e-6, '落点距离 ' .. dx .. ' ≠ ' .. dist)
        at(env, fish.Move.At + jump.JumpSec)
        local hits = env.hits
        local ok = #hits == 1 and hits[1].amount == tonumber(amount) and jump.JumpRadius == tonumber(radius)
        local detail = 'hits=' .. #hits .. ' radius=' .. tostring(jump.JumpRadius)
        closeCombat(world)
        assert(ok, detail)
    end },

    -- ===== 逃跑时限 =====
    -- 「过 (%d+) 秒」复用 forest_island_steps 的通用步骤。

    { '^海象转入逃脱且不再结算伤害$', function(world)
        local env, fish = world.combat, world.fish
        local ok = fish.State == 'escaping' and #env.hits == 0
        local detail = 'state=' .. tostring(fish.State) .. ' hits=' .. #env.hits
        closeCombat(world)
        assert(ok, detail)
    end },

    -- ===== 商店 / 兑换 / 摆渡 =====
    { '^沙滩岛内容已接入$', function()
        assert(GameCfg.Fish.item65.implemented and GameCfg.Fish.fish40Boss.implemented, '沙滩岛鱼种未翻开')
        assert(GameCfg.FishCombat.walrus and GameCfg.FishCombat.orca, '缺沙滩岛战斗参数')
    end },

    { '^五区买得到椰子 (%d+) 金与专业鱼竿 (%d+) 金和自动步枪 (%d+) 金，海象尾换海豹，虎头换礁石岛船票，第五区返程 (%d+) 金$',
        function(_, coconutPrice, rodPrice, riflePrice, returnPrice)
            local gear = {}
            for _, row in ipairs(GameCfg.Shop.ListForPage(5, '钓具')) do gear[row.ItemId] = row.Price end
            assert(gear.item117 == tonumber(coconutPrice), '五区椰子价 ' .. tostring(gear.item117))
            assert(gear.proRod == tonumber(rodPrice), '五区专业鱼竿价 ' .. tostring(gear.proRod))
            local weapons = {}
            for _, row in ipairs(GameCfg.Shop.ListForPage(5, '武器')) do weapons[row.ItemId] = row.Price end
            assert(weapons.item140 == tonumber(riflePrice), '五区自动步枪价 ' .. tostring(weapons.item140))
            local chain = GameCfg.Content.Exchanges[5]
            assert(chain.EliteToken == 'item79' and chain.BossToken == 'item80', '沙滩岛信物链不对')
            local exchange = GameCfg.Interact.Fishermen[5].Exchange
            assert(exchange.item79 == 'item124', '海象尾没有换海豹')
            assert(exchange.item80 == 'item150', '虎头没有换礁石岛船票')
            local route
            for _, candidate in ipairs(GameCfg.Ferry.Routes) do
                if candidate.FromZoneId == 'forestIsland' and candidate.ToZoneId == 'beachIsland' then
                    route = candidate
                end
            end
            assert(route and route.Return.Price == tonumber(returnPrice),
                '第五区返程价 ' .. tostring(route and route.Return.Price))
        end },
} }

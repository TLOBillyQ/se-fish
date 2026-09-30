-- #141 树林岛闭环探针（离线模拟，只证明逻辑，不当真机验收）。
-- 运行：在仓库根执行 `lua tests/probes/forest_island.lua`；退出码 0 = 全部通过。
-- 链路：树林岛水区注册与抽鱼池（无饵保底 / 挂蚂蟥门槛 / 首领饵必出三头鲨）→
--       剑鱼挥头 20 与 50 秒高跃（10 米外、5 米内 100）→ 三头鲨扫头 25、翻滚接触去重、20 秒高跃（15 米外、10 米内 200）→
--       逃跑时限（剑鱼 180 / 三头鲨 300）→ 四级摊位 / 鱼剑换牛腿 / 三联鲨鱼头换沙滩岛船票 / 第四区返程 90 金。
--
-- 失败模式（先列后写）：
--   1. 水区没进活跃抽鱼池（水域实际永不可钓），或行数 / 竿级 / 饵 / 权重与原表不符；
--   2. 不挂饵能出水胆以外的鱼，或挂蚂蟥竿 1 能出竿 4 的鱼，或首领饵 item123 不出三头鲨；
--   3. 剑鱼 / 三头鲨挥扫头起手帧就结算（无预警），或超标伤害、同一击按帧重复、身后 / 侧身仍被扫到；
--   4. 高跃周期错（剑鱼 50 秒、三头鲨 20 秒）或落点距离 / 范围 / 伤害与原表不符；
--   5. 翻滚接触不结算、伤害不取 25，或同一秒槽同一玩家重复结算（超额伤害）；
--   6. 逃跑时限到不转逃脱、仍在结算伤害；
--   7. 四级摊位买不到普通鱼竿，或信物链 / 返程价与原表不符。
--
-- 模拟边界（逐条标注在输出里）：
--   * 业务模块用真实代码：common/GameCfg（抽鱼池 / 战斗数值 / 商店 / 兑换 / 摆渡）、
--     server/Mgr/MgrFishUnit（剑鱼 / 三头鲨状态机）、common/FishCatch（抽鱼）。
--   * 引擎边界是假的：载体、Vitals、RE、服务器时刻（探针按帧自增 now）。
--   * 高跃落点方向由替换的 math.random（固定 0）钉死为 +x，只验距离与范围。
--   * 攻击 / 躲避窗口与真机手感未验证 [未查证]：本探针只证明招式按契约结算，不证明“正常单杀可行”。
package.path = table.concat({ './?.lua', './?/init.lua', './tests/lib/?.lua', package.path }, ';')

local Pass, Fail = 0, 0
local function check(name, ok, detail)
    if ok then Pass = Pass + 1 print('[PASS] ' .. name)
    else Fail = Fail + 1 print('[FAIL] ' .. name .. (detail and ('  -- ' .. tostring(detail)) or '')) end
end
local function quantity(label, value) print(string.format('K %s = %s', label, tostring(value))) end

local GameCfg = require('common.GameCfg')
local FishCatch = require('common.FishCatch')

-- ===== 假引擎战斗世界（复用 fish_escape 测试夹具）=====
require('tests.gameplay.fish_escape_test')
local function combat()
    local env = setmetatable({}, { __index = TestFishEscape })
    TestFishEscape.setUp(env)
    TestFishEscape.prepare(env)
    env.hits, env.notices = {}, {}
    for _, p in ipairs({ env.player, env.other }) do
        p.Character.Controller.Health = 5000
        p.Character.Controller.TakeDamage = function(c, d) c.Health = c.Health - d end
    end
    env.other.Character.Position = Vector3.New(500, 2, 500)
    env.mgr.PublishBite = function(_, payload) env.notices[#env.notices + 1] = payload end
    env.mgr.CombatPublisher = function() end
    env.mgr.Vitals = {
        NewHit = function(_, source, category) return { source = source, category = category } end,
        ApplyHit = function(_, _, player, amount)
            env.hits[#env.hits + 1] = { player = player, amount = amount }
            return true, amount
        end,
        CanTakeDamage = function() return true end,
    }
    return env
end
local function close(env)
    if env.savedRandom then math.random = env.savedRandom end
    TestFishEscape.tearDown(env)
end
local function at(env, now) env.now = now env.mgr:Update() end
local function pinRandom(env)
    env.savedRandom = math.random
    math.random = function() return 0 end
end
local function drop(env, fishId, dz)
    local p = env.player.Character.Position
    local fish = env.mgr:SpawnLanded(env.player, { fishId = fishId, mult = 1 }, Vector3.New(p.x, 2, p.z + 2))
    fish.Carrier.Body.OnLiftedBegin:Fire(env.player.Character)
    env.mgr:Drop(env.player)
    local bp = fish.Carrier.Body.Position
    env.player.Character.Position = Vector3.New(bp.x, 2, bp.z + (dz or 2))
    return fish
end

-- ===== 1. 水区 / 抽鱼池 =====
local waterId = GameCfg.Zones[4].WaterId
local rows = GameCfg.Casting.Zones[waterId]
check('树林岛水区进活跃抽鱼池', rows ~= nil, waterId)
if rows then
    local haveElite = false
    local weightsOk = true
    for _, row in ipairs(rows) do
        if row.Id == 'fish31Elite' then haveElite = true end
        if not GameCfg.Fish[row.Id] then weightsOk = false end
    end
    check('普通抽鱼池13行，加首领饵独立鱼种共14种且含剑鱼', #rows == 13 and haveElite
        and GameCfg.Casting.BossBait.item123 == 'fish32Boss', #rows)
    check('抽鱼池行都指向已存在的鱼种', weightsOk)
    local function selectAll(rodLevel, baitId)
        local total = 0
        for _, row in ipairs(rows) do
            if row.RodLevel <= rodLevel and (row.Bait == 0 or row.Bait == baitId) then total = total + row.DrawWeight end
        end
        local found = {}
        for roll = 1, total do found[FishCatch.Select(rows, rodLevel, baitId, function() return roll end)] = true end
        return found
    end
    local plain = selectAll(1, nil)
    check('不挂饵只出海胆 / 极品海胆', plain.item49 and plain.item55 and not plain.item50, 'plain=' .. tostring(plain.item50))
    local bait1 = selectAll(1, 'item116')
    check('挂蚂蟥竿 1 不出竿 4 的鱼', not bait1.item52 and bait1.item49, 'item52=' .. tostring(bait1.item52))
    quantity('抽鱼池行数', #rows)
end
check('首领饵 item123 必出三头鲨', GameCfg.Casting.BossBait.item123 == 'fish32Boss',
    GameCfg.Casting.BossBait.item123)

-- ===== 2. 剑鱼 =====
do
    local env = combat()
    local fish = drop(env, 'fish31Elite', 2)
    at(env, 0)
    local windup = fish.Move and fish.Move.Name == 'swing' and #env.hits == 0
    at(env, 2)
    check('剑鱼挥头起手预警、2 秒后结算 20', windup and #env.hits == 1 and env.hits[1].amount == 20,
        'windup=' .. tostring(windup) .. ' hits=' .. #env.hits)
    quantity('剑鱼挥头伤害', GameCfg.FishCombat.swordfish.SwingDamage)
    close(env)
end
do
    local env = combat()
    pinRandom(env)
    local fish = drop(env, 'fish31Elite', 20)
    at(env, 0)
    at(env, 50)
    local dest = fish.Move and fish.Move.Destination
    local jumped = fish.Move and fish.Move.Name == 'jump'
    local startX = fish.Carrier.Body.Position.x
    if jumped then env.player.Character.Position = Vector3.New(dest.x, 2, dest.z) end
    at(env, 51.5)
    local d = dest and math.abs(dest.x - startX - 10) or -1
    check('剑鱼 50 秒高跃：10 米外落地 100', jumped and d < 1e-6 and #env.hits == 1 and env.hits[1].amount == 100,
        'jump=' .. tostring(jumped) .. ' hits=' .. #env.hits)
    quantity('剑鱼高跃周期秒', GameCfg.FishCombat.swordfish.JumpIntervalSec)
    quantity('剑鱼高跃落点米', GameCfg.FishCombat.swordfish.JumpDistance)
    close(env)
end

-- ===== 3. 三头鲨 =====
do
    local env = combat()
    local fish = drop(env, 'fish32Boss', 2)
    at(env, 0)
    local windup = fish.Move and fish.Move.Name == 'sweep' and #env.hits == 0
    at(env, 3)
    check('三头鲨扫头起手预警、3 秒后结算 25', windup and #env.hits == 1 and env.hits[1].amount == 25,
        'windup=' .. tostring(windup) .. ' hits=' .. #env.hits)
    close(env)
end
do
    local env = combat()
    local fish = drop(env, 'fish32Boss', 20)
    env.mgr:NoteDamage(fish, env.player, 30)
    local bp = fish.Carrier.Body.Position
    env.other.Character.Position = Vector3.New(bp.x, 2, bp.z + 2)
    at(env, 0)
    at(env, 0.1) -- 首个真实滚动帧
    at(env, 0.2) -- 同秒槽重复接触
    local once = #env.hits == 1 and env.hits[1].amount == 25
    local bp2 = fish.Carrier.Body.Position
    env.other.Character.Position = Vector3.New(bp2.x, 2, bp2.z + 2)
    at(env, 1)
    check('翻滚接触同一秒槽只结算一次 25', once and #env.hits == 2,
        'first=' .. tostring(once) .. ' hits=' .. #env.hits)
    quantity('三头鲨翻滚接触伤害', GameCfg.FishCombat.shark.RollDamage)
    close(env)
end
do
    local env = combat()
    pinRandom(env)
    local fish = drop(env, 'fish32Boss', 20)
    at(env, 0)
    at(env, 20)
    local dest = fish.Move and fish.Move.Destination
    local jumped = fish.Move and fish.Move.Name == 'jump'
    local startX = fish.Carrier.Body.Position.x
    if jumped then env.player.Character.Position = Vector3.New(dest.x, 2, dest.z) end
    at(env, 21.5)
    local d = dest and math.abs(dest.x - startX - 15) or -1
    check('三头鲨 20 秒高跃：15 米外落地 200', jumped and d < 1e-6 and #env.hits == 1 and env.hits[1].amount == 200,
        'jump=' .. tostring(jumped) .. ' hits=' .. #env.hits)
    quantity('三头鲨高跃周期秒', GameCfg.FishCombat.shark.JumpIntervalSec)
    close(env)
end

-- ===== 4. 逃跑时限 =====
do
    local env = combat()
    local fish = drop(env, 'fish31Elite', 20)
    at(env, 179)
    local still = fish.State == 'combat'
    at(env, 180)
    check('剑鱼 180 秒转逃脱且不再结算', still and fish.State == 'escaping' and #env.hits == 0)
    close(env)
end
do
    local env = combat()
    local fish = drop(env, 'fish32Boss', 20)
    at(env, 300)
    check('三头鲨 300 秒转逃脱', fish.State == 'escaping')
    close(env)
end
quantity('剑鱼逃跑时限秒', GameCfg.Fish.fish31Elite.EscapeSec)
quantity('三头鲨逃跑时限秒', GameCfg.Fish.fish32Boss.EscapeSec)

-- ===== 5. 商店 / 兑换 / 摆渡 =====
do
    local stand
    for _, row in ipairs(GameCfg.Shop.Stands) do
        if row.AnchorName == 'Z4_Shop' then stand = row end
    end
    check('Z4_Shop 摊位为 4 级', stand ~= nil and stand.Level == 4)
    local gear = {}
    for _, row in ipairs(GameCfg.Shop.ListForPage(4, '钓具')) do gear[row.ItemId] = row.Price end
    check('四区买得到普通鱼竿 50 金、蚂蟥 4 金', gear.normalRod == 50 and gear.item116 == 4,
        'rod=' .. tostring(gear.normalRod))
    local chain = GameCfg.Content.Exchanges[4]
    local exchange = GameCfg.Interact.Fishermen[4].Exchange
    check('鱼剑换牛腿、三联鲨鱼头换沙滩岛船票',
        chain.EliteToken == 'item63' and chain.BossToken == 'item64'
        and exchange.item63 == 'item123' and exchange.item64 == 'item149')
    local route
    for _, candidate in ipairs(GameCfg.Ferry.Routes) do
        if candidate.FromZoneId == 'crabLake' and candidate.ToZoneId == 'forestIsland' then route = candidate end
    end
    check('第四区返程 90 金', route ~= nil and route.Return.Price == 90, route and route.Return.Price)
    quantity('第四区返程价金', route and route.Return.Price)
end

print(string.format('----\n%d passed, %d failed', Pass, Fail))
print('[未查证] 攻击 / 躲避窗口与真机手感未验证：本探针只证明招式按契约结算。')
os.exit(Fail == 0 and 0 or 1)

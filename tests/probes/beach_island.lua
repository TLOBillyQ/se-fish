-- #142 沙滩岛闭环探针（离线模拟，只证明逻辑，不当真机验收）。
-- 运行：在仓库根执行 `lua tests/probes/beach_island.lua`；退出码 0 = 全部通过。
-- 链路：沙滩岛水区注册与抽鱼池（海参无饵保底 / 椰子饵门槛 / 首领饵海豹必出虎鲸）→
--       海象甩头 25 与 40 秒突击（直线冲锋 20 米、撞到 120）→
--       虎鲸爪击 30（2 秒）、虎啸 10 秒远程 30、甩尾 10 秒 160（只打身后）、
--       鲸跃 25 秒（15 米外落地、10 米范围 240）→
--       逃跑时限（海象 180 / 虎鲸 300）→ 五级摊位 / 海象尾换海豹 / 虎头换礁石岛船票 / 第五区返程 270 金。
--
-- 失败模式（先列后写）：
--   1. 水区没进活跃抽鱼池（水域实际永不可钓），或行数 / 竿级 / 饵 / 权重与原表不符；
--   2. 不挂饵能出海参以外的鱼，或挂椰子竿 1 能出竿 5 的鱼，或首领饵 item124 不出虎鲸；
--   3. 海象甩头起手帧就结算（无预警）、超标伤害、同一击按帧重复，或突击周期 / 冲程 / 伤害错
--      （40 秒 / 20 米 / 120）、路径外玩家被撞 / 路径上玩家漏结算；
--   4. 虎鲸四招丢招 / 数值错：爪击不取 30（2 秒）、虎啸不取 10 秒远程 30、甩尾不取 10 秒 160
--      或打到身前、鲸跃周期 / 落点 / 范围 / 伤害错（25 秒 / 15 米 / 10 米 / 240）；
--   5. 鲸跃 / 突击位移失败后仍按预定位置结算伤害；
--   6. 逃跑时限到不转逃脱、仍在结算伤害；
--   7. 五级摊位买不到椰子 / 专业鱼竿 / 自动步枪，或信物链 / 返程价与原表不符。
--
-- 模拟边界（逐条标注在输出里）：
--   * 业务模块用真实代码：common/GameCfg（抽鱼池 / 战斗数值 / 商店 / 兑换 / 摆渡）、
--     server/Mgr/MgrFishUnit（海象 / 虎鲸状态机）、common/FishCatch（抽鱼）。
--   * 引擎边界是假的：载体、Vitals、RE、服务器时刻（探针按帧自增 now）。
--   * 鲸跃落点方向由替换的 math.random（固定 0）钉死为 +x，只验距离与范围。
--   * 虎啸伤害 30 是 #121 未给伤的独立基础披露细化；预警 / 前摇参数是配置细化 [未查证]。
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

-- ===== 假引擎战斗世界（tests/support/combat_world，复用 fish_escape 测试夹具）=====
local CombatWorld = require('tests.support.combat_world')
local combat, close, at, pinRandom, drop =
    CombatWorld.new, CombatWorld.close, CombatWorld.at, CombatWorld.pinRandom, CombatWorld.drop

-- 推进到 40 秒突击节拍并等预警起手（40 秒帧可能压着上一记甩头的预警，做有界等待）
local function startCharge(env, fish)
    for t = 0.5, 39.5, 0.5 do at(env, t) end
    at(env, 40)
    local guard = 0
    while (not fish.Move or fish.Move.Name ~= 'charge') and guard < 50 do
        env.now = env.now + 0.1
        env.mgr:Update()
        guard = guard + 1
    end
    return fish.Move, fish.Carrier.Body.Position
end

-- 从预警记录里捞某招的 Lock payload（双轴审查 P2：预警形状 / 半径必须与真实危险区一致）
local function findLock(env, moveName)
    local lock
    for _, notice in ipairs(env.notices) do
        if notice.kind == 'lock' and notice.move == moveName then lock = notice end
    end
    return lock
end

-- ===== 1. 水区 / 抽鱼池 =====
local waterId = GameCfg.Zones[5].WaterId
local rows = GameCfg.Casting.Zones[waterId]
check('沙滩岛水区进活跃抽鱼池', rows ~= nil, waterId)
if rows then
    local haveElite = false
    local weightsOk = true
    for _, row in ipairs(rows) do
        if row.Id == 'fish39Elite' then haveElite = true end
        if not GameCfg.Fish[row.Id] then weightsOk = false end
    end
    check('普通抽鱼池13行，加首领饵独立鱼种共14种且含海象', #rows == 13 and haveElite
        and GameCfg.Casting.BossBait.item124 == 'fish40Boss', #rows)
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
    check('不挂饵只出海参 / 极品海参', plain.item65 and plain.item71 and not plain.item66,
        'plain=' .. tostring(plain.item66))
    local bait1 = selectAll(1, 'item117')
    check('挂椰子竿 1 不出竿 5 的鱼', not bait1.item68 and bait1.item66, 'item68=' .. tostring(bait1.item68))
    quantity('抽鱼池行数', #rows)
end
check('首领饵 item124 必出虎鲸', GameCfg.Casting.BossBait.item124 == 'fish40Boss',
    GameCfg.Casting.BossBait.item124)

-- ===== 2. 海象 =====
do
    local env = combat()
    local fish = drop(env, 'fish39Elite', 2)
    at(env, 0)
    local windup = fish.Move and fish.Move.Name == 'swing' and #env.hits == 0
    at(env, 2)
    check('海象甩头起手预警、2 秒后结算 25', windup and #env.hits == 1 and env.hits[1].amount == 25,
        'windup=' .. tostring(windup) .. ' hits=' .. #env.hits)
    quantity('海象甩头伤害', GameCfg.FishCombat.walrus.SwingDamage)
    close(env)
end
do
    local env = combat()
    local fish = drop(env, 'fish39Elite', 20)
    local move, bp = startCharge(env, fish)
    env.hits = {}
    env.player.Character.Position = Vector3.New(bp.x, 2, bp.z + 10) -- 冲锋路径上
    at(env, move.At + GameCfg.FishCombat.walrus.ChargeWindupSec + 0.3)
    local midNoHit = #env.hits == 0
    at(env, move.StrikeAt + 0.1)
    check('海象 40 秒突击：冲锋 20 米、路径上的玩家吃一次 120',
        move.Name == 'charge' and midNoHit and #env.hits == 1 and env.hits[1].amount == 120
        and math.abs(fish.Carrier.Body.Position.z - bp.z - GameCfg.FishCombat.walrus.ChargeDistance) < 1e-6,
        'move=' .. tostring(move.Name) .. ' hits=' .. #env.hits)
    local chargeLock = findLock(env, 'charge')
    check('突击预警覆盖 20 米冲锋走廊', chargeLock ~= nil
        and math.abs(chargeLock.range - GameCfg.FishCombat.walrus.ChargeDistance) < 1e-9,
        'range=' .. tostring(chargeLock and chargeLock.range))
    quantity('海象突击周期秒', GameCfg.FishCombat.walrus.ChargeSec)
    quantity('海象突击伤害', GameCfg.FishCombat.walrus.ChargeDamage)
    close(env)
end
do
    local env = combat()
    local fish = drop(env, 'fish39Elite', 20)
    local move, bp = startCharge(env, fish)
    env.hits = {}
    env.player.Character.Position = Vector3.New(bp.x + 5, 2, bp.z + 10) -- 路径外侧 5 米
    at(env, move.StrikeAt + 0.1)
    check('海象突击不撞路径外的玩家', #env.hits == 0, 'hits=' .. #env.hits)
    close(env)
end

-- ===== 3. 虎鲸 =====
do
    local env = combat()
    local fish = drop(env, 'fish40Boss', 2)
    at(env, 0)
    local windup = fish.Move and fish.Move.Name == 'claw' and #env.hits == 0
    at(env, 1)
    check('虎鲸爪击起手预警、1 秒后结算 30', windup and #env.hits == 1 and env.hits[1].amount == 30,
        'windup=' .. tostring(windup) .. ' hits=' .. #env.hits)
    quantity('虎鲸爪击伤害', GameCfg.FishCombat.orca.ClawDamage)
    close(env)
end
do
    local env = combat()
    local fish = drop(env, 'fish40Boss', 2)
    for t = 0.5, 9.5, 0.5 do at(env, t) end
    local bp = fish.Carrier.Body.Position
    env.hits = {}
    env.player.Character.Position = Vector3.New(bp.x, 2, bp.z + 12) -- 咬距外、虎啸射程内
    at(env, 10)
    local roar = fish.Move and fish.Move.Name == 'roar'
    at(env, 10.5)
    local windupNoHit = roar and #env.hits == 0
    at(env, 11)
    check('虎鲸 10 秒虎啸远程：咬距外也结算 30', windupNoHit and #env.hits == 1 and env.hits[1].amount == 30,
        'roar=' .. tostring(roar) .. ' hits=' .. #env.hits)
    local roarLock = findLock(env, 'roar')
    check('虎啸预警为整圆（径向结算）', roarLock ~= nil and roarLock.shape == 'circle'
        and roarLock.halfAngleDeg == 180
        and math.abs(roarLock.range - GameCfg.FishCombat.orca.RoarRange) < 1e-9,
        'shape=' .. tostring(roarLock and roarLock.shape))
    quantity('虎啸周期秒', GameCfg.FishCombat.orca.RoarSec)
    close(env)
end
do
    local env = combat()
    local fish = drop(env, 'fish40Boss', 2)
    env.other.Character.Position = Vector3.New(fish.Carrier.Body.Position.x, 2,
        fish.Carrier.Body.Position.z - 4) -- 身后 4 米
    for t = 0.5, 9.5, 0.5 do at(env, t) end
    env.hits = {}
    at(env, 10) -- 虎啸（与甩尾同为 10 秒节拍，优先级压住）
    local roar = fish.Move and fish.Move.Name == 'roar'
    local guard = 0
    while (not fish.Move or fish.Move.Name ~= 'tail') and guard < 50 do
        env.now = env.now + 0.1
        env.mgr:Update()
        guard = guard + 1
    end
    env.hits = {} -- 虎啸结算（身前目标 30）不计入甩尾判定
    at(env, fish.Move.StrikeAt + 0.1)
    local rearOnly = true
    for _, hit in ipairs(env.hits) do
        if hit.player ~= env.other or hit.amount ~= 160 then rearOnly = false end
    end
    check('虎鲸甩尾只打身后 160（身前目标不沾）', roar and #env.hits == 1 and rearOnly,
        'roar=' .. tostring(roar) .. ' hits=' .. #env.hits)
    local tailLock = findLock(env, 'tail')
    check('甩尾预警为整圆（真实伤害区是身后半圆）', tailLock ~= nil and tailLock.shape == 'circle'
        and tailLock.halfAngleDeg == 180
        and math.abs(tailLock.range - GameCfg.FishCombat.orca.TailRadius) < 1e-9,
        'shape=' .. tostring(tailLock and tailLock.shape))
    quantity('甩尾伤害', GameCfg.FishCombat.orca.TailDamage)
    close(env)
end
do
    local env = combat()
    pinRandom(env)
    local fish = drop(env, 'fish40Boss', 20)
    for t = 0.5, 24.5, 0.5 do at(env, t) end
    at(env, 25)
    local guard = 0
    while (not fish.Move or fish.Move.Name ~= 'jump') and guard < 50 do
        env.now = env.now + 0.1
        env.mgr:Update()
        guard = guard + 1
    end
    local jumped = fish.Move and fish.Move.Name == 'jump'
    local dest = jumped and fish.Move.Destination
    local startX = fish.Carrier.Body.Position.x
    env.hits = {}
    if dest then env.player.Character.Position = Vector3.New(dest.x, 2, dest.z) end
    at(env, env.now + GameCfg.FishCombat.orca.JumpSec)
    local d = dest and math.abs(dest.x - startX - 15) or -1
    check('虎鲸 25 秒鲸跃：15 米外落地 240', jumped and d < 1e-6 and #env.hits == 1 and env.hits[1].amount == 240,
        'jump=' .. tostring(jumped) .. ' hits=' .. #env.hits)
    quantity('鲸跃周期秒', GameCfg.FishCombat.orca.JumpIntervalSec)
    close(env)
end

-- ===== 4. 逃跑时限 =====
do
    local env = combat()
    local fish = drop(env, 'fish39Elite', 20)
    at(env, 179)
    local still = fish.State == 'combat'
    at(env, 180)
    check('海象 180 秒转逃脱且不再结算', still and fish.State == 'escaping' and #env.hits == 0)
    close(env)
end
do
    local env = combat()
    local fish = drop(env, 'fish40Boss', 20)
    at(env, 300)
    check('虎鲸 300 秒转逃脱', fish.State == 'escaping')
    close(env)
end
quantity('海象逃跑时限秒', GameCfg.Fish.fish39Elite.EscapeSec)
quantity('虎鲸逃跑时限秒', GameCfg.Fish.fish40Boss.EscapeSec)

-- ===== 5. 商店 / 兑换 / 摆渡 =====
do
    local stand
    for _, row in ipairs(GameCfg.Shop.Stands) do
        if row.AnchorName == 'Z5_Shop' then stand = row end
    end
    check('Z5_Shop 摊位为 5 级', stand ~= nil and stand.Level == 5
        and stand.AnchorName == GameCfg.Zones[5].Scene.ShopName)
    local gear = {}
    for _, row in ipairs(GameCfg.Shop.ListForPage(5, '钓具')) do gear[row.ItemId] = row.Price end
    local weapons = {}
    for _, row in ipairs(GameCfg.Shop.ListForPage(5, '武器')) do weapons[row.ItemId] = row.Price end
    check('五区买得到椰子 5 金、专业鱼竿 100 金、自动步枪 1000 金',
        gear.item117 == 5 and gear.proRod == 100 and weapons.item140 == 1000,
        'coconut=' .. tostring(gear.item117) .. ' rod=' .. tostring(gear.proRod))
    local chain = GameCfg.Content.Exchanges[5]
    local exchange = GameCfg.Interact.Fishermen[5].Exchange
    check('海象尾换海豹、虎头换礁石岛船票',
        chain.EliteToken == 'item79' and chain.BossToken == 'item80'
        and exchange.item79 == 'item124' and exchange.item80 == 'item150')
    local route
    for _, candidate in ipairs(GameCfg.Ferry.Routes) do
        if candidate.FromZoneId == 'forestIsland' and candidate.ToZoneId == 'beachIsland' then route = candidate end
    end
    check('第五区返程 270 金', route ~= nil and route.Return.Price == 270, route and route.Return.Price)
    quantity('第五区返程价金', route and route.Return.Price)
end

print(string.format('----\n%d passed, %d failed', Pass, Fail))
print('[未查证] 攻击 / 躲避窗口与真机手感未验证：本探针只证明招式按契约结算。')
os.exit(Fail == 0 and 0 or 1)

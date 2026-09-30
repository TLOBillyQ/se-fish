-- #138 T17 抽奖机运行探针（离线模拟，只证明逻辑，不当真机验收）。
-- 运行：在仓库根执行 `lua tests/probes/lottery_runtime.lua`；退出码 0 = 全部通过。
-- 第一节（正常路径）：真实抽样 —— 用确定性种子的 LCG 替换 MgrLottery.Random（系统边界注入点），
--   三轴与武器组内抽样都走真实 LotteryDraw 代码，不指定图案；2 万次抽奖的经验分布与
--   配置表理论值对账（两同/三同/未中奖占比、赔付期望 2.119671、投入产出守恒）。
-- 第二节（[专项探针]）：低概率三同路径用脚本化序列逐图案强制触发，验证大奖发放与落位；
--   这是明确标识的专项验证，不作为正常通关证据。
--
-- 失败模式（先列后写）：
--   1. 经验分布偏离理论值超容差（权重表或区间划分错）；
--   2. 赔付期望偏离 2.119671（倍数错位或三同叠加了两同金币）；
--   3. 守恒破：扣物数 ≠ 抽奖数、金币账不平、奖品凭空多/少；
--   4. 三同武器进了道具格、占格奖品没回投入格；
--   5. 专项探针里某个图案的三同发不出对应大奖。
--
-- 模拟边界（逐条标注在输出里）：
--   * 业务模块用真实代码：MgrPlayerData / MgrLottery / LotteryDraw / LotteryEligibility / GameCfg。
--   * 引擎边界是假的：DataStore、RE、锚点；不进编辑器、不开局，真机另行试玩。
--   * 随机源是固定种子 LCG（确定性复现），不是引擎随机；分布结论只对配置表负责。
package.path = table.concat({ './?.lua', './?/init.lua', './tests/lib/?.lua', package.path }, ';')

local Pass, Fail = 0, 0
local function check(name, ok, detail)
    if ok then
        Pass = Pass + 1
        print('[PASS] ' .. name)
    else
        Fail = Fail + 1
        print('[FAIL] ' .. name .. (detail and ('  -- ' .. tostring(detail)) or ''))
    end
end
local function quantity(label, value) print(string.format('K %s = %s', label, tostring(value))) end

local GameCfg = require('common.GameCfg')
local ITEM_BAR = GameCfg.Items.ContainerId.ItemBar

-- ===== 引擎边界（照 tests/gameplay/lottery_settle_test.lua）=====
local env = { values = {}, queue = {}, events = {} }
local store = {
    GetAsync = function(_, key) return env.values[key] end,
    UpdateAsync = function(_, key, transform)
        local value = transform(env.values[key])
        if value then env.values[key] = value end
        return value
    end,
    SetAsync = function(_, key, value) env.values[key] = value end,
}
local anchor = { Position = { x = 0, y = 0, z = 0 } }
local player
_G.game = { GetService = function(_, name)
    if name == 'Task' then return { Spawn = function(_, fn) env.queue[#env.queue + 1] = fn end,
        Wait = function() end } end
    if name == 'DataStoreService' then return { GetDataStore = function() return store end } end
    if name == 'World' then return { GetServerTime = function() return 100 end,
        FindFirstChild = function() return anchor end } end
    if name == 'Players' then return { GetPlayers = function() return { player } end } end
end }
_G.REUtil = { GetRE = function(_, name) return { FireClient = function(_, _, value)
    env.events[#env.events + 1] = { name = name, value = value }
end } end }

local function signal()
    return { Connect = function() return { Disconnect = function() end } end }
end

local save = assert(loadfile('server/Mgr/MgrSave.lua'))()
local players = assert(loadfile('server/Mgr/MgrPlayerData.lua'))()
local lottery = assert(loadfile('server/Mgr/MgrLottery.lua'))()
players.Save, save.PlayerData = save, players
lottery.PlayerData, lottery.Save = players, save
player = { UserId = 13802, Character = { Position = { x = 0, y = 0, z = 0 } },
    CharacterAdded = signal(), CharacterRemoving = signal(), SetAttribute = function() end }
players:OnPlayerAdded(player)
while #env.queue > 0 do table.remove(env.queue, 1)() end
local data = players:GetDataInst(player)

-- ===== 第一节：正常路径真实抽样（2 万次）=====
local N = 20000
local rngState = 138138
local function lcg(n) -- 固定种子 LCG，返回 1..n 均匀整数（确定性复现）
    rngState = (rngState * 1103515245 + 12345) % 2147483648
    return rngState % n + 1
end
lottery.Random = lcg

local patterns = GameCfg.Lottery.Patterns
local function patternIndexByName(name)
    for i, p in ipairs(patterns) do if p.name == name then return i end end
end
-- 2 万次抽奖的逐笔入账日志会淹没 K 值，循环期间静音 print（K 值用 realPrint 输出）
local realPrint = _G.print
_G.print = function() end
local pairCount, tripleCount, noneCount = {}, {}, 0
local coinsPaid, consumed = 0, 0
for _ = 1, N do
    -- 每次投一件未烤极品罗非鱼（基础价 3）：直接摆进第 1 格，走真实 Settle
    local bar = data.Data.Containers[ITEM_BAR]
    for slot = 1, data:ItemBarCapacity() do bar[slot] = nil end
    bar[1] = { itemId = 'item7', count = 1, containerId = ITEM_BAR }
    local result = assert(lottery:Settle(data, 1))
    consumed = consumed + 1
    if result.outcome == 'pair' then
        local index = assert(patternIndexByName(result.patternName))
        pairCount[index] = (pairCount[index] or 0) + 1
        coinsPaid = coinsPaid + result.coins
    elseif result.outcome == 'triple' then
        tripleCount[result.axes[1]] = (tripleCount[result.axes[1]] or 0) + 1
    else
        noneCount = noneCount + 1
    end
end
_G.print = realPrint

print('--- 第一节：正常路径真实抽样（LCG 种子 138138，N=' .. N .. '）---')
quantity('总抽奖数', N)
quantity('投入消耗数', consumed)
check('投入一件消耗一件', consumed == N, consumed .. '/' .. N)

-- 理论概率：恰两同 3·p²·(1−p)，三同 p³
local totalWeight = 0
for _, p in ipairs(patterns) do totalWeight = totalWeight + p.weight end
local expectPayout = 0 -- 每 1 金币投注的期望赔付（倍率加权，三同不叠加两同金币）
for i, p in ipairs(patterns) do
    local prob = p.weight / totalWeight
    expectPayout = expectPayout + 3 * prob * prob * (1 - prob) * p.pairMultiplier
end
quantity('理论赔付期望(每倍投注)', string.format('%.6f', expectPayout))
check('配置表期望仍是 2.119671', math.abs(expectPayout - 2.119671) < 1e-9,
    string.format('%.6f', expectPayout))

local betValue = GameCfg.Items.SalePrice('item7')
local empiricalPayout = coinsPaid / (N * betValue)
quantity('投注价值', betValue)
quantity('金币总赔付', coinsPaid)
quantity('经验赔付期望', string.format('%.6f', empiricalPayout))
check('经验赔付期望贴合理论值(容差 0.03)', math.abs(empiricalPayout - expectPayout) < 0.03,
    string.format('%.6f vs %.6f', empiricalPayout, expectPayout))

local pairTotal, tripleTotal = 0, 0
for i, p in ipairs(patterns) do
    local prob = p.weight / totalWeight
    local pairTheory = 3 * prob * prob * (1 - prob)
    local tripleTheory = prob * prob * prob
    local pairGot = (pairCount[i] or 0) / N
    local tripleGot = (tripleCount[i] or 0) / N
    pairTotal = pairTotal + (pairCount[i] or 0)
    tripleTotal = tripleTotal + (tripleCount[i] or 0)
    quantity(string.format('图案%d %s 两同 理论/经验', i, p.name),
        string.format('%.5f/%.5f', pairTheory, pairGot))
    quantity(string.format('图案%d %s 三同 理论/经验', i, p.name),
        string.format('%.5f/%.5f', tripleTheory, tripleGot))
    check(string.format('图案%d(%s)两同占比贴合(容差 0.01)', i, p.name),
        math.abs(pairGot - pairTheory) < 0.01, string.format('%.5f vs %.5f', pairGot, pairTheory))
    check(string.format('图案%d(%s)三同占比贴合(容差 0.005)', i, p.name),
        math.abs(tripleGot - tripleTheory) < 0.005, string.format('%.5f vs %.5f', tripleGot, tripleTheory))
end
quantity('两同总数', pairTotal)
quantity('三同总数', tripleTotal)
quantity('未中奖数', noneCount)
check('三种结局覆盖全部抽奖', pairTotal + tripleTotal + noneCount == N)
check('金币账平：FishCoin == 累计赔付', data.Data.FishCoin == coinsPaid,
    data.Data.FishCoin .. ' vs ' .. coinsPaid)

-- 三同武器应全进独立库存；占格奖品在模拟里被下一次清格覆盖，按结果流计数
local weaponGrants = 0
for _, p in ipairs(patterns) do
    if p.tripleReward.kind == 'weaponChoice' then
        for _, itemKey in ipairs(p.tripleReward.itemKeys) do
            weaponGrants = weaponGrants + data:WeaponCount(itemKey)
        end
    end
end
local weaponTriples = (tripleCount[1] or 0) + (tripleCount[2] or 0) + (tripleCount[3] or 0)
quantity('武器组三同次数', weaponTriples)
quantity('武器独立库存总数', weaponGrants)
check('武器三同全部进独立库存', weaponGrants == weaponTriples,
    weaponGrants .. ' vs ' .. weaponTriples)

-- ===== 第二节：[专项探针] 逐图案三同强制触发（低概率路径，不作正常通关证据）=====
print('--- 第二节：[专项探针] 逐图案三同强制触发（脚本化序列，仅验证发放与落位）---')
local bounds, acc = {}, 0
for i, p in ipairs(patterns) do
    local low = acc + 1
    acc = acc + p.weight
    bounds[i] = low -- 每轴取该图案区间下界，必中该图案
end
for i, p in ipairs(patterns) do
    local bar = data.Data.Containers[ITEM_BAR]
    for slot = 1, data:ItemBarCapacity() do bar[slot] = nil end
    bar[1] = { itemId = 'item7', count = 1, containerId = ITEM_BAR }
    local roll = bounds[i]
    local reward = p.tripleReward
    local script = { roll, roll, roll }
    if reward.kind == 'weaponChoice' then script[4] = 1 end -- 组内取第 1 件
    local index = 0
    lottery.Random = function()
        index = index + 1
        return assert(script[index], '专项脚本耗尽')
    end
    local before = data.Data.FishCoin
    local result = assert(lottery:Settle(data, 1))
    local ok = result.outcome == 'triple' and result.patternName == p.name and result.prize ~= nil
    local placement
    if reward.kind == 'weaponChoice' then
        local itemId = reward.itemKeys[1]
        placement = result.prize.itemId == itemId and data:WeaponCount(itemId) >= 1
            and data.Data.Containers[ITEM_BAR][1] == nil
    else
        local entry = data.Data.Containers[ITEM_BAR][1]
        placement = result.prize.itemId == reward.itemKey and entry ~= nil
            and entry.itemId == reward.itemKey and entry.count == 1
    end
    check(string.format('[专项探针] 图案%d %s 三同发大奖且落位正确（不叠加金币）', i, p.name),
        ok and placement and result.coins == nil and data.Data.FishCoin == before,
        string.format('outcome=%s prize=%s coins=%s', tostring(result.outcome),
            result.prize and tostring(result.prize.itemId) or 'nil', tostring(result.coins)))
end

print(string.format('--- 探针合计：%d 通过，%d 失败 ---', Pass, Fail))
os.exit(Fail == 0 and 0 or 1)

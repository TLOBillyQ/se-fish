-- #134 鱼塘正常闭环真机探针（server 端，可重跑续跑）。
--
-- 用法：试玩中（Debug.Enabled=false 的新验收槽）执行
--   editor-cli exec --platform server --file <本文件绝对路径> --json
-- 取证：editor-cli log grep 'PONDLOOP' --play-session <id> --json（每行带唯一标记 PL<UserId>-<起点秒>）。
--
-- 只走正常业务意图：与客户端事件处理函数同一入口
--   拾饵   MgrLoot:Pickup(player, id)            （ItemBarAction.Pickup 的处理函数）
--   选中   data:SelectSlot / data:SelectBait      （ItemBarAction 的同名方法）
--   喂食   MgrInteract:Handle {target='fisherman', action='Feed', seq}
--   买竿   MgrShop:Handle {action='Buy', itemId='starterRod', seq}
--   抛竿   MgrCast:Cast / :Reel / :Drop           （CastAction 的处理函数）
--   收线   MgrReelIn:Accept {s, n, q}             （ReelInRE）
--   攻击   MgrWeapon:Attack                       （WeaponAction.attack）
--   摆渡   MgrFerry:Handle {action='Board', routeId, seq}
--   买匕首 MgrShop:Handle {action='Buy', number=25, seq}（钓场商店 Level1 摊位，itemKey item135）
--   装备   data:SelectWeapon('item135')（必要时 data:HoldWeapon），用 MgrWeapon:EquippedWeapon 复核
--   整理   data:MoveToItemBar / data:MoveSlot(from, index, target, slot)（背包/道具栏满时的合法换格）
-- 成长：正常击杀卖鱼；空手追鱼失败时可拾免费蚯蚓喂食攒匕首（50），买到并装备后再打电鳗/鳄雀鳝。
-- 战斗：对电鳗/鳄雀鳝先提示「绕后」站位（鱼身后 ≈range-0.8 米）并暂停；倒地/死亡只等待原地弱复活（免费），
--   复活后继续正常补给动作，不治疗、不传送。
-- 不改 RNG / 血量 / 金币 / 库存 / 时间，不发 GM，不直接记录上岸、不指定鱼、不 SetPosition。
-- 需要玩家走位时输出 "PONDLOOP-MOVE x z" 并暂停循环；用合法 input 走到该点后重新执行本文件即可续跑，
-- 所有阶段都由玩家当前存档状态推出，没有外部进度文件。
-- 冷却全部异步等待（Task:Wait），不会在一个调用里阻塞。

local GameCfg = require('common.GameCfg')
local MathWaterJudge = require('common.MathWaterJudge')
local MgrPlayerData = require('server.Mgr.MgrPlayerData')
local MgrLoot = require('server.Mgr.MgrLoot')
local MgrInteract = require('server.Mgr.MgrInteract')
local MgrShop = require('server.Mgr.MgrShop')
local MgrCast = require('server.Mgr.MgrCast')
local MgrReelIn = require('server.Mgr.MgrReelIn')
local MgrFishUnit = require('server.Mgr.MgrFishUnit')
local MgrWeapon = require('server.Mgr.MgrWeapon')
local MgrFerry = require('server.Mgr.MgrFerry')

local Task = game:GetService('Task')
local World = game:GetService('World')
local Players = game:GetService('Players')

local STEP_SEC = 0.5          -- 常规轮询间隔
local CLICK_SEC = 0.25        -- 收线批次间隔（每批 2 击，≤ 8 击/秒，低于 HighFreqInput.MaxCount）
local SETTLE_SEC = 1.5        -- 持久操作（Save:Execute）发出后等待落账
local COMBAT_WAIT_SEC = 90    -- 战斗等待多久没进展就暂停
local WORM_TARGET = 5         -- 免费补给余量：食用与抛竿共用
local LAND_STAND = { x = 5, z = 31 } -- 上岸后先正常步行到陆地再放鱼，避开岸外不可达掉落
local DAGGER = { Id = 'item135', Number = 25, MinLevel = 1 }
local STAND_SHIFT = 4.4       -- 站位点：从 NPC 锚点向陆地中心移这么远（Radius 5 + Slack 0.5 内）
local CAST_SPOT = { x = -1.5, z = 27.75 }  -- 面朝 -x 抛竿，落点 x≈-6.5 在 PondNotch/WaterCircle2 内

local function now() return World:GetServerTime() end

-- ========== 跨次执行状态：只放观测记账，不放业务进度 ==========
_G.PondLoopRT = _G.PondLoopRT or {}
local RT = _G.PondLoopRT
RT.token = (RT.token or 0) + 1       -- 新一次执行使旧循环退出
local myToken = RT.token
local player = Players:GetPlayers()[1]
if not player then print('PONDLOOP-ABORT 没有在线玩家') return end
if not RT.tag then
    RT.t0 = now()
    RT.tag = 'PL' .. tostring(player.UserId) .. '-' .. tostring(math.floor(RT.t0))
    RT.counts = { pick = 0, feed = 0, buy = 0, cast = 0, hooked = 0, landed = 0, dropped = 0, attacks = 0, kills = 0, moves = 0, deaths = 0, flanks = 0, dagger = 0 }
    RT.flanked = {}
    RT.ignore = {}
    RT.catches = {}
    RT.coinLog = {}
    RT.ledgerVer = 2
end
-- 计数口径 v2：feed/buy = 确认到账数，feedTry/buyTry = 尝试数。旧 RT 的 feed/buy 是尝试数，
-- 转存为 legacy 并从 0 起算，不冒充已确认；旧 daggerTries 按尝试累加，同样清零。
if RT.ledgerVer ~= 2 then
    RT.legacy = { feedTry = RT.counts.feed or 0, buyTry = RT.counts.buy or 0, daggerTries = RT.daggerTries or 0 }
    RT.counts.feed, RT.counts.buy, RT.daggerTries, RT.pendingOp = 0, 0, 0, nil
    RT.ledgerVer = 2
end
for _, k in ipairs({ 'pick', 'feed', 'buy', 'cast', 'hooked', 'landed', 'dropped', 'attacks', 'kills', 'moves', 'deaths', 'flanks', 'dagger', 'feedTry', 'buyTry', 'rejected', 'unsettled' }) do RT.counts[k] = RT.counts[k] or 0 end
RT.flanked, RT.ignore = RT.flanked or {}, RT.ignore or {}
RT.unreachableLoot = RT.unreachableLoot or {}
local TAG = RT.tag
local uid = player.UserId

local function say(kind, ...)
    print('PONDLOOP', TAG, string.format('t=%.1f', now() - RT.t0), kind, ...)
end

local function fmt(x) return string.format('%.2f', x) end

local function dataOf() return MgrPlayerData:GetDataInst(player) end

local function coins(data) return data.Data.FishCoin or 0 end
local function worms(data) return data.Data.Bait.worm or 0 end

local function snapshot(reason)
    local data = dataOf()
    if not data then return end
    local c = RT.counts
    say('K', reason, 'coin=' .. tostring(coins(data)), 'worm=' .. tostring(worms(data)),
        'eelHead=' .. data:ItemCount('eelHead'), 'duck=' .. data:ItemCount('duck'),
        'garHead=' .. data:ItemCount('garHead'), 'ticket=' .. data:ItemCount('shrimpTicket'),
        'zone=' .. tostring(data.Data.Zone),
        'pick=' .. c.pick, 'feed=' .. c.feed .. '/' .. c.feedTry, 'buy=' .. c.buy .. '/' .. c.buyTry,
        'rejected=' .. c.rejected, 'unsettled=' .. c.unsettled, 'cast=' .. c.cast,
        'hooked=' .. c.hooked, 'landed=' .. c.landed, 'dropped=' .. c.dropped, 'attacks=' .. c.attacks,
        'ended=' .. c.kills, 'moves=' .. c.moves, 'deaths=' .. c.deaths, 'flanks=' .. c.flanks,
        'dagger=' .. data:WeaponCount(DAGGER.Id), 'equipped=' .. tostring(MgrWeapon:EquippedWeapon(data)),
        RT.legacy and ('legacy{feedTry=' .. RT.legacy.feedTry .. ' buyTry=' .. RT.legacy.buyTry
            .. ' daggerTries=' .. RT.legacy.daggerTries .. ' 未确认}') or 'legacy=none')
end

-- ========== 场景 / 距离 / 站位 ==========
local function flat(a, b)
    local dx, dz = a.x - b.x, a.z - b.z
    return math.sqrt(dx * dx + dz * dz)
end

local function charPos()
    local character = player.Character
    return character and character.Position
end

local zone1 = GameCfg.Zones[1]
local scene1 = zone1.Scene
local chain = GameCfg.Content.Exchanges[1]
local route = GameCfg.Ferry.Routes[1]

-- 站位点：锚点向陆地中心移 STAND_SHIFT 米（锚点本身可能在水或高处，只给 x/z）
local function standPoint(anchorPos)
    local land = scene1.Land
    local cx, cz = (land.MinX + land.MaxX) / 2, (land.MinZ + land.MaxZ) / 2
    local dx, dz = cx - anchorPos.x, cz - anchorPos.z
    local len = math.sqrt(dx * dx + dz * dz)
    if len < 0.01 then return { x = anchorPos.x, z = anchorPos.z } end
    local k = math.min(STAND_SHIFT, len) / len
    return { x = anchorPos.x + dx * k, z = anchorPos.z + dz * k }
end

local function anchorPos(name)
    local unit = MgrInteract:FindAnchor(name)
    return unit and unit.Position
end

local function pause(reason, point, label)
    if point then
        say('MOVE', label or reason, fmt(point.x), fmt(point.z),
            '(y 取地面 ≈5；用 input move-to 走到该点后重新执行本文件)')
        print('PONDLOOP-MOVE', TAG, fmt(point.x), fmt(point.z), label or reason)
    else
        say('PAUSE', reason)
    end
    snapshot('pause')
    return 'pause'
end

local function inRangeOf(names, radius, slack)
    return MgrInteract:InRange(player, { AnchorNames = names, Radius = radius, Slack = slack })
end

-- 去某个 NPC 锚点：不在范围内返回 pause，在范围内返回 nil
local function needNear(names, radius, slack, label)
    if inRangeOf(names, radius, slack) then return nil end
    local pos
    for _, name in ipairs(names) do pos = pos or anchorPos(name) end
    if not pos then return pause('锚点缺失 ' .. names[1]) end
    return pause(label, standPoint(pos), label)
end

-- ========== 库存辅助 ==========
local function itemBar(data) return data.Data.Containers[GameCfg.Items.ContainerId.ItemBar] end

local function slotOf(data, predicate)
    for slot, entry in pairs(itemBar(data)) do
        if entry.count and entry.count > 0 and predicate(entry) then return slot, entry end
    end
end

local function isRodEntry(entry)
    local def = GameCfg.Items.Definitions[entry.itemId]
    return def and type(def.Level) == 'number'
end

local function rodSlot(data)
    return slotOf(data, function(entry)
        local def = GameCfg.Items.Definitions[entry.itemId]
        return def and type(def.Level) == 'number'
    end)
end

local ids = GameCfg.Items.ContainerId

local function freeSlots(data)
    local free = 0
    for _, c in ipairs({ { ids.ItemBar, data:ItemBarCapacity() }, { ids.Backpack, data:BackpackCapacity() } }) do
        local items = data.Data.Containers[c[1]]
        for i = 1, c[2] do
            local e = items[i]
            if not e or e.count <= 0 then free = free + 1 end
        end
    end
    return free
end

-- 道具栏 + 背包里找物品：返回 容器id, 格号, 条目
local function findEntry(data, predicate)
    local slot, entry = slotOf(data, predicate)
    if slot then return ids.ItemBar, slot, entry end
    local bp = data.Data.Containers[ids.Backpack]
    for i = 1, data:BackpackCapacity() do
        local e = bp[i]
        if e and e.count > 0 and predicate(e) then return ids.Backpack, i, e end
    end
end

local function hasRod(data) return (findEntry(data, isRodEntry)) ~= nil end

local KEEP = { duck = true, eelHead = true, garHead = true, shrimpTicket = true }
local function keepOnBar(entry)
    local def = GameCfg.Items.Definitions[entry.itemId]
    return KEEP[entry.itemId] or (def and type(def.Level) == 'number')
end

-- 保证物品在道具栏（选中/挂饵/喂食只认道具栏）：返回 格号；换格后返回 'moved'；失败返回 nil, 原因。
-- 背包→道具栏先 MoveToItemBar（找空格）；道具栏满则用 MoveSlot 与一个非关键格互换（该格进背包，不丢物品）。
local function ensureOnBar(data, predicate)
    local c, i = findEntry(data, predicate)
    if not c then return nil, 'missing' end
    if c == ids.ItemBar then return i end
    if data:MoveToItemBar(i) then
        RT.counts.moves = RT.counts.moves + 1
        say('MOVE-SLOT', 'MoveToItemBar', 'backpack#' .. i)
        MgrPlayerData:SendItemBar(player)
        return 'moved'
    end
    local bar = itemBar(data)
    for s = 1, data:ItemBarCapacity() do
        local e = bar[s]
        if e and e.count > 0 and not keepOnBar(e) then
            if data:MoveSlot(ids.Backpack, i, ids.ItemBar, s) then
                RT.counts.moves = RT.counts.moves + 1
                say('MOVE-SLOT', 'MoveSlot swap', 'backpack#' .. i .. ' <-> bar#' .. s, 'out=' .. tostring(e.itemId))
                MgrPlayerData:SendItemBar(player)
                return 'moved'
            end
        end
    end
    return nil, 'bar-full'
end

-- SelectSlot 是开关：已选中再选会取消，所以只在需要切换时调
local function focus(data, slot)
    if slot == nil then
        if data.Data.SelectedSlot ~= nil then data:SelectSlot(data.Data.SelectedSlot) end
    elseif data.Data.SelectedSlot ~= slot then
        data:SelectSlot(slot)
    end
    MgrPlayerData:SendItemBar(player)
end

local function nextSeq(mgr) return ((mgr.LastSeq[uid]) or 0) + 1 end

-- ========== 交易落账观测 ==========
-- Handle 返回 true 只表示请求被接受，结果随 Save:Execute 异步落账。feed/buy 计确认到账数，feedTry/buyTry 计尝试数；
-- accepted=false 只记 rejected，不进 pendingOp、不算未到账。pendingOp 记发出前 coin/worm/weapon/rod/所选物品数量，
-- 等 data.Inited 且 Save 未暂停后按 settledBy 分种类判定：满足记到账（SETTLED），超时仍不满足记 unsettled。
local SETTLE_TIMEOUT_SEC = 8
local PENDING_KIND = { feed = 'feed', rod = 'buy', dagger = 'buy' }

local function selectedItem(data)
    local slot = data.Data.SelectedSlot
    local entry = slot and itemBar(data)[slot]
    return entry and entry.count and entry.count > 0 and entry.itemId or nil
end

local function ledger(data, itemId)
    return { coin = coins(data), worm = worms(data), weapon = data:WeaponCount(DAGGER.Id),
        rod = hasRod(data) and 1 or 0, item = itemId and data:ItemCount(itemId) or 0,
        duck = data:ItemCount(chain.BossBait), ticket = data:ItemCount(chain.Result) }
end

local function ledgerText(l)
    return 'coin=' .. l.coin .. ' worm=' .. l.worm .. ' weapon=' .. l.weapon .. ' rod=' .. l.rod .. ' item=' .. l.item
        .. ' duck=' .. l.duck .. ' ticket=' .. l.ticket
end

-- 按交易种类判定到账：买竿要 rod 增加；买匕首要 weapon 增加；
-- 喂食要（所选物品减少或 worm 减少）且（金币增加或兑换目标 duck/ticket 增加）。兑换头时金币可能不变。
local function settledBy(kind, b, a)
    if kind == 'rod' then return a.rod > b.rod end
    if kind == 'dagger' then return a.weapon > b.weapon end
    local paid = a.item < b.item or a.worm < b.worm
    local got = a.coin > b.coin or a.duck > b.duck or a.ticket > b.ticket
    return paid and got
end

local function savePaused()
    for _, mgr in ipairs({ MgrInteract, MgrShop }) do
        if mgr.Save and mgr.Save:IsPaused(uid) then return true end
    end
    return false
end

-- 发出请求后调用：计尝试；accepted 才登记 pendingOp
local function beginOp(kind, label, data, accepted, itemId, before)
    local tryKey = PENDING_KIND[kind] .. 'Try'
    RT.counts[tryKey] = RT.counts[tryKey] + 1
    if not accepted then
        RT.counts.rejected = RT.counts.rejected + 1
        say('REJECT', kind, label, ledgerText(before))
        return
    end
    RT.pendingOp = { kind = kind, label = label, itemId = itemId, before = before, at = now() }
end

-- 放行后核对：返回 nil 表示无待核对或已结清，返回 'wait', 秒 表示仍在等
local function settleOp(data)
    local op = RT.pendingOp
    if not op then return nil end
    local after = ledger(data, op.itemId)
    local b = op.before
    local settled = settledBy(op.kind, b, after)
    local age = now() - op.at
    if not settled and age < SETTLE_TIMEOUT_SEC then return 'wait', 0.3 end
    RT.pendingOp = nil
    local countKey = PENDING_KIND[op.kind]
    if settled then
        RT.counts[countKey] = RT.counts[countKey] + 1
        if op.kind == 'dagger' then RT.daggerTries = 0 end
        say('SETTLED', op.kind, op.label, string.format('sec=%.1f', age),
            'before{' .. ledgerText(b) .. '}', 'after{' .. ledgerText(after) .. '}')
        snapshot('settled-' .. op.kind)
    else
        RT.counts.unsettled = RT.counts.unsettled + 1
        if op.kind == 'dagger' then RT.daggerTries = (RT.daggerTries or 0) + 1 end
        say('UNSETTLED', op.kind, op.label, string.format('sec=%.1f', age),
            'before{' .. ledgerText(b) .. '}', 'after{' .. ledgerText(after) .. '}')
    end
    return nil
end

-- ========== 各类意图 ==========
local function nearestBait(pos)
    local best, bd
    for _, loot in pairs(MgrLoot.Loots) do
        if loot.Kind == 'bait' and loot.ItemId == 'worm' then
            local d = flat(pos, loot.Position)
            if not bd or d < bd then best, bd = loot, d end
        end
    end
    return best, bd
end

local function pickBait()
    local pos = charPos()
    if not pos then return pause('角色不可用') end
    local loot, d = nearestBait(pos)
    if not loot then
        say('WAIT', '场上暂无蚯蚓，等刷新', 'respawnSec=' .. GameCfg.BaitSpots.RespawnSec)
        return 'wait', GameCfg.BaitSpots.RespawnSec
    end
    local reach = GameCfg.Loot.PickupRadius + (GameCfg.Loot.PickupSlack or 0)
    if d > reach then
        return pause('拾饵', { x = loot.Position.x, z = loot.Position.z }, '拾饵 spot=' .. tostring(loot.SpotId))
    end
    if MgrLoot:Pickup(player, loot.Id) then
        RT.counts.pick = RT.counts.pick + 1
        say('PICK', 'worm', 'spot=' .. tostring(loot.SpotId), 'loot=' .. tostring(loot.Id))
        snapshot('pick')
    end
    return 'wait', 0.3
end

local function feed(data, label)
    local wait = needNear(GameCfg.Interact.Fishermen[1].AnchorNames,
        GameCfg.Interact.Fisherman.Radius, GameCfg.Interact.Fisherman.Slack, '喂食钓鱼佬 ' .. label)
    if wait then return wait end
    local itemId = selectedItem(data)
    local before = ledger(data, itemId)
    local ok = MgrInteract:Handle(player, { target = 'fisherman', action = 'Feed', seq = nextSeq(MgrInteract) })
    say('FEED', label, 'accepted=' .. tostring(ok), 'item=' .. tostring(itemId), ledgerText(before))
    beginOp('feed', label, data, ok, itemId, before)
    return 'wait', SETTLE_SEC
end

local function buyRod(data)
    local stand = GameCfg.Shop.Stands[1]
    local wait = needNear({ stand.AnchorName }, GameCfg.Shop.Radius, GameCfg.Shop.Slack, '钓场商店买竿')
    if wait then return wait end
    local before = ledger(data)
    local ok = MgrShop:Handle(player, { action = 'Buy', itemId = 'starterRod', seq = nextSeq(MgrShop) })
    say('BUY', 'starterRod', 'accepted=' .. tostring(ok), ledgerText(before))
    beginOp('rod', 'starterRod', data, ok, nil, before)
    return 'wait', SETTLE_SEC
end

local function daggerPrice()
    local goods = MgrShop:FindGoodsByNumber(DAGGER.Number, DAGGER.MinLevel)
    return goods and goods.Price
end

local function buyDagger(data)
    RT.daggerTries = RT.daggerTries or 0
    if RT.daggerTries >= 3 then return pause('匕首购买连续 3 次未到账，检查商店回包/日志') end
    local stand = GameCfg.Shop.Stands[1]
    local wait = needNear({ stand.AnchorName }, GameCfg.Shop.Radius, GameCfg.Shop.Slack, '钓场商店买匕首')
    if wait then return wait end
    local before = ledger(data)
    local ok = MgrShop:Handle(player, { action = 'Buy', number = DAGGER.Number, seq = nextSeq(MgrShop) })
    say('BUY', 'dagger#' .. DAGGER.Number, 'accepted=' .. tostring(ok), ledgerText(before), 'price=' .. tostring(daggerPrice()))
    -- daggerTries 只在 accepted 且超时未到账时由 settleOp 累加，到账后清零
    beginOp('dagger', 'dagger#' .. DAGGER.Number, data, ok, nil, before)
    return 'wait', SETTLE_SEC
end

-- 装备匕首：SelectWeapon 是开关，只在未选中时调；EquippedWeapon 复核，被别的手持武器压住时才用 HoldWeapon 切换
local function equipDagger(data)
    if MgrWeapon:EquippedWeapon(data) == DAGGER.Id then return true end
    if data.Data.SelectedWeapon ~= DAGGER.Id then data:SelectWeapon(DAGGER.Id) end
    if MgrWeapon:EquippedWeapon(data) ~= DAGGER.Id then
        local held = data.Extra.inventory.selection.held
        if held.kind == 'weapon' and held.id ~= DAGGER.Id then data:HoldWeapon(DAGGER.Id) end
    end
    MgrPlayerData:SendItemBar(player)
    local ok = MgrWeapon:EquippedWeapon(data) == DAGGER.Id
    RT.counts.dagger = RT.counts.dagger + 1
    say('EQUIP', DAGGER.Id, 'equipped=' .. tostring(MgrWeapon:EquippedWeapon(data)), 'ok=' .. tostring(ok))
    return ok
end

-- 真实管理器字段与调用签名校验：缺任何一个就暂停并列出，避免带着错误假设空转
local function validate(data)
    local missing = {}
    local function need(label, ok) if not ok then missing[#missing + 1] = label end end
    local function fn(label, mod, name) need(label .. name, type(mod) == 'table' and type(mod[name]) == 'function') end
    fn('MgrPlayerData:', MgrPlayerData, 'GetDataInst') fn('MgrPlayerData:', MgrPlayerData, 'SendItemBar')
    fn('MgrLoot:', MgrLoot, 'Pickup') need('MgrLoot.Loots', type(MgrLoot.Loots) == 'table')
    for _, name in ipairs({ 'Handle', 'InRange', 'FindAnchor' }) do fn('MgrInteract:', MgrInteract, name) end
    fn('MgrShop:', MgrShop, 'Handle') fn('MgrShop:', MgrShop, 'FindGoodsByNumber')
    for _, name in ipairs({ 'Cast', 'Reel', 'Drop' }) do fn('MgrCast:', MgrCast, name) end
    need('MgrCast.Sessions', type(MgrCast.Sessions) == 'table')
    fn('MgrReelIn:', MgrReelIn, 'Accept')
    need('MgrFishUnit.Fish', type(MgrFishUnit.Fish) == 'table')
    fn('MgrWeapon:', MgrWeapon, 'Attack') fn('MgrWeapon:', MgrWeapon, 'EquippedWeapon')
    fn('MgrFerry:', MgrFerry, 'Handle')
    for _, m in ipairs({ { 'MgrInteract', MgrInteract }, { 'MgrShop', MgrShop }, { 'MgrFerry', MgrFerry } }) do
        need(m[1] .. '.LastSeq', type(m[2].LastSeq) == 'table')
    end
    for _, name in ipairs({ 'SelectSlot', 'SelectBait', 'SelectWeapon', 'HoldWeapon', 'MoveSlot', 'MoveToItemBar',
        'ItemCount', 'WeaponCount', 'GetItemBarSnapshot', 'ItemBarCapacity', 'BackpackCapacity' }) do
        need('data:' .. name, type(data[name]) == 'function')
    end
    need('data.Data.Containers', type(data.Data.Containers) == 'table' and type(data.Data.Containers[ids.ItemBar]) == 'table'
        and type(data.Data.Containers[ids.Backpack]) == 'table')
    need('data.Data.Weapons', type(data.Data.Weapons) == 'table')
    need('data.Data.Bait', type(data.Data.Bait) == 'table')
    need('data.Extra.inventory.selection.held', type(data.Extra) == 'table' and type(data.Extra.inventory) == 'table'
        and type(data.Extra.inventory.selection) == 'table' and type(data.Extra.inventory.selection.held) == 'table')
    local goods = type(MgrShop.FindGoodsByNumber) == 'function' and MgrShop:FindGoodsByNumber(DAGGER.Number, DAGGER.MinLevel)
    need('商店编号 25 = item135', goods and goods.ItemId == DAGGER.Id and type(goods.Price) == 'number')
    need('GameCfg.Ability.MeleeWeapons.item135', GameCfg.Ability.MeleeWeapons and GameCfg.Ability.MeleeWeapons[DAGGER.Id] ~= nil)
    need('GameCfg.Ability.Unarmed', GameCfg.Ability.Unarmed ~= nil)
    local vitals = MgrWeapon.Vitals
    need('MgrWeapon.Vitals:LifeStatus/CanAct', vitals and type(vitals.LifeStatus) == 'function' and type(vitals.CanAct) == 'function')
    if #missing > 0 then
        say('CHECK-FAIL', table.concat(missing, ' | '))
        return false
    end
    say('CHECK', 'ok', 'dagger.price=' .. tostring(goods.Price),
        'bar=' .. data:ItemBarCapacity(), 'backpack=' .. data:BackpackCapacity(), 'free=' .. freeSlots(data))
    return true
end

-- 抛竿落点预判：与 MgrCast.castLanding 同公式，只用于决定是否提示走位
local function predictLanding()
    local character = player.Character
    if not character or not character.Position or not character.Rotation then return nil end
    local forward = character.Rotation:GetForward()
    local len = math.sqrt(forward.x * forward.x + forward.z * forward.z)
    if len < 0.01 then return nil end
    local x = character.Position.x + GameCfg.Casting.Distance * forward.x / len
    local z = character.Position.z + GameCfg.Casting.Distance * forward.z / len
    for _, water in ipairs(GameCfg.Water.Zones) do
        if MathWaterJudge.InZone(water, { x = x, y = water.SurfaceY, z = z }) then return water, x, z end
    end
    return nil, x, z
end

local function castRod(data, useDuck)
    local function isRod(entry)
        local def = GameCfg.Items.Definitions[entry.itemId]
        return def and type(def.Level) == 'number'
    end
    local slot, why = ensureOnBar(data, isRod)
    if slot == 'moved' then return 'wait', 0.4 end
    if not slot then return pause('鱼竿不在道具栏: ' .. tostring(why)) end
    local entry = itemBar(data)[slot]
    focus(data, slot)
    local bait = useDuck and 'duck' or 'worm'
    if useDuck then
        local duckSlot, duckWhy = ensureOnBar(data, function(e) return e.itemId == 'duck' end)
        if duckSlot == 'moved' then return 'wait', 0.4 end
        if not duckSlot then return pause('鸭子饵不在道具栏: ' .. tostring(duckWhy)) end
    end
    if data.Data.SelectedBait ~= bait then
        if not data:SelectBait(bait) then return pause('无法挂饵 ' .. bait) end
        MgrPlayerData:SendItemBar(player)
    end
    local water, lx, lz = predictLanding()
    if not water then
        return pause('落点不在水里(' .. (lx and (fmt(lx) .. ',' .. fmt(lz)) or 'nil') .. ')，站到抛竿位并朝 -x 走入',
            CAST_SPOT, '抛竿位（面朝 -x）')
    end
    MgrCast:Cast(player, { action = 'Cast', slot = slot, itemId = entry.itemId })
    RT.counts.cast = RT.counts.cast + 1
    say('CAST', 'bait=' .. bait, 'water=' .. tostring(water.Id))
    return 'wait', 0.4
end

local function reelClick(current)
    local session = current.session
    if RT.reelFor ~= session.reelSession then RT.reelFor, RT.reelQ = session.reelSession, 0 end
    RT.reelQ = RT.reelQ + 1
    MgrReelIn:Accept(player, { s = session.reelSession, n = 2, q = RT.reelQ })
end

-- ========== 鱼与战利品 ==========
-- held：举着的鱼；live：存活的目标鱼（电鳗/鳄雀鳝）优先，否则是逃跑中的普通鱼（击杀卖钱）
local function myFish()
    local held, live, prey
    for _, fish in pairs(MgrFishUnit.Fish) do
        if fish.Owner == player or fish.Holder == player then
            if fish.State == 'held' then held = fish
            elseif fish.FishId == chain.EliteFish or fish.FishId == chain.BossFish then live = live or fish
            elseif not RT.ignore[fish.Id] then prey = prey or fish end
        end
    end
    return held, live or prey
end

-- 当前武器射程/间隔（与 MgrWeapon.AttackMelee 同表）
local function weaponStats(data)
    local id = MgrWeapon:EquippedWeapon(data)
    local mcfg = id and GameCfg.Ability.MeleeWeapons[id] or GameCfg.Ability.Unarmed
    return mcfg.Range, mcfg.IntervalSec
end

local function fishPos(fish)
    local ok, p = pcall(function() return fish.Carrier.Body.Position end)
    return ok and p or nil
end

local function isTarget(fishId) return fishId == chain.EliteFish or fishId == chain.BossFish end

-- 可捡/可卖的鱼获：所有鱼的掉落（普通鱼整鱼卖金币，电鳗鳄雀鳝的肉与头）
local dropIds = {}
for _, species in pairs(GameCfg.Fish) do
    for _, drop in ipairs(species.Drops or {}) do dropIds[drop.ItemId] = true end
end

-- 战斗站位：鱼的正前方是咬/放电方向；绕后点 = 鱼身后 max(1, range-0.8) 米
local function flankPoint(fish, range)
    local p = fishPos(fish)
    if not p then return nil end
    local fx, fz
    pcall(function() local f = fish.Carrier.Body.Rotation:GetForward() fx, fz = f.x, f.z end)
    if not fx and fish.Heading then fx, fz = fish.Heading.x, fish.Heading.z end
    local len = fx and math.sqrt(fx * fx + fz * fz) or 0
    if len < 0.01 then return nil end
    fx, fz = fx / len, fz / len
    local d = math.max(1.0, range - 0.8)
    return { x = p.x - fx * d, z = p.z - fz * d }, fx, fz, p
end

local function pickDrops()
    local pos = charPos()
    if not pos then return nil end
    local best, bd
    for _, loot in pairs(MgrLoot.Loots) do
        if loot.Kind ~= 'bait' and dropIds[loot.ItemId] and not RT.unreachableLoot[loot.Id] then
            local d = flat(pos, loot.Position)
            if not bd or d < bd then best, bd = loot, d end
        end
    end
    if not best then return nil end
    local reach = GameCfg.Loot.PickupRadius + (GameCfg.Loot.PickupSlack or 0)
    if bd <= reach and freeSlots(dataOf()) == 0 then
        -- 满包：Pickup 会失败。先把可卖的整理上道具栏喂掉腾格；没有可卖的就暂停交给玩家丢弃/整理
        local slot, why = ensureOnBar(dataOf(), function(e) return dropIds[e.itemId] end)
        if slot == 'moved' then return 'wait', 0.4 end
        if slot then focus(dataOf(), slot) return feed(dataOf(), 'full-bag sell') end
        return pause('背包与道具栏已满且没有可卖鱼获(' .. tostring(why) .. ')，请手动整理后重跑')
    end
    if bd > reach then
        return pause('拾取鱼获', { x = best.Position.x, z = best.Position.z }, '拾取鱼获 ' .. best.ItemId)
    end
    if MgrLoot:Pickup(player, best.Id) then
        RT.counts.pick = RT.counts.pick + 1
        say('PICK', best.ItemId, 'loot=' .. tostring(best.Id))
        local fishDef = GameCfg.Fish[best.ItemId]
        if fishDef and fishDef.Grade == 'rare' then
            local _, _, entry = findEntry(dataOf(), function(e) return e.itemId == best.ItemId end)
            local eligible, reason = require('common.LotteryEligibility').Check(entry)
            say('LOTTERY', best.ItemId, 'eligible=' .. tostring(eligible), 'reason=' .. tostring(reason))
        end
        snapshot('loot')
    end
    return 'wait', 0.4
end

-- ========== 主状态机：每步只做一件事，返回 'wait',秒 / 'pause' / 'done' ==========
local function step()
    local data = dataOf()
    if not data then return 'wait', 0.3 end
    if GameCfg.Debug.Enabled then return pause('Debug.Enabled=true，请用 Debug=false 的新验收槽') end
    if not RT.checked then
        if not validate(data) then return 'pause' end
        RT.checked = true
    end

    -- 死亡免费恢复：倒地 15s → 死亡 30s → 原地弱复活（10% 血、半速）。只等待，不治疗不传送；
    -- 复活后继续正常拾饵、喂食；饥饿仍为零时静等会再次饿死，不用等待代替恢复。
    local vitals = MgrWeapon.Vitals
    local life = vitals and vitals:LifeStatus(player) or 'alive'
    if life == 'downed' or life == 'dead' then
        if not RT.lifeSince then
            RT.lifeSince = now()
            RT.counts.deaths = RT.counts.deaths + 1
            RT.combatSince = nil
            say('DEATH', life, '等待原地弱复活（免费），不治疗不传送')
            snapshot('death')
        elseif RT.lastLife ~= life then
            say('LIFE', life)
        end
        RT.lastLife = life
        return 'wait', 2
    elseif RT.lifeSince then
        say('REVIVE', string.format('downSec=%.1f', now() - RT.lifeSince), '弱复活，继续正常补给')
        RT.recoverUntil = nil
        RT.lifeSince, RT.lastLife = nil, nil
        snapshot('revive')
    end
    if not charPos() then return pause('角色不可用（重生中）') end
    if not data.Inited or savePaused() then
        return 'wait', 0.3
    end
    -- 存档放行后先核对上一笔 feed/buy 是否到账，结清前不发起新动作
    local settleWait, settleSecs = settleOp(data)
    if settleWait then return settleWait, settleSecs end
    -- 与 ItemBarAction.EatBait 相同的库存扣除与食用入口，低饥饿时正常吃蚯蚓续命。
    local hunger = player:GetAttribute('Hunger')
    local _, combatFish = myFish()
    if type(hunger) == 'number' and hunger < 30 then
        if worms(data) < 1 then
            if combatFish then return 'wait', 0.5 end
            return pickBait()
        end
        local v = MgrPlayerData.Vitals
        if v:CanEat(player, 'worm') and data:EatBait('worm') then
            v:Eat(player, 'worm')
            MgrPlayerData:SendItemBar(player)
            say('EAT', 'worm', 'hungerBefore=' .. hunger)
            return 'wait', 0.3
        end
        return 'wait', 0.5
    end
    if data:WeaponCount(DAGGER.Id) >= 1 and not equipDagger(data) then
        return pause('匕首已买到但装备失败，见 EQUIP 日志')
    end
    if RT.pendingUntil and now() < RT.pendingUntil then return 'wait', 0.3 end

    -- 0 摆渡：有船票就去 FerryBoat（航线 1），到达虾池即闭环完成
    if data.Data.Zone ~= zone1.Id then
        say('DONE', '已到达', tostring(data.Data.Zone))
        snapshot('done')
        return 'done'
    end
    if data:ItemCount('shrimpTicket') >= 1 then
        focus(data, nil)
        local wait = needNear({ route.Outbound.AnchorName }, route.Outbound.Radius, route.Outbound.Slack, '摆渡上船')
        if wait then return wait end
        local ok = MgrFerry:Handle(player, { action = 'Board', routeId = route.Id, seq = nextSeq(MgrFerry) })
        say('FERRY', 'Board accepted=' .. tostring(ok))
        RT.pendingUntil = now() + route.Outbound.CountdownSec + 2
        return 'wait', 1
    end

    -- 1 鱼的处理：举着的鱼放下（目标鱼放下后打，其余任其逃脱）；存活目标鱼持续攻击
    local held, live = myFish()
    if held then
        local landedSession = MgrCast.Sessions[uid]
        local rs = landedSession and landedSession.session
        if rs and rs.phase == 'landed' and RT.landedFor ~= rs.reelSession then
            RT.landedFor = rs.reelSession
            RT.counts.landed = RT.counts.landed + 1
            RT.catches[#RT.catches + 1] = rs.fishId
            say('LAND', rs.fishId, 'mult=' .. tostring(rs.mult))
        end
        local target = isTarget(held.FishId)
        if target and type(hunger) == 'number' and hunger < 180 then
            if worms(data) < 1 then return pickBait() end
            local v = MgrPlayerData.Vitals
            if v:CanEat(player, 'worm') and data:EatBait('worm') then
                v:Eat(player, 'worm')
                MgrPlayerData:SendItemBar(player)
                say('EAT', 'worm', '战前补给', 'hungerBefore=' .. hunger)
            end
            return 'wait', 0.3
        end
        if flat(charPos(), LAND_STAND) > 1 then
            return pause('先把鱼带到陆地再放下', LAND_STAND, '陆地放鱼 ' .. held.FishId)
        end
        MgrCast:Drop(player)
        RT.combatSince = now()
        if target then
            say('DROP', 'target', held.FishId)
            return 'wait', 0.6
        end
        -- 普通鱼放下即逃（EscapeSec 很短）：不等，立刻挥击，击杀掉落整鱼卖钱攒匕首
        RT.counts.dropped = RT.counts.dropped + 1
        say('DROP', 'prey', held.FishId, 'weapon=' .. tostring(MgrWeapon:EquippedWeapon(data)))
        RT.counts.attacks = RT.counts.attacks + 1
        MgrWeapon:Attack(player)
        return 'wait', 0.3
    end
    if live then
        RT.combatSince = RT.combatSince or now()
        local range, interval = weaponStats(data)
        local p, me = fishPos(live), charPos()
        local dist = p and me and flat(p, me) or nil
        local isBoss = isTarget(live.FishId)
        if isBoss and data:WeaponCount(DAGGER.Id) < 1 then
            if not RT.ignore[live.Id] then
                RT.ignore[live.Id] = true
                say('EARLY-BOSS', live.FishId, '尚无匕首，正常退开等待逃跑，不挑战')
                return pause('提前钓到首领，先安全退开', { x = 5, z = 40 }, '安全退开 ' .. live.FishId)
            end
            return 'wait', 1
        end
        if not isBoss then
            -- 普通鱼：只在射程附近挥击；跑远或超过 8 秒就放弃（不追、不传送），不影响主流程
            if now() - RT.combatSince > 8 or (dist and dist > range + 6) then
                RT.ignore[live.Id] = true
                say('PREY-LOST', live.FishId, 'dist=' .. (dist and fmt(dist) or 'nil'))
                return 'wait', 0.3
            end
        elseif p and (not RT.flanked[live.Id]
            or (live.FishId == chain.BossFish and live.BiteAim
                and RT.flanked[live.Id] ~= live.BiteAim.StrikeAt)) then
            -- 鳄雀鳝每口重新锁定，按本口结算时刻重新提示走位。
            RT.flanked[live.Id] = live.BiteAim and live.BiteAim.StrikeAt or true
            local pt, fx, fz = flankPoint(live, range)
            if pt and me then
                local mx, mz = me.x - p.x, me.z - p.z
                local ml = math.sqrt(mx * mx + mz * mz)
                local front = ml > 0.01 and (fx * mx + fz * mz) / ml or 1
                RT.counts.flanks = RT.counts.flanks + 1
                say('FLANK', live.FishId, 'front=' .. fmt(front), 'state=' .. tostring(live.State))
                if front > 0.3 then
                    return pause('战斗：你在 ' .. live.FishId .. ' 正前方，先绕后再打', pt, '绕后 ' .. live.FishId)
                end
            end
        end
        if not dist or dist <= range + 1.5 then
            RT.counts.attacks = RT.counts.attacks + 1
            MgrWeapon:Attack(player)
        elseif isBoss and now() - RT.combatSince > 5 then
            say('COMBAT', live.FishId, 'state=' .. tostring(live.State), 'dist=' .. fmt(dist),
                'fish@' .. fmt(p.x) .. ',' .. fmt(p.z))
            if now() - RT.combatSince > COMBAT_WAIT_SEC then
                local pt = flankPoint(live, range) or { x = p.x, z = p.z }
                return pause('战斗超时/太远', pt, '靠近(绕后) ' .. live.FishId)
            end
        end
        return 'wait', interval + 0.05
    end
    if RT.combatSince then
        RT.combatSince = nil
        RT.counts.kills = RT.counts.kills + 1
        snapshot('kill-or-end')
    end

    -- 2 鱼获：先捡掉落，再按链喂食（电鳗头→鸭子；鳄雀鳝头→船票），肉也一并卖成金币
    local waitLoot, secs = pickDrops()
    if waitLoot then return waitLoot, secs end
    for _, itemId in ipairs({ chain.BossToken, chain.EliteToken }) do
        local slot = ensureOnBar(data, function(entry) return entry.itemId == itemId end)
        if slot == 'moved' then return 'wait', 0.4 end
        if slot then
            focus(data, slot)
            local w, s = feed(data, itemId)
            return w, s
        end
    end
    -- 鱼肉/整鱼卖成金币（攒匕首价与后续开销）
    local meatSlot = ensureOnBar(data, function(entry) return dropIds[entry.itemId] end)
    if meatSlot == 'moved' then return 'wait', 0.4 end
    if meatSlot then focus(data, meatSlot) return feed(data, 'fish/meat') end

    -- 3 有首领饵就必钓首领
    local hasDuck = data:ItemCount(chain.BossBait) >= 1
    local session = MgrCast.Sessions[uid]
    if session then
        local phase = session.session.phase
        if phase == 'hooked' then
            if RT.hookedFor ~= session.session.reelSession then
                RT.hookedFor = session.session.reelSession
                RT.counts.hooked = RT.counts.hooked + 1
                say('HOOK', session.session.fishId)
            end
            reelClick(session)
            return 'wait', CLICK_SEC
        elseif phase == 'landed' then
            if RT.landedFor ~= session.session.reelSession then
                RT.landedFor = session.session.reelSession
                RT.counts.landed = RT.counts.landed + 1
                RT.catches[#RT.catches + 1] = session.session.fishId
                say('LAND', session.session.fishId, 'mult=' .. tostring(session.session.mult))
                snapshot('land')
            end
            return 'wait', 0.5
        elseif phase == 'unhooked' then
            MgrCast:Reel(player)
            say('REEL-IN', 'unhooked 收竿')
            return 'wait', 0.4
        end
        return 'wait', STEP_SEC  -- cast 相位等上钩
    end

    -- 3.5 成长：无匕首且金币够价（普通鱼卖来的）→ 去商店买；买到后由 equipDagger 装备
    if data:WeaponCount(DAGGER.Id) < 1 and hasRod(data) and (coins(data) >= (daggerPrice() or math.huge)) then
        focus(data, nil)
        return buyDagger(data)
    end

    -- 空手追鱼失败时仍可用免费蚯蚓正常喂食攒匕首，保留两只供补给与抛竿。
    if data:WeaponCount(DAGGER.Id) < 1 and hasRod(data) then
        if worms(data) <= 2 then RT.growthGather = true end
        if RT.growthGather then
            if worms(data) < WORM_TARGET then return pickBait() end
            RT.growthGather = nil
        end
        focus(data, nil)
        data:SelectBait('worm')
        return feed(data, 'worm 成长')
    end

    -- 4 无鱼竿：够钱买竿，否则把蚯蚓喂成金币，再不够就捡蚯蚓
    if not hasRod(data) then
        if coins(data) >= 5 then focus(data, nil) return buyRod(data) end
        if worms(data) >= 1 then
            focus(data, nil)
            data:SelectBait('worm')
            return feed(data, 'worm')
        end
        return pickBait()
    end

    -- 5 有竿：抛竿（缺饵先捡）
    if not hasDuck then
        if worms(data) < 1 and RT.wormGoal == nil then RT.wormGoal = WORM_TARGET end
        if RT.wormGoal then
            if worms(data) < RT.wormGoal then return pickBait() end
            RT.wormGoal = nil
        end
    end
    local w, s = castRod(data, hasDuck)
    return w, s
end

-- ========== 异步驱动 ==========
Task:Spawn(function()
    say('START', 'Debug.Enabled=' .. tostring(GameCfg.Debug.Enabled), 'zone=' .. tostring(dataOf() and dataOf().Data.Zone))
    snapshot('start')
    local lastKind = nil
    while RT.token == myToken do
        local ok, status, secs = pcall(step)
        if not ok then
            say('ERROR', tostring(status))
            snapshot('error')
            break
        end
        if status == 'pause' or status == 'done' then break end
        lastKind = status
        Task:Wait(secs or STEP_SEC)
    end
    if RT.token ~= myToken then say('STOP', '被新一次执行取代') end
end)

return 'pond_loop_runtime started ' .. TAG

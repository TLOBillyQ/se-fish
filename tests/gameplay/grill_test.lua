-- #137 T16 烧烤：服务端曲线计时、取出结算、烤糊伤害与会话恢复
-- （common/GrillCurve.lua + server/Mgr/MgrGrill.lua + GameCfg.Grill）。
-- 数值来源：策划案--渔力全开.docx 烧烤段与 issue #137 验收（0/2/2.5/4.5 秒边界、
-- 烤糊 3 米 30 伤害、信物烤前提示、按玩家独立会话、关闭/死亡/断线/满格不复制不吞物）。
-- 失败方式（先列后写）：
--   1. 曲线：0/2/2.5/4.5 秒边界倍率错；按帧累加导致快慢帧收益不同（必须按服务器时刻一次算）；
--   2. 烤糊：4.5 秒不到就糊 / 到了不糊；糊两次（重复损毁、重复爆炸）；爆炸漏掉 3 米内或误伤
--      3 米外；伤害绕过 MgrVitals 统一入口（NewHit/ApplyHit）；
--   3. 会话：两玩家互相取到对方烤鱼；无会话能取出物品；取出后还能再取（复制）；烤糊后还能取；
--   4. 结算：关闭/死亡/断线时物品丢失或复制；满格取出吞掉可取回物；重进后倍率丢失；
--   5. 资格：烤过的鱼还能再烤；烤过信物还能兑换/抽奖（#138 守卫）；信物未经提示直接开烤；
--   6. 价格/恢复：烤过的鱼不按当时倍率出价；吃不按倍率恢复；倍率 <1 的存档被 Migrate 拒收。
-- 接缝：GrillCurve.Rate 纯函数、GameCfg.Grill 配置值、MgrGrill 管理器（注入 Vitals/PlayerData/
-- Save/Loot 替身 + 内存 DataStore）、PlayerData 存档字段（k 倍率往返）、server/main.lua 接线断言。
local lu = require('luaunit')
local GameCfg = require('common.GameCfg')

TestGrillConfig = {}

-- 配置值对齐策划案/docx 与 issue #137 验收
function TestGrillConfig:test_values_match_design_doc()
    local cfg = GameCfg.Grill
    lu.assertNotNil(cfg)
    lu.assertEquals(cfg.Radius, 2)          -- docx：2 米内出现「烧烤」操作
    lu.assertEquals(cfg.RiseSec, 2)         -- 0-2 秒：1 → 1.5
    lu.assertEquals(cfg.HoldSec, 0.5)       -- 2-2.5 秒：保持 1.5
    lu.assertEquals(cfg.FallSec, 2)         -- 2.5-4.5 秒：1.5 → 0
    lu.assertEquals(cfg.MaxRate, 1.5)       -- 烤熟 1.5 倍
    lu.assertEquals(cfg.BurnSec, 4.5)       -- 4.5 秒烤糊
    lu.assertEquals(cfg.BurnSec, cfg.RiseSec + cfg.HoldSec + cfg.FallSec)
    lu.assertEquals(cfg.BurnDamage, 30)     -- docx：烤糊爆炸 30 伤害
    lu.assertEquals(cfg.BurnRadius, 3)      -- docx：周围 3 米
    lu.assertEquals(cfg.NoFishText, '你没有可烤的鱼')
    lu.assertEquals(cfg.BurntText, '你的鱼烤糊了！')
    lu.assertEquals(cfg.CookedPrefix, '烤过的')
    lu.assertNotNil(cfg.TokenWarnText)
end

-- 烧烤锚点（#125 场景合同）：三区起每区一个 GrillName，前两区没有
function TestGrillConfig:test_anchors_cover_zones_three_to_seven()
    for index, zone in ipairs(GameCfg.Zones) do
        if index >= 3 then
            lu.assertNotNil(zone.Scene.GrillName)
        else
            lu.assertNil(zone.Scene.GrillName)
        end
    end
end

TestGrillCurve = {}

local Curve = require('common.GrillCurve')

local function rate(elapsed)
    return Curve.Rate(elapsed, GameCfg.Grill)
end

-- 验收边界：0 / 2 / 2.5 秒取出倍率；4.5 秒起为烤糊（物品损毁，不再给倍率）
function TestGrillCurve:test_boundary_rates()
    lu.assertEquals(rate(0), 1)
    lu.assertEquals(rate(2), 1.5)
    lu.assertEquals(rate(2.5), 1.5)
    lu.assertTrue(Curve.IsBurnt(4.5, GameCfg.Grill))
    lu.assertFalse(Curve.IsBurnt(4.49, GameCfg.Grill))
end

-- 线段中点：上升段线性 1→1.5，下降段线性 1.5→0
function TestGrillCurve:test_segment_midpoints()
    lu.assertAlmostEquals(rate(1), 1.25, 1e-9)    -- 0-2 秒中点
    lu.assertAlmostEquals(rate(2.2), 1.5, 1e-9)   -- 保持段
    lu.assertAlmostEquals(rate(3.5), 0.75, 1e-9)  -- 2.5-4.5 秒中点
end

-- 快慢帧不改变收益：倍率只由「投入时刻到取出时刻」的服务器时长一次算出，与调用次数无关
function TestGrillCurve:test_rate_depends_only_on_elapsed()
    lu.assertEquals(rate(1), rate(1))                       -- 重复查询结果稳定
    lu.assertAlmostEquals(rate(0.5 + 0.5), rate(1), 1e-9)   -- 一次算 1 秒 = 直接查 1 秒
    lu.assertAlmostEquals(rate(0.1) - 1, 0.5 * 0.1 / 2, 1e-9) -- 按整段时长插值，不按步长累加
end

-- 非法输入：负数按 0 秒（刚投入），非数字不给倍率
function TestGrillCurve:test_invalid_elapsed()
    lu.assertEquals(rate(-3), 1)
    lu.assertNil(rate('1'))
    lu.assertNil(rate(nil))
end

-- 界面两位小数（策划案：界面显示烧烤时间/倍率两位小数）
function TestGrillCurve:test_format_two_decimals()
    lu.assertEquals(Curve.Format(1), '1.00')
    lu.assertEquals(Curve.Format(1.5), '1.50')
    lu.assertEquals(Curve.Format(rate(1)), '1.25')
end

-- ========== 切片二：烤制倍率表示统一（取出倍率可以是 (0, 1.5] 的任意值）==========

local PlayerData = require('server.Data.PlayerData')
local LotteryEligibility = require('common.LotteryEligibility')

TestGrillCookedFields = {}

function TestGrillCookedFields:setUp()
    self.oldDebug = GameCfg.Debug
    GameCfg.Debug = { Enabled = false }
    self.player = { UserId = 73001, SetAttribute = function() end }
    self.data = PlayerData.New(self.player)
    self.data:Init()
end

function TestGrillCookedFields:tearDown()
    GameCfg.Debug = self.oldDebug
end

-- PlayerData 存档字段接缝：曲线下降段取出的倍率 <1，序列化往返不丢、不被 Migrate 拒收
function TestGrillCookedFields:test_sub_one_rate_survives_save_roundtrip()
    lu.assertTrue(self.data:AddItem('bass', 1.5, 0.75))
    local snapshot = self.data:Serialize()
    local restored = PlayerData.New(self.player)
    restored:Init()
    lu.assertTrue(restored:ApplySave(snapshot))
    local entry = restored.Data.Containers[GameCfg.Items.ContainerId.ItemBar][1]
    lu.assertEquals(entry.cooked, 0.75)
    lu.assertEquals(entry.saved.k, 0.75)
end

-- 倍率 0（烤糊）与负数永远是坏档：烤糊物品根本不进入库存
function TestGrillCookedFields:test_zero_or_negative_rate_is_rejected()
    lu.assertTrue(self.data:AddItem('bass', 1.5, 0.75))
    local snapshot = self.data:Serialize()
    snapshot.bar[1].k = 0
    lu.assertFalse(self.data:ApplySave(snapshot))
    local snapshot2 = self.data:Serialize()
    snapshot2.bar[1].k = -0.5
    lu.assertFalse(self.data:ApplySave(snapshot2))
end

TestGrillCookRate = {}

-- CookRate 统一读取三种来源：顶层数值（内存格位/快照）、saved.k（读档还原）、
-- 旧布尔 saved.cooked（#127 之前的手工标记，等价烤熟价倍率）；非法值一律 nil
function TestGrillCookRate:test_sources()
    lu.assertEquals(GameCfg.Items.CookRate({ cooked = 0.75 }), 0.75)
    lu.assertEquals(GameCfg.Items.CookRate({ saved = { k = 1.2 } }), 1.2)
    lu.assertEquals(GameCfg.Items.CookRate({ saved = { cooked = true } }), GameCfg.Items.CookedPriceScale)
    lu.assertNil(GameCfg.Items.CookRate({}))
    lu.assertNil(GameCfg.Items.CookRate({ cooked = 0 }))
    lu.assertNil(GameCfg.Items.CookRate({ cooked = -1 }))
    lu.assertNil(GameCfg.Items.CookRate({ cooked = 'x' }))
    lu.assertNil(GameCfg.Items.CookRate(nil))
end

TestGrillSalePrice = {}

-- 取出倍率直接定价：价格 = 基础价 × 个体倍率 × 烤制倍率（#137）；旧布尔标记仍是烤熟价 ×1.5
function TestGrillSalePrice:test_numeric_rate_prices()
    lu.assertEquals(GameCfg.Items.SalePrice('garHead', nil, 1.25), 25)  -- floor(20 × 1 × 1.25)
    lu.assertEquals(GameCfg.Items.SalePrice('garHead', nil, 0.5), 10)   -- 下降段取出也值钱
    lu.assertEquals(GameCfg.Items.SalePrice('bass', 2, 0.75), 9)        -- floor(6 × 2 × 0.75)
    lu.assertEquals(GameCfg.Items.SalePrice('bass', 2, 1.5), 18)        -- floor(6 × 2 × 1.5)
end

function TestGrillSalePrice:test_legacy_boolean_keeps_cooked_scale()
    lu.assertEquals(GameCfg.Items.SalePrice('garHead', nil, true), 30)  -- floor(20 × 1 × 1.5)
    lu.assertEquals(GameCfg.Items.SalePrice('bass', 2, true), 18)
    lu.assertEquals(GameCfg.Items.SalePrice('bass', 2), 12)             -- 未烤原价
end

TestGrillLotteryGuard = {}

-- #138 抽奖机守卫（本单先留接口）：烤过信物/极品鱼获哪怕倍率 <1 也算烤过，拒绝投入
function TestGrillLotteryGuard:test_cooked_rate_below_one_is_still_cooked()
    local ok, reason = LotteryEligibility.Check({ itemId = 'item47', count = 1, mult = 1.2, cooked = 0.75 })
    lu.assertFalse(ok)
    lu.assertEquals(reason, 'cooked')
end

function TestGrillLotteryGuard:test_uncooked_premium_still_eligible()
    lu.assertTrue(LotteryEligibility.Check({ itemId = 'item47', count = 1, mult = 1.2 }))
end

-- MgrInteract 回收接缝：数值烤制倍率的鱼按当时倍率出价；烤过信物（数值标记）不再兑换
TestGrillInteract = {}

local function vec(x, y, z) return { x = x, y = y, z = z } end

function TestGrillInteract:setUp()
    local env = self
    self.savedGame = _G.game
    self.savedCfg = package.loaded['common.GameCfg']
    package.loaded['common.GameCfg'] = nil
    self.cfg = require('common.GameCfg')
    self.cfg.Debug = { Enabled = false }
    self.PlayerData = assert(loadfile('server/Data/PlayerData.lua'))()
    self.player = { UserId = 1, Character = { Position = vec(0, 0, 0) },
        SetAttribute = function() end }
    self.anchors = {}
    for index, zone in ipairs(self.cfg.Zones) do
        for _, entity in ipairs(zone.Scene.Entities) do
            if entity.Role == 'Fisherman' then
                local name = self.cfg.Interact.Fishermen[index].AnchorNames[1]
                self.anchors[name] = { Name = name, Position = entity.Position }
            end
        end
    end
    self.replies = {}
    self.mgr = assert(loadfile('server/Mgr/MgrInteract.lua'))()
    self.mgr.FindAnchor = function(_, name) return env.anchors[name] end
    self.mgr.PlayerData = {
        GetDataInst = function(_, p) return p == env.player and env.data or nil end,
        SendItemBar = function() end,
    }
    self.mgr.Reply = function(_, p, payload) env.replies[#env.replies + 1] = payload end
    self.data = self.PlayerData.New(self.player)
    self.data:Init()
    self:standAt(1)
    self.seq = 0
end

function TestGrillInteract:tearDown()
    package.loaded['common.GameCfg'] = self.savedCfg
    _G.game = self.savedGame
end

function TestGrillInteract:standAt(zoneIndex)
    local name = self.cfg.Interact.Fishermen[zoneIndex].AnchorNames[1]
    local center = self.anchors[name].Position
    self.player.Character.Position = vec(center.x + 1, center.y, center.z)
end

function TestGrillInteract:feed()
    self.seq = self.seq + 1
    return self.mgr:Handle(self.player, { target = 'fisherman', action = 'Feed', seq = self.seq })
end

function TestGrillInteract:lastReply()
    return self.replies[#self.replies]
end

-- 数值烤制倍率的鱼获按当时倍率结金币（不再只看布尔标记）
function TestGrillInteract:test_numeric_cooked_fish_sells_at_rate()
    lu.assertTrue(self.data:AddItem('bass', 2, 0.75))
    lu.assertTrue(self.data:SelectSlot(1))
    lu.assertTrue(self:feed())
    lu.assertEquals(self.data.Data.FishCoin, 9) -- floor(6 × 2 × 0.75)
end

-- 数值标记的烤过信物不能走兑换链，只按倍率售卖
function TestGrillInteract:test_numeric_cooked_token_never_exchanges()
    lu.assertTrue(self.data:AddItem('eelHead', nil, 1.2))
    lu.assertTrue(self.data:SelectSlot(1))
    lu.assertTrue(self:feed())
    lu.assertEquals(self.data:ItemCount('eelHead'), 0)
    lu.assertEquals(self.data:ItemCount('duck'), 0, '烤过的精英信物不能再换首领饵')
    lu.assertEquals(self.data.Data.FishCoin, 12) -- floor(10 × 1 × 1.2)
    lu.assertNil(self:lastReply().exchange)
end


-- ========== 切片三：MgrGrill 管理器（会话、计时、烤糊、恢复）==========

TestGrillMgr = {}

local function signal()
    local handlers = {}
    return {
        Connect = function(_, fn)
            handlers[#handlers + 1] = fn
            return { Disconnect = function() for i, cb in ipairs(handlers) do
                if cb == fn then handlers[i] = nil end
            end end }
        end,
        Fire = function(_, ...) for _, cb in ipairs(handlers) do cb(...) end end,
    }
end

-- 三区烧烤锚点（#125 场景合同）：测试中用它做唯一合法烤位
local function grillAnchor()
    for _, entity in ipairs(GameCfg.Zones[3].Scene.Entities) do
        if entity.Role == 'Grill' then return entity end
    end
end

function TestGrillMgr:setUp()
    local env = self
    self.oldGame, self.oldRE = _G.game, _G.REUtil
    self.oldDebug = GameCfg.Debug
    GameCfg.Debug = { Enabled = false }
    self.now = 1000
    self.values, self.queue, self.writeFailure = {}, {}, nil
    self.store = {
        GetAsync = function(_, key) return env.values[key] end,
        UpdateAsync = function(_, key, transform)
            if env.writeFailure then error('写档失败') end
            local value = transform(env.values[key])
            if value then env.values[key] = value end
            return value
        end,
        SetAsync = function(_, key, value) env.values[key] = value end,
    }
    self.playerList = {}
    _G.game = { GetService = function(_, name)
        if name == 'Task' then
            return { Spawn = function(_, fn) env.queue[#env.queue + 1] = fn end, Wait = function() end }
        end
        if name == 'DataStoreService' then return { GetDataStore = function() return env.store end } end
        if name == 'World' then return { GetServerTime = function() return env.now end } end
        if name == 'Players' then return { GetPlayers = function() return env.playerList end } end
    end }
    self.events = {}
    _G.REUtil = { CheckRECD = function() return false end, GetRE = function(_, name)
        if not env.events[name] then
            env.events[name] = {
                OnServerEvent = signal(),
                FireClient = function(_, player, payload)
                    if name == 'GrillResult' then
                        player.grillResults = player.grillResults or {}
                        player.grillResults[#player.grillResults + 1] = payload
                    elseif name == 'GrillState' then
                        player.grillState = payload
                    end
                end,
            }
        end
        return env.events[name]
    end }
    self.PlayerData = assert(loadfile('server/Data/PlayerData.lua'))()
    self.save = assert(loadfile('server/Mgr/MgrSave.lua'))()
    self.mgr = assert(loadfile('server/Mgr/MgrGrill.lua'))()
    local anchor = grillAnchor()
    self.anchorPos = anchor.Position
    self.mgr.FindAnchor = function(_, name)
        if name == GameCfg.Zones[3].Scene.GrillName then return { Name = name, Position = env.anchorPos } end
    end
    self.datas = {}
    self.itembarSent = {}
    self.mgr.PlayerData = {
        GetDataInst = function(_, p) return env.datas[p.UserId] end,
        SendItemBar = function(_, p) env.itembarSent[p.UserId] = (env.itembarSent[p.UserId] or 0) + 1 end,
    }
    self.alive = {}
    self.hits = {}
    self.hitSeq = 0
    self.mgr.Vitals = {
        CanAct = function(_, p) return env.alive[p.UserId] ~= false end,
        NewHit = function(_, source, category)
            env.hitSeq = env.hitSeq + 1
            return { id = env.hitSeq, source = source, category = category, targets = {} }
        end,
        ApplyHit = function(_, hit, target, amount)
            if hit.targets[target.UserId] then return false end
            hit.targets[target.UserId] = true
            env.hits[#env.hits + 1] = { id = hit.id, category = hit.category,
                userId = target.UserId, amount = amount }
            return true, amount
        end,
    }
    self.drops = {}
    self.mgr.Loot = { SpawnItem = function(_, itemId, mult, cooked, pos)
        env.drops[#env.drops + 1] = { itemId = itemId, mult = mult, cooked = cooked }
        return { Id = #env.drops }
    end }
    self.mgr.Save = self.save
    self.mgr:Start()
    self.seq = 0
end

function TestGrillMgr:tearDown()
    _G.game = self.oldGame
    _G.REUtil = self.oldRE
    GameCfg.Debug = self.oldDebug
end

function TestGrillMgr:drain()
    while #self.queue > 0 do table.remove(self.queue, 1)() end
end

function TestGrillMgr:join(id, atGrill)
    local player = { UserId = id, Name = 'p' .. id, attrs = {},
        CharacterAdded = signal(),
        Character = { Position = { x = self.anchorPos.x + (atGrill == false and 100 or 1),
            y = self.anchorPos.y, z = self.anchorPos.z } } }
    function player:SetAttribute(k, v) self.attrs[k] = v end
    local data = self.PlayerData.New(player)
    data:Init(true)
    self.save:LoadInto(player, data)
    self:drain()
    lu.assertEquals(data.LoadState, 'ready')
    self.datas[id] = data
    self.playerList[#self.playerList + 1] = player
    self.mgr:OnPlayerAdded(player)
    return player, data
end

function TestGrillMgr:act(player, payload)
    self.seq = self.seq + 1
    payload.seq = self.seq
    self.events.GrillAction.OnServerEvent:Fire(player, payload)
    self:drain()
    return player.grillResults and player.grillResults[#player.grillResults]
end

function TestGrillMgr:advance(seconds)
    self.now = self.now + seconds
    self.mgr:Update()
    self:drain()
end

function TestGrillMgr:giveSelected(data, itemId, mult, cooked)
    lu.assertTrue(data:AddItem(itemId, mult, cooked))
    lu.assertTrue(data:SelectSlot(1))
end

local function countItem(data, itemId)
    local total = 0
    for _, container in pairs(data.Data.Containers) do
        for _, entry in pairs(container) do
            if entry.itemId == itemId and entry.count > 0 then total = total + entry.count end
        end
    end
    return total
end

local function findEntry(data, itemId)
    for _, container in pairs(data.Data.Containers) do
        for index, entry in pairs(container) do
            if entry.itemId == itemId and entry.count > 0 then return entry, index end
        end
    end
end

-- 开烤：选中未烤鱼获被移出库存、会话建立、状态下发 cooking
function TestGrillMgr:test_start_locks_item_into_session()
    local player, data = self:join(8101)
    self:giveSelected(data, 'carp', 1.5)
    local reply = self:act(player, { action = 'Start' })
    lu.assertTrue(reply.ok)
    lu.assertEquals(reply.itemId, 'carp')
    lu.assertEquals(reply.mult, 1.5)
    lu.assertEquals(reply.startedAt, 1000)
    lu.assertEquals(countItem(data, 'carp'), 0, '投入后库存里不再有这件')
    local session = self.mgr:GetSession(player)
    lu.assertNotNil(session)
    lu.assertEquals(session.state, 'cooking')
    lu.assertEquals(player.grillState.state, 'cooking')
    lu.assertNil(data.Data.SelectedSlot, '投入后选中格归位')
end

-- 验收边界：0 / 2 / 2.5 秒取出倍率 1 / 1.5 / 1.5，烤过标记随存档落位
function TestGrillMgr:test_takeout_boundary_rates()
    local cases = { { 0, 1 }, { 2, 1.5 }, { 2.5, 1.5 } }
    for index, case in ipairs(cases) do
        local player, data = self:join(8110 + index)
        self:giveSelected(data, 'carp', 1.5)
        lu.assertTrue(self:act(player, { action = 'Start' }).ok)
        self:advance(case[1])
        local reply = self:act(player, { action = 'Takeout' })
        lu.assertTrue(reply.ok)
        lu.assertEquals(reply.rate, case[2])
        local entry = findEntry(data, 'carp')
    lu.assertNotNil(entry)
        lu.assertEquals(entry.cooked, case[2])
        lu.assertEquals(entry.saved.k, case[2], '倍率要随存档槽位持久化')
        lu.assertNil(data.Extra.recovery.grill, '取出后不再有待恢复会话')
        lu.assertNil(self.mgr:GetSession(player))
    end
end

-- 取出放回可用格位并保持选中（验收）
function TestGrillMgr:test_takeout_returns_to_free_slot_and_keeps_selection()
    local player, data = self:join(8140)
    self:giveSelected(data, 'carp', 1.5)
    lu.assertTrue(self:act(player, { action = 'Start' }).ok)
    self:advance(2)
    lu.assertTrue(self:act(player, { action = 'Takeout' }).ok)
    lu.assertEquals(data.Data.Containers[GameCfg.Items.ContainerId.ItemBar][1].itemId, 'carp')
    lu.assertEquals(data.Data.SelectedSlot, 1, '取出后保持选中')
end

-- 4.5 秒烤糊：物品损毁一次、对烤炉 3 米内玩家各结算 30 伤害一次、状态下发 burnt
function TestGrillMgr:test_burn_destroys_once_and_damages_in_radius()
    local near, dataA = self:join(8150)
    local also = self:join(8151)
    local far = self:join(8152, false) -- 站在 100 米外
    self:giveSelected(dataA, 'carp', 1.5)
    lu.assertTrue(self:act(near, { action = 'Start' }).ok)
    self:advance(4.5)
    lu.assertEquals(countItem(dataA, 'carp'), 0, '烤糊物品损毁')
    lu.assertNil(dataA.Extra.recovery.grill)
    lu.assertEquals(#self.hits, 2, '3 米内两名玩家各吃一次伤害')
    for _, hit in ipairs(self.hits) do
        lu.assertEquals(hit.amount, 30)
        lu.assertEquals(hit.category, 'grillBurn')
    end
    lu.assertEquals(near.grillState.state, 'burnt')
    self:advance(10)
    lu.assertEquals(#self.hits, 2, '烤糊只损毁一次，不重复爆炸')
    local reply = self:act(near, { action = 'Takeout' })
    lu.assertFalse(reply.ok)
    lu.assertEquals(reply.reason, 'no-session', '烤糊后没有可取出的会话')
end

-- 快慢帧不改变收益：燃烧判定只看服务器时刻，不按帧数累加
function TestGrillMgr:test_burn_depends_on_server_time_not_ticks()
    local player, data = self:join(8160)
    self:giveSelected(data, 'carp', 1.5)
    lu.assertTrue(self:act(player, { action = 'Start' }).ok)
    for _ = 1, 44 do self:advance(0.1) end -- 44 帧共 4.4 秒：不糊
    lu.assertEquals(#self.hits, 0)
    lu.assertNotNil(self.mgr:GetSession(player))
    self:advance(0.1) -- 第 45 帧到 4.5 秒：糊
    lu.assertEquals(#self.hits, 1)
    lu.assertEquals(countItem(data, 'carp'), 0)
end

-- 两玩家身份交错：B 取不到 A 的会话物，A 正常取出
function TestGrillMgr:test_sessions_are_isolated_per_player()
    local a, dataA = self:join(8170)
    local b, dataB = self:join(8171)
    self:giveSelected(dataA, 'carp', 1.5)
    self:giveSelected(dataB, 'bass', 1.2)
    lu.assertTrue(self:act(a, { action = 'Start' }).ok)
    self:advance(2)
    local stolen = self:act(b, { action = 'Takeout' })
    lu.assertFalse(stolen.ok)
    lu.assertEquals(stolen.reason, 'no-session')
    lu.assertEquals(countItem(dataB, 'carp'), 0, 'B 拿不到 A 的鱼')
    lu.assertTrue(self:act(a, { action = 'Takeout' }).ok)
    lu.assertEquals(countItem(dataA, 'carp'), 1)
    lu.assertEquals(countItem(dataA, 'bass'), 0)
end

-- 同请求重放不重复结算：开烤重放不移除第二件，取出重放不多发一件
function TestGrillMgr:test_replay_never_settles_twice()
    local player, data = self:join(8180)
    self:giveSelected(data, 'carp', 1.5)
    lu.assertTrue(data:AddItem('bass', 1.1))
    self.events.GrillAction.OnServerEvent:Fire(player, { action = 'Start', seq = 1 })
    self:drain()
    lu.assertEquals(countItem(data, 'carp'), 0)
    self.events.GrillAction.OnServerEvent:Fire(player, { action = 'Start', seq = 1 }) -- 重放
    self:drain()
    lu.assertEquals(countItem(data, 'bass'), 1, '重放不能再移走别的物品')
    lu.assertTrue(player.grillResults[#player.grillResults].ok)
    self:advance(2)
    self.events.GrillAction.OnServerEvent:Fire(player, { action = 'Takeout', seq = 2 })
    self:drain()
    self.events.GrillAction.OnServerEvent:Fire(player, { action = 'Takeout', seq = 2 }) -- 重放
    self:drain()
    lu.assertEquals(countItem(data, 'carp'), 1, '取出重放不复制物品')
end

-- 满格取出：物品留在会话里不丢；腾出格位后按首次取出冻结的倍率取回
function TestGrillMgr:test_full_inventory_takeout_keeps_retrievable_with_frozen_rate()
    local player, data = self:join(8190)
    self:giveSelected(data, 'carp', 1.5)
    lu.assertTrue(self:act(player, { action = 'Start' }).ok)
    self:advance(2) -- 倍率 1.5 时首次取出
    while data:AddItem('tilapia') do end
    local full = self:act(player, { action = 'Takeout' })
    lu.assertFalse(full.ok)
    lu.assertEquals(full.reason, 'full')
    lu.assertEquals(countItem(data, 'carp'), 0, '满格也不能把烤鱼吞掉')
    local session = self.mgr:GetSession(player)
    lu.assertEquals(session.state, 'ready')
    self:advance(1.5) -- 曲线已跌到 0.75，但倍率在首次取出时冻结
    data.Data.Containers[GameCfg.Items.ContainerId.Backpack][1] = nil
    local retry = self:act(player, { action = 'Takeout' })
    lu.assertTrue(retry.ok)
    lu.assertEquals(retry.rate, 1.5, '满格冻结倍率，重试不继续烤')
    local entry = findEntry(data, 'carp')
    lu.assertNotNil(entry)
    lu.assertEquals(entry.cooked, 1.5)
end

-- 断线：离开前按当前倍率结算回库存（BeforeLeave 先于存档序列化），重进倍率保持
function TestGrillMgr:test_disconnect_settles_once_and_rejoin_keeps_rate()
    local player, data = self:join(8200)
    self:giveSelected(data, 'carp', 1.5)
    lu.assertTrue(self:act(player, { action = 'Start' }).ok)
    self:advance(1) -- 倍率 1.25
    self.mgr:BeforeLeave(player)
    lu.assertNil(self.mgr:GetSession(player))
    lu.assertNil(data.Extra.recovery.grill, '已结算回库存，不留待恢复')
    local entry = findEntry(data, 'carp')
    lu.assertNotNil(entry)
    lu.assertAlmostEquals(entry.cooked, 1.25, 1e-9)
    -- 重进：序列化往返后倍率保持
    local restored = self.PlayerData.New(player)
    restored:Init()
    lu.assertTrue(restored:ApplySave(data:Serialize()))
    local back = findEntry(restored, 'carp')
    lu.assertNotNil(back)
    lu.assertAlmostEquals(back.cooked, 1.25, 1e-9)
end

-- 断线且满格：结算成待恢复标记，重进腾出格位后按原倍率取回，不吞物
function TestGrillMgr:test_disconnect_with_full_inventory_recovers_after_rejoin()
    local player, data = self:join(8210)
    self:giveSelected(data, 'carp', 1.5)
    lu.assertTrue(self:act(player, { action = 'Start' }).ok)
    self:advance(2)
    while data:AddItem('tilapia') do end
    self.mgr:BeforeLeave(player)
    lu.assertEquals(countItem(data, 'carp'), 0, '满格塞不回去，但不能丢')
    local pending = data.Extra.recovery.grill
    lu.assertNotNil(pending)
    lu.assertEquals(pending.itemId, 'carp')
    lu.assertEquals(pending.cooked, 1.5)
    -- 重进：老存档快照载入新玩家
    local snapshot = data:Serialize()
    local rejoined, reData = self:join(8211)
    lu.assertTrue(reData:ApplySave(snapshot))
    self.mgr:OnPlayerAdded(rejoined)
    self:advance(0.1)
    lu.assertEquals(countItem(reData, 'carp'), 0, '满格时保持待恢复，不复制')
    reData.Data.Containers[GameCfg.Items.ContainerId.Backpack][1] = nil -- 玩家腾出一格
    self:advance(0.1)
    local entry = findEntry(reData, 'carp')
    lu.assertNotNil(entry)
    lu.assertEquals(entry.cooked, 1.5, '倍率保持')
    lu.assertNil(reData.Extra.recovery.grill)
end

-- 死亡：Update 检出不可行动即按当前倍率结算回库存（结算一次，不烤糊不吞物）
function TestGrillMgr:test_death_settles_at_current_rate()
    local player, data = self:join(8220)
    self:giveSelected(data, 'carp', 1.5)
    lu.assertTrue(self:act(player, { action = 'Start' }).ok)
    self:advance(1)
    self.alive[player.UserId] = false
    self:advance(0.05) -- 死亡检出发生在这一帧，投入时长已是 1.05 秒
    lu.assertNil(self.mgr:GetSession(player))
    local entry = findEntry(data, 'carp')
    lu.assertNotNil(entry)
    lu.assertAlmostEquals(entry.cooked, Curve.Rate(1.05, GameCfg.Grill), 1e-9)
    self:advance(10)
    lu.assertEquals(#self.hits, 0, '死亡结算后不会再烤糊爆炸')
end

-- 信物守卫：未确认先提示（不扣物），确认后才开烤；烤过信物倍率照走
function TestGrillMgr:test_token_requires_confirm_first()
    local player, data = self:join(8230)
    self:giveSelected(data, 'eelHead')
    local warned = self:act(player, { action = 'Start' })
    lu.assertFalse(warned.ok)
    lu.assertEquals(warned.reason, 'token-warn')
    lu.assertEquals(countItem(data, 'eelHead'), 1, '提示阶段不扣信物')
    local started = self:act(player, { action = 'Start', confirm = true })
    lu.assertTrue(started.ok)
    lu.assertEquals(countItem(data, 'eelHead'), 0)
    self:advance(2)
    lu.assertTrue(self:act(player, { action = 'Takeout' }).ok)
    local entry = findEntry(data, 'eelHead')
    lu.assertNotNil(entry)
    lu.assertEquals(entry.cooked, 1.5)
end

-- 资格：烤过的鱼不能再烤；非鱼获（鱼竿）不能烤
function TestGrillMgr:test_only_uncooked_catches_are_grillable()
    local player, data = self:join(8240)
    self:giveSelected(data, 'bass', 1.5, 1.5) -- 已烤过
    local recook = self:act(player, { action = 'Start' })
    lu.assertFalse(recook.ok)
    lu.assertEquals(recook.reason, 'no-fish')
    lu.assertEquals(countItem(data, 'bass'), 1, '拒绝时不扣物')
    lu.assertTrue(data:AddItem('normalRod'))
    lu.assertTrue(data:SelectSlot(2))
    local rod = self:act(player, { action = 'Start' })
    lu.assertFalse(rod.ok)
    lu.assertEquals(rod.reason, 'no-fish')
end

-- 会话中不能再开第二炉
function TestGrillMgr:test_second_start_while_cooking_is_busy()
    local player, data = self:join(8250)
    self:giveSelected(data, 'carp', 1.5)
    lu.assertTrue(data:AddItem('bass', 1.2))
    lu.assertTrue(self:act(player, { action = 'Start' }).ok)
    lu.assertTrue(data:SelectSlot(2))
    local second = self:act(player, { action = 'Start' })
    lu.assertFalse(second.ok)
    lu.assertEquals(second.reason, 'busy')
    lu.assertEquals(countItem(data, 'bass'), 1)
end

-- 服务器崩溃式中断（开烤已落账但会话未及建立）：重进按经过时长结算，倍率照曲线
function TestGrillMgr:test_crash_shape_pending_settles_by_elapsed_on_rejoin()
    local player, data = self:join(8260)
    self:giveSelected(data, 'carp', 1.5)
    lu.assertTrue(self:act(player, { action = 'Start' }).ok)
    -- 模拟重进：会话状态全丢，只剩存档里的 cooking 形标记
    self.mgr.Sessions[player.UserId] = nil
    self:advance(1) -- 离线经过了 1 秒
    self.mgr:OnPlayerAdded(player)
    self:drain()
    local entry = findEntry(data, 'carp')
    lu.assertNotNil(entry)
    lu.assertAlmostEquals(entry.cooked, 1.25, 1e-9)
    lu.assertNil(data.Extra.recovery.grill)
end

-- 崩溃时早已烤糊：重进清标记、不再发鱼、不重复爆炸
function TestGrillMgr:test_crash_shape_burnt_while_offline_is_cleared_once()
    local player, data = self:join(8270)
    self:giveSelected(data, 'carp', 1.5)
    lu.assertTrue(self:act(player, { action = 'Start' }).ok)
    self.mgr.Sessions[player.UserId] = nil
    self:advance(10) -- 离线 10 秒，早已烤糊
    self.mgr:OnPlayerAdded(player)
    self:drain()
    lu.assertEquals(countItem(data, 'carp'), 0)
    lu.assertNil(data.Extra.recovery.grill)
    lu.assertEquals(#self.hits, 0, '离线烤糊不爆炸（无人在场）')
end

-- 接线断言（server/main.lua）：MgrGrill 注册、依赖注入、BeforeLeave 先于存档序列化
TestGrillWiring = {}

function TestGrillWiring:test_server_main_wires_grill()
    local file = assert(io.open('server/main.lua', 'r'))
    local src = file:read('*a')
    file:close()
    lu.assertStrContains(src, 'MgrGrill = require("server.Mgr.MgrGrill")')
    lu.assertStrContains(src, 'MgrMap.MgrGrill.Vitals = MgrMap.MgrVitals')
    lu.assertStrContains(src, 'MgrMap.MgrGrill.PlayerData = MgrMap.MgrPlayerData')
    lu.assertStrContains(src, 'MgrMap.MgrGrill.Save = MgrMap.MgrSave')
    lu.assertStrContains(src, 'MgrMap.MgrGrill.Loot = MgrMap.MgrLoot')
    lu.assertNotNil(src:find("MgrGrill', MgrMap.MgrGrill, 'BeforeLeave'"),
        '离开前要先结算烧烤会话再序列化存档')
end

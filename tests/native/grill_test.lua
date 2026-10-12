-- #86 迁移（原 tests/gameplay/grill_test.lua，#137 T16 烧烤）：
-- 服务端曲线计时、取出结算、烤糊伤害与会话恢复
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
-- 说明：describe 按旧 LuaUnit 的执行顺序登记（类名字节序、其内方法字节序），保持案例顺序一致。
-- 随机数：烤糊倍率与伤害由服务器时刻（假 World.GetServerTime）一次算出，烤位取场景锚点而非随机点位；
-- 链路上唯一的 math.random 是 MgrSave 的一次性会话 Token 字符串（server/Mgr/MgrSave.lua:143，仅做
-- fencing 命名空间），不参与任何断言，因此无需固定或恢复随机数函数。
local GameCfg = require('common.GameCfg')
local Curve = require('common.GrillCurve')
local PlayerData = require('server.Data.PlayerData')
local LotteryEligibility = require('common.LotteryEligibility')

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

local function rate(elapsed)
    return Curve.Rate(elapsed, GameCfg.Grill)
end

local function vec(x, y, z) return { x = x, y = y, z = z } end

-- 配置值与场景锚点（切片一）
describe("烧烤配置对齐策划案", function()
    -- 配置值对齐策划案/docx 与 issue #137 验收
    it("test_anchors_cover_zones_three_to_seven", function()
        for index, zone in ipairs(GameCfg.Zones) do
            if index >= 3 then
                assert.is_not_nil(zone.Scene.GrillName)
            else
                assert.is_nil(zone.Scene.GrillName)
            end
        end
    end)

    it("test_values_match_design_doc", function()
        local cfg = GameCfg.Grill
        assert.is_not_nil(cfg)
        assert.same(2, cfg.Radius)          -- docx：2 米内出现「烧烤」操作
        assert.same(2, cfg.RiseSec)         -- 0-2 秒：1 → 1.5
        assert.same(0.5, cfg.HoldSec)       -- 2-2.5 秒：保持 1.5
        assert.same(2, cfg.FallSec)         -- 2.5-4.5 秒：1.5 → 0
        assert.same(1.5, cfg.MaxRate)       -- 烤熟 1.5 倍
        assert.same(4.5, cfg.BurnSec)       -- 4.5 秒烤糊
        assert.same(cfg.RiseSec + cfg.HoldSec + cfg.FallSec, cfg.BurnSec)
        assert.same(30, cfg.BurnDamage)     -- docx：烤糊爆炸 30 伤害
        assert.same(3, cfg.BurnRadius)      -- docx：周围 3 米
        assert.same('你没有可烤的鱼', cfg.NoFishText)
        assert.same('你的鱼烤糊了！', cfg.BurntText)
        assert.same('烤', cfg.CookedPrefix)  -- CONTEXT.md 烤鱼条 Avoid「烤过的鱼」，前缀用「烤」
        assert.is_not_nil(cfg.TokenWarnText)
    end)
end)

-- 切片二：烤制倍率表示统一（取出倍率可以是 (0, 1.5] 的任意值）
describe("烤制倍率的来源", function()
    -- CookRate 统一读取三种来源：顶层数值（内存格位/快照）、saved.k（读档还原）、
    -- 旧布尔 saved.cooked（#127 之前的手工标记，等价烤熟价倍率）；非法值一律 nil
    it("test_sources", function()
        assert.same(0.75, GameCfg.Items.CookRate({ cooked = 0.75 }))
        assert.same(1.2, GameCfg.Items.CookRate({ saved = { k = 1.2 } }))
        assert.same(GameCfg.Items.CookedPriceScale, GameCfg.Items.CookRate({ saved = { cooked = true } }))
        assert.is_nil(GameCfg.Items.CookRate({}))
        assert.is_nil(GameCfg.Items.CookRate({ cooked = 0 }))
        assert.is_nil(GameCfg.Items.CookRate({ cooked = -1 }))
        assert.is_nil(GameCfg.Items.CookRate({ cooked = 'x' }))
        assert.is_nil(GameCfg.Items.CookRate(nil))
    end)
end)

describe("烤制值的存档字段", function()
    local ctx

    before_each(function()
        ctx = {}
        ctx.oldDebug = GameCfg.Debug
        GameCfg.Debug = { Enabled = false }
        ctx.player = { UserId = 73001, SetAttribute = function() end }
        ctx.data = PlayerData.New(ctx.player)
        ctx.data:Init()
    end)

    after_each(function()
        GameCfg.Debug = ctx.oldDebug
    end)

    -- PlayerData 存档字段接缝：曲线下降段取出的倍率 <1，序列化往返不丢、不被 Migrate 拒收
    it("test_sub_one_rate_survives_save_roundtrip", function()
        assert.is_true(ctx.data:AddItem('bass', 1.5, 0.75))
        local snapshot = ctx.data:Serialize()
        local restored = PlayerData.New(ctx.player)
        restored:Init()
        assert.is_true(restored:ApplySave(snapshot))
        local entry = restored.Data.Containers[GameCfg.Items.ContainerId.ItemBar][1]
        assert.same(0.75, entry.cooked)
        assert.same(0.75, entry.saved.k)
    end)

    -- 倍率 0（烤糊）与负数永远是坏档：烤糊物品根本不进入库存
    it("test_zero_or_negative_rate_is_rejected", function()
        assert.is_true(ctx.data:AddItem('bass', 1.5, 0.75))
        local snapshot = ctx.data:Serialize()
        snapshot.bar[1].k = 0
        assert.is_false(ctx.data:ApplySave(snapshot))
        local snapshot2 = ctx.data:Serialize()
        snapshot2.bar[1].k = -0.5
        assert.is_false(ctx.data:ApplySave(snapshot2))
    end)
end)

describe("烧烤曲线纯函数", function()
    -- 验收边界：0 / 2 / 2.5 秒取出倍率；4.5 秒起为烤糊（物品损毁，不再给倍率）
    it("test_boundary_rates", function()
        assert.same(1, rate(0))
        assert.same(1.5, rate(2))
        assert.same(1.5, rate(2.5))
        assert.is_true(Curve.IsBurnt(4.5, GameCfg.Grill))
        assert.is_false(Curve.IsBurnt(4.49, GameCfg.Grill))
    end)

    -- 界面两位小数（策划案：界面显示烧烤时间/倍率两位小数）
    it("test_format_two_decimals", function()
        assert.same('1.00', Curve.Format(1))
        assert.same('1.50', Curve.Format(1.5))
        assert.same('1.25', Curve.Format(rate(1)))
    end)

    -- 非法输入：负数按 0 秒（刚投入），非数字不给倍率
    it("test_invalid_elapsed", function()
        assert.same(1, rate(-3))
        assert.is_nil(rate('1'))
        assert.is_nil(rate(nil))
    end)

    -- 快慢帧不改变收益：倍率只由「投入时刻到取出时刻」的服务器时长一次算出，与调用次数无关
    it("test_rate_depends_only_on_elapsed", function()
        assert.same(rate(1), rate(1))                        -- 重复查询结果稳定
        assert.near(rate(1), rate(0.5 + 0.5), 1e-9)          -- 一次算 1 秒 = 直接查 1 秒
        assert.near(0.5 * 0.1 / 2, rate(0.1) - 1, 1e-9)      -- 按整段时长插值，不按步长累加
    end)

    -- 线段中点：上升段线性 1→1.5，下降段线性 1.5→0
    it("test_segment_midpoints", function()
        assert.near(1.25, rate(1), 1e-9)     -- 0-2 秒中点
        assert.near(1.5, rate(2.2), 1e-9)    -- 保持段
        assert.near(0.75, rate(3.5), 1e-9)   -- 2.5-4.5 秒中点
    end)
end)

-- 切片四：吃通道接缝（Operate 两步吃烤鱼时把格位倍率带给 Vitals）
describe("吃通道传递烤制倍率", function()
    local ctx

    before_each(function()
        ctx = { events = {}, eaten = {} }
        ctx.oldRE = _G.REUtil
        ctx.oldDebug = GameCfg.Debug
        GameCfg.Debug = { Enabled = false }
        _G.REUtil = { CheckRECD = function() return false end, GetRE = function(_, name)
            if not ctx.events[name] then
                ctx.events[name] = { OnServerEvent = signal(),
                    FireClient = function(_, player, payload) player.lastResult = payload end }
            end
            return ctx.events[name]
        end }
        ctx.player = { UserId = 9102, Character = { Name = 'Eggy' },
            CharacterAdded = signal(), CharacterRemoving = signal(), SetAttribute = function() end }
        ctx.mgr = assert(loadfile('server/Mgr/MgrPlayerData.lua'))()
        ctx.mgr.Vitals = { CanEat = function() return true end,
            Eat = function(_, player, itemId, rate)
                ctx.eaten[#ctx.eaten + 1] = { itemId = itemId, rate = rate }
                return true
            end }
        ctx.mgr:Start()
        ctx.mgr:OnPlayerAdded(ctx.player)
        ctx.data = ctx.mgr:GetDataInst(ctx.player)
    end)

    -- 管理器实例、全局与配置逐例恢复；setUp 中途失败也照样清理。
    after_each(function()
        if ctx.mgr then
            if ctx.player then ctx.mgr:OnPlayerRemoving(ctx.player) end
            ctx.mgr.Vitals = nil
        end
        _G.REUtil = ctx.oldRE
        GameCfg.Debug = ctx.oldDebug
    end)

    local function operate(payload)
        ctx.events.ItemBarAction.OnServerEvent:Fire(ctx.player, payload)
        return ctx.player.lastResult
    end

    -- #137 审查修复：吃通道走 CookRate 统一口径，#127 之前的旧布尔档 saved.cooked==true 按烤熟价倍率恢复
    it("test_operate_eat_legacy_boolean_archive_passes_scale", function()
        assert.is_true(ctx.data:AddItem('carp', 1.5))
        local entry = ctx.data.Data.Containers[GameCfg.Items.ContainerId.ItemBar][1]
        entry.saved = { [GameCfg.Items.CookedFlag] = true }
        operate({ action = 'Operate', op = 'eat', slot = 1 })
        operate({ action = 'Operate', op = 'eat', slot = 1 })
        assert.same(1, #ctx.eaten)
        assert.same(GameCfg.Items.CookedPriceScale, ctx.eaten[1].rate, '旧布尔档按烤熟价倍率恢复')
    end)

    it("test_operate_eat_passes_cook_rate", function()
        assert.is_true(ctx.data:AddItem('carp', 1.5, 1.5))
        operate({ action = 'Operate', op = 'eat', slot = 1 })
        local second = operate({ action = 'Operate', op = 'eat', slot = 1 })
        assert.same(true, second.ok)
        assert.same(1, #ctx.eaten)
        assert.same('carp', ctx.eaten[1].itemId)
        assert.same(1.5, ctx.eaten[1].rate, '烤鱼按倍率恢复')
    end)

    it("test_operate_eat_plain_fish_passes_no_rate", function()
        assert.is_true(ctx.data:AddItem('carp', 1.5))
        operate({ action = 'Operate', op = 'eat', slot = 1 })
        operate({ action = 'Operate', op = 'eat', slot = 1 })
        assert.same(1, #ctx.eaten)
        assert.is_nil(ctx.eaten[1].rate)
    end)
end)

describe("吃烤鱼的恢复量", function()
    local ctx

    before_each(function()
        ctx = {}
        ctx.oldGame = _G.game
        ctx.now = 500
        _G.game = { GetService = function(_, name)
            if name == 'World' then return { GetServerTime = function() return ctx.now end } end
        end }
        ctx.vitals = assert(loadfile('server/Mgr/MgrVitals.lua'))()
        local c = { Health = 100, MaxHealth = 300, HealthChanged = signal(), Died = signal(),
            OnReborn = signal() }
        function c:TakeDamage(n) self.Health = math.max(0, self.Health - n) end
        ctx.controller = c
        ctx.player = { UserId = 9101, attrs = {}, CharacterAdded = signal(),
            Character = { Controller = c, Position = { x = 0, y = 0, z = 0 }, Size = { y = 2 } } }
        function ctx.player:SetAttribute(k, v) self.attrs[k] = v end
        ctx.vitals:OnPlayerAdded(ctx.player)
        ctx.vitals:GetState(ctx.player).hunger = 0 -- 从空饥饿看恢复量
    end)

    -- 玩家与引擎全局逐例恢复；setUp 中途失败也照样清理。
    after_each(function()
        if ctx.vitals then
            if ctx.player then ctx.vitals:OnPlayerRemoving(ctx.player) end
        end
        _G.game = ctx.oldGame
    end)

    -- 恢复量同倍率（验收：价格、恢复量同乘当时倍率）：电鳗头 EatPercent=50，
    -- 烤熟 1.5 倍 → 恢复 75%（225 饥饿）；未烤 → 50%（150）；下降段 0.5 倍 → 25%（75）
    it("test_eat_restores_scaled_by_cook_rate", function()
        assert.is_true(ctx.vitals:Eat(ctx.player, 'eelHead', 1.5))
        assert.same(225, ctx.vitals:GetState(ctx.player).hunger)
        assert.same(300, ctx.controller.Health, '100 + 225 封顶 300')

        local state = ctx.vitals:GetState(ctx.player)
        state.hunger = 0
        ctx.controller.Health = 100
        assert.is_true(ctx.vitals:Eat(ctx.player, 'eelHead'))
        assert.same(150, state.hunger, '未烤按原恢复量')
        assert.same(250, ctx.controller.Health)

        state.hunger = 0
        ctx.controller.Health = 100
        assert.is_true(ctx.vitals:Eat(ctx.player, 'eelHead', 0.5))
        assert.same(75, state.hunger, '下降段取出恢复量打折')
        assert.same(175, ctx.controller.Health)
    end)

    -- 非法倍率按未烤处理，不能吃时（死亡）照旧拒绝
    it("test_eat_with_bad_rate_falls_back_to_plain", function()
        assert.is_true(ctx.vitals:Eat(ctx.player, 'eelHead', -1))
        assert.same(150, ctx.vitals:GetState(ctx.player).hunger)
    end)
end)

describe("回收烤鱼的金币结算", function()
    local ctx

    before_each(function()
        ctx = { anchors = {}, replies = {}, seq = 0 }
        ctx.savedGame = _G.game
        ctx.savedCfg = package.loaded['common.GameCfg']
        -- 换一份私有配置副本：用例改 Debug 不污染其它 spec。
        package.loaded['common.GameCfg'] = nil
        ctx.cfg = require('common.GameCfg')
        ctx.cfg.Debug = { Enabled = false }
        ctx.PlayerData = assert(loadfile('server/Data/PlayerData.lua'))()
        ctx.player = { UserId = 1, Character = { Position = vec(0, 0, 0) },
            SetAttribute = function() end }
        for index, zone in ipairs(ctx.cfg.Zones) do
            for _, entity in ipairs(zone.Scene.Entities) do
                if entity.Role == 'Fisherman' then
                    local name = ctx.cfg.Interact.Fishermen[index].AnchorNames[1]
                    ctx.anchors[name] = { Name = name, Position = entity.Position }
                end
            end
        end
        ctx.mgr = assert(loadfile('server/Mgr/MgrInteract.lua'))()
        ctx.mgr.FindAnchor = function(_, name) return ctx.anchors[name] end
        ctx.mgr.PlayerData = {
            GetDataInst = function(_, p) return p == ctx.player and ctx.data or nil end,
            SendItemBar = function() end,
        }
        ctx.mgr.Reply = function(_, p, payload) ctx.replies[#ctx.replies + 1] = payload end
        ctx.data = ctx.PlayerData.New(ctx.player)
        ctx.data:Init()
        local name = ctx.cfg.Interact.Fishermen[1].AnchorNames[1]
        local center = ctx.anchors[name].Position
        ctx.player.Character.Position = vec(center.x + 1, center.y, center.z)
    end)

    -- 配置模块缓存与全局逐例恢复；setUp 中途失败也照样清理。
    after_each(function()
        package.loaded['common.GameCfg'] = ctx.savedCfg
        _G.game = ctx.savedGame
    end)

    local function feed()
        ctx.seq = ctx.seq + 1
        return ctx.mgr:Handle(ctx.player, { target = 'fisherman', action = 'Feed', seq = ctx.seq })
    end

    local function lastReply()
        return ctx.replies[#ctx.replies]
    end

    -- 数值烤制倍率的鱼获按当时倍率结金币（不再只看布尔标记）
    it("test_numeric_cooked_fish_sells_at_rate", function()
        assert.is_true(ctx.data:AddItem('bass', 2, 0.75))
        assert.is_true(ctx.data:SelectSlot(1))
        assert.is_true(feed())
        assert.same(9, ctx.data.Data.FishCoin) -- floor(6 × 2 × 0.75)
    end)

    -- 数值标记的烤过信物不能走兑换链，只按倍率售卖
    it("test_numeric_cooked_token_never_exchanges", function()
        assert.is_true(ctx.data:AddItem('eelHead', nil, 1.2))
        assert.is_true(ctx.data:SelectSlot(1))
        assert.is_true(feed())
        assert.same(0, ctx.data:ItemCount('eelHead'))
        assert.same(0, ctx.data:ItemCount('duck'), '烤过的精英信物不能再换首领饵')
        assert.same(12, ctx.data.Data.FishCoin) -- floor(10 × 1 × 1.2)
        assert.is_nil(lastReply().exchange)
    end)
end)

describe("烤过物品的抽奖资格", function()
    -- #138 抽奖机守卫（本单先留接口）：烤过信物/极品鱼获哪怕倍率 <1 也算烤过，拒绝投入
    it("test_cooked_rate_below_one_is_still_cooked", function()
        local ok, reason = LotteryEligibility.Check({ itemId = 'item47', count = 1, mult = 1.2, cooked = 0.75 })
        assert.is_false(ok)
        assert.same('cooked', reason)
    end)

    it("test_uncooked_premium_still_eligible", function()
        assert.is_true(LotteryEligibility.Check({ itemId = 'item47', count = 1, mult = 1.2 }))
    end)
end)

-- ========== 切片三：MgrGrill 管理器（会话、计时、烤糊、恢复）==========
describe("烧烤管理器", function()
    local ctx

    -- 三区烧烤锚点（#125 场景合同）：测试中用它做唯一合法烤位
    local function grillAnchor()
        for _, entity in ipairs(GameCfg.Zones[3].Scene.Entities) do
            if entity.Role == 'Grill' then return entity end
        end
    end

    before_each(function()
        ctx = { values = {}, queue = {}, writeFailure = nil, now = 1000,
            events = {}, itembarSent = {}, alive = {}, hits = {}, hitSeq = 0, seq = 0 }
        ctx.oldGame, ctx.oldRE = _G.game, _G.REUtil
        ctx.oldDebug = GameCfg.Debug
        GameCfg.Debug = { Enabled = false }
        ctx.store = {
            GetAsync = function(_, key) return ctx.values[key] end,
            UpdateAsync = function(_, key, transform)
                if ctx.writeFailure then error('写档失败') end
                local value = transform(ctx.values[key])
                if value then ctx.values[key] = value end
                return value
            end,
            SetAsync = function(_, key, value) ctx.values[key] = value end,
        }
        ctx.playerList = {}
        _G.game = { GetService = function(_, name)
            if name == 'Task' then
                return { Spawn = function(_, fn) ctx.queue[#ctx.queue + 1] = fn end, Wait = function() end }
            end
            if name == 'DataStoreService' then return { GetDataStore = function() return ctx.store end } end
            if name == 'World' then return { GetServerTime = function() return ctx.now end } end
            if name == 'Players' then return { GetPlayers = function() return ctx.playerList end } end
        end }
        _G.REUtil = { CheckRECD = function() return false end, GetRE = function(_, name)
            if not ctx.events[name] then
                ctx.events[name] = {
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
            return ctx.events[name]
        end }
        ctx.PlayerData = assert(loadfile('server/Data/PlayerData.lua'))()
        ctx.save = assert(loadfile('server/Mgr/MgrSave.lua'))()
        ctx.mgr = assert(loadfile('server/Mgr/MgrGrill.lua'))()
        ctx.anchorPos = grillAnchor().Position
        ctx.mgr.FindAnchor = function(_, name)
            if name == GameCfg.Zones[3].Scene.GrillName then return { Name = name, Position = ctx.anchorPos } end
        end
        ctx.datas = {}
        ctx.mgr.PlayerData = {
            GetDataInst = function(_, p) return ctx.datas[p.UserId] end,
            SendItemBar = function(_, p) ctx.itembarSent[p.UserId] = (ctx.itembarSent[p.UserId] or 0) + 1 end,
        }
        ctx.mgr.Vitals = {
            CanAct = function(_, p) return ctx.alive[p.UserId] ~= false end,
            NewHit = function(_, source, category)
                ctx.hitSeq = ctx.hitSeq + 1
                return { id = ctx.hitSeq, source = source, category = category, targets = {} }
            end,
            ApplyHit = function(_, hit, target, amount)
                if hit.targets[target.UserId] then return false end
                hit.targets[target.UserId] = true
                ctx.hits[#ctx.hits + 1] = { id = hit.id, category = hit.category,
                    userId = target.UserId, amount = amount }
                return true, amount
            end,
        }
        ctx.mgr.Save = ctx.save
        ctx.mgr:Start()
    end)

    -- 引擎全局与调试配置逐例恢复；setUp 中途失败也照样清理。
    after_each(function()
        _G.game = ctx.oldGame
        _G.REUtil = ctx.oldRE
        GameCfg.Debug = ctx.oldDebug
    end)

    local function drain()
        while #ctx.queue > 0 do table.remove(ctx.queue, 1)() end
    end

    local function join(id, atGrill)
        local player = { UserId = id, Name = 'p' .. id, attrs = {},
            CharacterAdded = signal(),
            Character = { Position = { x = ctx.anchorPos.x + (atGrill == false and 100 or 1),
                y = ctx.anchorPos.y, z = ctx.anchorPos.z } } }
        function player:SetAttribute(k, v) self.attrs[k] = v end
        local data = ctx.PlayerData.New(player)
        data:Init(true)
        ctx.save:LoadInto(player, data)
        drain()
        assert.same('ready', data.LoadState)
        ctx.datas[id] = data
        ctx.playerList[#ctx.playerList + 1] = player
        ctx.mgr:OnPlayerAdded(player)
        return player, data
    end

    local function act(player, payload)
        ctx.seq = ctx.seq + 1
        payload.seq = ctx.seq
        ctx.events.GrillAction.OnServerEvent:Fire(player, payload)
        drain()
        return player.grillResults and player.grillResults[#player.grillResults]
    end

    local function advance(seconds)
        ctx.now = ctx.now + seconds
        ctx.mgr:Update()
        drain()
    end

    local function giveSelected(data, itemId, mult, cooked)
        assert.is_true(data:AddItem(itemId, mult, cooked))
        assert.is_true(data:SelectSlot(1))
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

    -- 快慢帧不改变收益：燃烧判定只看服务器时刻，不按帧数累加
    it("test_burn_depends_on_server_time_not_ticks", function()
        local player, data = join(8160)
        giveSelected(data, 'carp', 1.5)
        assert.is_true(act(player, { action = 'Start' }).ok)
        for _ = 1, 44 do advance(0.1) end -- 44 帧共 4.4 秒：不糊
        assert.same(0, #ctx.hits)
        assert.is_not_nil(ctx.mgr:GetSession(player))
        advance(0.1) -- 第 45 帧到 4.5 秒：糊
        assert.same(1, #ctx.hits)
        assert.same(0, countItem(data, 'carp'))
    end)

    -- 4.5 秒烤糊：物品损毁一次、对烤炉 3 米内玩家各结算 30 伤害一次、状态下发 burnt
    it("test_burn_destroys_once_and_damages_in_radius", function()
        local near, dataA = join(8150)
        join(8151)
        join(8152, false) -- 站在 100 米外
        giveSelected(dataA, 'carp', 1.5)
        assert.is_true(act(near, { action = 'Start' }).ok)
        advance(4.5)
        assert.same(0, countItem(dataA, 'carp'), '烤糊物品损毁')
        assert.is_nil(dataA.Extra.recovery.grill)
        assert.same(2, #ctx.hits, '3 米内两名玩家各吃一次伤害')
        for _, hit in ipairs(ctx.hits) do
            assert.same(30, hit.amount)
            assert.same('grillBurn', hit.category)
        end
        assert.same('burnt', near.grillState.state)
        advance(10)
        assert.same(2, #ctx.hits, '烤糊只损毁一次，不重复爆炸')
        local reply = act(near, { action = 'Takeout' })
        assert.is_false(reply.ok)
        assert.same('no-session', reply.reason, '烤糊后没有可取出的会话')
    end)

    -- 崩溃时早已烤糊：重进清标记、不再发鱼、不重复爆炸
    it("test_crash_shape_burnt_while_offline_is_cleared_once", function()
        local player, data = join(8270)
        giveSelected(data, 'carp', 1.5)
        assert.is_true(act(player, { action = 'Start' }).ok)
        ctx.mgr.Sessions[player.UserId] = nil
        advance(10) -- 离线 10 秒，早已烤糊
        ctx.mgr:OnPlayerAdded(player)
        drain()
        assert.same(0, countItem(data, 'carp'))
        assert.is_nil(data.Extra.recovery.grill)
        assert.same(0, #ctx.hits, '离线烤糊不爆炸（无人在场）')
    end)

    -- 服务器崩溃式中断（开烤已落账但会话未及建立）：重进按经过时长结算，倍率照曲线
    it("test_crash_shape_pending_settles_by_elapsed_on_rejoin", function()
        local player, data = join(8260)
        giveSelected(data, 'carp', 1.5)
        assert.is_true(act(player, { action = 'Start' }).ok)
        -- 模拟重进：会话状态全丢，只剩存档里的 cooking 形标记
        ctx.mgr.Sessions[player.UserId] = nil
        advance(1) -- 离线经过了 1 秒
        ctx.mgr:OnPlayerAdded(player)
        drain()
        local entry = findEntry(data, 'carp')
        assert.is_not_nil(entry)
        assert.near(1.25, entry.cooked, 1e-9)
        assert.is_nil(data.Extra.recovery.grill)
    end)

    -- 死亡：Update 检出不可行动即按当前倍率结算回库存（结算一次，不烤糊不吞物）
    it("test_death_settles_at_current_rate", function()
        local player, data = join(8220)
        giveSelected(data, 'carp', 1.5)
        assert.is_true(act(player, { action = 'Start' }).ok)
        advance(1)
        ctx.alive[player.UserId] = false
        advance(0.05) -- 死亡检出发生在这一帧，投入时长已是 1.05 秒
        assert.is_nil(ctx.mgr:GetSession(player))
        local entry = findEntry(data, 'carp')
        assert.is_not_nil(entry)
        assert.near(Curve.Rate(1.05, GameCfg.Grill), entry.cooked, 1e-9)
        advance(10)
        assert.same(0, #ctx.hits, '死亡结算后不会再烤糊爆炸')
    end)

    -- 断线：离开前按当前倍率结算回库存（BeforeLeave 先于存档序列化），重进倍率保持
    it("test_disconnect_settles_once_and_rejoin_keeps_rate", function()
        local player, data = join(8200)
        giveSelected(data, 'carp', 1.5)
        assert.is_true(act(player, { action = 'Start' }).ok)
        advance(1) -- 倍率 1.25
        ctx.mgr:BeforeLeave(player)
        assert.is_nil(ctx.mgr:GetSession(player))
        assert.is_nil(data.Extra.recovery.grill, '已结算回库存，不留待恢复')
        local entry = findEntry(data, 'carp')
        assert.is_not_nil(entry)
        assert.near(1.25, entry.cooked, 1e-9)
        -- 重进：序列化往返后倍率保持
        local restored = ctx.PlayerData.New(player)
        restored:Init()
        assert.is_true(restored:ApplySave(data:Serialize()))
        local back = findEntry(restored, 'carp')
        assert.is_not_nil(back)
        assert.near(1.25, back.cooked, 1e-9)
    end)

    -- 断线且满格：结算成待恢复标记，重进腾出格位后按原倍率取回，不吞物
    it("test_disconnect_with_full_inventory_recovers_after_rejoin", function()
        local player, data = join(8210)
        giveSelected(data, 'carp', 1.5)
        assert.is_true(act(player, { action = 'Start' }).ok)
        advance(2)
        while data:AddItem('tilapia') do end
        ctx.mgr:BeforeLeave(player)
        assert.same(0, countItem(data, 'carp'), '满格塞不回去，但不能丢')
        local pending = data.Extra.recovery.grill
        assert.is_not_nil(pending)
        assert.same('carp', pending.itemId)
        assert.same(1.5, pending.cooked)
        -- 重进：老存档快照载入新玩家
        local snapshot = data:Serialize()
        local rejoined, reData = join(8211)
        assert.is_true(reData:ApplySave(snapshot))
        ctx.mgr:OnPlayerAdded(rejoined)
        advance(0.1)
        assert.same(0, countItem(reData, 'carp'), '满格时保持待恢复，不复制')
        reData.Data.Containers[GameCfg.Items.ContainerId.Backpack][1] = nil -- 玩家腾出一格
        advance(0.1)
        local entry = findEntry(reData, 'carp')
        assert.is_not_nil(entry)
        assert.same(1.5, entry.cooked, '倍率保持')
        assert.is_nil(reData.Extra.recovery.grill)
    end)

    -- 满格取出：物品留在会话里不丢；腾出格位后按首次取出冻结的倍率取回
    it("test_full_inventory_takeout_keeps_retrievable_with_frozen_rate", function()
        local player, data = join(8190)
        giveSelected(data, 'carp', 1.5)
        assert.is_true(act(player, { action = 'Start' }).ok)
        advance(2) -- 倍率 1.5 时首次取出
        while data:AddItem('tilapia') do end
        local full = act(player, { action = 'Takeout' })
        assert.is_false(full.ok)
        assert.same('full', full.reason)
        assert.same(0, countItem(data, 'carp'), '满格也不能把烤鱼吞掉')
        local session = ctx.mgr:GetSession(player)
        assert.same('ready', session.state)
        advance(1.5) -- 曲线已跌到 0.75，但倍率在首次取出时冻结
        data.Data.Containers[GameCfg.Items.ContainerId.Backpack][1] = nil
        local retry = act(player, { action = 'Takeout' })
        assert.is_true(retry.ok)
        assert.same(1.5, retry.rate, '满格冻结倍率，重试不继续烤')
        local entry = findEntry(data, 'carp')
        assert.is_not_nil(entry)
        assert.same(1.5, entry.cooked)
    end)

    -- 资格：烤过的鱼不能再烤；非鱼获（鱼竿）不能烤
    it("test_only_uncooked_catches_are_grillable", function()
        local player, data = join(8240)
        giveSelected(data, 'bass', 1.5, 1.5) -- 已烤过
        local recook = act(player, { action = 'Start' })
        assert.is_false(recook.ok)
        assert.same('no-fish', recook.reason)
        assert.same(1, countItem(data, 'bass'), '拒绝时不扣物')
        assert.is_true(data:AddItem('normalRod'))
        assert.is_true(data:SelectSlot(2))
        local rod = act(player, { action = 'Start' })
        assert.is_false(rod.ok)
        assert.same('no-fish', rod.reason)
    end)

    -- 同请求重放不重复结算：开烤重放不移除第二件，取出重放不多发一件
    it("test_replay_never_settles_twice", function()
        local player, data = join(8180)
        giveSelected(data, 'carp', 1.5)
        assert.is_true(data:AddItem('bass', 1.1))
        ctx.events.GrillAction.OnServerEvent:Fire(player, { action = 'Start', seq = 1 })
        drain()
        assert.same(0, countItem(data, 'carp'))
        ctx.events.GrillAction.OnServerEvent:Fire(player, { action = 'Start', seq = 1 }) -- 重放
        drain()
        assert.same(1, countItem(data, 'bass'), '重放不能再移走别的物品')
        assert.is_true(player.grillResults[#player.grillResults].ok)
        advance(2)
        ctx.events.GrillAction.OnServerEvent:Fire(player, { action = 'Takeout', seq = 2 })
        drain()
        ctx.events.GrillAction.OnServerEvent:Fire(player, { action = 'Takeout', seq = 2 }) -- 重放
        drain()
        assert.same(1, countItem(data, 'carp'), '取出重放不复制物品')
    end)

    -- 会话中不能再开第二炉
    it("test_second_start_while_cooking_is_busy", function()
        local player, data = join(8250)
        giveSelected(data, 'carp', 1.5)
        assert.is_true(data:AddItem('bass', 1.2))
        assert.is_true(act(player, { action = 'Start' }).ok)
        assert.is_true(data:SelectSlot(2))
        local second = act(player, { action = 'Start' })
        assert.is_false(second.ok)
        assert.same('busy', second.reason)
        assert.same(1, countItem(data, 'bass'))
    end)

    -- 两玩家身份交错：B 取不到 A 的会话物，A 正常取出
    it("test_sessions_are_isolated_per_player", function()
        local a, dataA = join(8170)
        local b, dataB = join(8171)
        giveSelected(dataA, 'carp', 1.5)
        giveSelected(dataB, 'bass', 1.2)
        assert.is_true(act(a, { action = 'Start' }).ok)
        advance(2)
        local stolen = act(b, { action = 'Takeout' })
        assert.is_false(stolen.ok)
        assert.same('no-session', stolen.reason)
        assert.same(0, countItem(dataB, 'carp'), 'B 拿不到 A 的鱼')
        assert.is_true(act(a, { action = 'Takeout' }).ok)
        assert.same(1, countItem(dataA, 'carp'))
        assert.same(0, countItem(dataA, 'bass'))
    end)

    -- 开烤：选中未烤鱼获被移出库存、会话建立、状态下发 cooking
    it("test_start_locks_item_into_session", function()
        local player, data = join(8101)
        giveSelected(data, 'carp', 1.5)
        local reply = act(player, { action = 'Start' })
        assert.is_true(reply.ok)
        assert.same('carp', reply.itemId)
        assert.same(1.5, reply.mult)
        assert.same(1000, reply.startedAt)
        assert.same(0, countItem(data, 'carp'), '投入后库存里不再有这件')
        local session = ctx.mgr:GetSession(player)
        assert.is_not_nil(session)
        assert.same('cooking', session.state)
        assert.same('cooking', player.grillState.state)
        assert.is_nil(data.Data.SelectedSlot, '投入后选中格归位')
    end)

    -- 验收边界：0 / 2 / 2.5 秒取出倍率 1 / 1.5 / 1.5，烤过标记随存档落位
    it("test_takeout_boundary_rates", function()
        local cases = { { 0, 1 }, { 2, 1.5 }, { 2.5, 1.5 } }
        for index, case in ipairs(cases) do
            local player, data = join(8110 + index)
            giveSelected(data, 'carp', 1.5)
            assert.is_true(act(player, { action = 'Start' }).ok)
            advance(case[1])
            local reply = act(player, { action = 'Takeout' })
            assert.is_true(reply.ok)
            assert.same(case[2], reply.rate)
            local entry = findEntry(data, 'carp')
            assert.is_not_nil(entry)
            assert.same(case[2], entry.cooked)
            assert.same(case[2], entry.saved.k, '倍率要随存档槽位持久化')
            assert.is_nil(data.Extra.recovery.grill, '取出后不再有待恢复会话')
            assert.is_nil(ctx.mgr:GetSession(player))
        end
    end)

    -- #137 审查修复：取出与 Start 同口径要求玩家在烧烤点旁——走远取出被拒（会话不消费、不发还），
    -- 靠近后取出成功。恢复/自动结算路径不经过 RequestTakeout，不受此校验影响
    it("test_takeout_requires_player_near_grill", function()
        local player, data = join(8141)
        giveSelected(data, 'carp', 1.5)
        assert.is_true(act(player, { action = 'Start' }).ok)
        advance(2)
        player.Character.Position = { x = ctx.anchorPos.x + 100, y = ctx.anchorPos.y, z = ctx.anchorPos.z }
        local rejected = act(player, { action = 'Takeout' })
        assert.is_false(rejected.ok)
        assert.same('out-of-range', rejected.reason)
        assert.same(0, countItem(data, 'carp'), '远程取出被拒不能发还物品')
        assert.same('cooking', player.grillState.state, '会话仍在烤，未被远程取出消费')
        player.Character.Position = { x = ctx.anchorPos.x + 1, y = ctx.anchorPos.y, z = ctx.anchorPos.z }
        assert.is_true(act(player, { action = 'Takeout' }).ok)
        assert.same(1, countItem(data, 'carp'))
        assert.same(1, data.Data.SelectedSlot, '靠近后取出成功且保持选中')
    end)

    -- 取出放回可用格位并保持选中（验收）
    it("test_takeout_returns_to_free_slot_and_keeps_selection", function()
        local player, data = join(8140)
        giveSelected(data, 'carp', 1.5)
        assert.is_true(act(player, { action = 'Start' }).ok)
        advance(2)
        assert.is_true(act(player, { action = 'Takeout' }).ok)
        assert.same('carp', data.Data.Containers[GameCfg.Items.ContainerId.ItemBar][1].itemId)
        assert.same(1, data.Data.SelectedSlot, '取出后保持选中')
    end)

    -- 信物守卫：未确认先提示（不扣物），确认后才开烤；烤过信物倍率照走
    it("test_token_requires_confirm_first", function()
        local player, data = join(8230)
        giveSelected(data, 'eelHead')
        local warned = act(player, { action = 'Start' })
        assert.is_false(warned.ok)
        assert.same('token-warn', warned.reason)
        assert.same(1, countItem(data, 'eelHead'), '提示阶段不扣信物')
        local started = act(player, { action = 'Start', confirm = true })
        assert.is_true(started.ok)
        assert.same(0, countItem(data, 'eelHead'))
        advance(2)
        assert.is_true(act(player, { action = 'Takeout' }).ok)
        local entry = findEntry(data, 'eelHead')
        assert.is_not_nil(entry)
        assert.same(1.5, entry.cooked)
    end)
end)

describe("烤鱼的售价", function()
    -- 旧布尔标记仍是烤熟价 ×1.5
    it("test_legacy_boolean_keeps_cooked_scale", function()
        assert.same(30, GameCfg.Items.SalePrice('garHead', nil, true))  -- floor(20 × 1 × 1.5)
        assert.same(18, GameCfg.Items.SalePrice('bass', 2, true))
        assert.same(12, GameCfg.Items.SalePrice('bass', 2))             -- 未烤原价
    end)

    -- 取出倍率直接定价：价格 = 基础价 × 个体倍率 × 烤制倍率（#137）
    it("test_numeric_rate_prices", function()
        assert.same(25, GameCfg.Items.SalePrice('garHead', nil, 1.25))  -- floor(20 × 1 × 1.25)
        assert.same(10, GameCfg.Items.SalePrice('garHead', nil, 0.5))   -- 下降段取出也值钱
        assert.same(9, GameCfg.Items.SalePrice('bass', 2, 0.75))        -- floor(6 × 2 × 0.75)
        assert.same(18, GameCfg.Items.SalePrice('bass', 2, 1.5))        -- floor(6 × 2 × 1.5)
    end)
end)

-- 切片五接线断言：双端入口与 ScreenMain 前缀渲染
describe("烧烤的接线", function()
    -- 接线断言（server/main.lua）：MgrGrill 注册、依赖注入、BeforeLeave 先于存档序列化
    it("test_client_main_starts_screen_grill", function()
        local file = assert(io.open('client/main.lua', 'r'))
        local src = file:read('*a')
        file:close()
        assert.matches('ScreenGrill = require("client.ScreenHandlers.ScreenGrill")', src, nil, true)
        assert.matches('ScreenGrill:Start()', src, nil, true)
        local file2 = assert(io.open('client/ScreenHandlers/ScreenMain.lua', 'r'))
        local src2 = file2:read('*a')
        file2:close()
        assert.matches('GameCfg.Grill.CookedPrefix', src2, nil, true)
    end)

    it("test_server_main_wires_grill", function()
        local file = assert(io.open('server/main.lua', 'r'))
        local src = file:read('*a')
        file:close()
        assert.matches('MgrGrill = require("server.Mgr.MgrGrill")', src, nil, true)
        assert.matches('MgrMap.MgrGrill.Vitals = MgrMap.MgrVitals', src, nil, true)
        assert.matches('MgrMap.MgrGrill.PlayerData = MgrMap.MgrPlayerData', src, nil, true)
        assert.matches('MgrMap.MgrGrill.Save = MgrMap.MgrSave', src, nil, true)
        assert.is_nil(src:find('MgrMap.MgrGrill.Loot'), '满格走 ready 冻结重试，不接 MgrLoot')
        assert.is_not_nil(src:find("MgrGrill', MgrMap.MgrGrill, 'BeforeLeave'"),
            '离开前要先结算烧烤会话再序列化存档')
    end)
end)

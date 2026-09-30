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


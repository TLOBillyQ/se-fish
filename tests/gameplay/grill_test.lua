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

-- #38 本地收线反馈：点击先显示 +5%，与权威差距 ≤5% 不调整，超过则 150–200ms 内平滑追平。
-- 失败方式（先列后写）：
--   1. 点击不立即显示 +5%，或追平途中点击没有即时反馈；
--   2. 差距 ≤5% 时也去拉显示值（抖动），或差距 >5% 时不追；
--   3. 追平是瞬跳、或用时不在 150–200ms、或途中越过目标 / 往回跳；
--   4. 已发出但服务端还没处理的点击被当成「本地超前」，误追向下再弹回；
--   5. 服务端 clamp 少采纳时显示值永远停在高位；在途记录不过期造成长期偏高；
--   6. 两次权威报告之间显示值不衰减，或越出 [0,100]；
--   7. 服务端 progress 回包不带 q，客户端没法确认在途批次。
local lu = require('luaunit')
local ReelDisplay = require('common.ReelDisplay')

TestReelDisplay = {}

local cfg = { Initial = 50, DecayPerSec = 5, ClickGain = 5, Tolerance = 5, ChaseSec = 0.18, PendingTimeoutSec = 1 }

function TestReelDisplay:test_click_shows_gain_immediately_and_decays_locally()
    local d = ReelDisplay.New(0, cfg)
    lu.assertEquals(d:Value(0), 50)
    d:Click(0)
    lu.assertEquals(d:Value(0), 55)
    lu.assertAlmostEquals(d:Value(1), 50, 1e-9)
end

function TestReelDisplay:test_within_tolerance_keeps_local_value()
    local d = ReelDisplay.New(0, cfg)
    d:Authority(0.1, 45.5)
    lu.assertAlmostEquals(d:Value(0.1), 49.5, 1e-9)
    lu.assertAlmostEquals(d:Value(0.3), 48.5, 1e-9)
end

function TestReelDisplay:test_beyond_tolerance_chases_smoothly_within_window()
    local d = ReelDisplay.New(0, cfg)
    d:Authority(0, 40)
    lu.assertEquals(d:Value(0), 50)
    local mid = d:Value(0.09)
    lu.assertTrue(mid < 50 and mid > 39.55, tostring(mid))
    local last = 50
    for step = 1, 18 do
        local value = d:Value(step * 0.01)
        lu.assertTrue(value <= last + 1e-9, '追平途中往回跳')
        last = value
    end
    lu.assertAlmostEquals(d:Value(0.18), 40 - 5 * 0.18, 1e-9)
    lu.assertAlmostEquals(d:Value(0.5), 40 - 5 * 0.5, 1e-9)
    lu.assertTrue(cfg.ChaseSec >= 0.15 and cfg.ChaseSec <= 0.2)
end

function TestReelDisplay:test_upward_chase_when_server_ahead()
    local d = ReelDisplay.New(0, cfg)
    d:Authority(0, 70)
    lu.assertAlmostEquals(d:Value(0.2), 70 - 1, 1e-9)
end

function TestReelDisplay:test_in_flight_clicks_do_not_trigger_false_down_chase()
    local d = ReelDisplay.New(0, cfg)
    for _ = 1, 4 do d:Click(0) end
    lu.assertEquals(d:Value(0), 70)
    d:Authority(0.05, 49.75)
    lu.assertAlmostEquals(d:Value(0.05), 69.75, 1e-9)
    d:Sent(1, 4, 0.1)
    d:Authority(0.12, 49.4)
    lu.assertAlmostEquals(d:Value(0.12), 69.4, 1e-9)
    d:Authority(0.2, 69, 1)
    lu.assertAlmostEquals(d:Value(0.2), 69, 1e-9)
end

function TestReelDisplay:test_clamped_batch_is_corrected_downward()
    local d = ReelDisplay.New(0, cfg)
    for _ = 1, 6 do d:Click(0) end
    d:Sent(1, 6, 0)
    d:Authority(0.1, 59.5, 1)
    lu.assertAlmostEquals(d:Value(0.1 + cfg.ChaseSec), 59.5 - 5 * cfg.ChaseSec, 1e-9)
end

function TestReelDisplay:test_unacknowledged_batch_expires()
    local d = ReelDisplay.New(0, cfg)
    for _ = 1, 3 do d:Click(0) end
    d:Sent(1, 3, 0)
    d:Authority(1.5, 42.5)
    lu.assertAlmostEquals(d:Value(1.5 + cfg.ChaseSec), 42.5 - 5 * cfg.ChaseSec, 1e-9)
end

function TestReelDisplay:test_click_during_chase_still_gives_feedback()
    local d = ReelDisplay.New(0, cfg)
    d:Authority(0, 30)
    local before = d:Value(0.09)
    d:Click(0.09)
    lu.assertAlmostEquals(d:Value(0.09), before + 5, 1e-9)
    lu.assertAlmostEquals(d:Value(0.09 + cfg.ChaseSec), 35 - 5 * (0.09 + cfg.ChaseSec), 1e-9)
end

function TestReelDisplay:test_value_stays_within_bounds()
    local d = ReelDisplay.New(0, cfg)
    for _ = 1, 30 do d:Click(0) end
    lu.assertEquals(d:Value(0), 100)
    lu.assertEquals(ReelDisplay.New(0, cfg):Value(100), 0)
    local e = ReelDisplay.New(0, cfg)
    e:Authority(0, 2)
    lu.assertTrue(e:Value(5) >= 0)
end

function TestReelDisplay:test_config_carries_display_parameters()
    local GameCfg = assert(loadfile('common/GameCfg.lua'))()
    lu.assertEquals(GameCfg.ReelIn.Tolerance, 5)
    lu.assertTrue(GameCfg.ReelIn.ChaseSec >= 0.15 and GameCfg.ReelIn.ChaseSec <= 0.2)
    lu.assertTrue(GameCfg.ReelIn.PendingTimeoutSec > GameCfg.HighFreqInput.AggregateSec)
end

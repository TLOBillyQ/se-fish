-- 迁移自 tests/gameplay/reel_display_test.lua（#85）；行为契约原文见 #38。
-- #38 本地收线反馈：点击先显示 +5%，与权威差距 ≤5% 不调整，超过则 150–200ms 内平滑追平。
-- 失败方式（先列后写）：
--   1. 点击不立即显示 +5%，或追平途中点击没有即时反馈；
--   2. 差距 ≤5% 时也去拉显示值（抖动），或差距 >5% 时不追；
--   3. 追平是瞬跳、或用时不在 150–200ms、或途中越过目标 / 往回跳；
--   4. 已发出但服务端还没处理的点击被当成「本地超前」，误追向下再弹回；
--   5. 服务端 clamp 少采纳时显示值永远停在高位；在途记录不过期造成长期偏高；
--   6. 两次权威报告之间显示值不衰减，或越出 [0,100]；
--   7. 服务端 progress 回包不带 q，客户端没法确认在途批次。
-- it 名字沿用旧方法名，注册顺序 = LuaUnit sortedPairs 的实际执行顺序。
local ReelDisplay = require('common.ReelDisplay')

-- 只读夹具：与旧套件一样在文件顶层共享，用例不修改它。
local cfg = { Initial = 50, DecayPerSec = 5, ClickGain = 5, Tolerance = 5, ChaseSec = 0.18, PendingTimeoutSec = 1 }

describe('本地收线显示（ReelDisplay）', function()
  it('test_beyond_tolerance_chases_smoothly_within_window', function()
    local d = ReelDisplay.New(0, cfg)
    d:Authority(0, 40)
    assert.same(50, d:Value(0))
    local mid = d:Value(0.09)
    assert.message(tostring(mid)).is_true(mid < 50 and mid > 39.55)
    local last = 50
    for step = 1, 18 do
      local value = d:Value(step * 0.01)
      assert.message('追平途中往回跳').is_true(value <= last + 1e-9)
      last = value
    end
    assert.near(40 - 5 * 0.18, d:Value(0.18), 1e-9)
    assert.near(40 - 5 * 0.5, d:Value(0.5), 1e-9)
    assert.is_true(cfg.ChaseSec >= 0.15 and cfg.ChaseSec <= 0.2)
  end)

  it('test_clamped_batch_is_corrected_downward', function()
    local d = ReelDisplay.New(0, cfg)
    for _ = 1, 6 do d:Click(0) end
    d:Sent(1, 6, 0)
    d:Authority(0.1, 59.5, 1)
    assert.near(59.5 - 5 * cfg.ChaseSec, d:Value(0.1 + cfg.ChaseSec), 1e-9)
  end)

  it('test_click_during_chase_still_gives_feedback', function()
    local d = ReelDisplay.New(0, cfg)
    d:Authority(0, 30)
    local before = d:Value(0.09)
    d:Click(0.09)
    assert.near(before + 5, d:Value(0.09), 1e-9)
    assert.near(35 - 5 * (0.09 + cfg.ChaseSec), d:Value(0.09 + cfg.ChaseSec), 1e-9)
  end)

  it('test_click_shows_gain_immediately_and_decays_locally', function()
    local d = ReelDisplay.New(0, cfg)
    assert.same(50, d:Value(0))
    d:Click(0)
    assert.same(55, d:Value(0))
    assert.near(50, d:Value(1), 1e-9)
  end)

  it('test_config_carries_display_parameters', function()
    local GameCfg = assert(loadfile('common/GameCfg.lua'))()
    assert.same(5, GameCfg.ReelIn.Tolerance)
    assert.is_true(GameCfg.ReelIn.ChaseSec >= 0.15 and GameCfg.ReelIn.ChaseSec <= 0.2)
    assert.is_true(GameCfg.ReelIn.PendingTimeoutSec > GameCfg.HighFreqInput.AggregateSec)
  end)

  it('test_in_flight_clicks_do_not_trigger_false_down_chase', function()
    local d = ReelDisplay.New(0, cfg)
    for _ = 1, 4 do d:Click(0) end
    assert.same(70, d:Value(0))
    d:Authority(0.05, 49.75)
    assert.near(69.75, d:Value(0.05), 1e-9)
    d:Sent(1, 4, 0.1)
    d:Authority(0.12, 49.4)
    assert.near(69.4, d:Value(0.12), 1e-9)
    d:Authority(0.2, 69, 1)
    assert.near(69, d:Value(0.2), 1e-9)
  end)

  it('test_unacknowledged_batch_expires', function()
    local d = ReelDisplay.New(0, cfg)
    for _ = 1, 3 do d:Click(0) end
    d:Sent(1, 3, 0)
    d:Authority(1.5, 42.5)
    assert.near(42.5 - 5 * cfg.ChaseSec, d:Value(1.5 + cfg.ChaseSec), 1e-9)
  end)

  it('test_upward_chase_when_server_ahead', function()
    local d = ReelDisplay.New(0, cfg)
    d:Authority(0, 70)
    assert.near(69, d:Value(0.2), 1e-9)
  end)

  it('test_value_stays_within_bounds', function()
    local d = ReelDisplay.New(0, cfg)
    for _ = 1, 30 do d:Click(0) end
    assert.same(100, d:Value(0))
    assert.same(0, ReelDisplay.New(0, cfg):Value(100))
    local e = ReelDisplay.New(0, cfg)
    e:Authority(0, 2)
    assert.is_true(e:Value(5) >= 0)
  end)

  it('test_within_tolerance_keeps_local_value', function()
    local d = ReelDisplay.New(0, cfg)
    d:Authority(0.1, 45.5)
    assert.near(49.5, d:Value(0.1), 1e-9)
    assert.near(48.5, d:Value(0.3), 1e-9)
  end)
end)

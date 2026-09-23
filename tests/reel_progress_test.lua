local lu = require('luaunit')
local Core = require('common.ReelProgress')
local cfg = require('common.GameCfg').ReelIn

TestReelProgress = {}

function TestReelProgress:test_natural_unhook_and_grace()
    local reel = Core.New(0, cfg)
    lu.assertNil(reel:Advance(10))
    lu.assertEquals(reel.Progress, 0)
    lu.assertAlmostEquals(reel.ZeroAt, 10, 0.00001)
    lu.assertNil(reel:Advance(10.17))
    lu.assertEquals(reel:Advance(10.181), 'unhooked')
    lu.assertEquals(reel:Advance(20, 10), 'unhooked')
end

function TestReelProgress:test_zero_rescue_and_late_packet()
    local reel = Core.New(0, cfg)
    reel:Advance(10.1)
    lu.assertNil(reel:Advance(10.16, 1, 0.1))
    lu.assertAlmostEquals(reel.Progress, 5, 0.5)
    local late = Core.New(0, cfg)
    late:Advance(10.1)
    lu.assertEquals(late:Advance(10.19, 1, 0.1), 'unhooked')
    local withoutTick = Core.New(0, cfg)
    lu.assertEquals(withoutTick:Advance(10.19, 1, 0.1), 'unhooked')
end

function TestReelProgress:test_exact_hundred_and_batch_integral()
    local reel = Core.New(0, cfg)
    lu.assertEquals(reel:Advance(0, 10, 0.1), 'landed')
    lu.assertEquals(reel.Progress, 100)
    local spread = Core.New(0, cfg)
    spread:Advance(1, 3, 0.1)
    lu.assertAlmostEquals(spread.Progress, 60, 0.00001)
    local distributed = Core.New(0, cfg)
    distributed:Advance(0.1, 1, 0.1)
    lu.assertAlmostEquals(distributed.Progress, 54.5, 0.00001)
end

function TestReelProgress:test_frame_partition_error_under_half_percent()
    local a, b = Core.New(0, cfg), Core.New(0, cfg)
    for i = 1, 100 do a:Advance(i / 100) end
    b:Advance(1)
    lu.assertTrue(math.abs(a.Progress - b.Progress) <= 0.5)
end

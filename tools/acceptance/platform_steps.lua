-- #147 验收复用单测的引擎边界夹具，调用真实管理器公共接口；支付替身不代表真实平台验收。
package.path = './tests/lib/?.lua;' .. package.path
dofile('tests/gameplay/blindbox_settle_test.lua')
dofile('tests/gameplay/revive_callback_test.lua')
local GameCfg = require('common.GameCfg')

local function finish(w, check)
    local ok, err = pcall(check)
    w.fixture:tearDown()
    assert(ok, err)
end

return { patterns = {
    { '^平台接缝测试档已就绪$', function(w)
        w.fixture = setmetatable({}, { __index = TestBlindboxSettle })
        w.fixture:setUp()
    end },
    { '^盲盒连续未中为 (%d+)$', function(w, n)
        w.fixture.data.Extra.lottery.pity = tonumber(n)
        w.fixture:persistReady()
    end },
    { '^盲盒单抽支付成功且保底选择 (%d+)$', function(w, roll)
        w.fixture.rolls = { tonumber(roll) }
        assert(w.fixture:draw(1, 1, 'success'))
    end },
    { '^盲盒单抽支付成功且普通选择 (%d+)$', function(w, roll)
        w.fixture.rolls = { tonumber(roll) }
        assert(w.fixture:draw(1, 1, 'success'))
    end },
    { '^盲盒玩家重进$', function(w)
        local f = w.fixture
        w.original = f:lastResult()
        f.players:OnPlayerAdded(f.player)
        f:drain()
        f.data = f.players:GetDataInst(f.player)
        f.blindbox:PushState(f.player)
    end },
    { '^盲盒奖品为 (%w+) 且保底计数为 (%d+)$', function(w, item, pity)
        finish(w, function()
            assert(w.original.draws[1].itemKey == item and w.original.draws[1].guaranteed)
            assert(w.fixture.data.Extra.lottery.pity == tonumber(pity))
            assert(w.fixture:lastResult().pity == tonumber(pity))
        end)
    end },
    { '^盲盒十连第五抽保底支付成功$', function(w)
        w.fixture.rolls = { 1000, 1000, 1000, 1000, 2, 1000, 1000, 1000, 1000, 1000 }
        assert(w.fixture:draw(10, 1, 'success'))
    end },
    { '^第五抽保底且后五抽连续未中计数为 (%d+)$', function(w, pity)
        finish(w, function()
            local r = w.fixture:lastResult()
            assert(r.draws[5].guaranteed and r.draws[5].pityAfter == 0)
            assert(r.pityAfter == tonumber(pity) and w.fixture.data.Extra.lottery.pity == tonumber(pity))
        end)
    end },
    { '^盲盒玩家库存全满$', function(w)
        while w.fixture.data:AddItem('carp') do end
        w.fixture:persistReady()
    end },
    { '^盲盒请求原序号重试$', function(w)
        assert(w.fixture.blindbox:Handle(w.fixture.player, { action = 'Draw', count = 1, seq = 1 }))
        w.fixture:drain()
    end },
    { '^盲盒只落地一件倍率1奖品且计数只增加一次$', function(w)
        finish(w, function()
            assert(#w.fixture.spawned == 1 and w.fixture.spawned[1].mult == 1)
            assert(w.fixture.data.Extra.lottery.pity == 1)
            assert(not w.fixture.platform:HasFlow(w.fixture.player))
        end)
    end },
    { '^关闭调试后尝试盲盒与测试支付成功$', function(w)
        GameCfg.Debug = { Enabled = false }
        assert(w.fixture.blindbox:Handle(w.fixture.player, { action = 'Draw', count = 1, seq = 1 }))
        w.fixture:drain()
        assert(not w.fixture.platform:HandleTestAction(w.fixture.player,
            { action = 'ResolveFlow', outcome = 'success' }))
    end },
    { '^未配置平台不发奖也不改变保底$', function(w)
        finish(w, function()
            assert(w.fixture:lastResult().reason == 'unavailable')
            assert(w.fixture.data.Extra.lottery.pity == 0 and #w.fixture.spawned == 0)
            assert(w.fixture.data:ItemCount('item7') == 0)
        end)
    end },
    { '^玩家濒死后购买一份肾上腺素并自救$', function(w)
        local f = w.fixture
        -- 生命夹具提供控制器与信号，结算仍用本场景真实存档和平台管理器。
        local life = setmetatable({}, { __index = TestReviveCallback })
        life:setUp()
        w.life = life
        local s, v = life.s, life.v
        s.States[f.player.UserId], v.States[f.player.UserId] = s.States[life.player.UserId], v.States[life.player.UserId]
        s.States[life.player.UserId], v.States[life.player.UserId] = nil, nil
        f.player.Character = life.player.Character
        life.player = f.player
        s.States[f.player.UserId].player, v.States[f.player.UserId].player = f.player, f.player
        s.PlayerData, s.Save, s.Platform = f.players, f.save, f.platform
        life:ctrl().Health = 50
        v:ApplyHit(v:NewHit(life.attacker, 'fishAttack'), life.player, 100)
        assert(s:Phase(life.player) == 'downed')
        assert(f.platform:HandleAction(life.player, { action = 'Purchase', goods = 'adrenaline1' }))
        assert(f.platform:HandleTestAction(life.player, { action = 'ResolveFlow', outcome = 'success' }))
        f:drain()
        assert(f.data:ItemCount(GameCfg.Survival.AdrenalineItemId) == 1)
        assert(s:UseAdrenaline(life.player, { seq = 1 }))
        f:drain()
    end },
    { '^玩家恢复10%%血量且只消耗一份肾上腺素$', function(w)
        local ok, err = pcall(function()
            assert(w.life.s:Phase(w.life.player) == 'alive')
            assert(w.life:ctrl().Health == GameCfg.Vitals.MaxHealth * 0.1)
            assert(w.fixture.data:ItemCount(GameCfg.Survival.AdrenalineItemId) == 0)
        end)
        w.life:tearDown()
        w.fixture:tearDown()
        assert(ok, err)
    end },
    { '^复活回调测试档已死亡$', function(w)
        w.fixture = setmetatable({}, { __index = TestReviveCallback })
        w.fixture:setUp()
        w.fixture:enterDead()
    end },
    { '^广告成功后免费倒计时与迟到超时再次触发$', function(w)
        local f = w.fixture
        assert(f.s:PlatformRevive(f.player, { mode = 'ad', seq = 1 }))
        f.platformFlow.onResult('success')
        f.now = f.now + GameCfg.Survival.DeadSec + 1
        f.s:Update()
        f.platformFlow.onResult('timeout')
        f.platformFlow.onResult('success')
    end },
    { '^本轮只有一次满血复活结果$', function(w)
        finish(w, function()
            local f = w.fixture
            assert(f.s:Phase(f.player) == 'alive' and f:ctrl().Health == GameCfg.Vitals.MaxHealth)
            assert(#f:results() == 1)
        end)
    end },
    { '^平台回调为 ([%w]+) 后免费倒计时结束$', function(w, outcome)
        local f = w.fixture
        assert(f.s:PlatformRevive(f.player, { mode = 'ad', seq = 1 }))
        f.now = f.now + 7
        f.platformFlow.onResult(outcome)
        f.now = f.now + GameCfg.Survival.DeadSec
        f.s:Update()
        f.platformFlow.onResult('success') -- 免费复活后迟到成功不能覆盖
        f.s:Update()
    end },
    { '^本轮只产生一次10%%血量虚弱复活$', function(w)
        finish(w, function()
            local f = w.fixture
            assert(f.s:Phase(f.player) == 'alive' and f:ctrl().Health == GameCfg.Vitals.MaxHealth * 0.1)
            assert(#f:results() == 1 and f:lastResult().ok == false)
            assert(f.s:GetState(f.player).weakUntil ~= nil)
        end)
    end },
} }

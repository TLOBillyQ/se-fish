-- #89 迁移（原 tests/gameplay/revive_callback_test.lua，#147 T26 平台复活回调状态）：
-- server/Mgr/MgrSurvival.lua 扩展。失败方式先列：
--   1. 相位错：活动/濒死相位也能发起平台满血复活；离线恢复中（recovering）放行；
--   2. 暂停错：平台 flow 在飞时免费死亡倒计时照跑（玩家还没看完广告就被虚弱复活）；
--   3. 互斥错：成功回调、迟到回调不互斥——成功回调后又来迟到回调二次复活/二次回包，
--      或成功后免费倒计时又触发虚弱复活覆盖满血；
--   4. 恢复错：取消/失败/超时回调后免费倒计时没平移暂停时长（提前或延后触发）；
--   5. 满血口径错：满血复活血量不是 MaxHealth、饥饿低于 10%、或错误带上虚弱（虚弱只属于免费复活）；
--   6. 迟到回调错：新一轮死亡（episode 前进）后旧 flow 回调改新状态；旧 platform 标记的回调串场；
--   7. 可用性错：平台不可用（生产未配置）时不明确回包，或还暂停了倒计时；
--   8. 并发错：flow 在飞时重复发起被接受（应 busy），payload 畸形报错而不是拒绝。
-- seam：MgrSurvival:PlatformRevive / FullRevive / Update 暂停分支；真实 MgrVitals + MgrSurvival，
--   Platform 替身脚本化回调（成功/取消/失败/超时/迟到由测试驱动）；REUtil 替身收 SurvivalResult。
-- 旧 setUp 是逐例的（含替换 package.loaded['common.REUtil']），映射为 before_each，
-- after_each 恢复模块缓存，并对未完成的 before_each 幂等。
-- describe/it 名沿用旧类名与方法名，案例顺序沿用旧 LuaUnit 的字典序执行序。
local GameCfg = require('common.GameCfg')

local function signal()
    local s = { handlers = {} }
    function s:Connect(fn)
        self.handlers[#self.handlers + 1] = fn
        return { Disconnect = function() end }
    end
    function s:Fire(...) for _, fn in ipairs(self.handlers) do fn(...) end end
    return s
end

local function newPlayer(id)
    local c = { Health = 300, MaxHealth = 300, WalkSpeed = 10, HealthChanged = signal(),
        Died = signal(), OnReborn = signal() }
    function c:TakeDamage(n)
        self.Health = math.max(0, self.Health - n)
        self.HealthChanged:Fire(self.Health)
        if self.Health <= 0 then self.Died:Fire() end
    end
    local p = { UserId = id, Name = 'p' .. id, attrs = {}, CharacterAdded = signal(),
        Character = { Controller = c, Position = { x = id, y = 0, z = 0 } } }
    function p:SetAttribute(k, v) self.attrs[k] = v end
    return p
end

-- 平台替身：记录拉起参数，回调由测试脚本化驱动（含迟到回调）
local function newPlatform(state)
    return {
        calls = {},
        ShowAd = function(_, player, adKey, purpose, onResult)
            local call = { kind = 'ad', adKey = adKey, purpose = purpose, onResult = onResult }
            state.platform.calls[#state.platform.calls + 1] = call
            if state.platformUnavailable then return false, 'unavailable' end
            state.platformFlow = call
            return true
        end,
        Purchase = function(_, player, goodsKey, purpose, onResult)
            local call = { kind = 'goods', goodsKey = goodsKey, purpose = purpose, onResult = onResult }
            state.platform.calls[#state.platform.calls + 1] = call
            if state.platformUnavailable then return false, 'unavailable' end
            state.platformFlow = call
            return true
        end,
    }
end

describe('TestReviveCallback', function()
    local ctx

    -- 旧案例在循环里重复调用 setUp/tearDown 来换一套全新管理器（但会把 savedRE 覆盖成上一轮的桩，
    -- 泄漏给后续类）。原生侧把「装一套新夹具」抽成 install()：savedRE 只在真正进入案例时抓一次，
    -- 循环内重装夹具不再改它，after_each 总能恢复到进案例前的模块缓存。
    local function install(state)
        state.now = 100
        state.messages = {}
        package.loaded['common.REUtil'] = {
            GetRE = function(_, name)
                state.messages[name] = state.messages[name] or {}
                return { FireClient = function(_, player, value)
                    table.insert(state.messages[name], { player = player, value = value })
                end, OnServerEvent = signal() }
            end,
            CheckRECD = function() return false end,
        }
        state.platformUnavailable = false
        state.platformFlow = nil
        state.platform = newPlatform(state)
        state.v = assert(loadfile('server/Mgr/MgrVitals.lua'))()
        state.v.Now = function() return state.now end
        state.s = assert(loadfile('server/Mgr/MgrSurvival.lua'))()
        state.s.Now = function() return state.now end
        require('tests.tooling.modifier_runtime').AttachSurvival(state.s, function() return state.now end)
        state.s.Vitals = state.v
        state.s.Platform = state.platform
        state.v:SetLifeHooks(state.s:Hooks())
        state.player = newPlayer(1473)
        state.attacker = newPlayer(2)
        state.v:OnPlayerAdded(state.player)
        state.s:OnPlayerAdded(state.player)
    end

    before_each(function()
        ctx = { now = 100, savedRE = package.loaded['common.REUtil'] }
        install(ctx)
    end)

    after_each(function()
        package.loaded['common.REUtil'] = ctx and ctx.savedRE
    end)

    local function ctrl() return ctx.player.Character.Controller end

    local function results()
        return ctx.messages['SurvivalResult'] or {}
    end

    local function lastResult()
        local r = results()
        return r[#r] and r[#r].value or nil
    end

    local function enterDead()
        ctrl().Health = 50
        ctx.v:ApplyHit(ctx.v:NewHit(ctx.attacker, 'fishAttack'), ctx.player, 100) -- 锁血进濒死
        ctx.now = ctx.now + GameCfg.Survival.DownedSec
        ctx.s:Update()
        assert.same('dead', ctx.s:Phase(ctx.player))
    end

    -- 广告成功回调：满血复活（MaxHealth、饥饿至少 10%、无虚弱），回包 ok
    it('test_ad_success_full_revives_without_weakness', function()
        enterDead()
        ctx.v:GetState(ctx.player).hunger = 0 -- 死前饿空：满血复活也要把饥饿抬到 10%
        assert.is_true(ctx.s:PlatformRevive(ctx.player, { action = 'FullRevive', mode = 'ad', seq = 1 }))
        ctx.now = ctx.now + 8
        ctx.platformFlow.onResult('success')
        assert.same('alive', ctx.s:Phase(ctx.player))
        assert.same(GameCfg.Vitals.MaxHealth, ctrl().Health) -- 满血，不是 10%
        assert.is_true(ctx.v:GetState(ctx.player).hunger
            >= math.floor(GameCfg.Vitals.MaxHunger * GameCfg.Survival.ReviveHungerPercent / 100))
        assert.is_nil(ctx.s:GetState(ctx.player).weakUntil) -- 满血复活不带虚弱
        local result = lastResult()
        assert.is_true(result.ok)
        assert.same('FullRevive', result.action)
        assert.same('ad', result.mode)
        assert.same(1, result.seq)
        -- 复活后免费倒计时不应再触发任何复活
        ctx.now = ctx.now + 999
        ctx.s:Update()
        assert.same('alive', ctx.s:Phase(ctx.player))
        assert.same(GameCfg.Vitals.MaxHealth, ctrl().Health)
    end)

    -- 取消/失败/超时：恢复免费倒计时且 deadAt 平移暂停时长，免费复活按原节奏 + 暂停时长触发
    it('test_failed_flows_resume_shifted_free_countdown', function()
        for _, outcome in ipairs({ 'cancel', 'fail', 'timeout' }) do
            install(ctx) -- 旧案例在循环里重复 setUp：换一套全新管理器与时钟
            enterDead()
            local deadAt = ctx.s:GetState(ctx.player).deadAt
            assert.is_true(ctx.s:PlatformRevive(ctx.player, { action = 'FullRevive', mode = 'ad', seq = 1 }))
            ctx.now = ctx.now + 7 -- 平台流程花了 7 秒
            ctx.platformFlow.onResult(outcome)
            local result = lastResult()
            assert.is_false(result.ok)
            assert.same(outcome, result.reason)
            assert.same('dead', ctx.s:Phase(ctx.player))
            -- 倒计时平移：新终点 = 原 deadAt + DeadSec + 暂停 7 秒
            ctx.now = deadAt + GameCfg.Survival.DeadSec + 6.9
            ctx.s:Update()
            assert.same('dead', ctx.s:Phase(ctx.player)) -- 没平移的话这里已经复活了
            ctx.now = deadAt + GameCfg.Survival.DeadSec + 7
            ctx.s:Update()
            assert.same('alive', ctx.s:Phase(ctx.player)) -- 免费虚弱复活照常兜底
            assert.same(math.floor(GameCfg.Vitals.MaxHealth
                * GameCfg.Survival.ReviveHealthPercent / 100), ctrl().Health)
        end
    end)

    -- 相位守卫：活动/濒死不能发起平台复活，不拉起平台、不回包成功
    it('test_full_revive_rejected_outside_dead_phase', function()
        assert.is_false(ctx.s:PlatformRevive(ctx.player, { action = 'FullRevive', mode = 'goods', seq = 1 }))
        assert.same('not-dead', lastResult().reason)
        ctrl().Health = 50
        ctx.v:ApplyHit(ctx.v:NewHit(ctx.attacker, 'fishAttack'), ctx.player, 100) -- 濒死
        assert.same('downed', ctx.s:Phase(ctx.player))
        assert.is_false(ctx.s:PlatformRevive(ctx.player, { action = 'FullRevive', mode = 'ad', seq = 2 }))
        assert.same({}, ctx.platform.calls)
    end)

    -- 5 金豆商品成功回调：同一单点满血复活，走 Purchase('reviveFull')
    it('test_goods_success_full_revives_via_purchase', function()
        enterDead()
        assert.is_true(ctx.s:PlatformRevive(ctx.player, { action = 'FullRevive', mode = 'goods', seq = 1 }))
        assert.same('goods', ctx.platform.calls[1].kind)
        assert.same('reviveFull', ctx.platform.calls[1].goodsKey)
        ctx.platformFlow.onResult('success')
        assert.same('alive', ctx.s:Phase(ctx.player))
        assert.same(GameCfg.Vitals.MaxHealth, ctrl().Health)
    end)

    -- 互斥：成功回调后迟到回调（同 flow 重复驱动/另一结局）不产生第二个复活结果、不再回包
    it('test_late_callback_after_success_is_ignored', function()
        enterDead()
        assert.is_true(ctx.s:PlatformRevive(ctx.player, { action = 'FullRevive', mode = 'goods', seq = 1 }))
        local callback = ctx.platformFlow.onResult
        callback('success')
        assert.same('alive', ctx.s:Phase(ctx.player))
        local resultCount = #results()
        callback('timeout') -- 迟到回调：flow 已结算，不能改状态
        callback('success')
        assert.same('alive', ctx.s:Phase(ctx.player))
        assert.same(GameCfg.Vitals.MaxHealth, ctrl().Health)
        assert.same(resultCount, #results()) -- 没有第二份回包
    end)

    -- 畸形请求：坏 mode / 坏 seq / 非表 payload 拒绝，不碰平台
    it('test_malformed_payloads_rejected', function()
        enterDead()
        assert.is_false(ctx.s:PlatformRevive(ctx.player, nil))
        assert.is_false(ctx.s:PlatformRevive(ctx.player, { action = 'FullRevive', mode = 'cash', seq = 1 }))
        assert.is_false(ctx.s:PlatformRevive(ctx.player, { action = 'FullRevive', mode = 'ad' }))
        assert.is_false(ctx.s:PlatformRevive(ctx.player, { action = 'FullRevive', mode = 'ad', seq = -1 }))
        assert.same({}, ctx.platform.calls)
        assert.is_false(ctx.s:GetState(ctx.player).platform ~= nil) -- 没进入暂停
    end)

    -- 暂停：广告 flow 在飞时免费死亡倒计时冻结，到点不虚弱复活
    it('test_platform_flow_pauses_free_countdown', function()
        enterDead()
        assert.is_true(ctx.s:PlatformRevive(ctx.player, { action = 'FullRevive', mode = 'ad', seq = 1 }))
        assert.same(1, #ctx.platform.calls)
        assert.same('ad', ctx.platform.calls[1].kind)
        assert.same('revive', ctx.platform.calls[1].adKey)
        ctx.now = ctx.now + GameCfg.Survival.DeadSec + 10 -- 远超 30 秒免费倒计时
        ctx.s:Update()
        assert.same('dead', ctx.s:Phase(ctx.player)) -- 倒计时暂停：没被虚弱复活
        assert.same(1, ctrl().Health)
    end)

    -- #139 整合：平台满血复活必须采用玩家成长后的上限，不能退回固定 300。
    it('test_platform_revive_uses_grown_health_cap', function()
        enterDead()
        ctx.v.MaxHealthProvider = function() return 900 end
        ctrl().MaxHealth = 900
        assert.is_true(ctx.s:PlatformRevive(ctx.player, { mode = 'ad', seq = 1 }))
        ctx.platformFlow.onResult('success')
        assert.same(900, ctrl().Health)
    end)

    -- 并发：flow 在飞时重复发起 busy，不再拉起平台
    it('test_second_request_busy_while_flow_in_flight', function()
        enterDead()
        assert.is_true(ctx.s:PlatformRevive(ctx.player, { action = 'FullRevive', mode = 'ad', seq = 1 }))
        assert.is_false(ctx.s:PlatformRevive(ctx.player, { action = 'FullRevive', mode = 'goods', seq = 2 }))
        assert.same('busy', lastResult().reason)
        assert.same(1, #ctx.platform.calls)
    end)

    -- 串场守卫：旧 flow 的回调不能结算新 flow（取消后再发起，旧回调迟到）
    it('test_stale_callback_cannot_settle_new_flow', function()
        enterDead()
        assert.is_true(ctx.s:PlatformRevive(ctx.player, { action = 'FullRevive', mode = 'ad', seq = 1 }))
        local stale = ctx.platformFlow.onResult
        stale('cancel') -- 第一个 flow 正常取消，倒计时恢复
        assert.is_true(ctx.s:PlatformRevive(ctx.player, { action = 'FullRevive', mode = 'ad', seq = 2 }))
        stale('success') -- 旧回调迟到：不能复活（当前 flow 是第二个）
        assert.same('dead', ctx.s:Phase(ctx.player))
        assert.same(1, ctrl().Health)
        ctx.platformFlow.onResult('success') -- 第二个 flow 的成功回调才生效
        assert.same('alive', ctx.s:Phase(ctx.player))
        assert.same(GameCfg.Vitals.MaxHealth, ctrl().Health)
        assert.same(2, lastResult().seq)
    end)

    -- 状态同步：平台 pending 期间 SurvivalState 带 platformPending 标记，恢复后消失
    it('test_state_marks_platform_pending', function()
        enterDead()
        assert.is_true(ctx.s:PlatformRevive(ctx.player, { action = 'FullRevive', mode = 'ad', seq = 1 }))
        local states = ctx.messages['SurvivalState']
        local pending = states[#states].value
        assert.same('dead', pending.phase)
        assert.same('ad', pending.platformPending)
        ctx.platformFlow.onResult('cancel')
        local resumed = ctx.messages['SurvivalState']
        assert.is_nil(resumed[#resumed].value.platformPending)
    end)

    -- 可用性：平台不可用（生产未配置）时明确回包 unavailable，倒计时不暂停
    it('test_unavailable_platform_does_not_pause', function()
        enterDead()
        ctx.platformUnavailable = true
        assert.is_false(ctx.s:PlatformRevive(ctx.player, { action = 'FullRevive', mode = 'goods', seq = 1 }))
        assert.same('unavailable', lastResult().reason)
        assert.is_nil(ctx.s:GetState(ctx.player).platform)
        ctx.now = ctx.now + GameCfg.Survival.DeadSec
        ctx.s:Update()
        assert.same('alive', ctx.s:Phase(ctx.player)) -- 免费倒计时没被打断
    end)
end)

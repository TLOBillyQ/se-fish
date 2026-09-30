-- #147 T26 平台复活回调状态（server/Mgr/MgrSurvival.lua 扩展）失败方式先列：
--   1. 相位错：活动/濒死相位也能发起平台满血复活；离线恢复中（recovering）放行；
--   2. 暂停错：平台 flow 在飞时免费死亡倒计时照跑（玩家还没看完广告就被虚弱复活）；
--   3. 互斥错：免费复活、成功回调、超时回调不互斥——成功回调后又来迟到回调二次复活/二次回包，
--      或成功后免费倒计时又触发虚弱复活覆盖满血；
--   4. 恢复错：取消/失败/超时回调后免费倒计时没平移暂停时长（提前或延后触发）；
--   5. 满血口径错：满血复活血量不是 MaxHealth、饥饿低于 10%、或错误带上虚弱（虚弱只属于免费复活）；
--   6. 迟到回调错：新一轮死亡（episode 前进）后旧 flow 回调改新状态；旧 platform 标记的回调串场；
--   7. 可用性错：平台不可用（生产未配置）时不明确回包，或还暂停了倒计时；
--   8. 并发错：flow 在飞时重复发起被接受（应 busy），payload 畸形报错而不是拒绝。
-- seam：MgrSurvival:PlatformRevive / FullRevive / Update 暂停分支；真实 MgrVitals + MgrSurvival，
--   Platform 替身脚本化回调（成功/取消/失败/超时/迟到由测试驱动）；REUtil 替身收 SurvivalResult。
local lu = require('luaunit')
local GameCfg = require('common.GameCfg')

TestReviveCallback = {}

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
local function newPlatform(env)
    return {
        calls = {},
        ShowAd = function(_, player, adKey, purpose, onResult)
            local call = { kind = 'ad', adKey = adKey, purpose = purpose, onResult = onResult }
            env.platform.calls[#env.platform.calls + 1] = call
            if env.platformUnavailable then return false, 'unavailable' end
            env.platformFlow = call
            return true
        end,
        Purchase = function(_, player, goodsKey, purpose, onResult)
            local call = { kind = 'goods', goodsKey = goodsKey, purpose = purpose, onResult = onResult }
            env.platform.calls[#env.platform.calls + 1] = call
            if env.platformUnavailable then return false, 'unavailable' end
            env.platformFlow = call
            return true
        end,
    }
end

function TestReviveCallback:setUp()
    local env = self
    self.now = 100
    self.messages = {}
    self.savedRE = package.loaded['common.REUtil']
    package.loaded['common.REUtil'] = {
        GetRE = function(_, name)
            self.messages[name] = self.messages[name] or {}
            return { FireClient = function(_, player, value)
                table.insert(env.messages[name], { player = player, value = value })
            end, OnServerEvent = signal() }
        end,
        CheckRECD = function() return false end,
    }
    self.platformUnavailable = false
    self.platformFlow = nil
    self.platform = newPlatform(self)
    self.v = assert(loadfile('server/Mgr/MgrVitals.lua'))()
    self.v.Now = function() return env.now end
    self.s = assert(loadfile('server/Mgr/MgrSurvival.lua'))()
    self.s.Now = function() return env.now end
    self.s.Vitals = self.v
    self.s.Platform = self.platform
    self.v:SetLifeHooks(self.s:Hooks())
    self.player = newPlayer(1473)
    self.attacker = newPlayer(2)
    self.v:OnPlayerAdded(self.player)
    self.s:OnPlayerAdded(self.player)
end

function TestReviveCallback:tearDown()
    package.loaded['common.REUtil'] = self.savedRE
end

function TestReviveCallback:ctrl() return self.player.Character.Controller end

function TestReviveCallback:results()
    return self.messages['SurvivalResult'] or {}
end

function TestReviveCallback:lastResult()
    local results = self:results()
    return results[#results] and results[#results].value or nil
end

function TestReviveCallback:enterDead()
    self:ctrl().Health = 50
    self.v:ApplyHit(self.v:NewHit(self.attacker, 'fishAttack'), self.player, 100) -- 锁血进濒死
    self.now = self.now + GameCfg.Survival.DownedSec
    self.s:Update()
    lu.assertEquals(self.s:Phase(self.player), 'dead')
end

-- 相位守卫：活动/濒死不能发起平台复活，不拉起平台、不回包成功
function TestReviveCallback:test_full_revive_rejected_outside_dead_phase()
    lu.assertFalse(self.s:PlatformRevive(self.player, { action = 'FullRevive', mode = 'goods', seq = 1 }))
    lu.assertEquals(self:lastResult().reason, 'not-dead')
    self:ctrl().Health = 50
    self.v:ApplyHit(self.v:NewHit(self.attacker, 'fishAttack'), self.player, 100) -- 濒死
    lu.assertEquals(self.s:Phase(self.player), 'downed')
    lu.assertFalse(self.s:PlatformRevive(self.player, { action = 'FullRevive', mode = 'ad', seq = 2 }))
    lu.assertEquals(self.platform.calls, {})
end

-- 畸形请求：坏 mode / 坏 seq / 非表 payload 拒绝，不碰平台
function TestReviveCallback:test_malformed_payloads_rejected()
    self:enterDead()
    lu.assertFalse(self.s:PlatformRevive(self.player, nil))
    lu.assertFalse(self.s:PlatformRevive(self.player, { action = 'FullRevive', mode = 'cash', seq = 1 }))
    lu.assertFalse(self.s:PlatformRevive(self.player, { action = 'FullRevive', mode = 'ad' }))
    lu.assertFalse(self.s:PlatformRevive(self.player, { action = 'FullRevive', mode = 'ad', seq = -1 }))
    lu.assertEquals(self.platform.calls, {})
    lu.assertFalse(self.s:GetState(self.player).platform ~= nil) -- 没进入暂停
end

-- 暂停：广告 flow 在飞时免费死亡倒计时冻结，到点不虚弱复活
function TestReviveCallback:test_platform_flow_pauses_free_countdown()
    self:enterDead()
    lu.assertTrue(self.s:PlatformRevive(self.player, { action = 'FullRevive', mode = 'ad', seq = 1 }))
    lu.assertEquals(#self.platform.calls, 1)
    lu.assertEquals(self.platform.calls[1].kind, 'ad')
    lu.assertEquals(self.platform.calls[1].adKey, 'revive')
    self.now = self.now + GameCfg.Survival.DeadSec + 10 -- 远超 30 秒免费倒计时
    self.s:Update()
    lu.assertEquals(self.s:Phase(self.player), 'dead') -- 倒计时暂停：没被虚弱复活
    lu.assertEquals(self:ctrl().Health, 1)
end

-- 广告成功回调：满血复活（MaxHealth、饥饿至少 10%、无虚弱），回包 ok
function TestReviveCallback:test_ad_success_full_revives_without_weakness()
    self:enterDead()
    self.v:GetState(self.player).hunger = 0 -- 死前饿空：满血复活也要把饥饿抬到 10%
    lu.assertTrue(self.s:PlatformRevive(self.player, { action = 'FullRevive', mode = 'ad', seq = 1 }))
    self.now = self.now + 8
    self.platformFlow.onResult('success')
    lu.assertEquals(self.s:Phase(self.player), 'alive')
    lu.assertEquals(self:ctrl().Health, GameCfg.Vitals.MaxHealth) -- 满血，不是 10%
    lu.assertTrue(self.v:GetState(self.player).hunger
        >= math.floor(GameCfg.Vitals.MaxHunger * GameCfg.Survival.ReviveHungerPercent / 100))
    lu.assertNil(self.s:GetState(self.player).weakUntil) -- 满血复活不带虚弱
    local result = self:lastResult()
    lu.assertTrue(result.ok)
    lu.assertEquals(result.action, 'FullRevive')
    lu.assertEquals(result.mode, 'ad')
    lu.assertEquals(result.seq, 1)
    -- 复活后免费倒计时不应再触发任何复活
    self.now = self.now + 999
    self.s:Update()
    lu.assertEquals(self.s:Phase(self.player), 'alive')
    lu.assertEquals(self:ctrl().Health, GameCfg.Vitals.MaxHealth)
end

-- 5 金豆商品成功回调：同一单点满血复活，走 Purchase('reviveFull')
function TestReviveCallback:test_goods_success_full_revives_via_purchase()
    self:enterDead()
    lu.assertTrue(self.s:PlatformRevive(self.player, { action = 'FullRevive', mode = 'goods', seq = 1 }))
    lu.assertEquals(self.platform.calls[1].kind, 'goods')
    lu.assertEquals(self.platform.calls[1].goodsKey, 'reviveFull')
    self.platformFlow.onResult('success')
    lu.assertEquals(self.s:Phase(self.player), 'alive')
    lu.assertEquals(self:ctrl().Health, GameCfg.Vitals.MaxHealth)
end

-- 取消/失败/超时：恢复免费倒计时且 deadAt 平移暂停时长，免费复活按原节奏 + 暂停时长触发
function TestReviveCallback:test_failed_flows_resume_shifted_free_countdown()
    for _, outcome in ipairs({ 'cancel', 'fail', 'timeout' }) do
        self:setUp()
        self:enterDead()
        local deadAt = self.s:GetState(self.player).deadAt
        lu.assertTrue(self.s:PlatformRevive(self.player, { action = 'FullRevive', mode = 'ad', seq = 1 }))
        self.now = self.now + 7 -- 平台流程花了 7 秒
        self.platformFlow.onResult(outcome)
        local result = self:lastResult()
        lu.assertFalse(result.ok)
        lu.assertEquals(result.reason, outcome)
        lu.assertEquals(self.s:Phase(self.player), 'dead')
        -- 倒计时平移：新终点 = 原 deadAt + DeadSec + 暂停 7 秒
        self.now = deadAt + GameCfg.Survival.DeadSec + 6.9
        self.s:Update()
        lu.assertEquals(self.s:Phase(self.player), 'dead') -- 没平移的话这里已经复活了
        self.now = deadAt + GameCfg.Survival.DeadSec + 7
        self.s:Update()
        lu.assertEquals(self.s:Phase(self.player), 'alive') -- 免费虚弱复活照常兜底
        lu.assertEquals(self:ctrl().Health, math.floor(GameCfg.Vitals.MaxHealth
            * GameCfg.Survival.ReviveHealthPercent / 100))
        self:tearDown()
    end
end

-- 互斥：成功回调后迟到回调（同 flow 重复驱动/另一结局）不产生第二个复活结果、不再回包
function TestReviveCallback:test_late_callback_after_success_is_ignored()
    self:enterDead()
    lu.assertTrue(self.s:PlatformRevive(self.player, { action = 'FullRevive', mode = 'goods', seq = 1 }))
    local callback = self.platformFlow.onResult
    callback('success')
    lu.assertEquals(self.s:Phase(self.player), 'alive')
    local resultCount = #self:results()
    callback('timeout') -- 迟到回调：flow 已结算，不能改状态
    callback('success')
    lu.assertEquals(self.s:Phase(self.player), 'alive')
    lu.assertEquals(self:ctrl().Health, GameCfg.Vitals.MaxHealth)
    lu.assertEquals(#self:results(), resultCount) -- 没有第二份回包
end

-- 串场守卫：旧 flow 的回调不能结算新 flow（取消后再发起，旧回调迟到）
function TestReviveCallback:test_stale_callback_cannot_settle_new_flow()
    self:enterDead()
    lu.assertTrue(self.s:PlatformRevive(self.player, { action = 'FullRevive', mode = 'ad', seq = 1 }))
    local stale = self.platformFlow.onResult
    stale('cancel') -- 第一个 flow 正常取消，倒计时恢复
    lu.assertTrue(self.s:PlatformRevive(self.player, { action = 'FullRevive', mode = 'ad', seq = 2 }))
    stale('success') -- 旧回调迟到：不能复活（当前 flow 是第二个）
    lu.assertEquals(self.s:Phase(self.player), 'dead')
    lu.assertEquals(self:ctrl().Health, 1)
    self.platformFlow.onResult('success') -- 第二个 flow 的成功回调才生效
    lu.assertEquals(self.s:Phase(self.player), 'alive')
    lu.assertEquals(self:ctrl().Health, GameCfg.Vitals.MaxHealth)
    lu.assertEquals(self:lastResult().seq, 2)
end

-- 并发：flow 在飞时重复发起 busy，不再拉起平台
function TestReviveCallback:test_second_request_busy_while_flow_in_flight()
    self:enterDead()
    lu.assertTrue(self.s:PlatformRevive(self.player, { action = 'FullRevive', mode = 'ad', seq = 1 }))
    lu.assertFalse(self.s:PlatformRevive(self.player, { action = 'FullRevive', mode = 'goods', seq = 2 }))
    lu.assertEquals(self:lastResult().reason, 'busy')
    lu.assertEquals(#self.platform.calls, 1)
end

-- 可用性：平台不可用（生产未配置）时明确回包 unavailable，倒计时不暂停
function TestReviveCallback:test_unavailable_platform_does_not_pause()
    self:enterDead()
    self.platformUnavailable = true
    lu.assertFalse(self.s:PlatformRevive(self.player, { action = 'FullRevive', mode = 'goods', seq = 1 }))
    lu.assertEquals(self:lastResult().reason, 'unavailable')
    lu.assertNil(self.s:GetState(self.player).platform)
    self.now = self.now + GameCfg.Survival.DeadSec
    self.s:Update()
    lu.assertEquals(self.s:Phase(self.player), 'alive') -- 免费倒计时没被打断
end

-- 状态同步：平台 pending 期间 SurvivalState 带 platformPending 标记，恢复后消失
function TestReviveCallback:test_state_marks_platform_pending()
    self:enterDead()
    lu.assertTrue(self.s:PlatformRevive(self.player, { action = 'FullRevive', mode = 'ad', seq = 1 }))
    local states = self.messages['SurvivalState']
    local pending = states[#states].value
    lu.assertEquals(pending.phase, 'dead')
    lu.assertEquals(pending.platformPending, 'ad')
    self.platformFlow.onResult('cancel')
    local resumed = self.messages['SurvivalState']
    lu.assertNil(resumed[#resumed].value.platformPending)
end

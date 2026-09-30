-- #147 T26 平台适配层（server/Mgr/MgrPlatform.lua）失败方式先列：
--   1. 可用性口径错：商品未配置（goodsId 空）却放行购买；Debug 关闭却还能进测试支付成功入口；
--   2. 流程并发错：同一玩家第二个在飞购买/广告被接受（应 busy），或回调串到别人的 flow；
--   3. 回调路由错：成功/取消/失败/超时没有各归各的 onResult；超时不触发（免费复活倒计时无法恢复）；
--   4. 发货错：GoodsPurchaseCompleted 匹配 pending flow 却不结算；未配置商品的信号也发货；
--      发货不走持久操作（重进丢失）；信号重复到达时伪防重吞掉真实购买（订单身份未查证，不拼 UserId+goodsId 防重）；
--   5. 生命周期错：玩家离开残留 flow，重进后旧回调改新会话；payload 畸形直接报错而不是拒绝。
-- seam：MgrPlatform:Purchase / ShowAd / OpenAdrenalineShop / OpenCoinShop / Update / HandleTestAction +
--   GoodsPurchaseCompleted 订阅入口；引擎边界（CommodityService / AdvertisementService / World 时钟 /
--   DataStore / RE）全部替身，真实 MgrSave + MgrPlayerData 验证发货落账。
-- 注意：真实平台无订单 ID、购买无取消/失败事件（docs/技术难点识别.md §4），本地接缝只做
-- pending flow 关联与超时兜底；跨会话防重、补发与对账归 #148，本文件不断言这些能力存在。
local lu = require('luaunit')
local GameCfg = require('common.GameCfg')

TestPlatformSeam = {}

local function signal()
    local s = { handlers = {} }
    function s:Connect(fn)
        self.handlers[#self.handlers + 1] = fn
        return { Disconnect = function() end }
    end
    function s:Fire(...) for _, fn in ipairs(self.handlers) do fn(...) end end
    return s
end

function TestPlatformSeam:setUp()
    self.oldGame, self.oldRE = _G.game, _G.REUtil
    self.oldDebug = GameCfg.Debug
    -- 商品 goodsId 是共享配置表的字段：快照原值，tearDown 逐个还原（不是换表，避免突变泄漏）
    self.oldGoodsIds = {}
    for key, row in pairs(GameCfg.Platform.Goods) do self.oldGoodsIds[key] = row.goodsId end
    GameCfg.Debug = { Enabled = true }
    self.now = 1000
    self.values, self.queue, self.events = {}, {}, {}
    local env = self
    self.purchasePanels, self.adCalls = {}, {}
    self.goodsSignal = signal()
    self.commodity = {
        ShowGoodsPurchasePanel = function(_, player, goodsId, showTime)
            env.purchasePanels[#env.purchasePanels + 1] = { player = player, goodsId = goodsId, showTime = showTime }
        end,
        GoodsPurchaseCompleted = self.goodsSignal,
    }
    self.advertisement = {
        ShowRewardedVideoAd = function(_, player, goodsId, successEvent, failEvent, adTag)
            env.adCalls[#env.adCalls + 1] = { player = player, goodsId = goodsId }
        end,
    }
    local store = {
        GetAsync = function(_, key) return env.values[key] end,
        UpdateAsync = function(_, key, transform)
            local value = transform(env.values[key])
            if value then env.values[key] = value end
            return value
        end,
        SetAsync = function(_, key, value) env.values[key] = value end,
    }
    _G.game = { GetService = function(_, name)
        if name == 'Task' then return { Spawn = function(_, fn) env.queue[#env.queue + 1] = fn end,
            Wait = function() end } end
        if name == 'DataStoreService' then return { GetDataStore = function() return store end } end
        if name == 'World' then return { GetServerTime = function() return env.now end } end
        if name == 'Players' then return { GetPlayers = function() return {} end } end
        if name == 'CommodityService' then return env.commodity end
        if name == 'AdvertisementService' then return env.advertisement end
    end }
    _G.REUtil = { GetRE = function(_, name) return { FireClient = function(_, player, value)
        env.events[#env.events + 1] = { name = name, player = player, value = value }
    end, OnServerEvent = signal() } end }
    self.save = assert(loadfile('server/Mgr/MgrSave.lua'))()
    self.players = assert(loadfile('server/Mgr/MgrPlayerData.lua'))()
    self.platform = assert(loadfile('server/Mgr/MgrPlatform.lua'))()
    self.players.Save, self.save.PlayerData = self.save, self.players
    self.platform.Save, self.platform.PlayerData = self.save, self.players
    self.platform.Now = function() return env.now end
    self.platform:Start() -- 订阅 GoodsPurchaseCompleted 与 RE 通道
    self.player = { UserId = 1471, Character = { Position = { x = 0, y = 0, z = 0 } },
        CharacterAdded = signal(), CharacterRemoving = signal(), SetAttribute = function() end }
    self.players:OnPlayerAdded(self.player)
    self:drain()
    self.data = self.players:GetDataInst(self.player)
    self.events = {}
end

function TestPlatformSeam:tearDown()
    _G.game, _G.REUtil = self.oldGame, self.oldRE
    GameCfg.Debug = self.oldDebug
    for key, row in pairs(GameCfg.Platform.Goods) do row.goodsId = self.oldGoodsIds[key] end
end

function TestPlatformSeam:drain()
    while #self.queue > 0 do table.remove(self.queue, 1)() end
end

function TestPlatformSeam:messages(name)
    local values = {}
    for _, event in ipairs(self.events) do if event.name == name then values[#values + 1] = event.value end end
    return values
end

function TestPlatformSeam:persistReady()
    lu.assertTrue(self.save:SaveExplicit(self.player.UserId, self.data, function(ok) lu.assertTrue(ok) end))
    self:drain()
    self.events = {}
end

-- 未配置商品（goodsId 空）+ 生产构建（Debug 关）：购买明确不可用，不建 flow、不发权益
function TestPlatformSeam:test_unconfigured_goods_unavailable_in_production()
    GameCfg.Debug = { Enabled = false }
    local outcomes = {}
    local accepted, reason = self.platform:Purchase(self.player, 'blindboxSingle', 'blindbox',
        function(outcome) outcomes[#outcomes + 1] = outcome end)
    lu.assertFalse(accepted)
    lu.assertEquals(reason, 'unavailable')
    lu.assertEquals(outcomes, {})
    lu.assertEquals(self.purchasePanels, {}) -- 不拉起真实面板
    lu.assertFalse(self.platform:HasFlow(self.player))
end

-- Debug 开：未配置商品走测试 flow（pending 等驱动器），不碰真实服务
function TestPlatformSeam:test_debug_build_opens_pending_test_flow()
    local outcomes = {}
    lu.assertTrue(self.platform:Purchase(self.player, 'blindboxSingle', 'blindbox',
        function(outcome) outcomes[#outcomes + 1] = outcome end))
    lu.assertTrue(self.platform:HasFlow(self.player))
    lu.assertEquals(self.purchasePanels, {})
    lu.assertEquals(outcomes, {}) -- 未结算，等回调
end

-- 同时第二个购买请求被拒（busy），第一个 flow 不受影响
function TestPlatformSeam:test_second_flow_is_busy_while_one_in_flight()
    lu.assertTrue(self.platform:Purchase(self.player, 'blindboxSingle', 'blindbox', function() end))
    local accepted, reason = self.platform:Purchase(self.player, 'reviveFull', 'revive', function() end)
    lu.assertFalse(accepted)
    lu.assertEquals(reason, 'busy')
    lu.assertTrue(self.platform:HasFlow(self.player))
end

-- 测试驱动器：成功/取消/失败各归各的 outcome，只结算一次
function TestPlatformSeam:test_driver_resolves_success_cancel_fail()
    for _, outcome in ipairs({ 'success', 'cancel', 'fail' }) do
        local outcomes = {}
        lu.assertTrue(self.platform:Purchase(self.player, 'blindboxSingle', 'blindbox',
            function(result) outcomes[#outcomes + 1] = result end))
        lu.assertTrue(self.platform:HandleTestAction(self.player, { action = 'ResolveFlow', outcome = outcome }))
        lu.assertEquals(outcomes, { outcome })
        lu.assertFalse(self.platform:HasFlow(self.player))
        -- 重复驱动不再产生第二个结果
        lu.assertFalse(self.platform:HandleTestAction(self.player, { action = 'ResolveFlow', outcome = 'success' }))
        lu.assertEquals(#outcomes, 1)
    end
end

-- 生产构建：测试驱动器整体拒绝，pending flow 不被伪造成功
function TestPlatformSeam:test_driver_rejected_in_production()
    local outcomes = {}
    lu.assertTrue(self.platform:Purchase(self.player, 'blindboxSingle', 'blindbox',
        function(result) outcomes[#outcomes + 1] = result end))
    GameCfg.Debug = { Enabled = false } -- 流程进行中切到生产口径
    lu.assertFalse(self.platform:HandleTestAction(self.player, { action = 'ResolveFlow', outcome = 'success' }))
    lu.assertEquals(outcomes, {})
    lu.assertTrue(self.platform:HasFlow(self.player)) -- 没被伪造结算
end

-- 超时兜底：平台没有取消/失败事件（技术难点 §4），FlowTimeoutSec 到点按 timeout 结算
function TestPlatformSeam:test_flow_times_out_and_reports_timeout()
    local outcomes = {}
    lu.assertTrue(self.platform:ShowAd(self.player, 'revive', 'revive',
        function(result) outcomes[#outcomes + 1] = result end))
    self.now = self.now + GameCfg.Platform.FlowTimeoutSec - 1
    self.platform:Update()
    lu.assertEquals(outcomes, {})
    self.now = self.now + 1
    self.platform:Update()
    lu.assertEquals(outcomes, { 'timeout' })
    lu.assertFalse(self.platform:HasFlow(self.player))
end

-- 已配置商品 + 服务可达：走真实面板，flow 等 GoodsPurchaseCompleted
function TestPlatformSeam:test_configured_goods_still_use_only_test_flow()
    GameCfg.Platform.Goods.adrenaline1.goodsId = 'goodsAdr1'
    local outcomes = {}
    lu.assertTrue(self.platform:Purchase(self.player, 'adrenaline1', 'adrenaline',
        function(result) outcomes[#outcomes + 1] = result end))
    lu.assertEquals(#self.purchasePanels, 0)
    self.goodsSignal:Fire('goodsAdr1', 1, self.player)
    lu.assertEquals(outcomes, {})
    lu.assertTrue(self.platform:HasFlow(self.player))
    self.platform:HandleTestAction(self.player, { action = 'ResolveFlow', outcome = 'success' })
    lu.assertEquals(outcomes, { 'success' })
end

-- 信号不串号：别人的购买完成不解我的 flow；不同商品的信号不解 flow
function TestPlatformSeam:test_signal_does_not_cross_players_or_goods()
    GameCfg.Platform.Goods.adrenaline1.goodsId = 'goodsAdr1'
    GameCfg.Platform.Goods.adrenaline5.goodsId = 'goodsAdr5'
    local outcomes = {}
    lu.assertTrue(self.platform:Purchase(self.player, 'adrenaline1', 'adrenaline',
        function(result) outcomes[#outcomes + 1] = result end))
    local other = { UserId = 9999, Character = { Position = { x = 0, y = 0, z = 0 } },
        CharacterAdded = signal(), CharacterRemoving = signal(), SetAttribute = function() end }
    self.goodsSignal:Fire('goodsAdr1', 1, other) -- 别人买的不算
    self.goodsSignal:Fire('goodsAdr5', 1, self.player) -- 别的商品不算
    lu.assertEquals(outcomes, {})
    lu.assertTrue(self.platform:HasFlow(self.player))
end

-- 无 pending flow 的已配置商品信号：按购买事实直接持久发货（平台扣费即事实）；
-- 两个信号发两份——没有订单 ID 不拼 UserId+goodsId 防重（教程明令禁止），真实对账归 #148
function TestPlatformSeam:test_unmatched_signals_never_grant_without_identity()
    GameCfg.Platform.Goods.adrenaline1.goodsId = 'goodsAdr1'
    self:persistReady()
    self.goodsSignal:Fire('goodsAdr1', 1, self.player)
    self:drain()
    lu.assertEquals(self.data:ItemCount(GameCfg.Survival.AdrenalineItemId), 0)
    self.goodsSignal:Fire('goodsAdr1', 1, self.player) -- 第二笔真实购买：再发一份
    self:drain()
    lu.assertEquals(self.data:ItemCount(GameCfg.Survival.AdrenalineItemId), 0)
end

-- 未配置商品的信号：不发货（不知道它该发什么），只记日志
function TestPlatformSeam:test_signal_for_unconfigured_goods_grants_nothing()
    self:persistReady()
    self.goodsSignal:Fire('goodsAdr1', 1, self.player) -- adrenaline1.goodsId 未配置
    self:drain()
    lu.assertEquals(self.data:ItemCount(GameCfg.Survival.AdrenalineItemId), 0)
end

-- 肾上腺素发货走持久操作：重进读档仍在
function TestPlatformSeam:test_adrenaline_grant_survives_reconnect()
    GameCfg.Platform.Goods.adrenaline1.goodsId = 'goodsAdr1'
    self:persistReady()
    self.platform:HandleAction(self.player, { action = 'Purchase', goods = 'adrenaline1' })
    self.platform:HandleTestAction(self.player, { action = 'ResolveFlow', outcome = 'success' })
    self:drain()
    self.players:OnPlayerAdded(self.player) -- 重进读档
    self:drain()
    local restored = self.players:GetDataInst(self.player)
    lu.assertEquals(restored:ItemCount(GameCfg.Survival.AdrenalineItemId), 1)
end

-- 肾上腺素五连装：4 金豆发 5 个
function TestPlatformSeam:test_adrenaline_five_pack_grants_five()
    GameCfg.Platform.Goods.adrenaline5.goodsId = 'goodsAdr5'
    self:persistReady()
    self.platform:HandleAction(self.player, { action = 'Purchase', goods = 'adrenaline5' })
    self.platform:HandleTestAction(self.player, { action = 'ResolveFlow', outcome = 'success' })
    self:drain()
    lu.assertEquals(self.data:ItemCount(GameCfg.Survival.AdrenalineItemId), 5)
end

-- 广告复活入口：未配置广告 + 生产 → 不可用；Debug 开 → pending flow
function TestPlatformSeam:test_ad_flow_availability()
    GameCfg.Debug = { Enabled = false }
    local accepted, reason = self.platform:ShowAd(self.player, 'revive', 'revive', function() end)
    lu.assertFalse(accepted)
    lu.assertEquals(reason, 'unavailable')
    GameCfg.Debug = { Enabled = true }
    lu.assertTrue(self.platform:ShowAd(self.player, 'revive', 'revive', function() end))
    lu.assertTrue(self.platform:HasFlow(self.player))
end

-- OpenAdrenalineShop / OpenCoinShop：未配置时明确回包不可用，不伪成功
function TestPlatformSeam:test_shop_entries_reply_unavailable_when_unconfigured()
    GameCfg.Debug = { Enabled = false }
    self.platform:OpenAdrenalineShop(self.player)
    self.platform:OpenCoinShop(self.player)
    local replies = self:messages('PlatformResult')
    lu.assertEquals(#replies, 2)
    for _, reply in ipairs(replies) do
        lu.assertFalse(reply.ok)
        lu.assertEquals(reply.reason, 'unavailable')
    end
end

-- 玩家离开清理在飞 flow；重进后旧 flow 不复活
function TestPlatformSeam:test_leaving_clears_flow()
    lu.assertTrue(self.platform:Purchase(self.player, 'blindboxSingle', 'blindbox', function() end))
    self.platform:OnPlayerRemoving(self.player)
    lu.assertFalse(self.platform:HasFlow(self.player))
    self.now = self.now + 9999
    self.platform:Update() -- 不报错、不结算
end

-- 畸形输入不报错
function TestPlatformSeam:test_malformed_calls_are_rejected()
    lu.assertFalse(self.platform:Purchase(self.player, 'no-such-goods', 'x', function() end))
    lu.assertFalse(self.platform:Purchase(nil, 'blindboxSingle', 'x', function() end))
    lu.assertFalse(self.platform:HandleTestAction(self.player, nil))
    lu.assertFalse(self.platform:HandleTestAction(self.player, { action = 'ResolveFlow', outcome = 'explode' }))
    lu.assertFalse(self.platform:ShowAd(self.player, 'no-such-ad', 'revive', function() end))
end

-- 测试 flow 开 / 关通知客户端驱动按钮；真实平台 flow 不发（生产也就看不到驱动入口）
function TestPlatformSeam:test_test_flow_notifies_client_driver()
    lu.assertTrue(self.platform:Purchase(self.player, 'blindboxTen', 'blindbox', function() end))
    local opened = self:messages('PlatformResult')
    lu.assertEquals(#opened, 1)
    lu.assertEquals(opened[1].action, 'TestFlow')
    lu.assertTrue(opened[1].open)
    lu.assertEquals(opened[1].key, 'blindboxTen')
    self.platform:HandleTestAction(self.player, { action = 'ResolveFlow', outcome = 'cancel' })
    local closed = self:messages('PlatformResult')
    lu.assertEquals(#closed, 2)
    lu.assertFalse(closed[2].open)
    self.events = {}
    GameCfg.Platform.Goods.adrenaline1.goodsId = 'goodsAdr1'
    lu.assertTrue(self.platform:Purchase(self.player, 'adrenaline1', 'adrenaline', function() end))
    lu.assertTrue(self:messages('PlatformResult')[1].open) -- 配置ID仍只允许测试flow
end

-- 无可信订单身份：配置goodsId不能放行生产，旧/重复信号不能结算新测试flow或发货。
function TestPlatformSeam:test_configured_production_is_fail_closed()
    GameCfg.Platform.Goods.adrenaline1.goodsId = 'goodsAdr1'
    GameCfg.Platform.Ads.revive.goodsId = 'adRevive'
    GameCfg.Debug = { Enabled = false }
    local accepted, reason = self.platform:Purchase(self.player, 'adrenaline1', 'adrenaline', function() end)
    lu.assertFalse(accepted); lu.assertEquals(reason, 'unavailable')
    lu.assertFalse(self.platform:ShowAd(self.player, 'revive', 'revive', function() end))
    self.goodsSignal:Fire('goodsAdr1', 1, self.player)
    self.goodsSignal:Fire('goodsAdr1', 1, self.player)
    self:drain()
    lu.assertEquals(self.data:ItemCount(GameCfg.Survival.AdrenalineItemId), 0)
    lu.assertEquals(self.purchasePanels, {})
end

function TestPlatformSeam:test_late_old_signal_cannot_settle_new_same_goods_flow()
    GameCfg.Platform.Goods.adrenaline1.goodsId = 'goodsAdr1'
    local outcomes = {}
    self.platform:Purchase(self.player, 'adrenaline1', 'adrenaline', function(r) outcomes[#outcomes + 1] = r end)
    self.now = self.now + GameCfg.Platform.FlowTimeoutSec
    self.platform:Update()
    self.platform:Purchase(self.player, 'adrenaline1', 'adrenaline', function(r) outcomes[#outcomes + 1] = r end)
    self.goodsSignal:Fire('goodsAdr1', 1, self.player)
    self.goodsSignal:Fire('goodsAdr1', 1, self.player)
    lu.assertEquals(outcomes, { 'timeout' })
    lu.assertTrue(self.platform:HasFlow(self.player))
    lu.assertEquals(self.data:ItemCount(GameCfg.Survival.AdrenalineItemId), 0)
end

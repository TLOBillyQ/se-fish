-- 迁移自 tests/gameplay/platform_seam_test.lua（#91）；行为契约原文见 #147 T26、docs/技术难点识别.md §4。
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
-- it 名字沿用旧方法名，注册顺序 = LuaUnit sortedPairs 的实际执行顺序。

local GameCfg = require('common.GameCfg')

local globalNames = { 'game', 'REUtil', 'MgrPlayerData' }

local function signal()
  local s = { handlers = {} }
  function s:Connect(fn)
    self.handlers[#self.handlers + 1] = fn
    return { Disconnect = function() end }
  end
  function s:Fire(...) for _, fn in ipairs(self.handlers) do fn(...) end end
  return s
end

describe('平台适配层（MgrPlatform）', function()
  local env
  local restore

  local function drain()
    while #env.queue > 0 do table.remove(env.queue, 1)() end
  end

  local function messages(name)
    local values = {}
    for _, event in ipairs(env.events) do
      if event.name == name then values[#values + 1] = event.value end
    end
    return values
  end

  local function persistReady()
    assert.is_true(env.save:SaveExplicit(env.player.UserId, env.data, function(ok)
      assert.is_true(ok)
    end))
    drain()
    env.events = {}
  end

  before_each(function()
    -- 快照先于任何改动：夹具中途失败时 after_each 仍能还原已改项。
    -- 商品 goodsId 是共享配置表的字段：快照原值，after_each 逐个还原（不是换表，避免突变泄漏）。
    -- GameCfg.Debug / Save.AcceptanceSlot 由 helper 的根级快照兜底，但本夹具把 Debug 换成新表，
    -- 这里再显式快照一次，保证 after_each 幂等（不依赖根级 hook 的执行时机）。
    -- _G.MgrPlayerData 是 server/Mgr/MgrPlayerData.lua 装载时写下的模块全局，旧单进程 runner 里
    -- 它跨套件长存；原生逐例隔离后必须快照并还原，否则同一 chunk 的实例会泄漏到后续案例。
    restore = { Debug = GameCfg.Debug }
    for _, name in ipairs(globalNames) do
      restore[name] = rawget(_G, name)
    end
    restore.oldGoodsIds = {}
    for key, row in pairs(GameCfg.Platform.Goods) do
      restore.oldGoodsIds[key] = row.goodsId
    end
    -- Ads 行与 Goods 行同口径：用例会在行上写 goodsId / adTag，逐字段快照还原。
    -- （旧套件的 tearDown 只还原了 Goods，漏了 Ads；原生逐例隔离后必须补上，否则跨案例残留。）
    restore.oldAdIds = {}
    for key, row in pairs(GameCfg.Platform.Ads) do
      restore.oldAdIds[key] = row.goodsId
    end
    GameCfg.Debug = { Enabled = true }
    env = { now = 1000, values = {}, queue = {}, events = {}, purchasePanels = {}, adCalls = {},
      replies = {} }
    env.goodsSignal = signal()
    env.commodity = {
      ShowGoodsPurchasePanel = function(_, player, goodsId, showTime)
        env.purchasePanels[#env.purchasePanels + 1] = { player = player, goodsId = goodsId, showTime = showTime }
      end,
      GoodsPurchaseCompleted = env.goodsSignal,
    }
    env.advertisement = {
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
    rawset(_G, 'game', { GetService = function(_, name)
      if name == 'Task' then return { Spawn = function(_, fn) env.queue[#env.queue + 1] = fn end,
        Wait = function() end } end
      if name == 'DataStoreService' then return { GetDataStore = function() return store end } end
      if name == 'World' then return { GetServerTime = function() return env.now end } end
      if name == 'Players' then return { GetPlayers = function() return {} end } end
      if name == 'CommodityService' then return env.commodity end
      if name == 'AdvertisementService' then return env.advertisement end
    end })
    rawset(_G, 'REUtil', { GetRE = function(_, name)
      return { FireClient = function(_, player, value)
        env.events[#env.events + 1] = { name = name, player = player, value = value }
      end, OnServerEvent = signal() }
    end })
    -- loadfile 每次得到全新的管理器实例表，避免 Mgr.Flows / DataMap 跨案例残留。
    env.save = assert(loadfile('server/Mgr/MgrSave.lua'))()
    env.players = assert(loadfile('server/Mgr/MgrPlayerData.lua'))()
    env.platform = assert(loadfile('server/Mgr/MgrPlatform.lua'))()
    env.players.Save, env.save.PlayerData = env.save, env.players
    env.platform.Save, env.platform.PlayerData = env.save, env.players
    env.platform.Now = function() return env.now end
    env.platform:Start() -- 订阅 GoodsPurchaseCompleted 与 RE 通道
    env.player = { UserId = 1471, Character = { Position = { x = 0, y = 0, z = 0 } },
      CharacterAdded = signal(), CharacterRemoving = signal(), SetAttribute = function() end }
    env.players:OnPlayerAdded(env.player)
    drain()
    env.data = env.players:GetDataInst(env.player)
    env.events = {}
  end)

  after_each(function()
    -- 顺序与旧 tearDown 一致：先还原引擎全局，再还原 Debug 开关，最后逐个还原商品 goodsId 字段。
    if restore then
      for _, name in ipairs(globalNames) do
        rawset(_G, name, restore[name])
      end
      GameCfg.Debug = restore.Debug
      for key, row in pairs(GameCfg.Platform.Goods) do
        row.goodsId = restore.oldGoodsIds[key]
      end
      for key, row in pairs(GameCfg.Platform.Ads) do
        row.goodsId = restore.oldAdIds[key]
      end
    end
    env = nil
    restore = nil
  end)

  -- 未配置商品（goodsId 空）+ 生产构建（Debug 关）：购买明确不可用，不建 flow、不发权益
  it('test_ad_flow_availability', function()
    GameCfg.Debug = { Enabled = false }
    local accepted, reason = env.platform:ShowAd(env.player, 'revive', 'revive', function() end)
    assert.is_false(accepted)
    assert.same('unavailable', reason)
    GameCfg.Debug = { Enabled = true }
    assert.is_true(env.platform:ShowAd(env.player, 'revive', 'revive', function() end))
    assert.is_true(env.platform:HasFlow(env.player))
  end)

  -- 肾上腺素五连装：4 金豆发 5 个
  it('test_adrenaline_five_pack_grants_five', function()
    GameCfg.Platform.Goods.adrenaline5.goodsId = 'goodsAdr5'
    persistReady()
    env.platform:HandleAction(env.player, { action = 'Purchase', goods = 'adrenaline5' })
    env.platform:HandleTestAction(env.player, { action = 'ResolveFlow', outcome = 'success' })
    drain()
    assert.same(5, env.data:ItemCount(GameCfg.Survival.AdrenalineItemId))
  end)

  -- 肾上腺素发货走持久操作：重进读档仍在
  it('test_adrenaline_grant_survives_reconnect', function()
    GameCfg.Platform.Goods.adrenaline1.goodsId = 'goodsAdr1'
    persistReady()
    env.platform:HandleAction(env.player, { action = 'Purchase', goods = 'adrenaline1' })
    env.platform:HandleTestAction(env.player, { action = 'ResolveFlow', outcome = 'success' })
    drain()
    env.players:OnPlayerAdded(env.player) -- 重进读档
    drain()
    local restored = env.players:GetDataInst(env.player)
    assert.same(1, restored:ItemCount(GameCfg.Survival.AdrenalineItemId))
  end)

  -- 已配置商品 + 服务可达：走真实面板，flow 等 GoodsPurchaseCompleted
  it('test_configured_goods_still_use_only_test_flow', function()
    GameCfg.Platform.Goods.adrenaline1.goodsId = 'goodsAdr1'
    local outcomes = {}
    assert.is_true(env.platform:Purchase(env.player, 'adrenaline1', 'adrenaline',
      function(result) outcomes[#outcomes + 1] = result end))
    assert.same(0, #env.purchasePanels)
    env.goodsSignal:Fire('goodsAdr1', 1, env.player)
    assert.same({}, outcomes)
    assert.is_true(env.platform:HasFlow(env.player))
    env.platform:HandleTestAction(env.player, { action = 'ResolveFlow', outcome = 'success' })
    assert.same({ 'success' }, outcomes)
  end)

  -- 无可信订单身份：配置goodsId不能放行生产，旧/重复信号不能结算新测试flow或发货。
  it('test_configured_production_is_fail_closed', function()
    GameCfg.Platform.Goods.adrenaline1.goodsId = 'goodsAdr1'
    GameCfg.Platform.Ads.revive.goodsId = 'adRevive'
    GameCfg.Debug = { Enabled = false }
    local accepted, reason = env.platform:Purchase(env.player, 'adrenaline1', 'adrenaline', function() end)
    assert.is_false(accepted)
    assert.same('unavailable', reason)
    assert.is_false(env.platform:ShowAd(env.player, 'revive', 'revive', function() end))
    env.goodsSignal:Fire('goodsAdr1', 1, env.player)
    env.goodsSignal:Fire('goodsAdr1', 1, env.player)
    drain()
    assert.same(0, env.data:ItemCount(GameCfg.Survival.AdrenalineItemId))
    assert.same({}, env.purchasePanels)
  end)

  -- Debug 开：未配置商品走测试 flow（pending 等驱动器），不碰真实服务
  it('test_debug_build_opens_pending_test_flow', function()
    local outcomes = {}
    assert.is_true(env.platform:Purchase(env.player, 'blindboxSingle', 'blindbox',
      function(outcome) outcomes[#outcomes + 1] = outcome end))
    assert.is_true(env.platform:HasFlow(env.player))
    assert.same({}, env.purchasePanels)
    assert.same({}, outcomes) -- 未结算，等回调
  end)

  -- 生产构建：测试驱动器整体拒绝，pending flow 不被伪造成功
  it('test_driver_rejected_in_production', function()
    local outcomes = {}
    assert.is_true(env.platform:Purchase(env.player, 'blindboxSingle', 'blindbox',
      function(result) outcomes[#outcomes + 1] = result end))
    GameCfg.Debug = { Enabled = false } -- 流程进行中切到生产口径
    assert.is_false(env.platform:HandleTestAction(env.player, { action = 'ResolveFlow', outcome = 'success' }))
    assert.same({}, outcomes)
    assert.is_true(env.platform:HasFlow(env.player)) -- 没被伪造结算
  end)

  -- 测试驱动器：成功/取消/失败各归各的 outcome，只结算一次
  it('test_driver_resolves_success_cancel_fail', function()
    for _, outcome in ipairs({ 'success', 'cancel', 'fail' }) do
      local outcomes = {}
      assert.is_true(env.platform:Purchase(env.player, 'blindboxSingle', 'blindbox',
        function(result) outcomes[#outcomes + 1] = result end))
      assert.is_true(env.platform:HandleTestAction(env.player, { action = 'ResolveFlow', outcome = outcome }))
      assert.same({ outcome }, outcomes)
      assert.is_false(env.platform:HasFlow(env.player))
      -- 重复驱动不再产生第二个结果
      assert.is_false(env.platform:HandleTestAction(env.player, { action = 'ResolveFlow', outcome = 'success' }))
      assert.same(1, #outcomes)
    end
  end)

  -- 超时兜底：平台没有取消/失败事件（技术难点 §4），FlowTimeoutSec 到点按 timeout 结算
  it('test_flow_times_out_and_reports_timeout', function()
    local outcomes = {}
    assert.is_true(env.platform:ShowAd(env.player, 'revive', 'revive',
      function(result) outcomes[#outcomes + 1] = result end))
    env.now = env.now + GameCfg.Platform.FlowTimeoutSec - 1
    env.platform:Update()
    assert.same({}, outcomes)
    env.now = env.now + 1
    env.platform:Update()
    assert.same({ 'timeout' }, outcomes)
    assert.is_false(env.platform:HasFlow(env.player))
  end)

  -- 超时结算后的新 flow：旧的/重复的真实信号仍不与它关联，既不结算也不发货
  it('test_late_old_signal_cannot_settle_new_same_goods_flow', function()
    GameCfg.Platform.Goods.adrenaline1.goodsId = 'goodsAdr1'
    local outcomes = {}
    env.platform:Purchase(env.player, 'adrenaline1', 'adrenaline', function(r) outcomes[#outcomes + 1] = r end)
    env.now = env.now + GameCfg.Platform.FlowTimeoutSec
    env.platform:Update()
    env.platform:Purchase(env.player, 'adrenaline1', 'adrenaline', function(r) outcomes[#outcomes + 1] = r end)
    env.goodsSignal:Fire('goodsAdr1', 1, env.player)
    env.goodsSignal:Fire('goodsAdr1', 1, env.player)
    assert.same({ 'timeout' }, outcomes)
    assert.is_true(env.platform:HasFlow(env.player))
    assert.same(0, env.data:ItemCount(GameCfg.Survival.AdrenalineItemId))
  end)

  -- 玩家离开清理在飞 flow；重进后旧 flow 不复活
  it('test_leaving_clears_flow', function()
    assert.is_true(env.platform:Purchase(env.player, 'blindboxSingle', 'blindbox', function() end))
    env.platform:OnPlayerRemoving(env.player)
    assert.is_false(env.platform:HasFlow(env.player))
    env.now = env.now + 9999
    env.platform:Update() -- 不报错、不结算
  end)

  -- 畸形输入不报错
  it('test_malformed_calls_are_rejected', function()
    assert.is_false(env.platform:Purchase(env.player, 'no-such-goods', 'x', function() end))
    assert.is_false(env.platform:Purchase(nil, 'blindboxSingle', 'x', function() end))
    assert.is_false(env.platform:HandleTestAction(env.player, nil))
    assert.is_false(env.platform:HandleTestAction(env.player, { action = 'ResolveFlow', outcome = 'explode' }))
    assert.is_false(env.platform:ShowAd(env.player, 'no-such-ad', 'revive', function() end))
  end)

  -- 同时第二个购买请求被拒（busy），第一个 flow 不受影响
  it('test_second_flow_is_busy_while_one_in_flight', function()
    assert.is_true(env.platform:Purchase(env.player, 'blindboxSingle', 'blindbox', function() end))
    local accepted, reason = env.platform:Purchase(env.player, 'reviveFull', 'revive', function() end)
    assert.is_false(accepted)
    assert.same('busy', reason)
    assert.is_true(env.platform:HasFlow(env.player))
  end)

  -- OpenAdrenalineShop / OpenCoinShop：未配置时明确回包不可用，不伪成功
  it('test_shop_entries_reply_unavailable_when_unconfigured', function()
    GameCfg.Debug = { Enabled = false }
    env.platform:OpenAdrenalineShop(env.player)
    env.platform:OpenCoinShop(env.player)
    local replies = messages('PlatformResult')
    assert.same(2, #replies)
    for _, reply in ipairs(replies) do
      assert.is_false(reply.ok)
      assert.same('unavailable', reply.reason)
    end
  end)

  -- 信号不串号：别人的购买完成不解我的 flow；不同商品的信号不解 flow
  it('test_signal_does_not_cross_players_or_goods', function()
    GameCfg.Platform.Goods.adrenaline1.goodsId = 'goodsAdr1'
    GameCfg.Platform.Goods.adrenaline5.goodsId = 'goodsAdr5'
    local outcomes = {}
    assert.is_true(env.platform:Purchase(env.player, 'adrenaline1', 'adrenaline',
      function(result) outcomes[#outcomes + 1] = result end))
    local other = { UserId = 9999, Character = { Position = { x = 0, y = 0, z = 0 } },
      CharacterAdded = signal(), CharacterRemoving = signal(), SetAttribute = function() end }
    env.goodsSignal:Fire('goodsAdr1', 1, other) -- 别人买的不算
    env.goodsSignal:Fire('goodsAdr5', 1, env.player) -- 别的商品不算
    assert.same({}, outcomes)
    assert.is_true(env.platform:HasFlow(env.player))
  end)

  -- 未配置商品的信号：不发货（不知道它该发什么），只记日志
  it('test_signal_for_unconfigured_goods_grants_nothing', function()
    persistReady()
    env.goodsSignal:Fire('goodsAdr1', 1, env.player) -- adrenaline1.goodsId 未配置
    drain()
    assert.same(0, env.data:ItemCount(GameCfg.Survival.AdrenalineItemId))
  end)

  -- 测试 flow 开 / 关通知客户端驱动按钮；真实平台 flow 不发（生产也就看不到驱动入口）
  it('test_test_flow_notifies_client_driver', function()
    assert.is_true(env.platform:Purchase(env.player, 'blindboxTen', 'blindbox', function() end))
    local opened = messages('PlatformResult')
    assert.same(1, #opened)
    assert.same('TestFlow', opened[1].action)
    assert.is_true(opened[1].open)
    assert.same('blindboxTen', opened[1].key)
    env.platform:HandleTestAction(env.player, { action = 'ResolveFlow', outcome = 'cancel' })
    local closed = messages('PlatformResult')
    assert.same(2, #closed)
    assert.is_false(closed[2].open)
    env.events = {}
    GameCfg.Platform.Goods.adrenaline1.goodsId = 'goodsAdr1'
    assert.is_true(env.platform:Purchase(env.player, 'adrenaline1', 'adrenaline', function() end))
    assert.is_true(messages('PlatformResult')[1].open) -- 配置ID仍只允许测试flow
  end)

  -- 未配置商品（goodsId 空）+ 生产构建（Debug 关）：购买明确不可用，不建 flow、不发权益
  it('test_unconfigured_goods_unavailable_in_production', function()
    GameCfg.Debug = { Enabled = false }
    local outcomes = {}
    local accepted, reason = env.platform:Purchase(env.player, 'blindboxSingle', 'blindbox',
      function(outcome) outcomes[#outcomes + 1] = outcome end)
    assert.is_false(accepted)
    assert.same('unavailable', reason)
    assert.same({}, outcomes)
    assert.same({}, env.purchasePanels) -- 不拉起真实面板
    assert.is_false(env.platform:HasFlow(env.player))
  end)

  -- 无可信订单身份：真实信号不与 flow 关联，也不凭空发货
  it('test_unmatched_signals_never_grant_without_identity', function()
    GameCfg.Platform.Goods.adrenaline1.goodsId = 'goodsAdr1'
    persistReady()
    env.goodsSignal:Fire('goodsAdr1', 1, env.player)
    drain()
    assert.same(0, env.data:ItemCount(GameCfg.Survival.AdrenalineItemId))
    env.goodsSignal:Fire('goodsAdr1', 1, env.player) -- 第二笔真实购买：仍不发货
    drain()
    assert.same(0, env.data:ItemCount(GameCfg.Survival.AdrenalineItemId))
  end)
end)

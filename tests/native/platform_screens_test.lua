-- 迁移自 tests/gameplay/platform_screens_test.lua（#91）；行为契约原文见 #147 T26。
-- #147 T26 盲盒与平台购买客户端（client/ScreenHandlers/ScreenBlindbox、ScreenPlatform）失败方式先列：
--   1. 单抽 / 十连上行抽数或 seq 错，按钮价目与 GameCfg.Platform.Goods（10 / 90 金豆）不一致；
--   2. 满格落地前不提示就直接上行；提示后无法确认；空格够时也被拦；
--   3. 等待回包期间重复点击重复上行；回包丢失后界面永久卡死（超时不解锁）；
--   4. 同 operation.id 的重放回包重复展示 / 覆盖已展示结果；
--   5. 保底计数不随 State 握手（重进）与抽取结果刷新，大奖名不是内容表的保底奖品；
--   6. 不可用 / 取消 / 失败 / 超时没有玩家可读提示；
--   7. 测试驱动按钮在非测试 flow（生产）出现，或 flow 结束后不收起；驱动上行不是 PlatformTestAction；
--   8. 肾上腺素报价不按服务端回包渲染；购买上行错商品；发货溢出不告知落地件数；
--   9. client/main.lua 未启动两个界面。
-- seam：替换 game / REUtil / EUI 边界，直接调 handler 公共方法与 RE 回包；超时用 UpdateAwait(dt) 推进。
-- 两个旧类 TestScreenBlindbox / TestScreenPlatform 各自一个 describe，
-- 注册顺序 = LuaUnit 类名字典序 + 类内 sortedPairs 的实际执行顺序。

-- GameUI 是真实 client.GameUI 装载时写下的模块全局（_G.GameUI），旧单进程 runner 里它跨套件长存；
-- 原生逐例隔离后纳入快照面，跑完不留下新全局。
local globalNames = { 'game', 'Vector2', 'Color', 'REUtil', 'LocalMsgNotice', 'PlatformShop', 'GameUI' }
local moduleNames = { 'common.GameCfg', 'common.REUtil', 'client.GameUI' }

local function signal()
  local listeners = {}
  return {
    Connect = function(_, fn)
      listeners[#listeners + 1] = fn
      return { Disconnect = function() end }
    end,
    Fire = function(_, ...) for _, fn in ipairs(listeners) do fn(...) end end,
  }
end

-- 每例重建客户端边界夹具。返回 env 与一个只做「还原」的闭包，供 after_each 幂等调用。
local function setUpClient()
  local env = { previous = {}, previousLoaded = {}, nodes = {}, commands = {}, notices = {}, events = {} }
  for _, key in ipairs(globalNames) do
    env.previous[key] = rawget(_G, key)
  end
  for _, name in ipairs(moduleNames) do
    env.previousLoaded[name] = package.loaded[name]
    package.loaded[name] = nil
  end
  env.cfg = require('common.GameCfg')
  local world = {}
  function world:CreateUnit(kind, attrs)
    local node = { Kind = kind, OnClicked = signal(), Visible = true }
    for key, value in pairs(attrs) do node[key] = value end
    if node.Name then env.nodes[node.Name] = node end
    return node
  end
  function world:FindFirstChild() return nil end
  local root = { Name = 'UIRoot', FindFirstChild = function() return nil end }
  local eui = { GetRootNode = function() return root end,
    GetDeviceResolution = function() return { x = 1920, y = 1080 } end }
  env.heartbeat = signal()
  rawset(_G, 'LocalMsgNotice', function(msg) env.notices[#env.notices + 1] = msg end)
  rawset(_G, 'Vector2', { New = function(x, y) return { x = x, y = y } end })
  rawset(_G, 'Color', { New = function(...) return { ... } end })
  rawset(_G, 'game', { GetService = function(_, name)
    if name == 'World' then return world end
    if name == 'Players' then return { LocalPlayer = { PlayerGui = { EuiManager = eui }, UserId = 7 } } end
    if name == 'RunService' then return { Heartbeat = env.heartbeat,
      IsClient = function() return true end, IsServer = function() return false end } end
    if name == 'Task' then return { Spawn = function(_, fn) fn() end, Wait = function() end } end
  end })
  local reStub = { GetRE = function(_, name)
    if not env.events[name] then
      env.events[name] = {
        OnClientEvent = signal(),
        FireServer = function(_, payload)
          env.commands[#env.commands + 1] = { name = name, payload = payload }
        end,
      }
    end
    return env.events[name]
  end }
  package.loaded['common.REUtil'] = reStub
  rawset(_G, 'REUtil', reStub)

  env.restore = function()
    for _, key in ipairs(globalNames) do
      rawset(_G, key, env.previous[key])
    end
    for _, name in ipairs(moduleNames) do
      package.loaded[name] = env.previousLoaded[name]
    end
  end
  return env
end

local function sent(env, name)
  local out = {}
  for _, command in ipairs(env.commands) do
    if command.name == name then out[#out + 1] = command.payload or {} end
  end
  return out
end

-- 道具栏 + 背包快照：free 个空格（其余占满）
local function snapshotWithFree(free)
  local slots, backpack = {}, {}
  for index = 1, 5 do slots[index] = { itemId = 'item1', count = 1 } end
  for index = 1, 10 do backpack[index] = { itemId = 'item1', count = 1 } end
  for index = 1, free do backpack[index] = nil end
  return { slots = slots, slotCount = 5, backpack = backpack, backpackCount = 10 }
end

describe('盲盒界面（ScreenBlindbox）', function()
  local env

  before_each(function()
    -- 快照先于任何改动：夹具中途失败时 after_each 仍能还原。
    env = setUpClient()
    env.screen = assert(loadfile('client/ScreenHandlers/ScreenBlindbox.lua'))()
    env.screen:Start()
  end)

  after_each(function()
    if env and env.restore then env.restore() end
    env = nil
  end)

  local function fireItemBar(state)
    env.events.ItemBarState.OnClientEvent:Fire(state)
  end

  local function fireResult(result)
    env.events.BlindboxResult.OnClientEvent:Fire(result)
  end

  it('test_awaiting_blocks_repeat_clicks_and_times_out', function()
    fireItemBar(snapshotWithFree(15))
    assert.is_true(env.screen:Draw(1))
    assert.is_false(env.screen:Draw(1))
    assert.same(1, #sent(env, 'BlindboxAction'))
    env.heartbeat:Fire(env.cfg.Blindbox.ResultTimeoutSec - 1)
    assert.is_false(env.screen:Draw(1)) -- 支付等待中仍锁
    env.heartbeat:Fire(1)
    assert.matches('超时', env.notices[#env.notices], 1, true)
    assert.is_false(env.screen:Draw(1))
    assert.same('Query', sent(env, 'BlindboxAction')[2].action)
    assert.same(1, sent(env, 'BlindboxAction')[2].seq)
  end)

  it('test_buttons_show_platform_prices_and_send_counts', function()
    assert.matches('10金豆', env.nodes.BtnBlindboxSingleText.Text, 1, true)
    assert.matches('90金豆', env.nodes.BtnBlindboxTenText.Text, 1, true)
    fireItemBar(snapshotWithFree(10))
    env.nodes.BtnBlindboxSingle.OnClicked:Fire()
    fireResult({ ok = true, operation = { id = 'op1' }, pityAfter = 1,
      draws = { { itemKey = 'item1', itemName = '甲' } }, grounded = 0 })
    env.nodes.BtnBlindboxTen.OnClicked:Fire()
    local draws = sent(env, 'BlindboxAction')
    assert.same({ action = 'Draw', count = 1, seq = 1 }, draws[1])
    assert.same({ action = 'Draw', count = 10, seq = 2 }, draws[2])
  end)

  it('test_failures_have_readable_notices_and_unlock', function()
    fireItemBar(snapshotWithFree(15))
    env.screen:Draw(1)
    fireResult({ ok = false, reason = 'unavailable' })
    assert.same(env.cfg.Blindbox.UnavailableText, env.notices[#env.notices])
    assert.is_true(env.screen:Draw(1)) -- 失败即解锁
    for _, reason in ipairs({ 'cancel', 'fail', 'timeout', 'pending', 'busy' }) do
      fireResult({ ok = false, reason = reason })
      assert.same(env.cfg.Platform.ReasonText[reason], env.notices[#env.notices])
    end
  end)

  it('test_full_inventory_warns_before_landing_and_second_click_confirms', function()
    fireItemBar(snapshotWithFree(3))
    assert.is_true(env.screen:Draw(1)) -- 3 个空格够单抽：不拦
    fireResult({ ok = true, operation = { id = 'op1' }, pityAfter = 1, draws = {}, grounded = 0 })
    assert.is_false(env.screen:Draw(10)) -- 放不下十连：先提示
    assert.same(env.cfg.Blindbox.FullNoticeText, env.notices[#env.notices])
    assert.same(1, #sent(env, 'BlindboxAction'))
    assert.is_true(env.screen:Draw(10)) -- 同一抽数再点确认
    assert.same(10, sent(env, 'BlindboxAction')[2].count)
  end)

  it('test_old_response_cannot_unlock_new_request', function()
    fireItemBar(snapshotWithFree(15))
    env.screen:Draw(1)
    fireResult({ ok = false, reason = 'cancel', seq = 1 })
    env.screen:Draw(1)
    fireResult({ ok = true, seq = 1, operation = { id = 'old' }, draws = {} })
    assert.is_true(env.screen.Awaiting)
    assert.same(2, env.screen.Seq)
  end)

  it('test_pending_adopts_original_identity_after_lost_state', function()
    fireItemBar(snapshotWithFree(15))
    env.screen.Seq = 1 -- State 握手丢失，新请求撞上原未决意图
    env.screen:Draw(1)
    fireResult({ ok = false, reason = 'busy', seq = 2, originalSeq = 1,
      requestId = 'original', deliveryPending = true })
    env.heartbeat:Fire(env.cfg.Blindbox.ResultTimeoutSec)
    local query = sent(env, 'BlindboxAction')[2]
    assert.same(1, query.seq)
    assert.same('original', query.requestId)
    fireResult({ ok = true, seq = 1, requestId = 'original', operation = { id = 'original' }, draws = {} })
    assert.is_false(env.screen.Awaiting)
    assert.is_true(env.screen:Draw(1))
  end)

  it('test_result_shows_draws_updates_pity_and_ignores_replay', function()
    fireItemBar(snapshotWithFree(15))
    env.screen:Draw(10)
    fireResult({ ok = true, operation = { id = 'op9' }, pityBefore = 45, pityAfter = 0, grounded = 2,
      draws = { { itemName = '鲫鱼' }, { itemName = '极品美人鱼', jackpot = true, guaranteed = true },
        { itemName = '鲤鱼', landed = true } } })
    local text = env.nodes.LabelBlindboxResult.Text
    assert.matches('极品美人鱼（保底）', text, 1, true)
    assert.matches('鲤鱼（落在地上）', text, 1, true)
    assert.matches('2 件物品落在面前地上', env.notices[#env.notices], 1, true)
    assert.matches('已连续 0 次', env.nodes.LabelBlindboxPity.Text, 1, true)
    local noticeCount = #env.notices
    env.nodes.LabelBlindboxResult.Text = 'kept'
    fireResult({ ok = true, operation = { id = 'op9' }, pityAfter = 0, grounded = 2, draws = {} })
    assert.same('kept', env.nodes.LabelBlindboxResult.Text) -- 重放不覆盖
    assert.same(noticeCount, #env.notices)
  end)

  it('test_start_handshakes_state_and_entry_toggles_panel', function()
    assert.same(1, #sent(env, 'BlindboxStateRequest')) -- 重进握手
    assert.is_false(env.nodes.ScreenBlindbox.Visible)
    env.nodes.BtnBlindboxEntry.OnClicked:Fire()
    assert.is_true(env.nodes.ScreenBlindbox.Visible)
    assert.same(2, #sent(env, 'BlindboxStateRequest')) -- 开面板再拉一次计数
    env.nodes.BtnBlindboxClose.OnClicked:Fire()
    assert.is_false(env.nodes.ScreenBlindbox.Visible)
  end)

  it('test_state_handshake_refreshes_pity_with_content_prize_names', function()
    fireResult({ ok = true, action = 'State', pity = 49, guaranteeAt = 50 })
    local text = env.nodes.LabelBlindboxPity.Text
    assert.matches('已连续 49 次', text, 1, true)
    assert.matches('再抽 1 次', text, 1, true)
    assert.matches('极品美人鱼', text, 1, true) -- 内容表 Pity.prizeItemKeys → 名字
    assert.matches('极品蛇颈龙', text, 1, true)
  end)
end)

describe('平台购买界面（ScreenPlatform）', function()
  local env

  before_each(function()
    env = setUpClient()
    env.panel = assert(loadfile('client/ScreenHandlers/ScreenPlatform.lua'))()
    env.panel:Start()
  end)

  after_each(function()
    if env and env.restore then env.restore() end
    env = nil
  end)

  local function fire(result)
    env.events.PlatformResult.OnClientEvent:Fire(result)
  end

  it('test_adrenaline_offers_render_server_prices_and_buy_selected_goods', function()
    fire({ ok = true, action = 'AdrenalineShop', offers = {
      { key = 'adrenaline1', name = '肾上腺素', beans = 1 },
      { key = 'adrenaline5', name = '肾上腺素×5', beans = 4 } } })
    assert.is_true(env.nodes.PlatformOffers.Visible)
    assert.same('肾上腺素×5（4金豆）', env.nodes.BtnPlatformOffer2Text.Text)
    env.nodes.BtnPlatformOffer2.OnClicked:Fire()
    assert.same({ action = 'Purchase', goods = 'adrenaline5' }, sent(env, 'PlatformAction')[1])
    assert.is_false(env.nodes.PlatformOffers.Visible)
  end)

  it('test_client_main_starts_both_screens', function()
    local file = assert(io.open('client/main.lua', 'r'))
    local src = file:read('a')
    file:close()
    assert.matches('require("client.ScreenHandlers.ScreenBlindbox")', src, 1, true)
    assert.matches('ScreenBlindbox:Start()', src, 1, true)
    assert.matches('require("client.ScreenHandlers.ScreenPlatform")', src, 1, true)
    assert.matches('ScreenPlatform:Start()', src, 1, true)
  end)

  it('test_coin_shop_entry_is_global_for_screen_shop', function()
    assert.are.equal(env.panel, rawget(_G, 'PlatformShop'))
    env.panel:Open()
    assert.same({ action = 'OpenCoinShop' }, sent(env, 'PlatformAction')[1])
  end)

  it('test_test_driver_only_follows_test_flow_notices', function()
    assert.is_false(env.nodes.PlatformTestDriver.Visible)
    fire({ ok = true, action = 'TestFlow', open = true, key = 'blindboxTen' })
    assert.is_true(env.nodes.PlatformTestDriver.Visible)
    assert.matches('blindboxTen', env.nodes.PlatformTestDriverTitle.Text, 1, true)
    env.nodes.BtnPlatformTest_success.OnClicked:Fire()
    assert.same({ action = 'ResolveFlow', outcome = 'success' }, sent(env, 'PlatformTestAction')[1])
    fire({ ok = true, action = 'TestFlow', open = false })
    assert.is_false(env.nodes.PlatformTestDriver.Visible)
  end)

  it('test_unavailable_and_failures_are_readable_and_grant_reports_overflow', function()
    fire({ ok = false, action = 'AdrenalineShop', reason = 'unavailable' })
    assert.same(env.cfg.Platform.UnavailableText, env.notices[#env.notices])
    assert.is_not_true(env.nodes.PlatformOffers.Visible)
    fire({ ok = false, action = 'Purchase', goods = 'adrenaline1', reason = 'cancel' })
    assert.same(env.cfg.Platform.ReasonText.cancel, env.notices[#env.notices])
    fire({ ok = true, action = 'Grant', goods = 'adrenaline5', overflow = 2 })
    assert.matches('肾上腺素×5', env.notices[#env.notices], 1, true)
    assert.matches('2 件落在面前地上', env.notices[#env.notices], 1, true)
  end)
end)

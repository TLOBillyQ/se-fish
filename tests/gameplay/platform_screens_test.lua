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
local lu = require('luaunit')

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

local function setUpClient(env)
    env.previous = {}
    for _, key in ipairs({ 'game', 'Vector2', 'Color', 'REUtil', 'LocalMsgNotice', 'PlatformShop' }) do
        env.previous[key] = rawget(_G, key)
    end
    env.previousLoaded = {}
    for _, name in ipairs({ 'common.GameCfg', 'common.REUtil', 'client.GameUI' }) do
        env.previousLoaded[name] = package.loaded[name]
        package.loaded[name] = nil
    end
    env.cfg = require('common.GameCfg')
    env.nodes, env.commands, env.notices, env.events = {}, {}, {}, {}
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
    _G.LocalMsgNotice = function(msg) env.notices[#env.notices + 1] = msg end
    _G.Vector2 = { New = function(x, y) return { x = x, y = y } end }
    _G.Color = { New = function(...) return { ... } end }
    _G.game = { GetService = function(_, name)
        if name == 'World' then return world end
        if name == 'Players' then return { LocalPlayer = { PlayerGui = { EuiManager = eui }, UserId = 7 } } end
        if name == 'RunService' then return { Heartbeat = env.heartbeat,
            IsClient = function() return true end, IsServer = function() return false end } end
        if name == 'Task' then return { Spawn = function(_, fn) fn() end, Wait = function() end } end
    end }
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
    _G.REUtil = reStub
end

local function tearDownClient(env)
    for key, value in pairs(env.previous) do rawset(_G, key, value) end
    for _, key in ipairs({ 'game', 'Vector2', 'Color', 'REUtil', 'LocalMsgNotice', 'PlatformShop' }) do
        if env.previous[key] == nil then rawset(_G, key, nil) end
    end
    for name, value in pairs(env.previousLoaded) do package.loaded[name] = value end
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

TestScreenBlindbox = {}

function TestScreenBlindbox:setUp()
    setUpClient(self)
    self.screen = assert(loadfile('client/ScreenHandlers/ScreenBlindbox.lua'))()
    self.screen:Start()
end

function TestScreenBlindbox:tearDown()
    tearDownClient(self)
end

function TestScreenBlindbox:fireItemBar(state)
    self.events.ItemBarState.OnClientEvent:Fire(state)
end

function TestScreenBlindbox:fireResult(result)
    self.events.BlindboxResult.OnClientEvent:Fire(result)
end

function TestScreenBlindbox:test_start_handshakes_state_and_entry_toggles_panel()
    lu.assertEquals(#sent(self, 'BlindboxStateRequest'), 1) -- 重进握手
    lu.assertFalse(self.nodes.ScreenBlindbox.Visible)
    self.nodes.BtnBlindboxEntry.OnClicked:Fire()
    lu.assertTrue(self.nodes.ScreenBlindbox.Visible)
    lu.assertEquals(#sent(self, 'BlindboxStateRequest'), 2) -- 开面板再拉一次计数
    self.nodes.BtnBlindboxClose.OnClicked:Fire()
    lu.assertFalse(self.nodes.ScreenBlindbox.Visible)
end

function TestScreenBlindbox:test_buttons_show_platform_prices_and_send_counts()
    lu.assertStrContains(self.nodes.BtnBlindboxSingleText.Text, '10金豆')
    lu.assertStrContains(self.nodes.BtnBlindboxTenText.Text, '90金豆')
    self:fireItemBar(snapshotWithFree(10))
    self.nodes.BtnBlindboxSingle.OnClicked:Fire()
    self:fireResult({ ok = true, operation = { id = 'op1' }, pityAfter = 1,
        draws = { { itemKey = 'item1', itemName = '甲' } }, grounded = 0 })
    self.nodes.BtnBlindboxTen.OnClicked:Fire()
    local draws = sent(self, 'BlindboxAction')
    lu.assertEquals(draws[1], { action = 'Draw', count = 1, seq = 1 })
    lu.assertEquals(draws[2], { action = 'Draw', count = 10, seq = 2 })
end

function TestScreenBlindbox:test_full_inventory_warns_before_landing_and_second_click_confirms()
    self:fireItemBar(snapshotWithFree(3))
    lu.assertTrue(self.screen:Draw(1)) -- 3 个空格够单抽：不拦
    self:fireResult({ ok = true, operation = { id = 'op1' }, pityAfter = 1, draws = {}, grounded = 0 })
    lu.assertFalse(self.screen:Draw(10)) -- 放不下十连：先提示
    lu.assertEquals(self.notices[#self.notices], self.cfg.Blindbox.FullNoticeText)
    lu.assertEquals(#sent(self, 'BlindboxAction'), 1)
    lu.assertTrue(self.screen:Draw(10)) -- 同一抽数再点确认
    lu.assertEquals(sent(self, 'BlindboxAction')[2].count, 10)
end

function TestScreenBlindbox:test_awaiting_blocks_repeat_clicks_and_times_out()
    self:fireItemBar(snapshotWithFree(15))
    lu.assertTrue(self.screen:Draw(1))
    lu.assertFalse(self.screen:Draw(1))
    lu.assertEquals(#sent(self, 'BlindboxAction'), 1)
    self.heartbeat:Fire(self.cfg.Blindbox.ResultTimeoutSec - 1)
    lu.assertFalse(self.screen:Draw(1)) -- 支付等待中仍锁
    self.heartbeat:Fire(1)
    lu.assertStrContains(self.notices[#self.notices], '超时')
    lu.assertTrue(self.screen:Draw(1))
    lu.assertEquals(sent(self, 'BlindboxAction')[2].seq, 2)
end

function TestScreenBlindbox:test_result_shows_draws_updates_pity_and_ignores_replay()
    self:fireItemBar(snapshotWithFree(15))
    self.screen:Draw(10)
    self:fireResult({ ok = true, operation = { id = 'op9' }, pityBefore = 45, pityAfter = 0, grounded = 2,
        draws = { { itemName = '鲫鱼' }, { itemName = '极品美人鱼', jackpot = true, guaranteed = true },
            { itemName = '鲤鱼', landed = true } } })
    local text = self.nodes.LabelBlindboxResult.Text
    lu.assertStrContains(text, '极品美人鱼（保底）')
    lu.assertStrContains(text, '鲤鱼（落在地上）')
    lu.assertStrContains(self.notices[#self.notices], '2 件物品落在面前地上')
    lu.assertStrContains(self.nodes.LabelBlindboxPity.Text, '已连续 0 次')
    local noticeCount = #self.notices
    self.nodes.LabelBlindboxResult.Text = 'kept'
    self:fireResult({ ok = true, operation = { id = 'op9' }, pityAfter = 0, grounded = 2, draws = {} })
    lu.assertEquals(self.nodes.LabelBlindboxResult.Text, 'kept') -- 重放不覆盖
    lu.assertEquals(#self.notices, noticeCount)
end

function TestScreenBlindbox:test_state_handshake_refreshes_pity_with_content_prize_names()
    self:fireResult({ ok = true, action = 'State', pity = 49, guaranteeAt = 50 })
    local text = self.nodes.LabelBlindboxPity.Text
    lu.assertStrContains(text, '已连续 49 次')
    lu.assertStrContains(text, '再抽 1 次')
    lu.assertStrContains(text, '极品美人鱼') -- 内容表 Pity.prizeItemKeys → 名字
    lu.assertStrContains(text, '极品蛇颈龙')
end

function TestScreenBlindbox:test_failures_have_readable_notices_and_unlock()
    self:fireItemBar(snapshotWithFree(15))
    self.screen:Draw(1)
    self:fireResult({ ok = false, reason = 'unavailable' })
    lu.assertEquals(self.notices[#self.notices], self.cfg.Blindbox.UnavailableText)
    lu.assertTrue(self.screen:Draw(1)) -- 失败即解锁
    for _, reason in ipairs({ 'cancel', 'fail', 'timeout', 'pending', 'busy' }) do
        self:fireResult({ ok = false, reason = reason })
        lu.assertEquals(self.notices[#self.notices], self.cfg.Platform.ReasonText[reason])
    end
end

TestScreenPlatform = {}

function TestScreenPlatform:setUp()
    setUpClient(self)
    self.panel = assert(loadfile('client/ScreenHandlers/ScreenPlatform.lua'))()
    self.panel:Start()
end

function TestScreenPlatform:tearDown()
    tearDownClient(self)
end

function TestScreenPlatform:fire(result)
    self.events.PlatformResult.OnClientEvent:Fire(result)
end

function TestScreenPlatform:test_test_driver_only_follows_test_flow_notices()
    lu.assertFalse(self.nodes.PlatformTestDriver.Visible)
    self:fire({ ok = true, action = 'TestFlow', open = true, key = 'blindboxTen' })
    lu.assertTrue(self.nodes.PlatformTestDriver.Visible)
    lu.assertStrContains(self.nodes.PlatformTestDriverTitle.Text, 'blindboxTen')
    self.nodes.BtnPlatformTest_success.OnClicked:Fire()
    lu.assertEquals(sent(self, 'PlatformTestAction')[1], { action = 'ResolveFlow', outcome = 'success' })
    self:fire({ ok = true, action = 'TestFlow', open = false })
    lu.assertFalse(self.nodes.PlatformTestDriver.Visible)
end

function TestScreenPlatform:test_adrenaline_offers_render_server_prices_and_buy_selected_goods()
    self:fire({ ok = true, action = 'AdrenalineShop', offers = {
        { key = 'adrenaline1', name = '肾上腺素', beans = 1 },
        { key = 'adrenaline5', name = '肾上腺素×5', beans = 4 } } })
    lu.assertTrue(self.nodes.PlatformOffers.Visible)
    lu.assertEquals(self.nodes.BtnPlatformOffer2Text.Text, '肾上腺素×5（4金豆）')
    self.nodes.BtnPlatformOffer2.OnClicked:Fire()
    lu.assertEquals(sent(self, 'PlatformAction')[1], { action = 'Purchase', goods = 'adrenaline5' })
    lu.assertFalse(self.nodes.PlatformOffers.Visible)
end

function TestScreenPlatform:test_unavailable_and_failures_are_readable_and_grant_reports_overflow()
    self:fire({ ok = false, action = 'AdrenalineShop', reason = 'unavailable' })
    lu.assertEquals(self.notices[#self.notices], self.cfg.Platform.UnavailableText)
    lu.assertNotEquals(self.nodes.PlatformOffers.Visible, true)
    self:fire({ ok = false, action = 'Purchase', goods = 'adrenaline1', reason = 'cancel' })
    lu.assertEquals(self.notices[#self.notices], self.cfg.Platform.ReasonText.cancel)
    self:fire({ ok = true, action = 'Grant', goods = 'adrenaline5', overflow = 2 })
    lu.assertStrContains(self.notices[#self.notices], '肾上腺素×5')
    lu.assertStrContains(self.notices[#self.notices], '2 件落在面前地上')
end

function TestScreenPlatform:test_coin_shop_entry_is_global_for_screen_shop()
    lu.assertIs(rawget(_G, 'PlatformShop'), self.panel)
    self.panel:Open()
    lu.assertEquals(sent(self, 'PlatformAction')[1], { action = 'OpenCoinShop' })
end

function TestScreenPlatform:test_client_main_starts_both_screens()
    local file = assert(io.open('client/main.lua', 'r'))
    local src = file:read('a')
    file:close()
    lu.assertStrContains(src, 'require("client.ScreenHandlers.ScreenBlindbox")')
    lu.assertStrContains(src, 'ScreenBlindbox:Start()')
    lu.assertStrContains(src, 'require("client.ScreenHandlers.ScreenPlatform")')
    lu.assertStrContains(src, 'ScreenPlatform:Start()')
end

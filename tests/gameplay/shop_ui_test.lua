-- #130 失败方式先列：页签缺失/页内容错（排序与 ListForPage 口径不一致）、
-- 升级页不分页、行状态错（锁定可点/已购可重复买）、购买发了 itemKey 而不是编号、
-- 金币页平台不可用时伪成功或卡死（不可返回）、失败提示缺 limit/level/金币页引导。
local lu = require('luaunit')
local GameCfg = require('common.GameCfg')

local function signal()
    local listeners = {}
    return {
        Connect = function(_, fn)
            listeners[#listeners + 1] = fn
            return { Disconnect = function()
                for i, cb in ipairs(listeners) do
                    if cb == fn then table.remove(listeners, i) break end
                end
            end }
        end,
        Fire = function(_, ...) for _, fn in ipairs(listeners) do fn(...) end end,
    }
end

TestScreenShop = {}

function TestScreenShop:setUp()
    self.previous = { game = rawget(_G, 'game'), Vector2 = rawget(_G, 'Vector2'),
        Color = rawget(_G, 'Color'), REUtil = rawget(_G, 'REUtil'),
        GameUI = rawget(_G, 'GameUI'), MgrGameUI = rawget(_G, 'MgrGameUI'),
        Players = rawget(_G, 'Players') }
    self.previousLocalShop = package.loaded['client.LocalShop']
    self.previousHandler = package.loaded['client.ScreenHandlers.ScreenShop']
    package.loaded['client.LocalShop'] = { Stand = { AnchorName = 'TGUnitShopShrimp', Level = 2 } }
    package.loaded['client.ScreenHandlers.ScreenShop'] = nil
    self.nodes, self.created = {}, {}
    local env = self
    local world = {}
    function world:CreateUnit(kind, attrs)
        local node = { Kind = kind, OnClicked = signal() }
        for key, value in pairs(attrs) do node[key] = value end
        function node:Destroy()
            self.Destroyed = true
            for _, child in ipairs(env.created) do
                if child.Parent == self then child:Destroy() end
            end
        end
        if node.Name then env.nodes[node.Name] = node end
        env.created[#env.created + 1] = node
        return node
    end
    self.localPlayer = { GetAttribute = function() return 77 end }
    _G.game = { GetService = function(_, name)
        if name == 'World' then return world end
        if name == 'Players' then return { LocalPlayer = self.localPlayer } end
    end }
    _G.Vector2 = { New = function(x, y) return { x = x, y = y } end }
    _G.Color = { New = function(...) return { ... } end }
    _G.GameUI = { GetEuiManager = function() return {
        GetDeviceResolution = function() return { x = 1920, y = 1080 } end } end }
    self.commands = {}
    self.events = {}
    _G.REUtil = { GetRE = function(_, name)
        if not self.events[name] then
            self.events[name] = { OnClientEvent = signal(), FireServer = function(_, payload)
                self.commands[#self.commands + 1] = payload end }
        end
        return self.events[name]
    end }
    self.handler = assert(loadfile('client/ScreenHandlers/ScreenShop.lua'))()
    for _, name in ipairs(self.handler.UINodes) do
        self.nodes[name] = { Visible = true, OnClicked = signal() }
    end
    self.handler.UINodeMap = self.nodes
    self.handler.RootNode = { Name = 'ScreenShop' }
    self.handler:Init()
    self.handler.IsOpen = true
end

function TestScreenShop:tearDown()
    package.loaded['client.LocalShop'] = self.previousLocalShop
    package.loaded['client.ScreenHandlers.ScreenShop'] = self.previousHandler
    for _, key in ipairs({ 'game', 'Vector2', 'Color', 'REUtil', 'GameUI', 'MgrGameUI' }) do
        _G[key] = self.previous[key]
    end
end

local function numbersOf(rows)
    local out = {}
    for i, row in ipairs(rows or {}) do out[i] = row and row.goods.Number or nil end
    return out
end

function TestScreenShop:test_tabs_cover_four_pages()
    for _, page in ipairs({ '钓具', '武器', '升级', '金币' }) do
        lu.assertNotNil(self.nodes['BtnShopPage' .. page], '缺页签 ' .. page)
    end
end

-- 2 级摊位钓具页：新品（香肠 11/钓虾竿 12）置顶，其后按编号；锁定行（等级不够）也列出但灰显
function TestScreenShop:test_page_rows_follow_list_for_page_order()
    lu.assertEquals(numbersOf(self.handler.VisibleRows), { 11, 12, 1, 2, 3, 4, 5, 6 })
    lu.assertEquals(self.nodes.ShopItemName1.Text, '香肠')
    lu.assertEquals(self.nodes.ShopItemName2.Text, '钓虾竿')
    -- 第 3 行起是运行时补位行：科技假饵（1）需 7 级摊位 → 锁定灰显
    local extra3 = self.nodes.BtnShopBuyExtra3
    lu.assertTrue(extra3.Visible)
    lu.assertFalse(extra3.TouchEnabled)
    lu.assertStrContains(self.nodes.LabelShopBuyExtra3.Text, '需 7 级摊位')
end

function TestScreenShop:test_page_switch_renders_target_page()
    self.handler:SetPage('武器')
    -- 新品手枪(23)/斧头(24)/鞭炮(17) 置顶组按编号 17<23<24，其后按编号含锁定行
    lu.assertEquals(numbersOf(self.handler.VisibleRows), { 17, 23, 24, 15, 16, 18, 19, 20 })
end

-- 行状态：锁定行灰显且不可点；购买后已购且同号重购被客户端拦下
function TestScreenShop:test_row_states_locked_and_owned()
    self.handler:SetPage('升级')
    local function rowOf(number)
        for index, row in ipairs(self.handler.VisibleRows) do
            if row and row.goods.Number == number then return row.goods, index end
        end
        return nil
    end
    -- 2 级摊位升级页：第 3 页才有近战 1 级（51）
    self.handler:TurnPage(1)
    self.handler:TurnPage(1)
    local melee1 = rowOf(51)
    lu.assertNotNil(melee1)
    lu.assertEquals(self.handler:RowState(melee1, 2), 'buy')
    lu.assertEquals(self.handler:RowState(rowOf(49), 2), 'locked') -- 近战 3 级需 3 级摊位
    self.handler:TurnPage(-2) -- 回第 1 页
    lu.assertEquals(self.handler:RowState(rowOf(32), 2), 'locked') -- 背包 2 级越级（当前 0 级）
    -- 模拟服务端回包：近战 1 级购买成功 → 行转已购，近战 2 级（50）逐级解锁
    self.events.ShopResult.OnClientEvent:Fire({ ok = true, number = 51, kind = 'melee', level = 1, price = 50 })
    lu.assertEquals(self.handler:RowState(melee1, 2), 'owned')
    lu.assertEquals(self.handler:RowState(rowOf(50), 2), 'buy')
    -- 已购行点击不发请求
    self.commands = {}
    self.handler:TurnPage(2)
    local _, index = rowOf(51)
    self.handler:Buy(index)
    lu.assertEquals(self.commands, {})
end

-- 购买一律发编号（升级行无 itemKey）；点击行与上行一致
function TestScreenShop:test_buy_sends_number_not_item_key()
    self.handler:Buy(1) -- 钓具页第 1 行 = 香肠(11)
    lu.assertEquals(self.commands, { { action = 'Buy', number = 11, seq = 1 } })
    self.handler:SetPage('升级')
    self.handler:Buy(2) -- 2 级摊位升级页第 2 行 = 弹容量升级1(41)，逐级可买
    lu.assertEquals(self.commands[2].number, 41)
    lu.assertNil(self.commands[2].itemId)
end

-- 页内翻页：7 级摊位升级页 24 行 > 8 行/页
function TestScreenShop:test_in_page_paging_for_upgrade_page()
    package.loaded['client.LocalShop'].Stand = { AnchorName = 'TGUnitShop7', Level = 7 }
    self.handler:SetPage('升级')
    local function nums()
        local out = {}
        for i, row in ipairs(self.handler.VisibleRows) do out[i] = row and row.goods.Number end
        return out
    end
    -- 7 级新品：远程5(34)/爆炸3(42)/近战7(45) 置顶（弹容3 是 6 级新品，不在 7 级组），其后按编号
    lu.assertEquals(nums(), { 34, 42, 45, 28, 29, 30, 31, 32 })
    lu.assertFalse(self.nodes.BtnShopPrev.Visible)
    lu.assertTrue(self.nodes.BtnShopNext.Visible)
    self.handler:TurnPage(1)
    lu.assertEquals(nums(), { 33, 35, 36, 37, 38, 39, 40, 41 })
    lu.assertTrue(self.nodes.BtnShopPrev.Visible)
    self.handler:TurnPage(1)
    lu.assertEquals(nums(), { 43, 44, 46, 47, 48, 49, 50, 51 })
    lu.assertFalse(self.nodes.BtnShopNext.Visible)
    self.handler:TurnPage(-1) -- 可返回上一页
    lu.assertEquals(nums()[1], 33)
end

-- 金币页：无商品行；平台不可用时提示、停留本屏（页签可返回）、不发购买请求（不伪成功）
function TestScreenShop:test_coin_page_degrades_without_platform()
    self.handler:SetPage('金币')
    lu.assertEquals(numbersOf(self.handler.VisibleRows), {})
    lu.assertTrue(self.nodes.LabelCoinPageHint.Visible)
    lu.assertTrue(self.nodes.BtnOpenPlatformShop.Visible)
    _G.PlatformShop = nil
    self.nodes.BtnOpenPlatformShop.OnClicked:Fire()
    lu.assertStrContains(self.nodes.LabelCoinPageHint.Text, '平台商店暂不可用')
    lu.assertTrue(self.handler.IsOpen) -- 未关闭，可返回
    self.handler:SetPage('钓具')
    lu.assertEquals(numbersOf(self.handler.VisibleRows), { 11, 12, 1, 2, 3, 4, 5, 6 })
    lu.assertEquals(self.commands, {}) -- 全程未发购买请求
end

-- 平台入口抛错同样不伪成功
function TestScreenShop:test_coin_page_platform_error_not_faked()
    _G.PlatformShop = { Open = function() error('平台未接入') end }
    self.handler:SetPage('金币')
    self.nodes.BtnOpenPlatformShop.OnClicked:Fire()
    lu.assertStrContains(self.nodes.LabelCoinPageHint.Text, '打开失败')
    lu.assertTrue(self.handler.IsOpen)
    _G.PlatformShop = nil
end

-- ===== LocalShop 失败提示（#130 文案） =====
TestLocalShopNotice = {}

function TestLocalShopNotice:setUp()
    self.previous = { game = rawget(_G, 'game'), Vector3 = rawget(_G, 'Vector3'),
        Color = rawget(_G, 'Color'), GameUI = rawget(_G, 'GameUI'),
        LocalMsgNotice = rawget(_G, 'LocalMsgNotice') }
    self.previousModules = { ['common.REUtil'] = package.loaded['common.REUtil'],
        ['common.Util'] = package.loaded['common.Util'], ['client.LocalShop'] = package.loaded['client.LocalShop'] }
    package.loaded['common.REUtil'] = { GetRE = function(_, name)
        if name == 'ShopResult' then return { OnClientEvent = self.shopResult,
            FireClient = function() end } end
        return { FireClient = function() end }
    end }
    package.loaded['common.Util'] = { WaitForChild = function() return nil end,
        MsgNotice = function() end }
    package.loaded['client.LocalShop'] = nil
    self.notices = {}
    _G.LocalMsgNotice = function(msg) self.notices[#self.notices + 1] = msg end
    self.created = {}
    local world = {}
    function world:CreateUnit(_, attrs)
        local node = attrs or {}
        self.created[#self.created + 1] = node
        return node
    end
    _G.game = { GetService = function(_, name)
        if name == 'World' then return world end
        if name == 'Players' then return { LocalPlayer = { Character = nil } } end
        if name == 'RunService' then return { IsServer = function() return false end,
            Heartbeat = { Connect = function() end } } end
    end }
    _G.Vector3 = { New = function(x, y, z) return { x = x, y = y, z = z } end }
    _G.Color = { New = function(...) return { ... } end }
    _G.GameUI = { CreateSceneNode = function() error('无预设') end,
        GetEuiManager = function() return { CreateSceneNodeAtPosition = function() return {} end } end }
    self.shopResult = signal()
    _G.REUtil = { GetRE = function(_, name)
        if name == 'ShopResult' then return { OnClientEvent = self.shopResult } end
        return { FireClient = function() end }
    end }
    self.localShop = assert(loadfile('client/LocalShop.lua'))()
end

function TestLocalShopNotice:tearDown()
    for key, value in pairs(self.previousModules) do package.loaded[key] = value end
    for _, key in ipairs({ 'game', 'Vector3', 'Color', 'GameUI', 'LocalMsgNotice' }) do
        _G[key] = self.previous[key]
    end
end

function TestLocalShopNotice:test_fail_text_covers_limit_level_and_coin_guidance()
    lu.assertStrContains(self.localShop.FailText.limit, '上限')
    lu.assertStrContains(self.localShop.FailText.level, '前一级')
    lu.assertStrContains(self.localShop.FailText.coin, '金币页')
end

function TestLocalShopNotice:test_notice_mapping_for_new_reasons()
    self.localShop:Start() -- 连接 ShopResult；摊位锚点缺失只打日志
    self.shopResult:Fire({ ok = false, reason = 'limit', number = 51 })
    self.shopResult:Fire({ ok = false, reason = 'level', number = 50 })
    self.shopResult:Fire({ ok = false, reason = 'coin', itemId = 'starterRod' })
    self.shopResult:Fire({ ok = true, number = 51, kind = 'melee', level = 1, price = 50, name = '近战武器升级1' })
    lu.assertEquals(self.notices, {
        self.localShop.FailText.limit,
        self.localShop.FailText.level,
        self.localShop.FailText.coin,
        '购买成功：近战武器升级1，花费 50 金币',
    })
end

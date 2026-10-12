-- #86 迁移（原 tests/gameplay/shop_ui_test.lua，#130）。失败方式先列：
-- 页签缺失/页内容错（排序与 ListForPage 口径不一致）、
-- 升级页不分页、行状态错（锁定可点/已购可重复买）、购买发了 itemKey 而不是编号、
-- 金币页平台不可用时伪成功或卡死（不可返回）、失败提示缺 limit/level/金币页引导。
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

local function numbersOf(rows)
    local out = {}
    for i, row in ipairs(rows or {}) do out[i] = row and row.goods.Number or nil end
    return out
end


-- ===== LocalShop 失败提示（#130 文案） =====
describe("钓场商店的失败提示", function()
    local ctx

    before_each(function()
        ctx = { notices = {}, created = {} }
        ctx.previous = { game = rawget(_G, 'game'), Vector3 = rawget(_G, 'Vector3'),
            Color = rawget(_G, 'Color'), GameUI = rawget(_G, 'GameUI'),
            LocalMsgNotice = rawget(_G, 'LocalMsgNotice') }
        ctx.previousModules = { ['common.REUtil'] = package.loaded['common.REUtil'],
            ['common.Util'] = package.loaded['common.Util'], ['client.LocalShop'] = package.loaded['client.LocalShop'] }
        ctx.shopResult = signal()
        package.loaded['common.REUtil'] = { GetRE = function(_, name)
            if name == 'ShopResult' then return { OnClientEvent = ctx.shopResult,
                FireClient = function() end } end
            return { FireClient = function() end }
        end }
        package.loaded['common.Util'] = { WaitForChild = function() return nil end,
            MsgNotice = function() end }
        package.loaded['client.LocalShop'] = nil
        _G.LocalMsgNotice = function(msg) ctx.notices[#ctx.notices + 1] = msg end
        local world = {}
        function world:CreateUnit(_, attrs)
            local node = attrs or {}
            ctx.created[#ctx.created + 1] = node
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
        _G.REUtil = { GetRE = function(_, name)
            if name == 'ShopResult' then return { OnClientEvent = ctx.shopResult } end
            return { FireClient = function() end }
        end }
        ctx.localShop = assert(loadfile('client/LocalShop.lua'))()
    end)

    after_each(function()
        for key, value in pairs(ctx.previousModules) do package.loaded[key] = value end
        for _, key in ipairs({ 'game', 'Vector3', 'Color', 'GameUI', 'LocalMsgNotice' }) do
            _G[key] = ctx.previous[key]
        end
    end)

    it("test_fail_text_covers_limit_level_and_coin_guidance", function()
        assert.matches('上限', ctx.localShop.FailText.limit, nil, true)
        assert.matches('前一级', ctx.localShop.FailText.level, nil, true)
        assert.matches('金币页', ctx.localShop.FailText.coin, nil, true)
    end)

    it("test_notice_mapping_for_new_reasons", function()
        ctx.localShop:Start() -- 连接 ShopResult；摊位锚点缺失只打日志
        ctx.shopResult:Fire({ ok = false, reason = 'limit', number = 51 })
        ctx.shopResult:Fire({ ok = false, reason = 'level', number = 50 })
        ctx.shopResult:Fire({ ok = false, reason = 'coin', itemId = 'starterRod' })
        ctx.shopResult:Fire({ ok = true, number = 51, kind = 'melee', level = 1, price = 50, name = '近战武器升级1' })
        assert.same({
            ctx.localShop.FailText.limit,
            ctx.localShop.FailText.level,
            ctx.localShop.FailText.coin,
            '购买成功：近战武器升级1，花费 50 金币',
        }, ctx.notices)
    end)
end)
describe("钓场商店界面", function()
    local ctx

    -- 与旧 LuaUnit 的每例 setUp/tearDown 同级成对：处理器逐例重载，页签状态不串味。
    before_each(function()
        ctx = { nodes = {}, created = {}, commands = {}, events = {} }
        ctx.previous = { game = rawget(_G, 'game'), Vector2 = rawget(_G, 'Vector2'),
            Color = rawget(_G, 'Color'), REUtil = rawget(_G, 'REUtil'),
            GameUI = rawget(_G, 'GameUI'), MgrGameUI = rawget(_G, 'MgrGameUI'),
            Players = rawget(_G, 'Players') }
        ctx.previousLocalShop = package.loaded['client.LocalShop']
        ctx.previousHandler = package.loaded['client.ScreenHandlers.ScreenShop']
        package.loaded['client.LocalShop'] = { Stand = { AnchorName = 'TGUnitShopShrimp', Level = 2 } }
        package.loaded['client.ScreenHandlers.ScreenShop'] = nil
        local world = {}
        function world:CreateUnit(kind, attrs)
            local node = { Kind = kind, OnClicked = signal() }
            for key, value in pairs(attrs) do node[key] = value end
            function node:Destroy()
                self.Destroyed = true
                for _, child in ipairs(ctx.created) do
                    if child.Parent == self then child:Destroy() end
                end
            end
            if node.Name then ctx.nodes[node.Name] = node end
            ctx.created[#ctx.created + 1] = node
            return node
        end
        ctx.localPlayer = { GetAttribute = function() return 77 end }
        _G.game = { GetService = function(_, name)
            if name == 'World' then return world end
            if name == 'Players' then return { LocalPlayer = ctx.localPlayer } end
        end }
        _G.Vector2 = { New = function(x, y) return { x = x, y = y } end }
        _G.Color = { New = function(...) return { ... } end }
        _G.GameUI = { GetEuiManager = function() return {
            GetDeviceResolution = function() return { x = 1920, y = 1080 } end } end }
        _G.REUtil = { GetRE = function(_, name)
            if not ctx.events[name] then
                ctx.events[name] = { OnClientEvent = signal(), FireServer = function(_, payload)
                    ctx.commands[#ctx.commands + 1] = payload end }
            end
            return ctx.events[name]
        end }
        ctx.handler = assert(loadfile('client/ScreenHandlers/ScreenShop.lua'))()
        for _, name in ipairs(ctx.handler.UINodes) do
            ctx.nodes[name] = { Visible = true, OnClicked = signal() }
        end
        ctx.handler.UINodeMap = ctx.nodes
        ctx.handler.RootNode = { Name = 'ScreenShop' }
        ctx.handler:Init()
        ctx.handler.IsOpen = true
    end)

    -- 全局与模块缓存逐例恢复；setUp 中途失败也照样清理。
    after_each(function()
        package.loaded['client.LocalShop'] = ctx.previousLocalShop
        package.loaded['client.ScreenHandlers.ScreenShop'] = ctx.previousHandler
        for _, key in ipairs({ 'game', 'Vector2', 'Color', 'REUtil', 'GameUI', 'MgrGameUI' }) do
            _G[key] = ctx.previous[key]
        end
    end)

    -- 购买一律发编号（升级行无 itemKey）；点击行与上行一致
    it("test_buy_sends_number_not_item_key", function()
        ctx.handler:Buy(1) -- 钓具页第 1 行 = 香肠(11)
        assert.same({ { action = 'Buy', number = 11, seq = 1 } }, ctx.commands)
        ctx.handler:SetPage('升级')
        ctx.handler:Buy(2) -- 2 级摊位升级页第 2 行 = 弹容量升级1(41)，逐级可买
        assert.same(41, ctx.commands[2].number)
        assert.is_nil(ctx.commands[2].itemId)
    end)

    -- 金币页：无商品行；平台不可用时提示、停留本屏（页签可返回）、不发购买请求（不伪成功）
    it("test_coin_page_degrades_without_platform", function()
        ctx.handler:SetPage('金币')
        assert.same({}, numbersOf(ctx.handler.VisibleRows))
        assert.is_true(ctx.nodes.LabelCoinPageHint.Visible)
        assert.is_true(ctx.nodes.BtnOpenPlatformShop.Visible)
        _G.PlatformShop = nil
        ctx.nodes.BtnOpenPlatformShop.OnClicked:Fire()
        assert.matches('平台商店暂不可用', ctx.nodes.LabelCoinPageHint.Text, nil, true)
        assert.is_true(ctx.handler.IsOpen) -- 未关闭，可返回
        ctx.handler:SetPage('钓具')
        assert.same({ 11, 12, 1, 2, 3, 4, 5, 6 }, numbersOf(ctx.handler.VisibleRows))
        assert.same({}, ctx.commands) -- 全程未发购买请求
    end)

    -- 平台入口抛错同样不伪成功
    it("test_coin_page_platform_error_not_faked", function()
        _G.PlatformShop = { Open = function() error('平台未接入') end }
        ctx.handler:SetPage('金币')
        ctx.nodes.BtnOpenPlatformShop.OnClicked:Fire()
        assert.matches('打开失败', ctx.nodes.LabelCoinPageHint.Text, nil, true)
        assert.is_true(ctx.handler.IsOpen)
        _G.PlatformShop = nil
    end)

    -- 页内翻页：7 级摊位升级页 24 行 > 8 行/页
    it("test_in_page_paging_for_upgrade_page", function()
        package.loaded['client.LocalShop'].Stand = { AnchorName = 'TGUnitShop7', Level = 7 }
        ctx.handler:SetPage('升级')
        local function nums()
            local out = {}
            for i, row in ipairs(ctx.handler.VisibleRows) do out[i] = row and row.goods.Number end
            return out
        end
        -- 7 级新品：远程5(34)/爆炸3(42)/近战7(45) 置顶（弹容3 是 6 级新品，不在 7 级组），其后按编号
        assert.same({ 34, 42, 45, 28, 29, 30, 31, 32 }, nums())
        assert.is_false(ctx.nodes.BtnShopPrev.Visible)
        assert.is_true(ctx.nodes.BtnShopNext.Visible)
        ctx.handler:TurnPage(1)
        assert.same({ 33, 35, 36, 37, 38, 39, 40, 41 }, nums())
        assert.is_true(ctx.nodes.BtnShopPrev.Visible)
        ctx.handler:TurnPage(1)
        assert.same({ 43, 44, 46, 47, 48, 49, 50, 51 }, nums())
        assert.is_false(ctx.nodes.BtnShopNext.Visible)
        ctx.handler:TurnPage(-1) -- 可返回上一页
        assert.same(33, nums()[1])
    end)

    -- 2 级摊位钓具页：新品（香肠 11/钓虾竿 12）置顶，其后按编号；锁定行（等级不够）也列出但灰显
    it("test_page_rows_follow_list_for_page_order", function()
        assert.same({ 11, 12, 1, 2, 3, 4, 5, 6 }, numbersOf(ctx.handler.VisibleRows))
        assert.same('香肠', ctx.nodes.ShopItemName1.Text)
        assert.same('钓虾竿', ctx.nodes.ShopItemName2.Text)
        -- 第 3 行起是运行时补位行：科技假饵（1）需 7 级摊位 → 锁定灰显
        local extra3 = ctx.nodes.BtnShopBuyExtra3
        assert.is_true(extra3.Visible)
        assert.is_false(extra3.TouchEnabled)
        assert.matches('需 7 级摊位', ctx.nodes.LabelShopBuyExtra3.Text, nil, true)
    end)

    it("test_page_switch_renders_target_page", function()
        ctx.handler:SetPage('武器')
        -- 新品手枪(23)/斧头(24)/鞭炮(17) 置顶组按编号 17<23<24，其后按编号含锁定行
        assert.same({ 17, 23, 24, 15, 16, 18, 19, 20 }, numbersOf(ctx.handler.VisibleRows))
    end)

    -- 行状态：锁定行灰显且不可点；购买后已购且同号重购被客户端拦下
    it("test_row_states_locked_and_owned", function()
        ctx.handler:SetPage('升级')
        local function rowOf(number)
            for index, row in ipairs(ctx.handler.VisibleRows) do
                if row and row.goods.Number == number then return row.goods, index end
            end
            return nil
        end
        -- 2 级摊位升级页：第 3 页才有近战 1 级（51）
        ctx.handler:TurnPage(1)
        ctx.handler:TurnPage(1)
        local melee1 = rowOf(51)
        assert.is_not_nil(melee1)
        assert.same('buy', ctx.handler:RowState(melee1, 2))
        assert.same('locked', ctx.handler:RowState(rowOf(49), 2)) -- 近战 3 级需 3 级摊位
        ctx.handler:TurnPage(-2) -- 回第 1 页
        assert.same('locked', ctx.handler:RowState(rowOf(32), 2)) -- 背包 2 级越级（当前 0 级）
        -- 模拟服务端回包：近战 1 级购买成功 → 行转已购，近战 2 级（50）逐级解锁
        ctx.events.ShopResult.OnClientEvent:Fire({ ok = true, number = 51, kind = 'melee', level = 1, price = 50 })
        assert.same('owned', ctx.handler:RowState(melee1, 2))
        assert.same('buy', ctx.handler:RowState(rowOf(50), 2))
        -- 已购行点击不发请求
        ctx.commands = {}
        ctx.handler:TurnPage(2)
        local _, index = rowOf(51)
        ctx.handler:Buy(index)
        assert.same({}, ctx.commands)
    end)

    it("test_tabs_cover_four_pages", function()
        for _, page in ipairs({ '钓具', '武器', '升级', '金币' }) do
            assert.is_not_nil(ctx.nodes['BtnShopPage' .. page], '缺页签 ' .. page)
        end
    end)
end)

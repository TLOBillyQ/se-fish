-- #90 迁移：特殊道具客户端接缝（原 tests/gameplay/special_item_ui_test.lua，1 类 7 例）。
-- describe / it 名沿用旧类名与方法名；注册顺序 = 旧套件实际执行顺序（单类，方法按字典序）。
-- #140 T19 特殊道具：客户端接缝（ScreenMain 道具键语义随服务端生效效果切换）。
-- 失败方式（先列后写）：
--   1. 特殊效果生效时按钮语义不变（还显示「抛竿」/ 还可抛竿），或钓鱼阶段被特殊道具抢按钮；
--   2. 风神之翼：按下不发 fly holding=true、松开发不出 holding=false（升 / 降指令丢失）；
--   3. 哥斯拉：点击不发 breath；冷却中按钮仍可点或不显示剩余秒数；
--   4. SpecialItemResult 失败原因不提示玩家；
--   5. 效果清空后按钮不回到钓鱼语义（残留「长按飞行」/「原子吐息」）。
-- seam：RE SpecialItemState / SpecialItemResult 入站，SpecialItemAction 出站，
--       BtnItemAction 的 OnClicked / OnTouchBegan / OnTouchEnded。
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

describe('TestSpecialItemUI', function()
    local ctx
    local previous
    before_each(function()
        previous = { game = rawget(_G, 'game'), Vector2 = rawget(_G, 'Vector2'), Color = rawget(_G, 'Color'),
            REUtil = rawget(_G, 'REUtil'), GameUI = rawget(_G, 'GameUI'), MgrGameUI = rawget(_G, 'MgrGameUI'),
            notice = rawget(_G, 'LocalMsgNotice'),
            attack = package.loaded['client.LocalAttackButton'] }
        package.loaded['client.LocalAttackButton'] = nil
        _G.MgrGameUI = { SetCustomControlUI = function() end }
        ctx = { nodes = {}, created = {}, commands = {}, snapshotRequests = 0, events = {}, notices = {} }
        ctx.now = 100
        ctx.heartbeat = signal()
        local world = { Created = ctx.created, GetServerTime = function() return ctx.now end }
        function world:CreateUnit(kind, attrs)
            local node = { Kind = kind, OnClicked = signal(),
                OnTouchBegan = signal(), OnTouchEnded = signal() }
            for key, value in pairs(attrs) do node[key] = value end
            function node:Destroy()
                self.Destroyed = true
                for _, child in ipairs(world.Created) do
                    if child.Parent == self then child:Destroy() end
                end
            end
            ctx.nodes[node.Name] = node
            ctx.created[#ctx.created + 1] = node
            return node
        end
        _G.game = { GetService = function(_, name)
            if name == 'World' then return world end
            if name == 'RunService' then return { Heartbeat = ctx.heartbeat } end
            return {}
        end }
        _G.Vector2 = { New = function(x, y) return { x = x, y = y } end }
        _G.Color = { New = function(...) return { ... } end }
        _G.GameUI = { GetEuiManager = function() return {
            GetDeviceResolution = function() return { x = 1920, y = 1080 } end,
        } end, GetUIRoot = function() return ctx.uiRoot end }
        _G.LocalMsgNotice = function(text) ctx.notices[#ctx.notices + 1] = text end
        _G.REUtil = { GetRE = function(_, name)
            if not ctx.events[name] then
                ctx.events[name] = { OnClientEvent = signal(), FireServer = function(_, payload)
                    if name == 'SpecialItemStateRequest' then ctx.snapshotRequests = ctx.snapshotRequests + 1 end
                    if name == 'SpecialItemAction' or name == 'ItemBarAction' then
                        ctx.commands[#ctx.commands + 1] = payload
                    end
                end }
            end
            return ctx.events[name]
        end }
        ctx.handler = assert(loadfile('client/ScreenHandlers/ScreenMain.lua'))()
        ctx.handler.RootNode = {
            Name = 'ScreenMain',
            FindFirstChild = function(_, name) return ctx.nodes[name] end,
        }
        ctx.currentRoot = ctx.handler.RootNode
        ctx.uiRoot = { FindFirstChild = function(_, name)
            if name == 'ScreenMain' then return ctx.currentRoot end
        end }
        ctx.handler:Init()
        ctx.handler.IsOpen = true
    end)
    after_each(function()
        require('client.LocalAttackButton'):Destroy()
        package.loaded['client.LocalAttackButton'] = previous.attack
        _G.LocalMsgNotice = previous.notice
        for _, key in ipairs({ 'game', 'Vector2', 'Color', 'REUtil', 'GameUI', 'MgrGameUI' }) do
            _G[key] = previous[key]
        end
    end)

    local function pushState(state)
        ctx.events.SpecialItemState.OnClientEvent:Fire(state)
    end

    local function specialCommands()
        local result = {}
        for _, cmd in ipairs(ctx.commands) do
            if cmd.action == 'fly' or cmd.action == 'breath' then result[#result + 1] = cmd end
        end
        return result
    end

    -- 失败方式 5：效果清空（切换 / 丢弃 / 死亡）后按钮回到钓鱼语义
    it('test_cleared_effect_restores_fishing_button', function()
        pushState({ effect = 'wings', airborne = false, breathRemaining = 0 })
        assert.same('长按飞行', ctx.nodes.BtnItemActionLabel.Text)
        pushState({ effect = nil, airborne = false, breathRemaining = 0 })
        assert.is_not.same('长按飞行', ctx.nodes.BtnItemActionLabel.Text)
        -- 翅膀指令也不再发（语义已还原）
        ctx.nodes.ItemAction2.OnTouchBegan:Fire()
        assert.same(0, #specialCommands())
    end)

    it('test_cooldown_works_without_os_and_expires_on_server_time', function()
        local previousOs = rawget(_G, 'os')
        _G.os = nil
        -- 旧用例用 pcall 兜住「没有 os 也必须走服务端时间」这条路径，再在最外层 assert 还原失败原因；
        -- 关键是无论断言成不成，_G.os 都要放回原样，否则后续案例的 os 被摘走。保留这层 pcall。
        local ok, err = pcall(function()
            pushState({ effect = 'godzilla', breathRemaining = 20 })
            assert.is_false(ctx.nodes.ItemAction2.TouchEnabled)
            ctx.now = ctx.now + 21
            ctx.heartbeat:Fire()
            assert.same('原子吐息', ctx.nodes.BtnItemActionLabel.Text)
            assert.is_true(ctx.nodes.ItemAction2.TouchEnabled)
        end)
        _G.os = previousOs
        assert(ok, err)
    end)

    -- 失败方式 4：失败回包给玩家具体提示
    it('test_failure_result_notifies_with_hint', function()
        ctx.events.SpecialItemResult.OnClientEvent:Fire({ ok = false, action = 'breath', reason = 'cooldown' })
        assert.same({ '原子吐息冷却中' }, ctx.notices)
    end)

    -- 失败方式 1：钓鱼阶段（线已抛出）不被特殊道具抢按钮
    it('test_fishing_phase_keeps_reel_semantics_over_special_effect', function()
        ctx.handler.CastState = { phase = 'cast' }
        pushState({ effect = 'godzilla', airborne = false, breathRemaining = 0 })
        assert.same('收竿', ctx.nodes.BtnItemActionLabel.Text)
        ctx.nodes.ItemAction2.OnClicked:Fire()
        assert.same(0, #specialCommands(), '收线阶段不得发吐息')
    end)

    -- 失败方式 1/3：哥斯拉生效时按钮变「原子吐息」，点击发 breath；冷却中禁点并显示剩余秒数
    it('test_godzilla_button_casts_breath_then_locks_on_cooldown', function()
        pushState({ effect = 'godzilla', airborne = false, breathRemaining = 0 })
        assert.same('原子吐息', ctx.nodes.BtnItemActionLabel.Text)
        assert.is_true(ctx.nodes.ItemAction2.TouchEnabled)
        ctx.nodes.ItemAction2.OnClicked:Fire()
        assert.same({ { action = 'breath' } }, specialCommands())
        -- 服务端回报冷却：按钮锁住、显示剩余秒数；点击不再发
        pushState({ effect = 'godzilla', airborne = false, breathRemaining = 20 })
        assert.is_false(ctx.nodes.ItemAction2.TouchEnabled)
        assert.matches('冷却', ctx.nodes.BtnItemActionLabel.Text, nil, true)
        ctx.nodes.ItemAction2.OnClicked:Fire()
        assert.same(1, #specialCommands())
    end)

    it('test_listeners_request_initial_special_snapshot', function()
        assert.same(1, ctx.snapshotRequests)
        pushState({ effect = 'godzilla', breathRemaining = 12 })
        assert.is_false(ctx.nodes.ItemAction2.TouchEnabled)
    end)

    -- 失败方式 1/2：风神之翼生效时按钮变「长按飞行」，按下 / 松开发出升 / 降指令
    it('test_wings_button_holds_flight', function()
        pushState({ effect = 'wings', airborne = false, breathRemaining = 0 })
        assert.same('长按飞行', ctx.nodes.BtnItemActionLabel.Text)
        assert.is_true(ctx.nodes.ItemAction2.Visible)
        assert.is_true(ctx.nodes.ItemAction2.TouchEnabled)
        ctx.nodes.ItemAction2.OnTouchBegan:Fire()
        ctx.nodes.ItemAction2.OnTouchEnded:Fire()
        assert.same({ { action = 'fly', holding = true }, { action = 'fly', holding = false } }, specialCommands())
    end)
end)

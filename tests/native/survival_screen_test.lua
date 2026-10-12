-- #89 迁移（原 tests/gameplay/survival_screen_test.lua，#131 生存状态蒙版）：
-- client/ScreenHandlers/ScreenSurvival.lua：只按服务端广播渲染，上行按钮带递增 seq；
-- 结果与呼救文本经 notice 展示，不做本地结算。
-- 接缝：loadfile 取全新 ScreenSurvival 实例；桩 _G.game（World:CreateUnit 收节点、GetServerTime 可控时钟、
--   RunService:Heartbeat）、_G.Vector2/_G.Color/_G.LocalMsgNotice、common.REUtil（OnClientEvent/FireServer）。
-- 旧 setUp/tearDown 是逐例的，映射为 before_each/after_each：被替换的全局（game / Vector2 / Color /
-- LocalMsgNotice）与模块缓存（common.REUtil）在 after_each 无条件恢复（原值即使为 nil 也写回，
-- 旧实现用 pairs 遍历会漏掉 nil 项），after_each 对未完成的 before_each 幂等。
-- describe/it 名沿用旧类名与方法名，案例顺序沿用旧 LuaUnit 的字典序执行序。
local GameCfg = require('common.GameCfg')

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

describe('TestScreenSurvival', function()
    local ctx

    before_each(function()
        ctx = {
            now = 1000,
            nodes = {},
            requests = {},
            events = {},
            notices = {},
            heartbeats = signal(),
            saved = {
                game = rawget(_G, 'game'),
                Vector2 = rawget(_G, 'Vector2'),
                Color = rawget(_G, 'Color'),
                LocalMsgNotice = rawget(_G, 'LocalMsgNotice'),
                reutil = package.loaded['common.REUtil'],
            },
        }
        local env = ctx
        _G.LocalMsgNotice = function(msg) env.notices[#env.notices + 1] = msg end
        _G.Vector2 = { New = function(x, y) return { x = x, y = y } end }
        _G.Color = { New = function(...) return { ... } end }
        local world = {
            CreateUnit = function(_, kind, props)
                local node = { Kind = kind, Visible = true, OnClicked = signal() }
                for key, value in pairs(props) do node[key] = value end
                env.nodes[node.Name] = node
                return node
            end,
            GetServerTime = function() return env.now or 1000 end,
        }
        _G.game = { GetService = function(_, name)
            if name == 'World' then return world end
            if name == 'Players' then return { LocalPlayer = { PlayerGui = { EuiManager = {
                GetRootNode = function() return {} end,
                GetDeviceResolution = function() return { x = 1920, y = 1080 } end,
            } } } } end
            if name == 'RunService' then return { Heartbeat = env.heartbeats } end
        end }
        package.loaded['common.REUtil'] = { GetRE = function(_, name)
            if not env.events[name] then env.events[name] = {
                OnClientEvent = signal(),
                FireServer = function(_, payload)
                    env.requests[#env.requests + 1] = payload
                end,
            } end
            return env.events[name]
        end }
        ctx.panel = assert(loadfile('client/ScreenHandlers/ScreenSurvival.lua'))()
        ctx.panel:Start()
    end)

    after_each(function()
        if not ctx then return end
        local saved = ctx.saved
        if saved then
            package.loaded['common.REUtil'] = saved.reutil
            _G.game = saved.game
            _G.Vector2 = saved.Vector2
            _G.Color = saved.Color
            _G.LocalMsgNotice = saved.LocalMsgNotice
        end
    end)

    -- 接线断言：client/main.lua 里注册并启动本屏
    it('test_client_main_starts_the_screen', function()
        local f = assert(io.open('client/main.lua', 'r'))
        local src = f:read('*a')
        f:close()
        assert.matches('ScreenSurvival = require("client.ScreenHandlers.ScreenSurvival")', src, nil, true)
        assert.matches('ScreenSurvival:Start()', src, nil, true)
    end)

    -- 同一组节点随相位复用：濒死 → 死亡 → 活动（虚弱）
    it('test_dead_and_revive_update_the_same_nodes', function()
        ctx.events.SurvivalState.OnClientEvent:Fire({ phase = 'downed', endsAt = 1015 })
        ctx.events.SurvivalState.OnClientEvent:Fire({ phase = 'dead', endsAt = 1040 })
        assert.matches(GameCfg.Survival.DeadTitle, ctx.nodes['SurvivalTitle'].Text, nil, true)
        assert.is_false(ctx.nodes['SurvivalAdrenaline'].Visible) -- 死亡倒计时里没有自救
        ctx.now = 1030
        ctx.heartbeats:Fire(0.1)
        assert.matches('10 秒', ctx.nodes['SurvivalTitle'].Text, nil, true)
        ctx.events.SurvivalState.OnClientEvent:Fire({ phase = 'alive', weakUntil = 1100 })
        assert.is_false(ctx.nodes['SurvivalBanner'].Visible)
        assert.is_true(ctx.nodes['SurvivalWeak'].Visible)
        assert.matches(GameCfg.Survival.WeakText, ctx.nodes['SurvivalWeak'].Text, nil, true)
        ctx.now = 1100
        ctx.heartbeats:Fire(0.1)
        assert.is_false(ctx.nodes['SurvivalWeak'].Visible)
    end)

    -- #147 平台满血复活：死亡相位才显示广告 / 5 金豆两枚按钮，上行带 mode；
    -- platformPending 期间隐藏按钮并显示等待文案（倒计时已被服务端冻结）
    it('test_dead_phase_offers_platform_revive_buttons', function()
        local cfg = GameCfg.Survival
        ctx.events.SurvivalState.OnClientEvent:Fire({ phase = 'downed', endsAt = 1015 })
        assert.is_false(ctx.nodes['SurvivalAdRevive'].Visible) -- 濒死没有平台复活
        ctx.events.SurvivalState.OnClientEvent:Fire({ phase = 'dead', endsAt = 1040 })
        assert.is_true(ctx.nodes['SurvivalAdRevive'].Visible)
        assert.is_true(ctx.nodes['SurvivalPaidRevive'].Visible)
        assert.same(cfg.PaidReviveText, ctx.nodes['SurvivalPaidReviveText'].Text)
        ctx.nodes['SurvivalAdRevive'].OnClicked:Fire()
        assert.same({ action = 'FullRevive', mode = 'ad', seq = 1 }, ctx.requests[1])
        ctx.nodes['SurvivalPaidRevive'].OnClicked:Fire()
        assert.same({ action = 'FullRevive', mode = 'goods', seq = 2 }, ctx.requests[2])
        ctx.events.SurvivalState.OnClientEvent:Fire({ phase = 'dead', endsAt = 1040, platformPending = 'ad' })
        assert.is_false(ctx.nodes['SurvivalAdRevive'].Visible)
        assert.same(cfg.PlatformWaitText, ctx.nodes['SurvivalTitle'].Text)
        ctx.events.SurvivalState.OnClientEvent:Fire({ phase = 'dead', endsAt = 1047 }) -- 取消后平移
        assert.is_true(ctx.nodes['SurvivalAdRevive'].Visible)
        assert.matches('47 秒', ctx.nodes['SurvivalTitle'].Text, nil, true)
        ctx.events.SurvivalState.OnClientEvent:Fire({ phase = 'alive' })
        assert.is_false(ctx.nodes['SurvivalPaidRevive'].Visible)
    end)

    -- 濒死横幅 + 肾上腺素按钮：倒计时按心跳刷新，上行 seq 递增
    it('test_downed_shows_banner_and_adrenaline_button', function()
        ctx.events.SurvivalState.OnClientEvent:Fire({ phase = 'downed', endsAt = 1015 })
        assert.is_true(ctx.nodes['SurvivalBanner'].Visible)
        assert.matches(GameCfg.Survival.DownedTitle, ctx.nodes['SurvivalTitle'].Text, nil, true)
        assert.is_true(ctx.nodes['SurvivalAdrenaline'].Visible)
        ctx.now = 1010
        ctx.heartbeats:Fire(0.1)
        assert.matches('5 秒', ctx.nodes['SurvivalTitle'].Text, nil, true)
        -- 按钮上行：动作 + 递增 seq
        ctx.nodes['SurvivalAdrenaline'].OnClicked:Fire()
        assert.same({ action = 'UseAdrenaline', seq = 1 }, ctx.requests[1])
        ctx.nodes['SurvivalAdrenaline'].OnClicked:Fire()
        assert.same(2, ctx.requests[2].seq)
    end)

    -- 失败结果走 notice：虚弱中不误弹提示，各原因各有文案
    it('test_failure_results_notice_and_weak_without_hint', function()
        ctx.events.SurvivalState.OnClientEvent:Fire({ phase = 'alive', weakUntil = 1100 })
        assert.same(0, #ctx.notices)
        ctx.events.SurvivalResult.OnClientEvent:Fire({ seq = 1, ok = false, reason = 'no-adrenaline' })
        assert.same(GameCfg.Survival.NoAdrenalineText, ctx.notices[#ctx.notices])
        ctx.events.SurvivalResult.OnClientEvent:Fire({ seq = 2, ok = false, reason = 'busy' })
        assert.same(GameCfg.Survival.AdrenalineText, ctx.notices[#ctx.notices])
    end)

    -- 平台复活失败有可读提示；安静结局（not-dead / 成功）不刷提示
    it('test_platform_revive_failures_have_readable_notices', function()
        local cfg = GameCfg.Survival
        ctx.events.SurvivalResult.OnClientEvent:Fire({ action = 'FullRevive', ok = false, reason = 'unavailable' })
        assert.same(cfg.PlatformPendingText, ctx.notices[#ctx.notices])
        ctx.events.SurvivalResult.OnClientEvent:Fire({ action = 'FullRevive', ok = false, reason = 'timeout' })
        assert.same(cfg.PlatformResumeText, ctx.notices[#ctx.notices])
        local count = #ctx.notices
        ctx.events.SurvivalResult.OnClientEvent:Fire({ action = 'FullRevive', ok = false, reason = 'not-dead' })
        ctx.events.SurvivalResult.OnClientEvent:Fire({ action = 'FullRevive', ok = true, mode = 'ad' })
        assert.same(count, #ctx.notices) -- 安静结局不刷提示
    end)
end)

-- #131 生存状态蒙版（client/ScreenHandlers/ScreenSurvival.lua）：只按服务端广播渲染，
-- 上行按钮带递增 seq；结果与呼救文本经 notice 展示，不做本地结算。
local lu = require('luaunit')

TestScreenSurvival = {}

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

function TestScreenSurvival:setUp()
    self.previous = { game = _G.game, Vector2 = _G.Vector2, Color = _G.Color,
        LocalMsgNotice = _G.LocalMsgNotice }
    self.modules = { ['common.REUtil'] = package.loaded['common.REUtil'] }
    self.nodes, self.requests, self.events, self.notices = {}, {}, {}, {}
    _G.LocalMsgNotice = function(msg) self.notices[#self.notices + 1] = msg end
    _G.Vector2 = { New = function(x, y) return { x = x, y = y } end }
    _G.Color = { New = function(...) return { ... } end }
    local env = self
    self.heartbeats = signal()
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
    self.now = 1000
    self.panel = assert(loadfile('client/ScreenHandlers/ScreenSurvival.lua'))()
    self.panel:Start()
end

function TestScreenSurvival:tearDown()
    for _, name in ipairs({ 'common.REUtil' }) do package.loaded[name] = self.modules[name] end
    for key, value in pairs(self.previous) do _G[key] = value end
end

function TestScreenSurvival:test_downed_shows_banner_and_adrenaline_button()
    self.events.SurvivalState.OnClientEvent:Fire({ phase = 'downed', endsAt = 1015 })
    lu.assertTrue(self.nodes['SurvivalBanner'].Visible)
    lu.assertStrContains(self.nodes['SurvivalTitle'].Text, require('common.GameCfg').Survival.DownedTitle)
    lu.assertTrue(self.nodes['SurvivalAdrenaline'].Visible)
    self.now = 1010
    self.heartbeats:Fire(0.1)
    lu.assertStrContains(self.nodes['SurvivalTitle'].Text, '5 秒')
    -- 按钮上行：动作 + 递增 seq
    self.nodes['SurvivalAdrenaline'].OnClicked:Fire()
    lu.assertEquals(self.requests[1], { action = 'UseAdrenaline', seq = 1 })
    self.nodes['SurvivalAdrenaline'].OnClicked:Fire()
    lu.assertEquals(self.requests[2].seq, 2)
end

function TestScreenSurvival:test_dead_and_revive_update_the_same_nodes()
    self.events.SurvivalState.OnClientEvent:Fire({ phase = 'downed', endsAt = 1015 })
    self.events.SurvivalState.OnClientEvent:Fire({ phase = 'dead', endsAt = 1040 })
    lu.assertStrContains(self.nodes['SurvivalTitle'].Text, require('common.GameCfg').Survival.DeadTitle)
    lu.assertFalse(self.nodes['SurvivalAdrenaline'].Visible) -- 死亡倒计时里没有自救
    self.now = 1030
    self.heartbeats:Fire(0.1)
    lu.assertStrContains(self.nodes['SurvivalTitle'].Text, '10 秒')
    self.events.SurvivalState.OnClientEvent:Fire({ phase = 'alive', weakUntil = 1100 })
    lu.assertFalse(self.nodes['SurvivalBanner'].Visible)
    lu.assertTrue(self.nodes['SurvivalWeak'].Visible)
    lu.assertStrContains(self.nodes['SurvivalWeak'].Text, require('common.GameCfg').Survival.WeakText)
    self.now = 1100
    self.heartbeats:Fire(0.1)
    lu.assertFalse(self.nodes['SurvivalWeak'].Visible)
end

function TestScreenSurvival:test_failure_results_notice_and_weak_without_hint()
    self.events.SurvivalState.OnClientEvent:Fire({ phase = 'alive', weakUntil = 1100 })
    lu.assertEquals(#self.notices, 0)
    self.events.SurvivalResult.OnClientEvent:Fire({ seq = 1, ok = false, reason = 'no-adrenaline' })
    lu.assertEquals(self.notices[#self.notices], require('common.GameCfg').Survival.NoAdrenalineText)
    self.events.SurvivalResult.OnClientEvent:Fire({ seq = 2, ok = false, reason = 'busy' })
    lu.assertEquals(self.notices[#self.notices], require('common.GameCfg').Survival.AdrenalineText)
end

function TestScreenSurvival:test_client_main_starts_the_screen()
    local f = assert(io.open('client/main.lua', 'r'))
    local src = f:read('*a')
    f:close()
    lu.assertStrContains(src, 'ScreenSurvival = require("client.ScreenHandlers.ScreenSurvival")')
    lu.assertStrContains(src, 'ScreenSurvival:Start()')
end

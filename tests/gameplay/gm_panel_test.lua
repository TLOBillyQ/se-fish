-- 运行时 GM 面板：分页选鱼、服务端反馈与重建清理。
local lu = require('luaunit')
local cfg = require('common.GameCfg')

TestGMPanel = {}

local function signal()
    local listeners = {}
    return {
        Connect = function(_, fn)
            listeners[#listeners + 1] = fn
            return { Disconnect = function()
                for index, callback in ipairs(listeners) do
                    if callback == fn then table.remove(listeners, index) break end
                end
            end }
        end,
        Fire = function(_, ...) for _, fn in ipairs(listeners) do fn(...) end end,
        Count = function() return #listeners end,
    }
end

function TestGMPanel:setUp()
    self.previous = { game = _G.game, Vector2 = _G.Vector2, Color = _G.Color }
    self.modules = {}
    for _, name in ipairs({ 'client.GameUI', 'common.REUtil' }) do
        self.modules[name] = package.loaded[name]
    end
    self.savedDebug = cfg.Debug
    cfg.Debug = { Enabled = true, InitialGrants = self.savedDebug.InitialGrants }
    local env = self
    self.nodes, self.requests, self.events = {}, {}, {}
    self.root = {}
    local world = { CreateUnit = function(_, kind, props)
        local node = { Kind = kind, OnClicked = signal(), Destroy = function() end }
        for key, value in pairs(props) do node[key] = value end
        env.nodes[node.Name] = node
        return node
    end }
    _G.game = { GetService = function(_, name)
        if name == 'World' then return world end
        if name == 'Players' then return { LocalPlayer = { UserId = 1 } } end
    end }
    _G.Vector2 = { New = function(x, y) return { x = x, y = y } end }
    _G.Color = { New = function(...) return { ... } end }
    package.loaded['client.GameUI'] = { GetEuiManager = function() return {
        GetRootNode = function() return env.root end,
        GetDeviceResolution = function() return { x = 1920, y = 1080 } end,
    } end }
    package.loaded['common.REUtil'] = { GetRE = function(_, name)
        if not env.events[name] then env.events[name] = {
            OnClientEvent = signal(),
            FireServer = function(_, payload)
                if name == 'GMAction' then env.requests[#env.requests + 1] = payload end
            end,
        } end
        return env.events[name]
    end }
    self.panel = assert(loadfile('client/ScreenHandlers/ScreenGM.lua'))()
    self.panel:Start()
end

function TestGMPanel:tearDown()
    self.panel:Destroy()
    cfg.Debug = self.savedDebug
    -- package.loaded 的 nil 项不会参与表遍历，逐项恢复。
    for _, name in ipairs({ 'client.GameUI', 'common.REUtil' }) do
        package.loaded[name] = self.modules[name]
    end
    for key, value in pairs(self.previous) do _G[key] = value end
    for _, name in ipairs({ 'game', 'Vector2', 'Color' }) do _G[name] = self.previous[name] end
end

function TestGMPanel:test_fish_page_selects_id_and_displays_server_result()
    lu.assertTrue(self.panel.Started)
    self.nodes['GM入口'].OnClicked:Fire()
    lu.assertTrue(self.panel.IsOpen)
    lu.assertEquals(self.nodes['GM操作文字_下一条鱼1'].Text, cfg.Fish.eel.Name)
    self.nodes['GM操作_下一条鱼1'].OnClicked:Fire()
    lu.assertEquals(self.requests[#self.requests], { action = 'NextFish', fishId = 'eel' })
    self.events.GMResult.OnClientEvent:Fire({ action = 'NextFish', ok = true, target = 1 })
    lu.assertStrContains(self.panel.Feedback.Text, '已设置')
    self.nodes['GM操作_下一条鱼8'].OnClicked:Fire()
    lu.assertEquals(self.panel.FishPage, 2)
    local label = self.nodes['GM操作文字_下一条鱼1'].Text
    local fishId
    for id, fish in pairs(cfg.Fish) do
        if fish.Name == label then fishId = id break end
    end
    lu.assertNotNil(fishId)
    self.nodes['GM操作_下一条鱼1'].OnClicked:Fire()
    lu.assertEquals(self.requests[#self.requests].fishId, fishId)
    self.nodes['GM操作_下一条鱼7'].OnClicked:Fire()
    lu.assertEquals(self.panel.FishPage, 1)
    self.events.GMResult.OnClientEvent:Fire({ action = 'NextFish', ok = false, reason = '调试开关已关闭' })
    lu.assertStrContains(self.panel.Feedback.Text, '调试开关已关闭')
end

function TestGMPanel:test_page_bounds_and_existing_buttons()
    self.nodes['GM操作_下一条鱼7'].OnClicked:Fire()
    lu.assertEquals(self.panel.FishPage, 1)
    for _ = 1, 20 do self.nodes['GM操作_下一条鱼8'].OnClicked:Fire() end
    lu.assertEquals(self.panel.FishPage, math.ceil((function()
        local count = 0
        for _ in pairs(cfg.Fish) do count = count + 1 end
        return count
    end)() / 6))
    self.nodes['GM入口'].OnClicked:Fire()
    local lastPageSlots = (function()
        local count = 0
        for _ in pairs(cfg.Fish) do count = count + 1 end
        return (count - 1) % 6 + 1
    end)()
    for index = 1, 6 do
        lu.assertEquals(self.nodes['GM操作_下一条鱼' .. index].Visible, index <= lastPageSlots)
        lu.assertEquals(self.nodes['GM操作文字_下一条鱼' .. index].Visible, index <= lastPageSlots)
    end
    self.nodes['GM入口'].OnClicked:Fire()
    self.nodes['GM入口'].OnClicked:Fire()
    for index = lastPageSlots + 1, 6 do
        lu.assertFalse(self.nodes['GM操作_下一条鱼' .. index].Visible)
    end
    self.nodes['GM操作_下一条鱼7'].OnClicked:Fire()
    for index = 1, 6 do
        lu.assertTrue(self.nodes['GM操作_下一条鱼' .. index].Visible)
        lu.assertTrue(self.nodes['GM操作文字_下一条鱼' .. index].Visible)
    end
    self.nodes['GM操作_金币1'].OnClicked:Fire()
    lu.assertEquals(self.requests[#self.requests], { action = 'Coin', amount = 100 })
end

function TestGMPanel:test_state_page_acknowledges_refresh_and_apply()
    self.nodes['GM入口'].OnClicked:Fire()
    self.nodes['GM操作_状态与存档1'].OnClicked:Fire()
    lu.assertEquals(self.requests[#self.requests], { action = 'GetState' })
    lu.assertEquals(self.panel.Feedback.Text, '等待服务端确认…')
    self.events.GMResult.OnClientEvent:Fire({ action = 'GetState', ok = true,
        status = { currentSlot = '', nextSlot = '', autosavePaused = false } })
    lu.assertStrContains(self.panel.Feedback.Text, '状态已同步')
    self.panel.Fields.coin.Text = '0'
    self.nodes['GM应用'].OnClicked:Fire()
    lu.assertEquals(self.requests[#self.requests], { action = 'ApplyState', coin = 0 })
    self.events.GMResult.OnClientEvent:Fire({ action = 'ApplyState', ok = true,
        status = { currentSlot = '', nextSlot = '', autosavePaused = true } })
    lu.assertStrContains(self.panel.Feedback.Text, '已应用到本局')
end

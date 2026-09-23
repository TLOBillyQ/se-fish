local lu = require('luaunit')

TestItemBarUI = {}

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
        Count = function() return #listeners end,
    }
end

function TestItemBarUI:setUp()
    self.previous = { game = _G.game, Vector2 = _G.Vector2, Color = _G.Color,
        REUtil = _G.REUtil, GameUI = _G.GameUI }
    self.nodes = {}
    self.created = {}
    local testCase = self
    local world = { Created = self.created }
    function world:CreateUnit(kind, attrs)
        local node = { Kind = kind, OnClicked = signal() }
        for key, value in pairs(attrs) do node[key] = value end
        function node:Destroy()
            self.Destroyed = true
            for _, child in ipairs(world.Created) do
                if child.Parent == self then child:Destroy() end
            end
        end
        testCase.nodes[node.Name] = node
        testCase.created[#testCase.created + 1] = node
        return node
    end
    _G.game = { GetService = function(_, name) if name == 'World' then return world end end }
    _G.Vector2 = { New = function(x, y) return { x = x, y = y } end }
    _G.Color = { New = function(...) return { ... } end }
    _G.GameUI = { GetEuiManager = function() return {
        GetDeviceResolution = function() return { x = 1920, y = 1080 } end,
    } end, GetUIRoot = function() return self.uiRoot end }
    self.commands = {}
    self.events = {}
    _G.REUtil = { GetRE = function(_, name)
        if not self.events[name] then
            self.events[name] = { OnClientEvent = signal(), FireServer = function(_, payload)
                if name == 'ItemBarAction' then self.commands[#self.commands + 1] = payload end
            end }
        end
        return self.events[name]
    end }
    self.states = _G.REUtil:GetRE('ItemBarState').OnClientEvent
    self.handler = assert(loadfile('client/ScreenHandlers/ScreenMain.lua'))()
    self.handler.RootNode = {
        Name = 'ScreenMain',
        FindFirstChild = function(_, name) return self.nodes[name] end,
    }
    self.nodes.BtnFishEnter = { Visible = true }
    self.currentRoot = self.handler.RootNode
    self.uiRoot = { FindFirstChild = function(_, name)
        if name == 'ScreenMain' then return self.currentRoot end
    end }
    self.handler:Init()
end

function TestItemBarUI:tearDown()
    for _, key in ipairs({ 'game', 'Vector2', 'Color', 'REUtil', 'GameUI' }) do
        _G[key] = self.previous[key]
    end
end

function TestItemBarUI:test_fixed_slots_bait_and_action_placement()
    for index = 1, 8 do lu.assertNotNil(self.nodes['ItemBarSlot' .. index]) end
    lu.assertNil(self.nodes.ItemBarSlot9)
    lu.assertEquals(self.nodes.ItemBarIcon1.Position, { x = 55, y = 70 })
    lu.assertEquals(self.nodes.ItemBarLabel1.Position, { x = 55, y = 20 })
    lu.assertEquals(self.nodes.ItemBarAmount1.Position, { x = 92, y = 92 })
    lu.assertEquals(self.nodes.ItemBarSlot1.NormalImage, 'official://image/11017')
    lu.assertEquals(self.nodes.BaitWorm.NormalImage, 'official://image/11017')
    lu.assertTrue(self.nodes.BaitWorm.ButtonTextFontSize >= 28)
    lu.assertIs(self.nodes.ItemBarIcon1.Parent, self.nodes.ItemBarSlot1)
    lu.assertNotNil(self.nodes.BaitWorm)
    lu.assertNotNil(self.nodes.BaitNone)
    lu.assertNotNil(self.nodes.ItemDiscard)
    lu.assertFalse(self.nodes.ItemAction2.TouchEnabled)
    lu.assertNil(self.nodes.BtnAttack)
    lu.assertFalse(self.nodes.BtnFishEnter.Visible)
    self.states:Fire({ slots = { [1] = { itemId = 'starterRod', count = 1 } },
        bait = { worm = 10 }, selectedSlot = 1 })
    lu.assertEquals(self.nodes.ItemAction2.ButtonText, '抛竿')
    lu.assertTrue(self.nodes.ItemAction2.Visible)
    self.states:Fire({ slots = {}, bait = { worm = 10 }, selectedBait = 'worm' })
    lu.assertEquals(self.nodes.BaitNone.ButtonText, '不挂鱼饵')
    self.nodes.ItemBarSlot1.OnClicked:Fire()
    lu.assertEquals(self.commands[1].action, 'SelectSlot')
    lu.assertEquals(self.commands[1].value, 1)
    self.nodes.BaitWorm.OnClicked:Fire()
    lu.assertEquals(self.commands[2].value, 'worm')
    self.nodes.BaitNone.OnClicked:Fire()
    lu.assertEquals(self.commands[3].action, 'SelectBait')
    lu.assertNil(self.commands[3].value)
end

function TestItemBarUI:test_legacy_entry_is_not_registered()
    local clientFile = assert(io.open('client/main.lua', 'r'))
    local client = clientFile:read('*a')
    clientFile:close()
    local serverFile = assert(io.open('server/main.lua', 'r'))
    local server = serverFile:read('*a')
    serverFile:close()
    lu.assertNil(client:find('LocalFishEnter:Start()', 1, true))
    lu.assertNil(server:find('MgrFish = require', 1, true))
    lu.assertStrContains(client, "OpenScreen('ScreenMain')")
    local agentsFile = assert(io.open('AGENTS.md', 'r'))
    local agents = agentsFile:read('*a')
    agentsFile:close()
    lu.assertStrContains(agents, '旧钓鱼入口 `LocalFishEnter` 已退役、不再启动')
    lu.assertNil(agents:find('`LocalFishEnter` / `LocalAttackButton`', 1, true))
end

function TestItemBarUI:test_empty_and_depleted_state_refresh()
    self.states:Fire({ slots = {}, bait = { worm = 0 } })
    lu.assertFalse(self.nodes.ItemAction2.Visible)
    lu.assertFalse(self.nodes.BaitWorm.TouchEnabled)
    lu.assertFalse(self.nodes.BaitEat.TouchEnabled)
    lu.assertEquals(self.nodes.BaitEat.ButtonText, '蚯蚓用尽')
    lu.assertEquals(self.nodes.BaitNone.ButtonText, '不挂鱼饵')
    self.nodes.BaitNone.OnClicked:Fire()
    lu.assertEquals(self.commands[1].action, 'SelectBait')
    lu.assertNil(self.commands[1].value)
    self.nodes.ItemBarSlot8.OnClicked:Fire()
    lu.assertEquals(self.commands[2].value, 8)
end

function TestItemBarUI:test_reentry_cleans_old_root_and_listeners()
    local originals = {
        ['common.Util'] = package.loaded['common.Util'],
        ['common.REUtil'] = package.loaded['common.REUtil'],
        ['client.GameUI'] = package.loaded['client.GameUI'],
        ['client.ScreenHandlers.ScreenMain'] = package.loaded['client.ScreenHandlers.ScreenMain'],
    }
    package.loaded['common.Util'] = {}
    package.loaded['common.REUtil'] = _G.REUtil
    package.loaded['client.GameUI'] = _G.GameUI
    package.loaded['client.ScreenHandlers.ScreenMain'] = self.handler
    local ok, err = pcall(function()
        local mgr = assert(loadfile('client/MgrGameUI.lua'))()
        local oldRoot, oldButton = self.currentRoot, self.nodes.ItemBarSlot1
        lu.assertIs(mgr:GetScreen('ScreenMain').RootNode, oldRoot)
        lu.assertIs(mgr:GetScreen('ScreenMain').RootNode, oldRoot)
        lu.assertEquals(self.states:Count(), 1)
        lu.assertEquals(oldButton.OnClicked:Count(), 1)
        self.currentRoot = { Name = 'ScreenMain', Visible = true,
            FindFirstChild = function() return nil end }
        mgr:GetScreen('ScreenMain')
        lu.assertTrue(oldButton.Destroyed)
        lu.assertEquals(oldButton.OnClicked:Count(), 0)
        lu.assertEquals(self.states:Count(), 1)
        local newButton = self.nodes.ItemBarSlot1
        lu.assertNotIs(newButton, oldButton)
        oldButton.OnClicked:Fire()
        lu.assertEquals(#self.commands, 0)
        newButton.OnClicked:Fire()
        lu.assertEquals(#self.commands, 1)
        self.handler:Cleanup()
        lu.assertEquals(self.states:Count(), 0)
        lu.assertTrue(newButton.Destroyed)
        self.handler:Destroy()
    end)
    for _, key in ipairs({ 'common.Util', 'common.REUtil', 'client.GameUI',
        'client.ScreenHandlers.ScreenMain' }) do
        package.loaded[key] = originals[key]
    end
    lu.assertTrue(ok, tostring(err))
end

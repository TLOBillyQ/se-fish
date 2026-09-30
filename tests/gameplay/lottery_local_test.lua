-- #138 T17 抽奖机入口（client/LocalLottery）失败方式先列：
--   1. 锚点缺失（编辑器还没摆 Z*_Lottery）直接报错中断，而不是只记日志；
--   2. 距离判定错轴（把 y 算进去）或错半径，气泡该显不显；
--   3. 点击气泡不开屏或开错屏；离开所有抽奖机范围不关窗；
--   4. 每次 Update 都重写 Visible（应只在状态变化时写，避免每帧刷节点）。
-- seam：直接调 LocalLottery 的 Start / Update / CreateBubble，替换 game / REUtil / Util /
--   GameUI / MgrGameUI 边界；锚点用假单位，距离用假 LocalPlayer.Character.Position。
local lu = require('luaunit')
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

TestLocalLottery = {}

function TestLocalLottery:setUp()
    self.previous = {}
    for _, key in ipairs({ 'game', 'Vector2', 'Vector3', 'Color', 'REUtil', 'GameUI', 'MgrGameUI' }) do
        self.previous[key] = rawget(_G, key)
    end
    self.previousUtil = package.loaded['common.Util']
    self.previousModule = package.loaded['client.LocalLottery']

    self.anchors = {}
    package.loaded['common.Util'] = {
        WaitForChild = function(_, _, name) return self.anchors[name] end,
    }

    self.nodes, self.prints = {}, {}
    local env = self
    local world = {}
    function world:CreateUnit(kind, attrs)
        local node = { Kind = kind, OnClicked = signal(), Visible = true }
        for key, value in pairs(attrs) do node[key] = value end
        if node.Name then env.nodes[node.Name] = node end
        return node
    end
    self.heartbeat = signal()
    self.character = { Position = { x = 0, y = 0, z = 0 } }
    _G.game = { GetService = function(_, name)
        if name == 'World' then return world end
        if name == 'Players' then return { LocalPlayer = { Character = env.character } } end
        if name == 'RunService' then return { Heartbeat = env.heartbeat } end
        if name == 'Task' then return { Spawn = function(_, fn) fn() end, Wait = function() end } end
    end }
    _G.Vector2 = { New = function(x, y) return { x = x, y = y } end }
    _G.Vector3 = { New = function(x, y, z) return { x = x, y = y, z = z } end }
    _G.Color = { New = function(...) return { ... } end }
    _G.REUtil = { GetRE = function(_, name)
        return { OnClientEvent = signal(), FireServer = function() end }
    end }
    _G.GameUI = {
        CreateSceneNode = function(_, _, anchor)
            return { Name = 'BubbleNode', Visible = true, Anchor = anchor,
                FindFirstChild = function() return nil end }
        end,
        GetEuiManager = function() return {} end,
    }
    self.screens = { open = {}, closed = {}, isOpen = {} }
    _G.MgrGameUI = {
        OpenScreen = function(_, name) env.screens.open[#env.screens.open + 1] = name
            env.screens.isOpen[name] = true end,
        CloseScreen = function(_, name) env.screens.closed[#env.screens.closed + 1] = name
            env.screens.isOpen[name] = false end,
        IsScreenOpen = function(_, name) return env.screens.isOpen[name] == true end,
    }

    local oldPrint = _G.print
    self.oldPrint = oldPrint
    _G.print = function(...)
        local parts = {}
        for i = 1, select('#', ...) do parts[#parts + 1] = tostring(select(i, ...)) end
        env.prints[#env.prints + 1] = table.concat(parts, '\t')
    end

    self.localLottery = assert(loadfile('client/LocalLottery.lua'))()
end

function TestLocalLottery:tearDown()
    _G.print = self.oldPrint
    for key, value in pairs(self.previous) do _G[key] = value end
    package.loaded['common.Util'] = self.previousUtil
    package.loaded['client.LocalLottery'] = self.previousModule
end

function TestLocalLottery:anchor(name, x, z)
    self.anchors[name] = { Name = name, Position = { x = x, y = 5, z = z } }
    return self.anchors[name]
end

function TestLocalLottery:test_bubble_per_anchor_and_missing_anchor_only_logs()
    local names = GameCfg.Lottery.MachineAnchors()
    lu.assertTrue(#names >= 1)
    self:anchor(names[1], 0, 0) -- 只摆第一台，其余锚点缺失
    self.localLottery:Start()
    lu.assertEquals(#self.localLottery.Bubbles, 1)
    local logged = false
    for _, line in ipairs(self.prints) do
        if line:find('LocalLottery') then logged = true break end
    end
    lu.assertTrue(logged) -- 缺失锚点只记日志
end

function TestLocalLottery:test_bubble_shows_within_radius_and_hides_outside()
    local names = GameCfg.Lottery.MachineAnchors()
    self:anchor(names[1], 0, 0)
    self.localLottery:Start()
    local bubble = self.localLottery.Bubbles[1]
    local radius = GameCfg.Lottery.Radius
    self.character.Position.x = radius + 1
    self.localLottery:Update()
    lu.assertFalse(bubble.Node.Visible)
    self.character.Position.x = radius - 1
    self.localLottery:Update()
    lu.assertTrue(bubble.Node.Visible)
    -- y 不参与距离判定：抬高角色不影响显隐
    self.character.Position.y = 999
    self.localLottery:Update()
    lu.assertTrue(bubble.Node.Visible)
end

function TestLocalLottery:test_click_opens_screen_and_leaving_range_closes_it()
    local names = GameCfg.Lottery.MachineAnchors()
    self:anchor(names[1], 0, 0)
    self.localLottery:Start()
    self.localLottery:Update()
    lu.assertTrue(self.localLottery.Bubbles[1].Near)
    self.localLottery:Open()
    lu.assertEquals(self.screens.open, { 'ScreenLottery' })
    self.character.Position.x = 999
    self.localLottery:Update()
    lu.assertEquals(self.screens.closed, { 'ScreenLottery' })
end

function TestLocalLottery:test_update_does_not_touch_visibility_without_state_change()
    local names = GameCfg.Lottery.MachineAnchors()
    self:anchor(names[1], 0, 0)
    self.localLottery:Start()
    local bubble = self.localLottery.Bubbles[1]
    -- 状态未变化时重复 Update 幂等：Near 与 Visible 都保持
    self.character.Position.x = 1
    self.localLottery:Update()
    lu.assertTrue(bubble.Near)
    local visible = bubble.Node.Visible
    self.localLottery:Update()
    self.localLottery:Update()
    lu.assertTrue(bubble.Near)
    lu.assertEquals(bubble.Node.Visible, visible)
end

-- #140 T19 特殊道具：客户端接缝（ScreenMain 道具键语义随服务端生效效果切换）。
-- 失败方式（先列后写）：
--   1. 特殊效果生效时按钮语义不变（还显示「抛竿」/ 还可抛竿），或钓鱼阶段被特殊道具抢按钮；
--   2. 风神之翼：按下不发 fly holding=true、松开发不出 holding=false（升 / 降指令丢失）；
--   3. 哥斯拉：点击不发 breath；冷却中按钮仍可点或不显示剩余秒数；
--   4. SpecialItemResult 失败原因不提示玩家；
--   5. 效果清空后按钮不回到钓鱼语义（残留「长按飞行」/「原子吐息」）。
-- seam：RE SpecialItemState / SpecialItemResult 入站，SpecialItemAction 出站，
--       BtnItemAction 的 OnClicked / OnTouchBegan / OnTouchEnded。
local lu = require('luaunit')

TestSpecialItemUI = {}

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

function TestSpecialItemUI:setUp()
    self.previous = { game = _G.game, Vector2 = _G.Vector2, Color = _G.Color,
        REUtil = _G.REUtil, GameUI = _G.GameUI, MgrGameUI = _G.MgrGameUI }
    self.previousAttack = package.loaded['client.LocalAttackButton']
    package.loaded['client.LocalAttackButton'] = nil
    _G.MgrGameUI = { SetCustomControlUI = function() end }
    self.nodes = {}
    self.created = {}
    local testCase = self
    self.now = 100
    self.heartbeat = signal()
    local world = { Created = self.created, GetServerTime = function() return self.now end }
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
        testCase.nodes[node.Name] = node
        testCase.created[#testCase.created + 1] = node
        return node
    end
    _G.game = { GetService = function(_, name)
        if name == 'World' then return world end
        if name == 'RunService' then return { Heartbeat = self.heartbeat } end
        return {}
    end }
    _G.Vector2 = { New = function(x, y) return { x = x, y = y } end }
    _G.Color = { New = function(...) return { ... } end }
    _G.GameUI = { GetEuiManager = function() return {
        GetDeviceResolution = function() return { x = 1920, y = 1080 } end,
    } end, GetUIRoot = function() return self.uiRoot end }
    self.commands = {}
    self.snapshotRequests = 0
    self.events = {}
    self.notices = {}
    _G.LocalMsgNotice = function(text) self.notices[#self.notices + 1] = text end
    _G.REUtil = { GetRE = function(_, name)
        if not self.events[name] then
            self.events[name] = { OnClientEvent = signal(), FireServer = function(_, payload)
                if name == 'SpecialItemStateRequest' then self.snapshotRequests = self.snapshotRequests + 1 end
                if name == 'SpecialItemAction' or name == 'ItemBarAction' then
                    self.commands[#self.commands + 1] = payload
                end
            end }
        end
        return self.events[name]
    end }
    self.handler = assert(loadfile('client/ScreenHandlers/ScreenMain.lua'))()
    self.handler.RootNode = {
        Name = 'ScreenMain',
        FindFirstChild = function(_, name) return self.nodes[name] end,
    }
    self.currentRoot = self.handler.RootNode
    self.uiRoot = { FindFirstChild = function(_, name)
        if name == 'ScreenMain' then return self.currentRoot end
    end }
    self.handler:Init()
    self.handler.IsOpen = true
end

function TestSpecialItemUI:tearDown()
    require('client.LocalAttackButton'):Destroy()
    package.loaded['client.LocalAttackButton'] = self.previousAttack
    _G.LocalMsgNotice = nil
    for _, key in ipairs({ 'game', 'Vector2', 'Color', 'REUtil', 'GameUI', 'MgrGameUI' }) do
        _G[key] = self.previous[key]
    end
end

function TestSpecialItemUI:pushState(state)
    self.events.SpecialItemState.OnClientEvent:Fire(state)
end

function TestSpecialItemUI:specialCommands()
    local result = {}
    for _, cmd in ipairs(self.commands) do
        if cmd.action == 'fly' or cmd.action == 'breath' then result[#result + 1] = cmd end
    end
    return result
end

-- 失败方式 1/2：风神之翼生效时按钮变「长按飞行」，按下 / 松开发出升 / 降指令
function TestSpecialItemUI:test_wings_button_holds_flight()
    self:pushState({ effect = 'wings', airborne = false, breathRemaining = 0 })
    lu.assertEquals(self.nodes.BtnItemActionLabel.Text, '长按飞行')
    lu.assertTrue(self.nodes.ItemAction2.Visible)
    lu.assertTrue(self.nodes.ItemAction2.TouchEnabled)
    self.nodes.ItemAction2.OnTouchBegan:Fire()
    self.nodes.ItemAction2.OnTouchEnded:Fire()
    local cmds = self:specialCommands()
    lu.assertEquals(cmds, { { action = 'fly', holding = true }, { action = 'fly', holding = false } })
end

-- 失败方式 1/3：哥斯拉生效时按钮变「原子吐息」，点击发 breath；冷却中禁点并显示剩余秒数
function TestSpecialItemUI:test_godzilla_button_casts_breath_then_locks_on_cooldown()
    self:pushState({ effect = 'godzilla', airborne = false, breathRemaining = 0 })
    lu.assertEquals(self.nodes.BtnItemActionLabel.Text, '原子吐息')
    lu.assertTrue(self.nodes.ItemAction2.TouchEnabled)
    self.nodes.ItemAction2.OnClicked:Fire()
    lu.assertEquals(self:specialCommands(), { { action = 'breath' } })
    -- 服务端回报冷却：按钮锁住、显示剩余秒数；点击不再发
    self:pushState({ effect = 'godzilla', airborne = false, breathRemaining = 20 })
    lu.assertFalse(self.nodes.ItemAction2.TouchEnabled)
    lu.assertStrContains(self.nodes.BtnItemActionLabel.Text, '冷却')
    self.nodes.ItemAction2.OnClicked:Fire()
    lu.assertEquals(#self:specialCommands(), 1)
end

-- 失败方式 4：失败回包给玩家具体提示
function TestSpecialItemUI:test_failure_result_notifies_with_hint()
    self.events.SpecialItemResult.OnClientEvent:Fire({ ok = false, action = 'breath', reason = 'cooldown' })
    lu.assertEquals(self.notices, { '原子吐息冷却中' })
end

-- 失败方式 5：效果清空（切换 / 丢弃 / 死亡）后按钮回到钓鱼语义
function TestSpecialItemUI:test_cleared_effect_restores_fishing_button()
    self:pushState({ effect = 'wings', airborne = false, breathRemaining = 0 })
    lu.assertEquals(self.nodes.BtnItemActionLabel.Text, '长按飞行')
    self:pushState({ effect = nil, airborne = false, breathRemaining = 0 })
    lu.assertNotEquals(self.nodes.BtnItemActionLabel.Text, '长按飞行')
    -- 翅膀指令也不再发（语义已还原）
    self.nodes.ItemAction2.OnTouchBegan:Fire()
    lu.assertEquals(#self:specialCommands(), 0)
end

-- 失败方式 1：钓鱼阶段（线已抛出）不被特殊道具抢按钮
function TestSpecialItemUI:test_fishing_phase_keeps_reel_semantics_over_special_effect()
    self.handler.CastState = { phase = 'cast' }
    self:pushState({ effect = 'godzilla', airborne = false, breathRemaining = 0 })
    lu.assertEquals(self.nodes.BtnItemActionLabel.Text, '收竿')
    self.nodes.ItemAction2.OnClicked:Fire()
    lu.assertEquals(#self:specialCommands(), 0, '收线阶段不得发吐息')
end

function TestSpecialItemUI:test_cooldown_works_without_os_and_expires_on_server_time()
    local previous = _G.os
    _G.os = nil
    local ok, err = pcall(function()
        self:pushState({ effect = 'godzilla', breathRemaining = 20 })
        lu.assertFalse(self.nodes.ItemAction2.TouchEnabled)
        self.now = self.now + 21
        self.heartbeat:Fire()
        lu.assertEquals(self.nodes.BtnItemActionLabel.Text, '原子吐息')
        lu.assertTrue(self.nodes.ItemAction2.TouchEnabled)
    end)
    _G.os = previous
    assert(ok, err)
end

function TestSpecialItemUI:test_listeners_request_initial_special_snapshot()
    lu.assertEquals(self.snapshotRequests, 1)
    self:pushState({ effect = 'godzilla', breathRemaining = 12 })
    lu.assertFalse(self.nodes.ItemAction2.TouchEnabled)
end

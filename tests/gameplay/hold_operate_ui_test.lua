-- #124 客户端失败方式：首点即消费、拖拽取消仍发请求、失败无提示、武器/饵不随快照更新、
-- 重进后拖拽与两步状态串味。接缝：ScreenMain 拖拽/操作入口。
local lu = require('luaunit')

TestHoldOperateUI = {}

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

function TestHoldOperateUI:setUp()
    self.previous = { game = _G.game, Vector2 = _G.Vector2, Color = _G.Color,
        REUtil = _G.REUtil, GameUI = _G.GameUI, MgrGameUI = _G.MgrGameUI,
        LocalMsgNotice = _G.LocalMsgNotice }
    self.previousAttack = package.loaded['client.LocalAttackButton']
    package.loaded['client.LocalAttackButton'] = nil
    _G.MgrGameUI = { SetCustomControlUI = function() end }
    self.notices = {}
    _G.LocalMsgNotice = function(text) self.notices[#self.notices + 1] = text end
    self.nodes = {}
    self.created = {}
    local testCase = self
    local world = { Created = self.created }
    function world:CreateUnit(kind, attrs)
        local node = { Kind = kind, OnClicked = signal(), OnTouchBegan = signal(),
            OnTouchMoved = signal(), OnTouchEnded = signal() }
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
    self.results = _G.REUtil:GetRE('ItemBarResult').OnClientEvent
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
end

function TestHoldOperateUI:tearDown()
    require('client.LocalAttackButton'):Destroy()
    package.loaded['client.LocalAttackButton'] = self.previousAttack
    for _, key in ipairs({ 'game', 'Vector2', 'Color', 'REUtil', 'GameUI', 'MgrGameUI',
        'LocalMsgNotice' }) do
        _G[key] = self.previous[key]
    end
end

-- 吃/丢弃走 Operate 两步：点击发带 seq 的 Operate 请求，手持确认态由服务端快照驱动。
function TestHoldOperateUI:test_eat_and_discard_send_operate_with_seq()
    self.states:Fire({ slots = { [1] = { itemId = 'carp', count = 1 } },
        bait = { worm = 10 }, selectedSlot = 1 })
    self.nodes.BaitEat.OnClicked:Fire()
    lu.assertEquals(self.commands[1], { action = 'Operate', op = 'eat', slot = 1, seq = 1 })
    -- 服务端回快照：手持已切 → 按钮进入确认态
    self.states:Fire({ slots = { [1] = { itemId = 'carp', count = 1 } },
        bait = { worm = 10 }, selectedSlot = 1, held = { kind = 'slot', id = 'carp', slot = 1 } })
    lu.assertEquals(self.nodes.BtnEatLabel.Text, '吃鲤鱼')
    self.nodes.BaitEat.OnClicked:Fire()
    lu.assertEquals(self.commands[2], { action = 'Operate', op = 'eat', slot = 1, seq = 2 })
    self.nodes.ItemDiscard.OnClicked:Fire()
    lu.assertEquals(self.commands[3], { action = 'Operate', op = 'discard', slot = 1, seq = 3 })
end

-- 操作失败回包：给出具体提示，不出现裸 reason。
function TestHoldOperateUI:test_operate_failure_shows_notice()
    self.results:Fire({ ok = false, op = 'eat', reason = 'potion-capped' })
    lu.assertEquals(self.notices, { '这类药水已到上限' })
    self.results:Fire({ ok = false, op = 'discard', reason = 'drop-unavailable' })
    lu.assertEquals(self.notices[2], '丢弃通道未就绪（地面物品）')
    self.results:Fire({ ok = true, op = 'eat', held = false, itemId = 'carp' })
    lu.assertEquals(#self.notices, 2)
end

-- 双向拖拽：道具栏格拖到背包格发 MoveSlot；原地按下抬起（点击）与拖出界都不发。
function TestHoldOperateUI:test_drag_between_containers_sends_move_slot()
    self.states:Fire({ slots = { [1] = { itemId = 'carp', count = 1 } }, slotCount = 2,
        backpack = { [1] = { itemId = 'bass', count = 1 } }, backpackCount = 5, bait = {} })
    self.nodes.BtnBackpack.OnClicked:Fire()
    lu.assertTrue(self.nodes.BackpackSlot1.Visible)
    local from = self.nodes.ItemBarSlot1.Position
    local to = self.nodes.BackpackSlot1.Position
    self.nodes.ItemBarSlot1.OnTouchBegan:Fire({ BeganPosition = { x = from.x, y = from.y } })
    self.nodes.ItemBarSlot1.OnTouchEnded:Fire({ EndedPosition = { x = to.x, y = to.y } })
    lu.assertEquals(self.commands[#self.commands],
        { action = 'MoveSlot', value = { from = 'itemBar', index = 1, target = 'backpack', slot = 1 } })
    local before = #self.commands
    -- 原地点击：位移不足，不发 MoveSlot（SelectSlot 仍由 OnClicked 通道发）
    self.nodes.ItemBarSlot2.OnTouchBegan:Fire({ BeganPosition = { x = 1, y = 1 } })
    self.nodes.ItemBarSlot2.OnTouchEnded:Fire({ EndedPosition = { x = 2, y = 2 } })
    lu.assertEquals(#self.commands, before)
    -- 拖出任何格子：取消，不发
    self.nodes.BackpackSlot1.OnTouchBegan:Fire({ BeganPosition = { x = to.x, y = to.y } })
    self.nodes.BackpackSlot1.OnTouchEnded:Fire({ EndedPosition = { x = 5, y = 5 } })
    lu.assertEquals(#self.commands, before)
end

-- 动态按钮：快照里的武器与硬编码三键之外的鱼饵各自生成按钮，点击发对应请求。
function TestHoldOperateUI:test_dynamic_weapon_and_extra_bait_buttons()
    self.states:Fire({ slots = {}, bait = { worm = 3, rareShrimp = 2 }, weapons = { item134 = 1 } })
    local baitBtn = self.nodes['BaitDyn_rareShrimp']
    local weaponBtn = self.nodes['WeaponItem_item134']
    lu.assertNotNil(baitBtn)
    lu.assertNotNil(weaponBtn)
    lu.assertTrue(baitBtn.Visible)
    lu.assertTrue(weaponBtn.Visible)
    baitBtn.OnClicked:Fire()
    lu.assertEquals(self.commands[#self.commands], { action = 'SelectBait', value = 'rareShrimp' })
    weaponBtn.OnClicked:Fire()
    lu.assertEquals(self.commands[#self.commands],
        { action = 'Operate', op = 'attack', weapon = 'item134', seq = 1 })
    -- 快照清空后动态按钮隐藏
    self.states:Fire({ slots = {}, bait = {}, weapons = {} })
    lu.assertFalse(baitBtn.Visible)
    lu.assertFalse(weaponBtn.Visible)
end

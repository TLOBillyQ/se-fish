-- #86 迁移（原 tests/gameplay/hold_operate_ui_test.lua，#124 客户端失败方式）：
-- 首点即消费、拖拽取消仍发请求、失败无提示、武器/饵不随快照更新、
-- 重进后拖拽与两步状态串味。接缝：ScreenMain 拖拽/操作入口。
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

describe("持有操作的界面侧", function()
    local ctx

    -- 与旧 LuaUnit 的每例 setUp/tearDown 同级成对：整屏假环境逐例重建，
    -- ScreenMain 逐例重载以清掉模块级拖拽/seq 状态。
    before_each(function()
        ctx = { notices = {}, commands = {}, events = {}, nodes = {}, created = {} }
        ctx.previous = { game = _G.game, Vector2 = _G.Vector2, Color = _G.Color,
            REUtil = _G.REUtil, GameUI = _G.GameUI, MgrGameUI = _G.MgrGameUI,
            LocalMsgNotice = _G.LocalMsgNotice }
        ctx.previousAttack = package.loaded['client.LocalAttackButton']
        package.loaded['client.LocalAttackButton'] = nil
        _G.MgrGameUI = { SetCustomControlUI = function() end }
        _G.LocalMsgNotice = function(text) ctx.notices[#ctx.notices + 1] = text end
        local world = { Created = ctx.created }
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
            ctx.nodes[node.Name] = node
            ctx.created[#ctx.created + 1] = node
            return node
        end
        _G.game = { GetService = function(_, name) if name == 'World' then return world end end }
        _G.Vector2 = { New = function(x, y) return { x = x, y = y } end }
        _G.Color = { New = function(...) return { ... } end }
        _G.GameUI = { GetEuiManager = function() return {
            GetDeviceResolution = function() return { x = 1920, y = 1080 } end,
        } end, GetUIRoot = function() return ctx.uiRoot end }
        _G.REUtil = { GetRE = function(_, name)
            if not ctx.events[name] then
                ctx.events[name] = { OnClientEvent = signal(), FireServer = function(_, payload)
                    if name == 'ItemBarAction' then ctx.commands[#ctx.commands + 1] = payload end
                end }
            end
            return ctx.events[name]
        end }
        ctx.states = _G.REUtil:GetRE('ItemBarState').OnClientEvent
        ctx.results = _G.REUtil:GetRE('ItemBarResult').OnClientEvent
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
    end)

    -- 攻击按钮逐例销毁，全局与模块缓存恢复；setUp 中途失败也照样清理。
    after_each(function()
        require('client.LocalAttackButton'):Destroy()
        package.loaded['client.LocalAttackButton'] = ctx.previousAttack
        for _, key in ipairs({ 'game', 'Vector2', 'Color', 'REUtil', 'GameUI', 'MgrGameUI',
            'LocalMsgNotice' }) do
            _G[key] = ctx.previous[key]
        end
    end)

    -- 吃/丢弃走 Operate 两步：点击发带 seq 的 Operate 请求，手持确认态由服务端快照驱动。
    it("test_eat_and_discard_send_operate_with_seq", function()
        ctx.states:Fire({ slots = { [1] = { itemId = 'carp', count = 1 } },
            bait = { worm = 10 }, selectedSlot = 1 })
        ctx.nodes.BaitEat.OnClicked:Fire()
        assert.same({ action = 'Operate', op = 'eat', slot = 1, seq = 1 }, ctx.commands[1])
        -- 服务端回快照：手持已切 → 按钮进入确认态
        ctx.states:Fire({ slots = { [1] = { itemId = 'carp', count = 1 } },
            bait = { worm = 10 }, selectedSlot = 1, held = { kind = 'slot', id = 'carp', slot = 1 } })
        assert.same('吃鲤鱼', ctx.nodes.BtnEatLabel.Text)
        ctx.nodes.BaitEat.OnClicked:Fire()
        assert.same({ action = 'Operate', op = 'eat', slot = 1, seq = 2 }, ctx.commands[2])
        ctx.nodes.ItemDiscard.OnClicked:Fire()
        assert.same({ action = 'Operate', op = 'discard', slot = 1, seq = 3 }, ctx.commands[3])
    end)

    -- 操作失败回包：给出具体提示，不出现裸 reason。
    it("test_operate_failure_shows_notice", function()
        ctx.results:Fire({ ok = false, op = 'eat', reason = 'potion-capped' })
        assert.same({ '这类药水已到上限' }, ctx.notices)
        ctx.results:Fire({ ok = false, op = 'discard', reason = 'drop-unavailable' })
        assert.same('丢弃通道未就绪（地面物品）', ctx.notices[2])
        ctx.results:Fire({ ok = true, op = 'eat', held = false, itemId = 'carp' })
        assert.same(2, #ctx.notices)
    end)

    -- 双向拖拽：道具栏格拖到背包格发 MoveSlot；原地按下抬起（点击）与拖出界都不发。
    it("test_drag_between_containers_sends_move_slot", function()
        ctx.states:Fire({ slots = { [1] = { itemId = 'carp', count = 1 } }, slotCount = 2,
            backpack = { [1] = { itemId = 'bass', count = 1 } }, backpackCount = 5, bait = {} })
        ctx.nodes.BtnBackpack.OnClicked:Fire()
        assert.is_true(ctx.nodes.BackpackSlot1.Visible)
        local from = ctx.nodes.ItemBarSlot1.Position
        local to = ctx.nodes.BackpackSlot1.Position
        ctx.nodes.ItemBarSlot1.OnTouchBegan:Fire({ BeganPosition = { x = from.x, y = from.y } })
        ctx.nodes.ItemBarSlot1.OnTouchEnded:Fire({ EndedPosition = { x = to.x, y = to.y } })
        assert.same({ action = 'MoveSlot',
            value = { from = 'itemBar', index = 1, target = 'backpack', slot = 1 } },
            ctx.commands[#ctx.commands])
        local before = #ctx.commands
        -- 原地点击：位移不足，不发 MoveSlot（SelectSlot 仍由 OnClicked 通道发）
        ctx.nodes.ItemBarSlot2.OnTouchBegan:Fire({ BeganPosition = { x = 1, y = 1 } })
        ctx.nodes.ItemBarSlot2.OnTouchEnded:Fire({ EndedPosition = { x = 2, y = 2 } })
        assert.same(before, #ctx.commands)
        -- 拖出任何格子：取消，不发
        ctx.nodes.BackpackSlot1.OnTouchBegan:Fire({ BeganPosition = { x = to.x, y = to.y } })
        ctx.nodes.BackpackSlot1.OnTouchEnded:Fire({ EndedPosition = { x = 5, y = 5 } })
        assert.same(before, #ctx.commands)
    end)

    -- 动态按钮：快照里的武器与硬编码三键之外的鱼饵各自生成按钮，点击发对应请求。
    it("test_dynamic_weapon_and_extra_bait_buttons", function()
        ctx.states:Fire({ slots = {}, bait = { worm = 3, rareShrimp = 2 }, weapons = { item134 = 1 } })
        local baitBtn = ctx.nodes['BaitDyn_rareShrimp']
        local weaponBtn = ctx.nodes['WeaponItem_item134']
        assert.is_not_nil(baitBtn)
        assert.is_not_nil(weaponBtn)
        assert.is_true(baitBtn.Visible)
        assert.is_true(weaponBtn.Visible)
        baitBtn.OnClicked:Fire()
        assert.same({ action = 'SelectBait', value = 'rareShrimp' }, ctx.commands[#ctx.commands])
        weaponBtn.OnClicked:Fire()
        assert.same({ action = 'Operate', op = 'attack', weapon = 'item134', seq = 1 },
            ctx.commands[#ctx.commands])
        -- 快照清空后动态按钮隐藏
        ctx.states:Fire({ slots = {}, bait = {}, weapons = {} })
        assert.is_false(baitBtn.Visible)
        assert.is_false(weaponBtn.Visible)
    end)
end)

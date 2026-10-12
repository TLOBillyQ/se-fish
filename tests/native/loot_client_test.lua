-- #86 迁移（原 tests/gameplay/loot_client_test.lua，#126 共享掉落客户端侧）：
-- client/LocalLoot.lua 的预警闪烁节奏、普通掉落距离判定、点击只发请求。失败方式（先列后写）：
--   1. warn 不进客户端：预警期内文字泡一直亮，玩家看不出「这份马上要被回收」；
--   2. 闪的节奏写死或不走 GameCfg.Loot.FlashIntervalSec，改配置后两侧不同步；
--   3. 预警结束（新快照不带 warn）后还在闪，闪烁状态没清；
--   4. 距离判定被闪烁带偏：2 米外的件也亮、2 米内的普通件不亮；
--   5. 点击发的不是这一件的 ItemBarAction{action='Pickup', value=<id>}。
local GameCfg = require('common.GameCfg')

local function signal()
    local callbacks = {}
    return { Connect = function(_, fn)
        callbacks[#callbacks + 1] = fn
        return { Disconnect = function() end }
    end, Fire = function(_, ...)
        for _, fn in ipairs(callbacks) do fn(...) end
    end }
end

describe("共享掉落的客户端侧", function()
    local ctx

    -- 与旧 LuaUnit 的每例 setUp/tearDown 同级成对：客户端假环境逐例重建。
    before_each(function()
        ctx = { sent = {}, events = {}, nodes = {}, created = {}, sceneNodes = {} }
        ctx.originalRE = package.loaded['common.REUtil']
        ctx.originalLoot = package.loaded['client.LocalLoot']
        ctx.originalBubble = package.loaded['client.InteractionBubble']
        ctx.originalGame, ctx.originalVector3 = _G.game, _G.Vector3
        ctx.originalColor, ctx.originalVector2 = _G.Color, _G.Vector2
        ctx.heartbeat = signal()
        ctx.character = { Position = { x = 0, y = 0, z = 0 } }
        _G.Vector3 = { New = function(x, y, z) return { x = x, y = y, z = z } end }
        _G.Vector2 = { New = function(x, y) return { x = x, y = y } end }
        _G.Color = { New = function(...) return { ... } end }
        _G.game = { GetService = function(_, name)
            if name == 'Players' then
                return { LocalPlayer = { Character = ctx.character,
                    PlayerGui = { EuiManager = { CreateSceneNodeAtPosition = function(_, position)
                        local node = { Position = position, Visible = false }
                        function node:Destroy() self.Destroyed = true end
                        ctx.sceneNodes[#ctx.sceneNodes + 1] = node
                        return node
                    end } } } }
            end
            if name == 'RunService' then return { Heartbeat = ctx.heartbeat } end
            if name == 'World' then
                return { CreateUnit = function(_, unitType, values)
                    local unit = { UnitType = unitType, OnClicked = signal() }
                    for k, v in pairs(values) do unit[k] = v end
                    function unit:Destroy() self.Destroyed = true end
                    ctx.created[#ctx.created + 1] = unit
                    return unit
                end }
            end
        end }
        package.loaded['common.REUtil'] = { GetRE = function(_, name)
            if not ctx.events[name] then
                ctx.events[name] = { OnClientEvent = signal(),
                    FireServer = function(_, payload) ctx.sent[#ctx.sent + 1] = { name = name, payload = payload } end }
            end
            return ctx.events[name]
        end }
        package.loaded['client.LocalLoot'] = nil
        ctx.client = require('client.LocalLoot')
        ctx.client:Start()
    end)

    -- 全局、模块缓存逐例恢复；setUp 中途失败也照样清理。
    after_each(function()
        package.loaded['common.REUtil'] = ctx.originalRE
        package.loaded['client.LocalLoot'] = ctx.originalLoot
        package.loaded['client.InteractionBubble'] = ctx.originalBubble
        _G.game, _G.Vector3 = ctx.originalGame, ctx.originalVector3
        _G.Color, _G.Vector2 = ctx.originalColor, ctx.originalVector2
    end)

    local function entry(id)
        return ctx.client.Nodes[id]
    end

    local function unitNamed(name)
        for _, unit in ipairs(ctx.created) do
            if unit.Name == name then return unit end
        end
    end

    -- 预警件按配置节奏闪：配置间隔的前半拍亮、后半拍暗（服务端模型同节奏）
    it("test_warned_loot_flickers_at_configured_interval", function()
        local interval = GameCfg.Loot.FlashIntervalSec
        assert.same('number', type(interval))
        ctx.events.LootState.OnClientEvent:Fire({ { id = 7, kind = 'fish', fishId = 'carp', x = 0, y = 0, z = 0, warn = true } })
        local node = entry(7).Node
        ctx.client:Update(interval / 2)
        assert.is_true(node.Visible)
        ctx.client:Update(interval / 2)
        assert.is_false(node.Visible)
        ctx.client:Update(interval / 2)
        assert.is_false(node.Visible)
        ctx.client:Update(interval / 2)
        assert.is_true(node.Visible)
    end)

    -- 普通掉落不闪；出 2 米（PickupRadius）才隐藏
    it("test_plain_loot_stays_visible_and_range_still_applies", function()
        ctx.events.LootState.OnClientEvent:Fire({ { id = 1, kind = 'fish', fishId = 'carp', x = 0, y = 0, z = 0 } })
        local node = entry(1).Node
        for _ = 1, 4 do ctx.client:Update(0.25) end
        assert.is_true(node.Visible)
        ctx.character.Position = { x = GameCfg.Loot.PickupRadius + 1, y = 0, z = 0 }
        ctx.client:Update(0.25)
        assert.is_false(node.Visible)
        -- 回到范围内又是亮的
        ctx.character.Position = { x = 1, y = 0, z = 0 }
        ctx.client:Update(0.25)
        assert.is_true(node.Visible)
    end)

    -- 预警结束（新快照不带 warn）后不再闪，节点回到常亮
    it("test_warning_flag_clears_with_the_next_snapshot", function()
        ctx.events.LootState.OnClientEvent:Fire({ { id = 5, kind = 'item', itemId = 'carp', x = 0, y = 0, z = 0, warn = true } })
        ctx.client:Update(0.25)
        assert.is_true(entry(5).Node.Visible)
        ctx.events.LootState.OnClientEvent:Fire({ { id = 5, kind = 'item', itemId = 'carp', x = 0, y = 0, z = 0 } })
        for _ = 1, 4 do ctx.client:Update(0.25) end
        assert.is_true(entry(5).Node.Visible)
    end)

    -- 掉落物从快照消失就销毁文字泡；
    it("test_missing_loot_clears_its_bubble", function()
        ctx.events.LootState.OnClientEvent:Fire({ { id = 3, kind = 'item', itemId = 'carp', x = 0, y = 0, z = 0 } })
        local node = entry(3).Node
        ctx.events.LootState.OnClientEvent:Fire({})
        assert.is_nil(entry(3))
        assert.is_true(node.Destroyed)
    end)

    -- 点击只发这一件的拾取请求，服务端回包为准
    it("test_click_sends_pickup_request_for_that_loot", function()
        ctx.events.LootState.OnClientEvent:Fire({ { id = 9, kind = 'item', itemId = 'carp', x = 0, y = 0, z = 0 } })
        local button = unitNamed('BtnPickup_9')
        assert.is_not_nil(button)
        ctx.sent = {}
        button.OnClicked:Fire()
        assert.same({ { name = 'ItemBarAction', payload = { action = 'Pickup', value = 9 } } }, ctx.sent)
    end)
end)

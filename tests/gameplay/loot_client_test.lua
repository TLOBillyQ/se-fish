-- #126 共享掉落客户端侧（client/LocalLoot.lua）：30 秒预警期的拾取泡要跟服务端模型同节奏闪，
-- 普通掉落不受影响，点击照旧只发请求。失败方式（先列后写）：
--   1. warn 不进客户端：预警期内文字泡一直亮，玩家看不出「这份马上要被回收」；
--   2. 闪的节奏写死或不走 GameCfg.Loot.FlashIntervalSec，改配置后两侧不同步；
--   3. 预警结束（新快照不带 warn）后还在闪，闪烁状态没清；
--   4. 距离判定被闪烁带偏：2 米外的件也亮、2 米内的普通件不亮；
--   5. 点击发的不是这一件的 ItemBarAction{action='Pickup', value=<id>}。
local lu = require('luaunit')

TestLootClient = {}

local function signal()
    local callbacks = {}
    return { Connect = function(_, fn)
        callbacks[#callbacks + 1] = fn
        return { Disconnect = function() end }
    end, Fire = function(_, ...)
        for _, fn in ipairs(callbacks) do fn(...) end
    end }
end

function TestLootClient:setUp()
    local env = self
    self.originalRE = package.loaded['common.REUtil']
    self.originalLoot = package.loaded['client.LocalLoot']
    self.originalBubble = package.loaded['client.InteractionBubble']
    self.originalGame, self.originalVector3 = _G.game, _G.Vector3
    self.originalColor, self.originalVector2 = _G.Color, _G.Vector2
    self.sent, self.events, self.nodes, self.created, self.sceneNodes = {}, {}, {}, {}, {}
    self.heartbeat = signal()
    self.character = { Position = { x = 0, y = 0, z = 0 } }
    _G.Vector3 = { New = function(x, y, z) return { x = x, y = y, z = z } end }
    _G.Vector2 = { New = function(x, y) return { x = x, y = y } end }
    _G.Color = { New = function(...) return { ... } end }
    _G.game = { GetService = function(_, name)
        if name == 'Players' then
            return { LocalPlayer = { Character = env.character,
                PlayerGui = { EuiManager = { CreateSceneNodeAtPosition = function(_, position)
                    local node = { Position = position, Visible = false }
                    function node:Destroy() self.Destroyed = true end
                    env.sceneNodes[#env.sceneNodes + 1] = node
                    return node
                end } } } }
        end
        if name == 'RunService' then return { Heartbeat = env.heartbeat } end
        if name == 'World' then
            return { CreateUnit = function(_, unitType, values)
                local unit = { UnitType = unitType, OnClicked = signal() }
                for k, v in pairs(values) do unit[k] = v end
                function unit:Destroy() self.Destroyed = true end
                env.created[#env.created + 1] = unit
                return unit
            end }
        end
    end }
    package.loaded['common.REUtil'] = { GetRE = function(_, name)
        if not env.events[name] then
            env.events[name] = { OnClientEvent = signal(),
                FireServer = function(_, payload) env.sent[#env.sent + 1] = { name = name, payload = payload } end }
        end
        return env.events[name]
    end }
    package.loaded['client.LocalLoot'] = nil
    self.client = require('client.LocalLoot')
    self.client:Start()
end

function TestLootClient:tearDown()
    package.loaded['common.REUtil'] = self.originalRE
    package.loaded['client.LocalLoot'] = self.originalLoot
    package.loaded['client.InteractionBubble'] = self.originalBubble
    _G.game, _G.Vector3 = self.originalGame, self.originalVector3
    _G.Color, _G.Vector2 = self.originalColor, self.originalVector2
end

function TestLootClient:entry(id)
    return self.client.Nodes[id]
end

function TestLootClient:unitNamed(name)
    for _, unit in ipairs(self.created) do
        if unit.Name == name then return unit end
    end
end

-- 预警件按配置节奏闪：配置间隔的前半拍亮、后半拍暗（服务端模型同节奏）
function TestLootClient:test_warned_loot_flickers_at_configured_interval()
    local interval = require('common.GameCfg').Loot.FlashIntervalSec
    lu.assertEquals(type(interval), 'number')
    self.events.LootState.OnClientEvent:Fire({ { id = 7, kind = 'fish', fishId = 'carp', x = 0, y = 0, z = 0, warn = true } })
    local node = self:entry(7).Node
    self.client:Update(interval / 2)
    lu.assertTrue(node.Visible)
    self.client:Update(interval / 2)
    lu.assertFalse(node.Visible)
    self.client:Update(interval / 2)
    lu.assertFalse(node.Visible)
    self.client:Update(interval / 2)
    lu.assertTrue(node.Visible)
end

-- 普通掉落不闪；出 2 米（PickupRadius）才隐藏
function TestLootClient:test_plain_loot_stays_visible_and_range_still_applies()
    self.events.LootState.OnClientEvent:Fire({ { id = 1, kind = 'fish', fishId = 'carp', x = 0, y = 0, z = 0 } })
    local node = self:entry(1).Node
    for _ = 1, 4 do self.client:Update(0.25) end
    lu.assertTrue(node.Visible)
    self.character.Position = { x = require('common.GameCfg').Loot.PickupRadius + 1, y = 0, z = 0 }
    self.client:Update(0.25)
    lu.assertFalse(node.Visible)
    -- 回到范围内又是亮的
    self.character.Position = { x = 1, y = 0, z = 0 }
    self.client:Update(0.25)
    lu.assertTrue(node.Visible)
end

-- 预警结束（新快照不带 warn）后不再闪，节点回到常亮
function TestLootClient:test_warning_flag_clears_with_the_next_snapshot()
    self.events.LootState.OnClientEvent:Fire({ { id = 5, kind = 'item', itemId = 'carp', x = 0, y = 0, z = 0, warn = true } })
    self.client:Update(0.25)
    lu.assertTrue(self:entry(5).Node.Visible)
    self.events.LootState.OnClientEvent:Fire({ { id = 5, kind = 'item', itemId = 'carp', x = 0, y = 0, z = 0 } })
    for _ = 1, 4 do self.client:Update(0.25) end
    lu.assertTrue(self:entry(5).Node.Visible)
end

-- 掉落物从快照消失就销毁文字泡；
function TestLootClient:test_missing_loot_clears_its_bubble()
    self.events.LootState.OnClientEvent:Fire({ { id = 3, kind = 'item', itemId = 'carp', x = 0, y = 0, z = 0 } })
    local node = self:entry(3).Node
    self.events.LootState.OnClientEvent:Fire({})
    lu.assertNil(self:entry(3))
    lu.assertTrue(node.Destroyed)
end

-- 点击只发这一件的拾取请求，服务端回包为准
function TestLootClient:test_click_sends_pickup_request_for_that_loot()
    self.events.LootState.OnClientEvent:Fire({ { id = 9, kind = 'item', itemId = 'carp', x = 0, y = 0, z = 0 } })
    local button = self:unitNamed('BtnPickup_9')
    lu.assertNotNil(button)
    self.sent = {}
    button.OnClicked:Fire()
    lu.assertEquals(self.sent, { { name = 'ItemBarAction', payload = { action = 'Pickup', value = 9 } } })
end

local lu = require('luaunit')
local GameCfg = require('common.GameCfg')
local Mgr = require('server.Mgr.MgrPlayerData')

TestItemBarFlow = {}

local function signal()
    local callbacks = {}
    return {
        Connect = function(_, fn)
            callbacks[#callbacks + 1] = fn
            return { Disconnect = function() end }
        end,
        Fire = function(_, ...) for _, fn in ipairs(callbacks) do fn(...) end end,
    }
end

function TestItemBarFlow:setUp()
    -- #49：进图白送只在调试开关下发放，这些用例沿用它的起始库存（鱼竿在第 1 格、蚯蚓若干）
    self.savedGrantDebug = require('common.GameCfg').Debug
    require('common.GameCfg').Debug = { Enabled = true, InitialGrants = self.savedGrantDebug.InitialGrants }
    self.previousREUtil = _G.REUtil
    self.events = {}
    self.now = 0
    self.cooldowns = {}
    self.enableCooldown = false
    _G.REUtil = { CheckRECD = function(_, player, name, duration)
        if not self.enableCooldown then return false end
        lu.assertEquals(name, 'ItemBarAction')
        lu.assertEquals(duration, GameCfg.Items.ActionCooldownSec)
        local expiry = self.cooldowns[player.UserId]
        if expiry and self.now <= expiry then return true end
        self.cooldowns[player.UserId] = self.now + duration
        return false
    end, GetRE = function(_, name)
        if not self.events[name] then
            self.events[name] = {
                OnServerEvent = signal(),
                FireClient = function(_, player, state)
                    player.lastState = state
                    player.stateCount = (player.stateCount or 0) + 1
                end,
            }
        end
        return self.events[name]
    end }
    self.player = { UserId = 341, attrs = {}, CharacterAdded = signal(), CharacterRemoving = signal() }
    function self.player:SetAttribute(key, value) self.attrs[key] = value end
    Mgr:Start()
    Mgr:OnPlayerAdded(self.player)
end

function TestItemBarFlow:tearDown()
    require('common.GameCfg').Debug = self.savedGrantDebug
    Mgr:OnPlayerRemoving(self.player)
    _G.REUtil = self.previousREUtil
end

function TestItemBarFlow:test_client_commands_are_authoritative_and_state_replies()
    local action = self.events.ItemBarAction.OnServerEvent
    action:Fire(self.player, { action = 'SelectSlot', value = 1 })
    lu.assertEquals(self.player.lastState.selectedSlot, 1)
    action:Fire(self.player, { action = 'SelectBait', value = 'worm' })
    lu.assertEquals(self.player.lastState.bait.worm, 10)
    action:Fire(self.player, { action = 'EatBait', value = 'worm' })
    lu.assertEquals(self.player.lastState.bait.worm, 9)
    action:Fire(self.player, { action = 'SelectSlot', value = 2 })
    lu.assertNil(self.player.lastState.selectedSlot)
    self.events.RequestItemBar.OnServerEvent:Fire(self.player)
    lu.assertEquals(self.player.lastState.selectedBait, 'worm')
end

function TestItemBarFlow:test_reject_invalid_commands_and_other_player()
    local action = self.events.ItemBarAction.OnServerEvent
    local previous = self.player.lastState
    action:Fire(self.player, { action = 'Invalid' })
    action:Fire(self.player, { action = 'DiscardSlot', value = '1' })
    action:Fire(self.player, { action = 'SelectBait', value = 'other' })
    action:Fire(self.player, { action = 'ConsumeSelectedBait' })
    action:Fire(self.player, 'SelectSlot')
    lu.assertIs(self.player.lastState, previous)
    local stranger = { UserId = self.player.UserId }
    action:Fire(stranger, { action = 'DiscardSlot', value = 1 })
    lu.assertEquals(Mgr:GetDataInst(self.player):GetItemBarSnapshot().slots[1].itemId, 'starterRod')
end

function TestItemBarFlow:test_external_item_depletion_broadcasts_state()
    self.events.ItemBarAction.OnServerEvent:Fire(self.player, { action = 'SelectSlot', value = 1 })
    Mgr:GetDataInst(self.player):UpdateData(function(data)
        data.Containers[GameCfg.Items.ContainerId.ItemBar][1].count = 0
    end, true)
    lu.assertNil(self.player.lastState.selectedSlot)
    lu.assertNil(self.player.lastState.slots[1])
end

function TestItemBarFlow:test_cast_consumption_broadcasts_and_clears_last_bait()
    local data = Mgr:GetDataInst(self.player)
    data:UpdateData(function(state) state.Bait.worm = 1 end, true)
    self.events.ItemBarAction.OnServerEvent:Fire(self.player, { action = 'SelectBait', value = 'worm' })
    lu.assertEquals(self.player.lastState.bait.worm, 1)
    lu.assertEquals(self.player.lastState.selectedBait, 'worm')
    local previous = self.player.lastState
    local ok, itemId = data:ConsumeSelectedBait()
    lu.assertTrue(ok)
    lu.assertEquals(itemId, 'worm')
    lu.assertNotIs(self.player.lastState, previous)
    lu.assertEquals(self.player.lastState.bait.worm, 0)
    lu.assertNil(self.player.lastState.selectedBait)
end

function TestItemBarFlow:test_eating_last_selected_bait_broadcasts_clear()
    local data = Mgr:GetDataInst(self.player)
    data:UpdateData(function(state) state.Bait.worm = 1 end, true)
    local action = self.events.ItemBarAction.OnServerEvent
    action:Fire(self.player, { action = 'SelectBait', value = 'worm' })
    local sent = self.player.stateCount
    action:Fire(self.player, { action = 'EatBait', value = 'worm' })
    lu.assertEquals(self.player.stateCount, sent + 1)
    lu.assertEquals(self.player.lastState.bait.worm, 0)
    lu.assertNil(self.player.lastState.selectedBait)
end

function TestItemBarFlow:test_discard_and_depletion_update_reply()
    local action = self.events.ItemBarAction.OnServerEvent
    action:Fire(self.player, { action = 'SelectSlot', value = 1 })
    action:Fire(self.player, { action = 'DiscardSlot', value = 1 })
    lu.assertNil(self.player.lastState.selectedSlot)
    lu.assertNil(self.player.lastState.slots[1])
    Mgr:GetDataInst(self.player).Data.Bait.worm = 1
    action:Fire(self.player, { action = 'EatBait', value = 'worm' })
    lu.assertEquals(self.player.lastState.bait.worm, 0)
end

function TestItemBarFlow:test_action_rate_limit_and_recovery()
    self.enableCooldown = true
    local action = self.events.ItemBarAction.OnServerEvent
    action:Fire(self.player, { action = 'Invalid', value = 'worm' })
    action:Fire(self.player, { action = 'EatBait', value = 'bogus' })
    action:Fire(self.player, { action = 'SelectSlot', value = '1' })
    lu.assertNil(self.cooldowns[self.player.UserId])
    local impostor = { UserId = self.player.UserId }
    action:Fire(impostor, { action = 'EatBait', value = 'worm' })
    lu.assertNil(self.cooldowns[self.player.UserId])
    action:Fire(self.player, { action = 'EatBait', value = 'worm' })
    lu.assertEquals(self.player.lastState.bait.worm, 9)
    local sent = self.player.stateCount
    action:Fire(self.player, { action = 'EatBait', value = 'worm' })
    action:Fire(self.player, { action = 'SelectSlot', value = 1 })
    lu.assertEquals(self.player.lastState.bait.worm, 9)
    lu.assertNil(self.player.lastState.selectedSlot)
    lu.assertEquals(self.player.stateCount, sent)
    self.now = GameCfg.Items.ActionCooldownSec + 0.001
    action:Fire(self.player, { action = 'SelectSlot', value = 1 })
    lu.assertEquals(self.player.lastState.selectedSlot, 1)
    self.now = self.now + GameCfg.Items.ActionCooldownSec + 0.001
    action:Fire(self.player, { action = 'EatBait', value = 'worm' })
    lu.assertEquals(self.player.lastState.bait.worm, 8)
end

function TestItemBarFlow:test_action_rate_limit_is_per_player()
    self.enableCooldown = true
    local other = { UserId = 342, CharacterAdded = signal(), CharacterRemoving = signal() }
    function other:SetAttribute() end
    Mgr:OnPlayerAdded(other)
    local action = self.events.ItemBarAction.OnServerEvent
    action:Fire(self.player, { action = 'EatBait', value = 'worm' })
    action:Fire(other, { action = 'EatBait', value = 'worm' })
    lu.assertEquals(self.player.lastState.bait.worm, 9)
    lu.assertEquals(other.lastState.bait.worm, 9)
    Mgr:OnPlayerRemoving(other)
end

-- #52 新手任务「挂饵」事实（失败方式：取消挂饵 / 挂不存在或已用完的饵也报挂饵；
--   每次挂饵不带唯一 eventId；别的动作也报挂饵）
function TestItemBarFlow:test_select_bait_success_notifies_equip_with_distinct_ids()
    local facts = {}
    Mgr.Quest = { Notify = function(_, kind, player, payload)
        facts[#facts + 1] = { kind = kind, player = player, itemId = payload.itemId, eventId = payload.eventId }
        return true
    end }
    local ok, err = pcall(function()
        local action = self.events.ItemBarAction.OnServerEvent
        action:Fire(self.player, { action = 'SelectSlot', value = 1 })
        action:Fire(self.player, { action = 'SelectBait', value = 'other' })
        action:Fire(self.player, { action = 'SelectBait' })
        action:Fire(self.player, { action = 'EatBait', value = 'worm' })
        lu.assertEquals(#facts, 0)
        action:Fire(self.player, { action = 'SelectBait', value = 'worm' })
        action:Fire(self.player, { action = 'SelectBait', value = 'worm' })
        lu.assertEquals(#facts, 2)
        lu.assertEquals(facts[1].kind, 'EquipBait')
        lu.assertEquals(facts[1].itemId, 'worm')
        lu.assertEquals(facts[1].player, self.player)
        lu.assertNotNil(facts[1].eventId)
        lu.assertNotEquals(facts[1].eventId, facts[2].eventId)
        Mgr:GetDataInst(self.player):UpdateData(function(state) state.Bait.worm = 0 end, true)
        action:Fire(self.player, { action = 'SelectBait', value = 'worm' })
        lu.assertEquals(#facts, 2)
    end)
    Mgr.Quest = nil
    if not ok then error(err, 0) end
end

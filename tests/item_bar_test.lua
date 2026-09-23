local lu = require('luaunit')
local GameCfg = require('common.GameCfg')
local PlayerData = require('server.Data.PlayerData')

TestItemBar = {}

local function player()
    local p = { UserId = 34, attributes = {} }
    function p:SetAttribute(key, value) self.attributes[key] = value end
    return p
end

function TestItemBar:setUp()
    self.data = PlayerData.New(player())
    self.data:Init()
end

function TestItemBar:test_injected_item_bar_notification_without_global_manager()
    local previous = _G.MgrPlayerData
    _G.MgrPlayerData = setmetatable({}, { __index = function() error('不应反查管理器') end })
    local events = {}
    local bound = PlayerData.New(player(), function(owner, data)
        events[#events + 1] = { owner = owner, data = data }
    end)
    local ok, err = pcall(function()
        bound:Init()
        bound:SelectBait('worm')
        bound:EatBait('worm')
        lu.assertEquals(#events, 1)
        lu.assertIs(events[1].owner, bound.Player)
        lu.assertIs(events[1].data, bound)
        bound:Destroy()
    end)
    _G.MgrPlayerData = previous
    lu.assertTrue(ok, tostring(err))
end

function TestItemBar:test_initial_snapshot_has_eight_slots_and_separate_bait()
    local state = self.data:GetItemBarSnapshot()
    lu.assertEquals(state.slotCount, 8)
    lu.assertEquals(state.slots[1].itemId, 'starterRod')
    lu.assertNil(state.slots[2])
    lu.assertEquals(state.bait.worm, 10)
    lu.assertNil(state.selectedSlot)
end

function TestItemBar:test_slot_selection_and_empty_or_same_slot_cancels()
    lu.assertTrue(self.data:SelectSlot(1))
    lu.assertEquals(self.data:GetItemBarSnapshot().selectedSlot, 1)
    lu.assertTrue(self.data:SelectSlot(1))
    lu.assertNil(self.data:GetItemBarSnapshot().selectedSlot)
    lu.assertTrue(self.data:SelectSlot(1))
    lu.assertTrue(self.data:SelectSlot(8))
    lu.assertNil(self.data:GetItemBarSnapshot().selectedSlot)
    lu.assertFalse(self.data:SelectSlot(9))
    lu.assertFalse(self.data:SelectSlot(1.5))
end

function TestItemBar:test_selection_does_not_consume_and_none_does_not_refund()
    lu.assertTrue(self.data:SelectBait('worm'))
    lu.assertEquals(self.data:GetItemBarSnapshot().bait.worm, 10)
    lu.assertEquals(self.data:GetItemBarSnapshot().selectedBait, 'worm')
    lu.assertTrue(self.data:SelectBait('worm'))
    lu.assertEquals(self.data:GetItemBarSnapshot().bait.worm, 10)
    lu.assertTrue(self.data:SelectBait(nil))
    lu.assertNil(self.data:GetItemBarSnapshot().selectedBait)
    lu.assertEquals(self.data:GetItemBarSnapshot().bait.worm, 10)
    lu.assertFalse(self.data:SelectBait('bogus'))
    lu.assertFalse(self.data:SelectBait(7))
end

function TestItemBar:test_switch_bait_does_not_spend_old_or_new_until_consume()
    self.data.Data.Bait.shrimp = 2
    lu.assertTrue(self.data:SelectBait('worm'))
    lu.assertTrue(self.data:SelectBait('shrimp'))
    lu.assertEquals(self.data:GetItemBarSnapshot().bait.worm, 10)
    lu.assertEquals(self.data:GetItemBarSnapshot().bait.shrimp, 2)
    local ok, itemId = self.data:ConsumeSelectedBait()
    lu.assertTrue(ok)
    lu.assertEquals(itemId, 'shrimp')
    lu.assertEquals(self.data:GetItemBarSnapshot().bait.worm, 10)
    lu.assertEquals(self.data:GetItemBarSnapshot().bait.shrimp, 1)
end

function TestItemBar:test_consume_selected_bait_only_on_effective_cast()
    lu.assertTrue(self.data:SelectBait('worm'))
    for remaining = 9, 1, -1 do
        local ok, itemId = self.data:ConsumeSelectedBait()
        lu.assertTrue(ok)
        lu.assertEquals(itemId, 'worm')
        lu.assertEquals(self.data:GetItemBarSnapshot().bait.worm, remaining)
        lu.assertEquals(self.data:GetItemBarSnapshot().selectedBait, 'worm')
    end
    local ok, itemId = self.data:ConsumeSelectedBait()
    lu.assertTrue(ok)
    lu.assertEquals(itemId, 'worm')
    lu.assertEquals(self.data:GetItemBarSnapshot().bait.worm, 0)
    lu.assertNil(self.data:GetItemBarSnapshot().selectedBait)
    local withoutBait, emptyId = self.data:ConsumeSelectedBait()
    lu.assertTrue(withoutBait)
    lu.assertNil(emptyId)
    lu.assertEquals(self.data:GetItemBarSnapshot().bait.worm, 0)
end

function TestItemBar:test_eat_and_cast_share_inventory_and_last_eat_clears_selection()
    self.data.Data.Bait.worm = 2
    lu.assertTrue(self.data:SelectBait('worm'))
    lu.assertTrue(self.data:EatBait('worm'))
    lu.assertEquals(self.data:GetItemBarSnapshot().bait.worm, 1)
    lu.assertEquals(self.data:GetItemBarSnapshot().selectedBait, 'worm')
    lu.assertTrue(self.data:EatBait('worm'))
    lu.assertEquals(self.data:GetItemBarSnapshot().bait.worm, 0)
    lu.assertNil(self.data:GetItemBarSnapshot().selectedBait)
    lu.assertFalse(self.data:EatBait('worm'))
    lu.assertFalse(self.data:SelectBait('worm'))
    lu.assertFalse(self.data:EatBait('bogus'))
end

function TestItemBar:test_unavailable_selected_bait_cannot_be_consumed()
    lu.assertTrue(self.data:SelectBait('worm'))
    self.data:UpdateData(function(data) data.Bait.worm = 0 end)
    lu.assertNil(self.data:GetItemBarSnapshot().selectedBait)
    lu.assertFalse(self.data:SelectBait('worm'))
    self.data.Data.SelectedBait = 'worm'
    local ok, itemId = self.data:ConsumeSelectedBait()
    lu.assertFalse(ok)
    lu.assertNil(itemId)
    lu.assertNil(self.data:GetItemBarSnapshot().selectedBait)
    lu.assertEquals(self.data:GetItemBarSnapshot().bait.worm, 0)
end

function TestItemBar:test_external_depletion_clears_selected_slot()
    lu.assertTrue(self.data:SelectSlot(1))
    self.data:UpdateData(function(data)
        data.Containers[GameCfg.Items.ContainerId.ItemBar][1].count = 0
    end)
    lu.assertNil(self.data:GetItemBarSnapshot().selectedSlot)
    lu.assertNil(self.data:GetItemBarSnapshot().slots[1])
end

function TestItemBar:test_depletion_and_discard_clear_selection()
    lu.assertTrue(self.data:SelectSlot(1))
    lu.assertTrue(self.data:DiscardSlot(1))
    lu.assertNil(self.data:GetItemBarSnapshot().selectedSlot)
    lu.assertNil(self.data:GetItemBarSnapshot().slots[1])
    lu.assertFalse(self.data:DiscardSlot(1))
    self.data.Data.Bait.worm = 1
    lu.assertTrue(self.data:SelectBait('worm'))
    lu.assertEquals(self.data:GetItemBarSnapshot().bait.worm, 1)
    lu.assertTrue(self.data:ConsumeSelectedBait())
    lu.assertEquals(self.data:GetItemBarSnapshot().bait.worm, 0)
    lu.assertNil(self.data:GetItemBarSnapshot().selectedBait)
    lu.assertFalse(self.data:EatBait('worm'))
    lu.assertTrue(self.data:SelectBait(nil))
end

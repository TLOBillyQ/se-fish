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
    -- #49：进图白送只在调试开关下发放，这些用例沿用它的起始库存（鱼竿在第 1 格、蚯蚓若干）
    self.savedGrantDebug = require('common.GameCfg').Debug
    require('common.GameCfg').Debug = { Enabled = true, InitialGrants = self.savedGrantDebug.InitialGrants }
    self.data = PlayerData.New(player())
    self.data:Init()
end

function TestItemBar:tearDown()
    require('common.GameCfg').Debug = self.savedGrantDebug
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

function TestItemBar:test_initial_snapshot_has_two_slots_and_separate_bait()
    local state = self.data:GetItemBarSnapshot()
    lu.assertEquals(state.slotCount, 2)
    lu.assertEquals(state.backpackCount, 5)
    lu.assertEquals(state.upgradeLevel, 0)
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
    lu.assertTrue(self.data:SelectSlot(2))
    lu.assertNil(self.data:GetItemBarSnapshot().selectedSlot)
    lu.assertFalse(self.data:SelectSlot(3))
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

function TestItemBar:test_backpack_requires_transfer_before_use()
    lu.assertTrue(self.data:AddItem('carp', 1.2))
    lu.assertTrue(self.data:AddItem('bass', 1.5))
    local snapshot = self.data:GetItemBarSnapshot()
    lu.assertEquals(snapshot.backpack[1].itemId, 'bass')
    lu.assertEquals(snapshot.backpack[1].mult, 1.5)
    lu.assertFalse(self.data:SelectSlot(3))
    lu.assertNil(self.data:EatSlot(1))
    lu.assertFalse(self.data:MoveToItemBar(1))
    lu.assertTrue(self.data:DiscardSlot(2))
    lu.assertFalse(self.data:MoveToItemBar(6))
    lu.assertTrue(self.data:MoveToItemBar(1))
    snapshot = self.data:GetItemBarSnapshot()
    lu.assertNil(snapshot.backpack[1])
    lu.assertEquals(snapshot.slots[2].mult, 1.5)
    lu.assertEquals(snapshot.slots[2].containerId, GameCfg.Items.ContainerId.ItemBar)
    lu.assertTrue(self.data:SelectSlot(2))
    lu.assertEquals(self.data:EatSlot(2), 'bass')
end

function TestItemBar:test_upgrade_prices_capacity_and_full_grant()
    lu.assertTrue(self.data:AddCoin(6300, nil, 'test'))
    for level, price in ipairs(GameCfg.Items.UpgradePrices) do
        local ok, paid = self.data:UpgradeStorage()
        lu.assertTrue(ok)
        lu.assertEquals(paid, price)
        local snapshot = self.data:GetItemBarSnapshot()
        lu.assertEquals(snapshot.slotCount, 2 + level)
        lu.assertEquals(snapshot.backpackCount, level == 6 and 40 or 5 + 5 * level)
    end
    lu.assertEquals(self.data.Data.FishCoin, 0)
    lu.assertFalse(self.data:UpgradeStorage())
    for _ = 1, 47 do lu.assertTrue(self.data:AddItem('carp', 1)) end
    lu.assertFalse(self.data:AddItem('carp', 1))
    lu.assertFalse(self.data:CanGrant('carp', 1))
end

function TestItemBar:test_chief_bait_occupies_storage_and_debug_grants_overflow_to_backpack()
    local cfg = GameCfg.Debug
    GameCfg.Debug = { Enabled = true, InitialGrants = {
        { itemId = 'starterRod', count = 1, containerId = GameCfg.Items.ContainerId.ItemBar },
        { itemId = 'carp', count = 1, containerId = GameCfg.Items.ContainerId.ItemBar },
        { itemId = 'bass', count = 1, containerId = GameCfg.Items.ContainerId.ItemBar },
    } }
    local other = PlayerData.New(player())
    other:Init()
    GameCfg.Debug = cfg
    lu.assertEquals(other:GetItemBarSnapshot().backpack[1].itemId, 'bass')
    lu.assertTrue(other:AddItem('duck'))
    lu.assertEquals(other:GetItemBarSnapshot().backpack[2].itemId, 'duck')
    -- #88 起鸭子作为首领饵进快照 bait 表（件数），驱动挂饵按钮
    lu.assertEquals(other:GetItemBarSnapshot().bait.duck, 1)
end

function TestItemBar:test_failed_upgrade_does_not_change_capacity_or_coin()
    local ok, reason = self.data:UpgradeStorage()
    lu.assertFalse(ok)
    lu.assertEquals(reason, 'coin')
    lu.assertEquals(self.data:GetItemBarSnapshot().slotCount, 2)
    lu.assertEquals(self.data.Data.FishCoin, 0)
end

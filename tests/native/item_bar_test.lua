-- #86 迁移（原 tests/gameplay/item_bar_test.lua）：道具栏/背包/鱼饵栏的数据层规则。
-- 接缝：PlayerData 公共库存接口 + 注入的通知回调。
local GameCfg = require('common.GameCfg')
local PlayerData = require('server.Data.PlayerData')

local function player()
    local p = { UserId = 34, attributes = {} }
    function p:SetAttribute(key, value) self.attributes[key] = value end
    return p
end

describe("道具栏与鱼饵栏", function()
    local ctx

    -- 与旧 LuaUnit 的每例 setUp/tearDown 同级成对。
    -- #49：进图白送只在调试开关下发放，这些用例沿用它的起始库存（鱼竿在第 1 格、蚯蚓若干）。
    before_each(function()
        ctx = {}
        ctx.savedGrantDebug = GameCfg.Debug
        GameCfg.Debug = { Enabled = true, InitialGrants = ctx.savedGrantDebug.InitialGrants }
        ctx.data = PlayerData.New(player())
        ctx.data:Init()
    end)

    -- 调试配置逐例恢复；setUp 中途失败也照样清理。
    after_each(function()
        GameCfg.Debug = ctx.savedGrantDebug
    end)

    it("test_backpack_requires_transfer_before_use", function()
        assert.is_true(ctx.data:AddItem('carp', 1.2))
        assert.is_true(ctx.data:AddItem('bass', 1.5))
        local snapshot = ctx.data:GetItemBarSnapshot()
        assert.same('bass', snapshot.backpack[1].itemId)
        assert.same(1.5, snapshot.backpack[1].mult)
        assert.is_false(ctx.data:SelectSlot(3))
        assert.is_nil(ctx.data:EatSlot(1))
        assert.is_false(ctx.data:MoveToItemBar(1))
        assert.is_true(ctx.data:DiscardSlot(2))
        assert.is_false(ctx.data:MoveToItemBar(6))
        assert.is_true(ctx.data:MoveToItemBar(1))
        snapshot = ctx.data:GetItemBarSnapshot()
        assert.is_nil(snapshot.backpack[1])
        assert.same(1.5, snapshot.slots[2].mult)
        assert.same(GameCfg.Items.ContainerId.ItemBar, snapshot.slots[2].containerId)
        assert.is_true(ctx.data:SelectSlot(2))
        assert.same('bass', ctx.data:EatSlot(2))
    end)

    it("test_chief_bait_occupies_storage_and_debug_grants_overflow_to_backpack", function()
        local cfg = GameCfg.Debug
        GameCfg.Debug = { Enabled = true, InitialGrants = {
            { itemId = 'starterRod', count = 1, containerId = GameCfg.Items.ContainerId.ItemBar },
            { itemId = 'carp', count = 1, containerId = GameCfg.Items.ContainerId.ItemBar },
            { itemId = 'bass', count = 1, containerId = GameCfg.Items.ContainerId.ItemBar },
        } }
        local other = PlayerData.New(player())
        other:Init()
        GameCfg.Debug = cfg
        assert.same('bass', other:GetItemBarSnapshot().backpack[1].itemId)
        assert.is_true(other:AddItem('duck'))
        assert.same('duck', other:GetItemBarSnapshot().backpack[2].itemId)
        -- #124 起背包鸭子仍可展示，但 bait 只列道具栏可挂数；转入后才出现在快照 bait 表
        assert.is_nil(other:GetItemBarSnapshot().bait.duck)
        assert.is_true(other:MoveSlot('backpack', 2, 'itemBar', 1))
        assert.same(1, other:GetItemBarSnapshot().bait.duck)
    end)

    it("test_consume_selected_bait_only_on_effective_cast", function()
        assert.is_true(ctx.data:SelectBait('worm'))
        for remaining = 9, 1, -1 do
            local ok, itemId = ctx.data:ConsumeSelectedBait()
            assert.is_true(ok)
            assert.same('worm', itemId)
            assert.same(remaining, ctx.data:GetItemBarSnapshot().bait.worm)
            assert.same('worm', ctx.data:GetItemBarSnapshot().selectedBait)
        end
        local ok, itemId = ctx.data:ConsumeSelectedBait()
        assert.is_true(ok)
        assert.same('worm', itemId)
        assert.same(0, ctx.data:GetItemBarSnapshot().bait.worm)
        assert.is_nil(ctx.data:GetItemBarSnapshot().selectedBait)
        local withoutBait, emptyId = ctx.data:ConsumeSelectedBait()
        assert.is_true(withoutBait)
        assert.is_nil(emptyId)
        assert.same(0, ctx.data:GetItemBarSnapshot().bait.worm)
    end)

    it("test_depletion_and_discard_clear_selection", function()
        assert.is_true(ctx.data:SelectSlot(1))
        assert.is_true(ctx.data:DiscardSlot(1))
        assert.is_nil(ctx.data:GetItemBarSnapshot().selectedSlot)
        assert.is_nil(ctx.data:GetItemBarSnapshot().slots[1])
        assert.is_false(ctx.data:DiscardSlot(1))
        ctx.data.Data.Bait.worm = 1
        assert.is_true(ctx.data:SelectBait('worm'))
        assert.same(1, ctx.data:GetItemBarSnapshot().bait.worm)
        assert.is_true(ctx.data:ConsumeSelectedBait())
        assert.same(0, ctx.data:GetItemBarSnapshot().bait.worm)
        assert.is_nil(ctx.data:GetItemBarSnapshot().selectedBait)
        assert.is_false(ctx.data:EatBait('worm'))
        assert.is_true(ctx.data:SelectBait(nil))
    end)

    it("test_eat_and_cast_share_inventory_and_last_eat_clears_selection", function()
        ctx.data.Data.Bait.worm = 2
        assert.is_true(ctx.data:SelectBait('worm'))
        assert.is_true(ctx.data:EatBait('worm'))
        assert.same(1, ctx.data:GetItemBarSnapshot().bait.worm)
        assert.same('worm', ctx.data:GetItemBarSnapshot().selectedBait)
        assert.is_true(ctx.data:EatBait('worm'))
        assert.same(0, ctx.data:GetItemBarSnapshot().bait.worm)
        assert.is_nil(ctx.data:GetItemBarSnapshot().selectedBait)
        assert.is_false(ctx.data:EatBait('worm'))
        assert.is_false(ctx.data:SelectBait('worm'))
        assert.is_false(ctx.data:EatBait('bogus'))
    end)

    it("test_external_depletion_clears_selected_slot", function()
        assert.is_true(ctx.data:SelectSlot(1))
        ctx.data:UpdateData(function(data)
            data.Containers[GameCfg.Items.ContainerId.ItemBar][1].count = 0
        end)
        assert.is_nil(ctx.data:GetItemBarSnapshot().selectedSlot)
        assert.is_nil(ctx.data:GetItemBarSnapshot().slots[1])
    end)

    it("test_failed_upgrade_does_not_change_capacity_or_coin", function()
        local ok, reason = ctx.data:UpgradeStorage()
        assert.is_false(ok)
        assert.same('coin', reason)
        assert.same(2, ctx.data:GetItemBarSnapshot().slotCount)
        assert.same(0, ctx.data.Data.FishCoin)
    end)

    it("test_initial_snapshot_has_two_slots_and_separate_bait", function()
        local state = ctx.data:GetItemBarSnapshot()
        assert.same(2, state.slotCount)
        assert.same(5, state.backpackCount)
        assert.same(0, state.upgradeLevel)
        assert.same('starterRod', state.slots[1].itemId)
        assert.is_nil(state.slots[2])
        assert.same(10, state.bait.worm)
        assert.is_nil(state.selectedSlot)
    end)

    -- 通知走注入的回调，不反查全局管理器。
    it("test_injected_item_bar_notification_without_global_manager", function()
        local previous = _G.MgrPlayerData
        _G.MgrPlayerData = setmetatable({}, { __index = function() error('不应反查管理器') end })
        local events = {}
        local bound = PlayerData.New(player(), function(owner, data)
            events[#events + 1] = { owner = owner, data = data }
        end)
        -- pcall 包住主体：中途失败也要恢复 _G.MgrPlayerData，再抛错让本例失败。
        local ok, err = pcall(function()
            bound:Init()
            bound:SelectBait('worm')
            bound:EatBait('worm')
            assert.same(1, #events)
            assert.equal(events[1].owner, bound.Player)
            assert.equal(events[1].data, bound)
            bound:Destroy()
        end)
        _G.MgrPlayerData = previous
        assert.is_true(ok, tostring(err))
    end)

    it("test_selection_does_not_consume_and_none_does_not_refund", function()
        assert.is_true(ctx.data:SelectBait('worm'))
        assert.same(10, ctx.data:GetItemBarSnapshot().bait.worm)
        assert.same('worm', ctx.data:GetItemBarSnapshot().selectedBait)
        assert.is_true(ctx.data:SelectBait('worm'))
        assert.same(10, ctx.data:GetItemBarSnapshot().bait.worm)
        assert.is_true(ctx.data:SelectBait(nil))
        assert.is_nil(ctx.data:GetItemBarSnapshot().selectedBait)
        assert.same(10, ctx.data:GetItemBarSnapshot().bait.worm)
        assert.is_false(ctx.data:SelectBait('bogus'))
        assert.is_false(ctx.data:SelectBait(7))
    end)

    it("test_slot_selection_and_empty_or_same_slot_cancels", function()
        assert.is_true(ctx.data:SelectSlot(1))
        assert.same(1, ctx.data:GetItemBarSnapshot().selectedSlot)
        assert.is_true(ctx.data:SelectSlot(1))
        assert.is_nil(ctx.data:GetItemBarSnapshot().selectedSlot)
        assert.is_true(ctx.data:SelectSlot(1))
        assert.is_true(ctx.data:SelectSlot(2))
        assert.is_nil(ctx.data:GetItemBarSnapshot().selectedSlot)
        assert.is_false(ctx.data:SelectSlot(3))
        assert.is_false(ctx.data:SelectSlot(1.5))
    end)

    it("test_switch_bait_does_not_spend_old_or_new_until_consume", function()
        ctx.data.Data.Bait.shrimp = 2
        assert.is_true(ctx.data:SelectBait('worm'))
        assert.is_true(ctx.data:SelectBait('shrimp'))
        assert.same(10, ctx.data:GetItemBarSnapshot().bait.worm)
        assert.same(2, ctx.data:GetItemBarSnapshot().bait.shrimp)
        local ok, itemId = ctx.data:ConsumeSelectedBait()
        assert.is_true(ok)
        assert.same('shrimp', itemId)
        assert.same(10, ctx.data:GetItemBarSnapshot().bait.worm)
        assert.same(1, ctx.data:GetItemBarSnapshot().bait.shrimp)
    end)

    it("test_unavailable_selected_bait_cannot_be_consumed", function()
        assert.is_true(ctx.data:SelectBait('worm'))
        ctx.data:UpdateData(function(data) data.Bait.worm = 0 end)
        assert.is_nil(ctx.data:GetItemBarSnapshot().selectedBait)
        assert.is_false(ctx.data:SelectBait('worm'))
        ctx.data.Data.SelectedBait = 'worm'
        local ok, itemId = ctx.data:ConsumeSelectedBait()
        assert.is_false(ok)
        assert.is_nil(itemId)
        assert.is_nil(ctx.data:GetItemBarSnapshot().selectedBait)
        assert.same(0, ctx.data:GetItemBarSnapshot().bait.worm)
    end)

    it("test_upgrade_prices_capacity_and_full_grant", function()
        assert.is_true(ctx.data:AddCoin(6300, nil, 'test'))
        for level, price in ipairs(GameCfg.Items.UpgradePrices) do
            local ok, paid = ctx.data:UpgradeStorage()
            assert.is_true(ok)
            assert.same(price, paid)
            local snapshot = ctx.data:GetItemBarSnapshot()
            assert.same(2 + level, snapshot.slotCount)
            assert.same(level == 6 and 40 or 5 + 5 * level, snapshot.backpackCount)
        end
        assert.same(0, ctx.data.Data.FishCoin)
        assert.is_false(ctx.data:UpgradeStorage())
        for _ = 1, 47 do assert.is_true(ctx.data:AddItem('carp', 1)) end
        assert.is_false(ctx.data:AddItem('carp', 1))
        assert.is_false(ctx.data:CanGrant('carp', 1))
    end)
end)

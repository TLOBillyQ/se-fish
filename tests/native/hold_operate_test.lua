-- #86 迁移（原 tests/gameplay/hold_operate_test.lua，#124）：
-- 失败方式先列：满格互换吞物/复制、取消拖拽仍移动、跨容器倍率丢失；
-- 首领饵从背包使用、普通饵/武器占格；选中即消费、重复操作重复扣物；
-- 非法身份/状态绕过持久屏障、落地失败扣物、重进手持悬空。
-- 接缝：PlayerData 公共库存/选择接口。
local GameCfg = require('common.GameCfg')
local PlayerData = require('server.Data.PlayerData')

describe("持有与操作的数据层规则", function()
    local ctx

    -- 与旧 LuaUnit 的每例 setUp/tearDown 同级成对：库存实例逐例新建，配置逐例恢复。
    before_each(function()
        ctx = {}
        ctx.debug = GameCfg.Debug
        GameCfg.Debug = { Enabled = false }
        ctx.data = PlayerData.New({ UserId = 124, SetAttribute = function() end })
        ctx.data:Init()
    end)

    -- 配置逐例恢复；setUp 中途失败也照样清理。
    after_each(function()
        GameCfg.Debug = ctx.debug
    end)

    -- 各容量档位：满格互换不吞物不复制，越界/缺目标拒绝，跨容器倍率随实例走。
    it("test_all_capacity_levels_move_swap_cancel_keep_instances", function()
        for level, capacity in ipairs({ 5, 10, 15, 20, 25, 30, 40 }) do
            local d = ctx.data
            assert.is_true(d:ApplyGMPatch({ upgradeLevel = level - 1, coin = 0 }))
            assert.same(level + 1, d:ItemBarCapacity())
            assert.same(capacity, d:BackpackCapacity())
            while d:AddItem('carp', 1.37) do end
            assert.is_false(d:AddItem('bass', 1.99))
            assert.is_true(d:ApplyGMPatch({ slots = {
                { container = 'itemBar', index = 1, itemId = 'bass', count = 1, mult = 1.99 },
            } }))
            local before = d:GetItemBarSnapshot()
            assert.is_false(d:MoveSlot('itemBar', 1, nil, nil))
            assert.is_false(d:MoveSlot('itemBar', 1, 'backpack', capacity + 1))
            assert.same(before, d:GetItemBarSnapshot())
            assert.is_true(d:MoveSlot('itemBar', 1, 'backpack', capacity))
            assert.same(1.99, d:GetItemBarSnapshot().backpack[capacity].mult)
            assert.same(1.37, d:GetItemBarSnapshot().slots[1].mult)
            assert.is_true(d:MoveSlot('backpack', capacity, 'itemBar', 1))
            assert.same(before, d:GetItemBarSnapshot())
            assert.is_true(d:DiscardSlot(2))
            assert.is_true(d:MoveSlot('backpack', capacity, 'itemBar', 2))
            assert.is_nil(d:GetItemBarSnapshot().backpack[capacity])
            assert.same(1.37, d:GetItemBarSnapshot().slots[2].mult)
        end
    end)

    -- 首领饵必须在道具栏选中才能用：背包里的饵不算持有。
    it("test_boss_bait_must_be_selected_in_item_bar_before_use", function()
        while ctx.data:AddItem('carp', 1.37) do end
        assert.is_true(ctx.data:DiscardSlot(1))
        assert.is_true(ctx.data:MoveSlot('backpack', 1, 'itemBar', 1))
        assert.is_true(ctx.data:GrantItem('duck', 1))
        assert.same('duck', ctx.data:GetItemBarSnapshot().backpack[1].itemId)
        assert.is_false(ctx.data:SelectBait('duck'))
        assert.is_false(ctx.data:HasBait('duck'))
        local ok, bait = ctx.data:ConsumeSelectedBait()
        assert.is_true(ok)
        assert.is_nil(bait)
        assert.same(1, ctx.data:ItemCount('duck'))
        assert.is_true(ctx.data:MoveSlot('backpack', 1, 'itemBar', 1))
        assert.is_true(ctx.data:SelectBait('duck'))
        local ok, bait = ctx.data:ConsumeSelectedBait()
        assert.is_true(ok)
        assert.same('duck', bait)
        assert.same(0, ctx.data:ItemCount('duck'))
        assert.is_nil(ctx.data.Data.SelectedBait)
    end)

    -- 重进恢复合法：手持持久化往返，槽位/武器失效时清空而不是悬空。
    it("test_held_persists_across_serialize_and_invalidates", function()
        local rod = GameCfg.Items.Id.StarterRod
        assert.is_true(ctx.data:AddItem(rod, 1.37))
        assert.is_true(ctx.data:AddItem('carp', 1.99))
        assert.is_true(ctx.data:HoldSlot(1))
        local snapshot = ctx.data:Serialize()
        local other = PlayerData.New({ UserId = 124, SetAttribute = function() end })
        other:Init()
        assert.is_true(other:ApplySave(snapshot))
        assert.same({ kind = 'slot', id = rod, slot = 1 }, other:GetItemBarSnapshot().held)
        -- 槽位物品与手持不符：重进后清空
        local broken = ctx.data:Serialize()
        broken.bar = { { i = 1, id = 'carp', n = 1, m = 1.99 }, { i = 2, id = rod, n = 1, m = 1.37 } }
        local third = PlayerData.New({ UserId = 124, SetAttribute = function() end })
        third:Init()
        assert.is_true(third:ApplySave(broken))
        assert.is_nil(third:GetItemBarSnapshot().held.kind)
    end)

    -- 切手持与实际使用分两次：首次仅切手持，手持匹配才算再次；重复点击合法。
    it("test_held_toggle_first_hold_then_use", function()
        local rod = GameCfg.Items.Id.StarterRod
        assert.is_true(ctx.data:AddItem(rod, 1.37))
        assert.is_true(ctx.data:AddItem('carp', 1.99))
        -- 首次：切手持，选中与使用不提前发生
        assert.is_true(ctx.data:HoldSlot(1))
        assert.same({ kind = 'slot', id = rod, slot = 1 }, ctx.data:GetItemBarSnapshot().held)
        assert.is_nil(ctx.data:GetItemBarSnapshot().selectedSlot)
        assert.same(1, ctx.data:GetItemBarSnapshot().slots[1].count)
        -- 重复点击同一槽：取消手持（合法，不扣物不吞格）
        assert.is_true(ctx.data:HoldSlot(1))
        assert.is_nil(ctx.data:GetItemBarSnapshot().held.kind)
        -- 换槽切换手持
        assert.is_true(ctx.data:HoldSlot(2))
        assert.same({ kind = 'slot', id = 'carp', slot = 2 }, ctx.data:GetItemBarSnapshot().held)
        -- 空槽/越界不成立
        assert.is_false(ctx.data:HoldSlot(3))
        assert.is_false(ctx.data:HoldSlot(0))
        -- 槽位物品变化后手持清空：丢弃后不再悬在失效物品上
        assert.is_true(ctx.data:HoldSlot(1))
        assert.is_true(ctx.data:DiscardSlot(1))
        assert.is_nil(ctx.data:GetItemBarSnapshot().held.kind)
    end)

    -- 武器手持：独立库存校验，耗尽即清空，不占格不影响格位快照。
    it("test_weapon_held_inventory_backed", function()
        while ctx.data:AddItem('carp', 1.37) do end
        local before = ctx.data:GetItemBarSnapshot()
        assert.is_false(ctx.data:HoldWeapon('item134'))
        assert.is_true(ctx.data:GrantWeapon('item134', 1))
        assert.is_true(ctx.data:HoldWeapon('item134'))
        assert.same({ kind = 'weapon', id = 'item134', slot = nil }, ctx.data:GetItemBarSnapshot().held)
        assert.same(before.slots, ctx.data:GetItemBarSnapshot().slots)
        -- 再次点击取消
        assert.is_true(ctx.data:HoldWeapon('item134'))
        assert.is_nil(ctx.data:GetItemBarSnapshot().held.kind)
        -- 耗尽清空
        assert.is_true(ctx.data:HoldWeapon('item134'))
        assert.is_true(ctx.data:ConsumeWeapon('item134', 1))
        assert.is_nil(ctx.data:GetItemBarSnapshot().held.kind)
        assert.is_nil(ctx.data:GetItemBarSnapshot().selectedWeapon)
    end)

    -- #130：武器不占格，满格也可授予；移动目标不能是武器容器。
    it("test_weapon_inventory_and_boss_bait_location_rules", function()
        local ids = GameCfg.Items.ContainerId
        while ctx.data:AddItem('carp', 1.37) do end
        local before = ctx.data:GetItemBarSnapshot()
        -- #130：武器不占格，满格也可购买/授予（与 GrantWeapon 行为一致）
        assert.is_true(ctx.data:CanGrant('item134', 1))
        assert.is_true(ctx.data:GrantWeapon('item134', 1))
        local granted = ctx.data:GetItemBarSnapshot()
        assert.same(before.slots, granted.slots)
        assert.same(before.backpack, granted.backpack)
        assert.same(1, ctx.data:WeaponCount('item134'))
        assert.same(1, granted.weapons.item134)
        assert.is_true(ctx.data:SelectWeapon('item134'))
        assert.same('item134', ctx.data:GetItemBarSnapshot().selectedWeapon)
        assert.is_true(ctx.data:SelectWeapon('item134'))
        assert.is_nil(ctx.data:GetItemBarSnapshot().selectedWeapon)
        assert.is_false(ctx.data:MoveSlot(ids.Backpack, 1, 'weapon', 1))
        assert.same(granted, ctx.data:GetItemBarSnapshot())
    end)
end)

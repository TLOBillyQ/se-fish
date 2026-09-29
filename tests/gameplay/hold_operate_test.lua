-- #124 失败方式先列：满格互换吞物/复制、取消拖拽仍移动、跨容器倍率丢失；
-- 首领饵从背包使用、普通饵/武器占格；选中即消费、重复操作重复扣物；
-- 非法身份/状态绕过持久屏障、落地失败扣物、重进手持悬空。
-- 接缝：PlayerData 公共库存/选择接口、MgrPlayerData:Handle、ScreenMain 拖拽与操作入口。
local lu = require('luaunit')
local GameCfg = require('common.GameCfg')
local PlayerData = require('server.Data.PlayerData')
TestHoldOperate = {}
function TestHoldOperate:setUp()
    self.debug = GameCfg.Debug
    GameCfg.Debug = { Enabled = false }
    self.data = PlayerData.New({ UserId = 124, SetAttribute = function() end })
    self.data:Init()
end
function TestHoldOperate:tearDown() GameCfg.Debug = self.debug end

-- 重进恢复合法：手持持久化往返，槽位/武器失效时清空而不是悬空。
function TestHoldOperate:test_held_persists_across_serialize_and_invalidates()
    local rod = GameCfg.Items.Id.StarterRod
    lu.assertTrue(self.data:AddItem(rod, 1.37))
    lu.assertTrue(self.data:AddItem('carp', 1.99))
    lu.assertTrue(self.data:HoldSlot(1))
    local snapshot = self.data:Serialize()
    local other = PlayerData.New({ UserId = 124, SetAttribute = function() end })
    other:Init()
    lu.assertTrue(other:ApplySave(snapshot))
    lu.assertEquals(other:GetItemBarSnapshot().held, { kind = 'slot', id = rod, slot = 1 })
    -- 槽位物品与手持不符：重进后清空
    local broken = self.data:Serialize()
    broken.bar = { { i = 1, id = 'carp', n = 1, m = 1.99 }, { i = 2, id = rod, n = 1, m = 1.37 } }
    local third = PlayerData.New({ UserId = 124, SetAttribute = function() end })
    third:Init()
    lu.assertTrue(third:ApplySave(broken))
    lu.assertNil(third:GetItemBarSnapshot().held.kind)
end

-- 切手持与实际使用分两次：首次仅切手持，手持匹配才算再次；重复点击合法。
function TestHoldOperate:test_held_toggle_first_hold_then_use()
    local rod = GameCfg.Items.Id.StarterRod
    lu.assertTrue(self.data:AddItem(rod, 1.37))
    lu.assertTrue(self.data:AddItem('carp', 1.99))
    -- 首次：切手持，选中与使用不提前发生
    lu.assertTrue(self.data:HoldSlot(1))
    lu.assertEquals(self.data:GetItemBarSnapshot().held, { kind = 'slot', id = rod, slot = 1 })
    lu.assertNil(self.data:GetItemBarSnapshot().selectedSlot)
    lu.assertEquals(self.data:GetItemBarSnapshot().slots[1].count, 1)
    -- 重复点击同一槽：取消手持（合法，不扣物不吞格）
    lu.assertTrue(self.data:HoldSlot(1))
    lu.assertNil(self.data:GetItemBarSnapshot().held.kind)
    -- 换槽切换手持
    lu.assertTrue(self.data:HoldSlot(2))
    lu.assertEquals(self.data:GetItemBarSnapshot().held, { kind = 'slot', id = 'carp', slot = 2 })
    -- 空槽/越界不成立
    lu.assertFalse(self.data:HoldSlot(3))
    lu.assertFalse(self.data:HoldSlot(0))
    -- 槽位物品变化后手持清空：丢弃后不再悬在失效物品上
    lu.assertTrue(self.data:HoldSlot(1))
    lu.assertTrue(self.data:DiscardSlot(1))
    lu.assertNil(self.data:GetItemBarSnapshot().held.kind)
end

-- 武器手持：独立库存校验，耗尽即清空，不占格不影响格位快照。
function TestHoldOperate:test_weapon_held_inventory_backed()
    while self.data:AddItem('carp', 1.37) do end
    local before = self.data:GetItemBarSnapshot()
    lu.assertFalse(self.data:HoldWeapon('item134'))
    lu.assertTrue(self.data:GrantWeapon('item134', 1))
    lu.assertTrue(self.data:HoldWeapon('item134'))
    lu.assertEquals(self.data:GetItemBarSnapshot().held, { kind = 'weapon', id = 'item134', slot = nil })
    lu.assertEquals(self.data:GetItemBarSnapshot().slots, before.slots)
    -- 再次点击取消
    lu.assertTrue(self.data:HoldWeapon('item134'))
    lu.assertNil(self.data:GetItemBarSnapshot().held.kind)
    -- 耗尽清空
    lu.assertTrue(self.data:HoldWeapon('item134'))
    lu.assertTrue(self.data:ConsumeWeapon('item134', 1))
    lu.assertNil(self.data:GetItemBarSnapshot().held.kind)
    lu.assertNil(self.data:GetItemBarSnapshot().selectedWeapon)
end

local lu = require('luaunit')
local GameCfg = require('common.GameCfg')
function TestHoldOperate:test_all_capacity_levels_move_swap_cancel_keep_instances()
    for level, capacity in ipairs({ 5, 10, 15, 20, 25, 30, 40 }) do
        local d = self.data
        lu.assertTrue(d:ApplyGMPatch({ upgradeLevel = level - 1, coin = 0 }))
        lu.assertEquals(d:ItemBarCapacity(), level + 1)
        lu.assertEquals(d:BackpackCapacity(), capacity)
        while d:AddItem('carp', 1.37) do end
        lu.assertFalse(d:AddItem('bass', 1.99))
        lu.assertTrue(d:ApplyGMPatch({ slots = {
            { container = 'itemBar', index = 1, itemId = 'bass', count = 1, mult = 1.99 },
        } }))
        local before = d:GetItemBarSnapshot()
        lu.assertFalse(d:MoveSlot('itemBar', 1, nil, nil))
        lu.assertFalse(d:MoveSlot('itemBar', 1, 'backpack', capacity + 1))
        lu.assertEquals(d:GetItemBarSnapshot(), before)
        lu.assertTrue(d:MoveSlot('itemBar', 1, 'backpack', capacity))
        lu.assertEquals(d:GetItemBarSnapshot().backpack[capacity].mult, 1.99)
        lu.assertEquals(d:GetItemBarSnapshot().slots[1].mult, 1.37)
        lu.assertTrue(d:MoveSlot('backpack', capacity, 'itemBar', 1))
        lu.assertEquals(d:GetItemBarSnapshot(), before)
        lu.assertTrue(d:DiscardSlot(2))
        lu.assertTrue(d:MoveSlot('backpack', capacity, 'itemBar', 2))
        lu.assertNil(d:GetItemBarSnapshot().backpack[capacity])
        lu.assertEquals(d:GetItemBarSnapshot().slots[2].mult, 1.37)
    end
end

function TestHoldOperate:test_weapon_inventory_and_boss_bait_location_rules()
    local ids = GameCfg.Items.ContainerId
    while self.data:AddItem('carp', 1.37) do end
    local before = self.data:GetItemBarSnapshot()
    lu.assertFalse(self.data:CanGrant('item134', 1))
    lu.assertTrue(self.data:GrantWeapon('item134', 1))
    local granted = self.data:GetItemBarSnapshot()
    lu.assertEquals(granted.slots, before.slots)
    lu.assertEquals(granted.backpack, before.backpack)
    lu.assertEquals(self.data:WeaponCount('item134'), 1)
    lu.assertEquals(granted.weapons.item134, 1)
    lu.assertTrue(self.data:SelectWeapon('item134'))
    lu.assertEquals(self.data:GetItemBarSnapshot().selectedWeapon, 'item134')
    lu.assertTrue(self.data:SelectWeapon('item134'))
    lu.assertNil(self.data:GetItemBarSnapshot().selectedWeapon)
    lu.assertFalse(self.data:MoveSlot(ids.Backpack, 1, 'weapon', 1))
    lu.assertEquals(self.data:GetItemBarSnapshot(), granted)
end

function TestHoldOperate:test_boss_bait_must_be_selected_in_item_bar_before_use()
    while self.data:AddItem('carp', 1.37) do end
    lu.assertTrue(self.data:DiscardSlot(1))
    lu.assertTrue(self.data:MoveSlot('backpack', 1, 'itemBar', 1))
    lu.assertTrue(self.data:GrantItem('duck', 1))
    lu.assertEquals(self.data:GetItemBarSnapshot().backpack[1].itemId, 'duck')
    lu.assertFalse(self.data:SelectBait('duck'))
    lu.assertFalse(self.data:HasBait('duck'))
    local ok, bait = self.data:ConsumeSelectedBait()
    lu.assertTrue(ok)
    lu.assertNil(bait)
    lu.assertEquals(self.data:ItemCount('duck'), 1)
    lu.assertTrue(self.data:MoveSlot('backpack', 1, 'itemBar', 1))
    lu.assertTrue(self.data:SelectBait('duck'))
    local ok, bait = self.data:ConsumeSelectedBait()
    lu.assertTrue(ok)
    lu.assertEquals(bait, 'duck')
    lu.assertEquals(self.data:ItemCount('duck'), 0)
    lu.assertNil(self.data.Data.SelectedBait)
end

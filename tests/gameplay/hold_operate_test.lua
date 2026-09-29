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

-- #49 退役旧成长系统并收口获取路径。
-- 失败方式（先列后写）：
--   1. 调试开关关闭（默认）时进图仍白送鱼竿 / 蚯蚓，与拾饵、喂食、购买并存成两套正式获取路径；
--   2. 白送配置仍挂在物品表下、与 GM 不是同一个开关；开关打开后白送不生效或发错容器；
--   3. 清理时把合法的鱼竿等级筛选一起删了：要求等级高于鱼竿的鱼也能钓上，或等级够的鱼钓不上。
local lu = require('luaunit')

TestGrowthCleanup = {}

function TestGrowthCleanup:setUp()
    self.cfg = require('common.GameCfg')
    self.savedDebug = self.cfg.Debug
    self.PlayerData = assert(loadfile('server/Data/PlayerData.lua'))()
end

function TestGrowthCleanup:tearDown()
    self.cfg.Debug = self.savedDebug
end

function TestGrowthCleanup:init()
    local data = self.PlayerData.New({ UserId = 1, SetAttribute = function() end })
    data:Init()
    return data
end

function TestGrowthCleanup:test_no_free_grant_by_default()
    local fresh = assert(loadfile('common/GameCfg.lua'))()
    lu.assertFalse(fresh.Debug.Enabled)
    lu.assertNil(fresh.Items.InitialGrants)
    self.cfg.Debug = fresh.Debug
    local data = self:init()
    lu.assertEquals(data:GetItemBarSnapshot().slots, {})
    lu.assertEquals(data:GetItemBarSnapshot().bait, {})
end

function TestGrowthCleanup:test_debug_switch_restores_grant_into_containers()
    local fresh = assert(loadfile('common/GameCfg.lua'))()
    self.cfg.Debug = { Enabled = true, InitialGrants = fresh.Debug.InitialGrants }
    local state = self:init():GetItemBarSnapshot()
    lu.assertEquals(state.slots[1].itemId, 'starterRod')
    lu.assertTrue(state.bait.worm >= 1)
    lu.assertNil(state.slots[2])
end

function TestGrowthCleanup:test_rod_level_filter_is_kept()
    local FishCatch = require('common.FishCatch')
    local rows = {
        { Id = 'low', Bait = 0, RodLevel = 1, DrawWeight = 1 },
        { Id = 'high', Bait = 0, RodLevel = 2, DrawWeight = 1000 },
    }
    local maxRoll = function(n) return n end
    lu.assertEquals(FishCatch.Select(rows, 1, nil, maxRoll), 'low')
    lu.assertEquals(FishCatch.Select(rows, 2, nil, maxRoll), 'high')
    lu.assertNil(FishCatch.Select({ rows[2] }, 1, nil, maxRoll))
end

function TestGrowthCleanup:test_draw_weight_and_rod_level_are_valid()
    local fresh = assert(loadfile('common/GameCfg.lua'))()
    for _, rows in pairs(fresh.Casting.Zones) do
        for _, row in ipairs(rows) do
            lu.assertTrue(type(row.DrawWeight) == 'number' and row.DrawWeight > 0, row.Id)
            lu.assertTrue(row.RodLevel >= 1, row.Id)
        end
    end
end

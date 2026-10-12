-- #89 迁移（原 tests/gameplay/growth_cleanup_test.lua，#49 退役旧成长系统并收口获取路径）：
-- 失败方式（先列后写）：
--   1. 调试开关关闭时进图仍白送鱼竿 / 蚯蚓，与拾饵、喂食、购买并存成两套正式获取路径；
--   2. 白送配置仍挂在物品表下、与 GM 不是同一个开关；开关打开后白送不生效或发错容器；
--   3. 清理时把合法的鱼竿等级筛选一起删了：要求等级高于鱼竿的鱼也能钓上，或等级够的鱼钓不上。
-- 旧套件的 setUp/tearDown 是逐例的（每案例各跑一次），因此映射为 before_each/after_each，
-- 不是 suite 级 setup/teardown；after_each 对未完成的 before_each 幂等（ctx 未建立就跳过）。
-- describe/it 名沿用旧类名与方法名，案例顺序沿用旧 LuaUnit 的字典序执行序。
local GameCfg = require('common.GameCfg')

describe('TestGrowthCleanup', function()
    local ctx

    before_each(function()
        ctx = { savedDebug = GameCfg.Debug }
        ctx.PlayerData = assert(loadfile('server/Data/PlayerData.lua'))()
    end)

    -- before_each 中途失败（loadfile 报错）时 ctx 可能只建了一半：恢复要逐项判空。
    after_each(function()
        if ctx and ctx.savedDebug ~= nil then
            GameCfg.Debug = ctx.savedDebug
        end
    end)

    local function init()
        local data = ctx.PlayerData.New({ UserId = 1, SetAttribute = function() end })
        data:Init()
        return data
    end

    -- 调试开关关闭时不白送任何东西
    it('test_debug_switch_restores_grant_into_containers', function()
        local fresh = assert(loadfile('common/GameCfg.lua'))()
        GameCfg.Debug = { Enabled = true, InitialGrants = fresh.Debug.InitialGrants }
        local state = init():GetItemBarSnapshot()
        assert.same('starterRod', state.slots[1].itemId)
        assert.is_true(state.bait.worm >= 1)
        assert.is_nil(state.slots[2])
    end)

    -- 校验全部钓鱼区鱼行的权重与鱼竿等级
    it('test_draw_weight_and_rod_level_are_valid', function()
        local fresh = assert(loadfile('common/GameCfg.lua'))()
        for _, rows in pairs(fresh.Casting.Zones) do
            for _, row in ipairs(rows) do
                assert.message(row.Id).is_true(type(row.DrawWeight) == 'number' and row.DrawWeight > 0)
                assert.message(row.Id).is_true(row.RodLevel >= 1)
            end
        end
    end)

    -- 白送挂在 Debug 开关下：关闭后物品栏与鱼饵栏都空
    it('test_no_free_grant_when_debug_is_disabled', function()
        local fresh = assert(loadfile('common/GameCfg.lua'))()
        assert.is_nil(fresh.Items.InitialGrants)
        fresh.Debug.Enabled = false
        GameCfg.Debug = fresh.Debug
        local data = init()
        assert.same({}, data:GetItemBarSnapshot().slots)
        assert.same({}, data:GetItemBarSnapshot().bait)
    end)

    -- 鱼竿等级筛选是合法逻辑，不能被成长清理一起删掉
    it('test_rod_level_filter_is_kept', function()
        local FishCatch = require('common.FishCatch')
        local rows = {
            { Id = 'low', Bait = 0, RodLevel = 1, DrawWeight = 1 },
            { Id = 'high', Bait = 0, RodLevel = 2, DrawWeight = 1000 },
        }
        local maxRoll = function(n) return n end
        assert.same('low', FishCatch.Select(rows, 1, nil, maxRoll))
        assert.same('high', FishCatch.Select(rows, 2, nil, maxRoll))
        assert.is_nil(FishCatch.Select({ rows[2] }, 1, nil, maxRoll))
    end)
end)

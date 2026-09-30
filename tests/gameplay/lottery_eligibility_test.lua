-- #134 / #138 抽奖投入资格（GameSpec §14、§13）。失败方式（先列后写）：
--   1. 鱼塘极品鱼获 item7–12 或信物（eelHead / garHead）被拒，抽奖机无物可投；
--   2. 普通鱼获（tilapia 等）或非食物被当成极品放行；
--   3. 烤过的极品鱼获/信物仍能投：库存格位 saved.cooked 标记、快照或读档后的顶层 cooked 任一被漏看；
--   4. 读档后烤制状态丢失（只剩 slot.k 压缩字段）导致烤过的又变可投；
--   5. 未知物品、多件、倍率/烤制值越界或类型错的畸形条目被放行，或直接抛错。
-- seam：真实 GameCfg 物品表 + 真实 PlayerData 的 AddItem / 快照 / Serialize / ApplySave。
local lu = require('luaunit')
local GameCfg = require('common.GameCfg')
local Eligibility = require('common.LotteryEligibility')

TestLotteryEligibility = {}

local function check(entry)
    return { Eligibility.Check(entry) }
end

function TestLotteryEligibility:test_uncooked_pond_rares_and_tokens_are_eligible()
    for _, itemId in ipairs({ 'item7', 'item8', 'item9', 'item10', 'item11', 'item12', 'eelHead', 'garHead' }) do
        lu.assertEquals(GameCfg.Items.Definitions[itemId].Type, '极品食物', itemId)
        lu.assertEquals(check({ itemId = itemId, count = 1, mult = 1.37 }), { true }, itemId)
        lu.assertEquals(check({ itemId = itemId }), { true }, itemId .. ' 缺省件数与倍率')
    end
end

function TestLotteryEligibility:test_ordinary_items_are_not_premium()
    for _, itemId in ipairs({ 'tilapia', 'carp', 'worm', 'shrimpTicket' }) do
        if GameCfg.Items.Definitions[itemId] then
            lu.assertEquals(check({ itemId = itemId, count = 1 }), { false, 'not-premium' }, itemId)
        end
    end
    lu.assertNotNil(GameCfg.Items.Definitions.tilapia, '普通鱼样本必须存在')
end

function TestLotteryEligibility:test_cooked_by_inventory_flag_or_snapshot_multiplier_is_rejected()
    local flag = GameCfg.Items.CookedFlag
    lu.assertEquals(check({ itemId = 'item12', count = 1, mult = 1.5, saved = { [flag] = true } }), { false, 'cooked' })
    lu.assertEquals(check({ itemId = 'eelHead', count = 1, saved = { [flag] = true } }), { false, 'cooked' })
    lu.assertEquals(check({ itemId = 'garHead', count = 1, cooked = 1.5 }), { false, 'cooked' })
    lu.assertEquals(check({ itemId = 'item7', count = 1, saved = { [flag] = false } }), { true })
    -- saved 里其他字段（读档 copy(slot) 带进来的 id/i/n/m）不影响未烤判定
    lu.assertEquals(check({ itemId = 'item7', count = 1, saved = { id = 'item7', i = 1, n = 1, m = 1.2 } }), { true })
end

function TestLotteryEligibility:test_malformed_and_unknown_entries_are_rejected_without_error()
    local flag = GameCfg.Items.CookedFlag
    local cases = {
        { nil, 'malformed' },
        { 'item7', 'malformed' },
        { {}, 'malformed' },
        { { itemId = 7 }, 'malformed' },
        { { itemId = 'item7', count = 2 }, 'malformed' },
        { { itemId = 'item7', count = 0 }, 'malformed' },
        { { itemId = 'item7', mult = 0.5 }, 'malformed' },
        { { itemId = 'item7', mult = 2.5 }, 'malformed' },
        { { itemId = 'item7', mult = '1.2' }, 'malformed' },
        { { itemId = 'item7', mult = 0 / 0 }, 'malformed' },
        { { itemId = 'item7', cooked = 0 }, 'malformed' },
        { { itemId = 'item7', cooked = -1 }, 'malformed' },
        { { itemId = 'item7', cooked = true }, 'malformed' },
        { { itemId = 'item7', cooked = math.huge }, 'malformed' },
        { { itemId = 'item7', saved = true }, 'malformed' },
        { { itemId = 'item7', saved = { [flag] = 1 } }, 'malformed' },
        { { itemId = 'noSuchItem', count = 1 }, 'bad-item' },
    }
    for index, case in ipairs(cases) do
        lu.assertEquals(check(case[1]), { false, case[2] }, 'case ' .. index)
    end
end

function TestLotteryEligibility:test_real_inventory_entries_keep_cooked_state_through_snapshot_and_reload()
    local PlayerData = require('server.Data.PlayerData')
    local data = PlayerData.New({ UserId = 134, SetAttribute = function() end })
    data:Init()
    lu.assertTrue(data:AddItem('item9', 1.42))
    lu.assertTrue(data:AddItem('eelHead', 1.1, 1.5))
    -- Init 自带初始物品占格，道具栏满后落背包：按 itemId 在两个容器里找真实格位
    local ids = GameCfg.Items.ContainerId
    local function find(player, itemId)
        for _, id in ipairs({ ids.ItemBar, ids.Backpack }) do
            for _, entry in pairs(player.Data.Containers[id]) do
                if entry.itemId == itemId then return entry end
            end
        end
        lu.fail('库存里没有 ' .. itemId)
    end
    lu.assertEquals(check(find(data, 'item9')), { true })
    lu.assertEquals(check(find(data, 'eelHead')), { false, 'cooked' })
    local snapshot = data:GetItemBarSnapshot()
    for _, entry in pairs(snapshot.slots) do
        if entry.itemId == 'item9' then lu.assertEquals(check(entry), { true }) end
        if entry.itemId == 'eelHead' then lu.assertEquals(check(entry), { false, 'cooked' }) end
    end

    local restored = PlayerData.New({ UserId = 135, SetAttribute = function() end })
    restored:Init()
    lu.assertTrue(restored:ApplySave(data:Serialize()))
    lu.assertEquals(check(find(restored, 'item9')), { true })
    lu.assertEquals(check(find(restored, 'eelHead')), { false, 'cooked' }, '读档后烤制状态不能丢')
end

-- 原生 Busted（#87 迁移自 tests/gameplay/lottery_eligibility_test.lua 的 TestLotteryEligibility）。
-- #134 / #138 抽奖投入资格（GameSpec §14、§13）。失败方式（先列后写）：
--   1. 鱼塘极品鱼获 item7–12 或信物（eelHead / garHead）被拒，抽奖机无物可投；
--   2. 普通鱼获（tilapia 等）或非食物被当成极品放行；
--   3. 烤过的极品鱼获/信物仍能投：库存格位 saved.cooked 标记、快照或读档后的顶层 cooked 任一被漏看；
--   4. 读档后烤制状态丢失（只剩 slot.k 压缩字段）导致烤过的又变可投；
--   5. 未知物品、多件、倍率/烤制值越界或类型错的畸形条目被放行，或直接抛错。
-- seam：真实 GameCfg 物品表 + 真实 PlayerData 的 AddItem / 快照 / Serialize / ApplySave。
-- 迁移说明：案例按旧 LuaUnit 实际执行序（方法名字典序）逐个 it 注册；
--   lu.fail(msg) 在 luassert 无对应断言，按语义用 error(msg, 0) 保持原消息不带位置前缀。
local GameCfg = require("common.GameCfg")
local Eligibility = require("common.LotteryEligibility")
local RandomGuard = require("tests.support.random_guard")

local function check(entry)
  return { Eligibility.Check(entry) }
end

describe("抽奖投入资格（common.LotteryEligibility × PlayerData）", function()
  after_each(RandomGuard.restore)

  it("test_cooked_by_inventory_flag_or_snapshot_multiplier_is_rejected", function()
    local flag = GameCfg.Items.CookedFlag
    assert.same({ false, "cooked" }, check({ itemId = "item12", count = 1, mult = 1.5, saved = { [flag] = true } }))
    assert.same({ false, "cooked" }, check({ itemId = "eelHead", count = 1, saved = { [flag] = true } }))
    assert.same({ false, "cooked" }, check({ itemId = "garHead", count = 1, cooked = 1.5 }))
    assert.same({ true }, check({ itemId = "item7", count = 1, saved = { [flag] = false } }))
    -- saved 里其他字段（读档 copy(slot) 带进来的 id/i/n/m）不影响未烤判定
    assert.same({ true }, check({ itemId = "item7", count = 1, saved = { id = "item7", i = 1, n = 1, m = 1.2 } }))
  end)

  it("test_malformed_and_unknown_entries_are_rejected_without_error", function()
    local flag = GameCfg.Items.CookedFlag
    local cases = {
      { nil, "malformed" },
      { "item7", "malformed" },
      { {}, "malformed" },
      { { itemId = 7 }, "malformed" },
      { { itemId = "item7", count = 2 }, "malformed" },
      { { itemId = "item7", count = 0 }, "malformed" },
      { { itemId = "item7", mult = 0.5 }, "malformed" },
      { { itemId = "item7", mult = 2.5 }, "malformed" },
      { { itemId = "item7", mult = "1.2" }, "malformed" },
      { { itemId = "item7", mult = 0 / 0 }, "malformed" },
      { { itemId = "item7", cooked = 0 }, "malformed" },
      { { itemId = "item7", cooked = -1 }, "malformed" },
      { { itemId = "item7", cooked = true }, "malformed" },
      { { itemId = "item7", cooked = math.huge }, "malformed" },
      { { itemId = "item7", saved = true }, "malformed" },
      { { itemId = "item7", saved = { [flag] = 1 } }, "malformed" },
      { { itemId = "noSuchItem", count = 1 }, "bad-item" },
    }
    for index, case in ipairs(cases) do
      assert.same({ false, case[2] }, check(case[1]), "case " .. index)
    end
  end)

  it("test_ordinary_items_are_not_premium", function()
    for _, itemId in ipairs({ "tilapia", "carp", "worm", "shrimpTicket" }) do
      if GameCfg.Items.Definitions[itemId] then
        assert.same({ false, "not-premium" }, check({ itemId = itemId, count = 1 }), itemId)
      end
    end
    assert.is_not_nil(GameCfg.Items.Definitions.tilapia, "普通鱼样本必须存在")
  end)

  it("test_real_inventory_entries_keep_cooked_state_through_snapshot_and_reload", function()
    local PlayerData = require("server.Data.PlayerData")
    local data = PlayerData.New({ UserId = 134, SetAttribute = function() end })
    data:Init()
    assert.is_true(data:AddItem("item9", 1.42))
    assert.is_true(data:AddItem("eelHead", 1.1, 1.5))
    -- Init 自带初始物品占格，道具栏满后落背包：按 itemId 在两个容器里找真实格位
    local ids = GameCfg.Items.ContainerId
    local function find(player, itemId)
      for _, id in ipairs({ ids.ItemBar, ids.Backpack }) do
        for _, entry in pairs(player.Data.Containers[id]) do
          if entry.itemId == itemId then
            return entry
          end
        end
      end
      error("库存里没有 " .. itemId, 0)
    end
    assert.same({ true }, check(find(data, "item9")))
    assert.same({ false, "cooked" }, check(find(data, "eelHead")))
    local snapshot = data:GetItemBarSnapshot()
    for _, entry in pairs(snapshot.slots) do
      if entry.itemId == "item9" then
        assert.same({ true }, check(entry))
      end
      if entry.itemId == "eelHead" then
        assert.same({ false, "cooked" }, check(entry))
      end
    end

    local restored = PlayerData.New({ UserId = 135, SetAttribute = function() end })
    restored:Init()
    assert.is_true(restored:ApplySave(data:Serialize()))
    assert.same({ true }, check(find(restored, "item9")))
    assert.same({ false, "cooked" }, check(find(restored, "eelHead")), "读档后烤制状态不能丢")
  end)

  it("test_uncooked_pond_rares_and_tokens_are_eligible", function()
    for _, itemId in ipairs({ "item7", "item8", "item9", "item10", "item11", "item12", "eelHead", "garHead" }) do
      assert.same("极品食物", GameCfg.Items.Definitions[itemId].Type, itemId)
      assert.same({ true }, check({ itemId = itemId, count = 1, mult = 1.37 }), itemId)
      assert.same({ true }, check({ itemId = itemId }), itemId .. " 缺省件数与倍率")
    end
  end)
end)

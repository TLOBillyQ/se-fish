-- 原生 Busted（#87 迁移自 tests/gameplay/lottery_settle_test.lua 的 TestLotterySettle）。
-- #138 T17 抽奖机服务端结算（MgrLottery）失败方式先列：
--   1. 资格漏洞：非极品食物、烤鱼、烤过信物、背包物品、空槽或越界格号被接受；
--   2. 投注价值错：不用实际价值（个体倍率丢失）或误用烤熟价；
--   3. 结算错：两同金币倍数错位、三同叠加两同金币、无中奖发奖或多扣；
--   4. 落位错：占格大奖没回投入格、武器占了道具格而不是独立库存；
--   5. 幂等错：同 seq 重复点击双扣、operation 重放重发奖、断线重进恢复时又发一次；
--   6. 持久化错：写库失败却把结果发布给玩家；结果未先落账就回包；
--   7. 校验缺失：不在抽奖机旁也能抽；payload 畸形导致报错而不是拒绝。
-- seam：MgrLottery:Handle / OnPlayerAdded；真实 PlayerData、MgrPlayerData、MgrSave、MgrInteract，
--   替换引擎边界（game / REUtil / DataStore）；随机数经 MgrLottery.Random 注入（系统边界）。
-- 迁移说明：案例按旧 LuaUnit 实际执行序（方法名字典序）逐个 it 注册；随机数走模块字段注入，
--   未替换 math.random，仍逐案例还原全局随机函数。
local GameCfg = require("common.GameCfg")
local RandomGuard = require("tests.support.random_guard")

local ITEM_BAR = GameCfg.Items.ContainerId.ItemBar

--- 搭一次抽奖机结算世界；调用方负责 cleanup()。
local function newWorld()
  local env = {}

  function env:join()
    local signal = { Connect = function() return { Disconnect = function() end } end }
    self.player = {
      UserId = 777,
      Character = { Position = { x = 0, y = 0, z = 0 } },
      CharacterAdded = signal,
      CharacterRemoving = signal,
      SetAttribute = function() end,
    }
    self.players:OnPlayerAdded(self.player)
  end

  function env:drain()
    while #self.queue > 0 do
      table.remove(self.queue, 1)()
    end
  end

  function env:clearEvents()
    self.events = {}
  end

  function env:messages(name)
    local values = {}
    for _, event in ipairs(self.events) do
      if event.name == name then
        values[#values + 1] = event.value
      end
    end
    return values
  end

  -- 发一件极品食物到道具栏；返回格号。item7 极品罗非鱼基础价 3，item31 虾尾（信物）基础价 50
  function env:givePremium(itemId, mult, cooked)
    assert(self.data:AddItem(itemId, mult, cooked))
    return 1
  end

  -- 脚本化 RNG：先三轴（各取 1..100），武器组三同再取一次组内（1..5）
  function env:scriptAxes(a, b, c, weaponPick)
    self.rolls = { a, b, c }
    if weaponPick then
      self.rolls[4] = weaponPick
    end
  end

  function env:draw(slot, seq)
    local accepted = self.lottery:Handle(self.player, { action = "Draw", slot = slot, seq = seq })
    self:drain()
    return accepted
  end

  function env:persistReady()
    assert(self.save:SaveExplicit(self.player.UserId, self.data, function(ok)
      assert(ok)
    end))
    self:drain()
    self:clearEvents()
  end

  function env:cleanup()
    _G.game, _G.REUtil = self.oldGame, self.oldRE
    GameCfg.Debug = self.oldDebug
  end

  env.oldGame, env.oldRE = _G.game, _G.REUtil
  env.oldDebug = GameCfg.Debug
  GameCfg.Debug = { Enabled = false }
  env.values, env.queue, env.events = {}, {}, {}
  env.readFailure, env.writeFailure = false, false
  env.store = {
    GetAsync = function(_, key)
      if env.readFailure then
        error("读档失败")
      end
      return env.values[key]
    end,
    UpdateAsync = function(_, key, transform)
      if env.writeFailure then
        error("写档失败")
      end
      local value = transform(env.values[key])
      if value then
        env.values[key] = value
      end
      return value
    end,
    SetAsync = function(_, key, value)
      env.values[key] = value
    end,
  }
  env.anchor = { Position = { x = 0, y = 0, z = 0 } }
  _G.game = {
    GetService = function(_, name)
      if name == "Task" then
        return {
          Spawn = function(_, fn)
            env.queue[#env.queue + 1] = fn
          end,
          Wait = function() end,
        }
      end
      if name == "DataStoreService" then
        return { GetDataStore = function() return env.store end }
      end
      if name == "World" then
        return {
          GetServerTime = function() return 100 end,
          FindFirstChild = function() return env.anchor end,
        }
      end
      if name == "Players" then
        return { GetPlayers = function() return { env.player } end }
      end
    end,
  }
  _G.REUtil = {
    GetRE = function(_, name)
      return {
        FireClient = function(_, player, value)
          env.events[#env.events + 1] = { name = name, player = player, value = value }
        end,
      }
    end,
  }
  env.save = assert(loadfile("server/Mgr/MgrSave.lua"))()
  env.players = assert(loadfile("server/Mgr/MgrPlayerData.lua"))()
  env.interact = assert(loadfile("server/Mgr/MgrInteract.lua"))()
  env.lottery = assert(loadfile("server/Mgr/MgrLottery.lua"))()
  env.players.Save, env.save.PlayerData = env.save, env.players
  env.interact.PlayerData, env.interact.Save = env.players, env.save
  env.lottery.PlayerData, env.lottery.Save, env.lottery.Interact = env.players, env.save, env.interact
  env.rolls = {}
  env.lottery.Random = function()
    local roll = table.remove(env.rolls, 1)
    assert(roll, "测试脚本 RNG 序列耗尽")
    return roll
  end
  env:join()
  env:drain()
  env.data = env.players:GetDataInst(env.player)
  env:clearEvents()

  return env
end

describe("抽奖机服务端结算（MgrLottery × MgrSave × MgrInteract）", function()
  local env
  before_each(function()
    env = newWorld()
  end)
  after_each(function()
    RandomGuard.restore()
    if env then
      env:cleanup()
      env = nil
    end
  end)

  it("test_bet_value_uses_individual_mult_and_never_cooked_price", function()
    env:givePremium("item31", 2) -- 信物虾尾：实际价值 floor(50 × 2) = 100
    env:persistReady()
    env:scriptAxes(96, 100, 5) -- 哥斯拉 / 哥斯拉 / 鳄雀鳝 → 恰两同哥斯拉 ×20
    assert.is_true(env:draw(1, 1))
    local result = env:messages("LotteryResult")[1]
    assert.same(100, result.betValue)
    assert.same(2000, result.coins)
    assert.same(2000, env.data.Data.FishCoin)
  end)

  it("test_consecutive_draws_settle_independently", function()
    -- 连续抽奖：上一次结果落定后不必关窗即可再投下一件
    env:givePremium("item7", 1.5)
    assert.is_true(env.data:AddItem("item31"))
    env:persistReady()
    env:scriptAxes(1, 22, 23)
    assert.is_true(env:draw(1, 1))
    env:scriptAxes(96, 96, 1) -- 哥斯拉两同 ×20，投注价值 50
    assert.is_true(env:draw(2, 2))
    local results = env:messages("LotteryResult")
    assert.same(2, #results)
    assert.same(1000, results[2].coins)
    assert.same(1008, env.data.Data.FishCoin)
    assert.same(0, env.data:ItemCount("item7"))
    assert.same(0, env.data:ItemCount("item31"))
  end)

  it("test_duplicate_seq_and_operation_replay_return_the_unique_result", function()
    env:givePremium("item7")
    env:persistReady()
    env:scriptAxes(1, 22, 23)
    assert.is_true(env:draw(1, 1))
    local first = env:messages("LotteryResult")[1]
    env:clearEvents()
    -- 同 seq 重发：日志未淘汰时按重放处理，回原结果、不重复结算（#123 协议）
    assert.is_true(env.lottery:Handle(env.player, { action = "Draw", slot = 1, seq = 1 }))
    env:drain()
    local seqReplay = env:messages("LotteryResult")
    assert.same(1, #seqReplay)
    assert.same(first.coins, seqReplay[1].coins)
    env:clearEvents()
    assert.is_true(env.lottery:Handle(env.player,
      { action = "Draw", slot = 1, seq = 2, operation = first.operation }))
    env:drain()
    local replayed = env:messages("LotteryResult")
    assert.same(1, #replayed)
    assert.same(first.coins, replayed[1].coins)
    assert.same(first.operation.id, replayed[1].operation.id)
    assert.same(6, env.data.Data.FishCoin) -- 不重复发奖（本用例投注价值 3 × 2 倍）
    assert.same(0, env.data:ItemCount("item7")) -- 不重复扣物
  end)

  it("test_failed_write_never_publishes_the_result", function()
    env:givePremium("item7")
    env:persistReady()
    env:scriptAxes(1, 22, 23)
    env.writeFailure = true
    assert.is_true(env:draw(1, 1))
    for _ = 1, 4 do
      env.save:Update()
      env:drain()
    end
    assert.is_nil(env.players:GetDataInst(env.player)) -- 写档重试耗尽，读写屏障关闭
    assert.same(0, env.data.Data.FishCoin)
    -- 会话关闭后 ItemCount 走 Inited 短路，直接读 Data 核对库存未被 draft 污染
    local kept = env.data.Data.Containers[ITEM_BAR][1]
    assert.is_not_nil(kept)
    assert.same("item7", kept.itemId)
    assert.same({}, env:messages("ItemBarState"))
    local result = env:messages("LotteryResult")[1]
    assert.is_false(result.ok)
  end)

  it("test_no_pair_consumes_only_the_bet", function()
    env:givePremium("item7")
    env:persistReady()
    env:scriptAxes(1, 23, 43) -- 鳄雀鳝/小白龙/蟹老板 → 无两同
    assert.is_true(env:draw(1, 1))
    local result = env:messages("LotteryResult")[1]
    assert.is_true(result.ok)
    assert.same("none", result.outcome)
    assert.is_nil(result.coins)
    assert.is_nil(result.prize)
    assert.same(0, env.data.Data.FishCoin)
    assert.is_nil(env.data.Data.Containers[ITEM_BAR][1])
  end)

  it("test_non_premium_cooked_and_grilled_token_are_rejected", function()
    env.data.Data.UpgradeLevel = 1 -- 道具栏升到 3 格，三件拒绝样本同栏摆放
    assert.is_true(env.data:AddItem("carp")) -- 普通食物
    assert.is_true(env.data:AddItem("item7", nil, 1.5)) -- 烤鱼（烤制倍率字段，#137 最小约定）
    assert.is_true(env.data:AddItem("item31"))
    -- 烤过信物：存档格位的 saved.cooked 布尔标记（同 MgrInteract 权威口径）
    env.data.Data.Containers[ITEM_BAR][3].saved = { cooked = true }
    env:persistReady()
    for slot, reason in ipairs({ "not-premium", "cooked", "cooked" }) do
      env:draw(slot, slot) -- 业务拒绝：受理与否看回包 reason（与商店/喂食同口径）
      local result = env:messages("LotteryResult")[slot]
      assert.is_false(result.ok)
      assert.same(reason, result.reason)
    end
    assert.same(1, env.data:ItemCount("carp"))
    assert.same(1, env.data:ItemCount("item7"))
    assert.same(1, env.data:ItemCount("item31"))
    assert.same(0, env.data.Data.FishCoin)
    assert.same(0, env.data:Serialize().meta.sequence)
  end)

  it("test_pair_pays_actual_bet_value_times_multiplier_and_consumes_one", function()
    env:givePremium("item7", 1.5) -- 实际价值 floor(3 × 1.5) = 4
    env:persistReady()
    env:scriptAxes(1, 22, 23) -- 鳄雀鳝 / 鳄雀鳝 / 小白龙 → 恰两同鳄雀鳝 ×2
    assert.is_true(env:draw(1, 1))
    local result = env:messages("LotteryResult")[1]
    assert.is_true(result.ok)
    assert.same("pair", result.outcome)
    assert.same(4, result.betValue)
    assert.same(2, result.multiplier)
    assert.same(8, result.coins)
    assert.same({ 1, 1, 2 }, result.axes)
    assert.same(8, env.data.Data.FishCoin)
    assert.is_nil(env.data.Data.Containers[ITEM_BAR][1])
    assert.same(0, result.coinBefore)
    assert.same(8, result.coinAfter)
  end)

  it("test_pending_window_second_handle_is_dropped_silently", function()
    -- 审查回归用例：存档 pending 窗口内的第二次 Handle 被静默丢弃（不回包）——
    -- 客户端闩锁靠超时兜底解除（见抽奖机界面用例 test_awaiting_latch_releases_on_reply_timeout）
    env:givePremium("item7")
    env:persistReady()
    env:scriptAxes(1, 22, 23)
    assert.is_true(env.lottery:Handle(env.player, { action = "Draw", slot = 1, seq = 1 }))
    -- 不 drain：第一次结算仍在存档 pending 窗口
    local before = #env.events
    assert.is_false(env.lottery:Handle(env.player, { action = "Draw", slot = 1, seq = 2 }))
    assert.same(before, #env.events) -- 静默：没有失败回包
    env:drain()
    assert.same(1, #env:messages("LotteryResult")) -- 只有第一次的回包
  end)

  it("test_range_and_bad_slot_are_rejected_without_mutation", function()
    env:givePremium("item7")
    env:persistReady()
    env:scriptAxes(1, 1, 23)
    env.player.Character.Position.x = 999 -- 不在任何抽奖机旁
    env:draw(1, 1)
    local range = env:messages("LotteryResult")[1]
    assert.is_false(range.ok)
    assert.same("range", range.reason)
    assert.same(1, env.data:ItemCount("item7"))
    env.player.Character.Position.x = 0
    for _, slot in ipairs({ 0, 100, 2, "x", 1.5 }) do
      assert.is_false(env.lottery:Handle(env.player, { action = "Draw", slot = slot, seq = 10 }))
    end
    env:drain()
    assert.same(1, env.data:ItemCount("item7"))
    assert.same(0, env.data.Data.FishCoin)
    assert.same(0, env.data:Serialize().meta.sequence)
  end)

  it("test_reconnect_recovers_the_same_result_without_double_grant", function()
    env:givePremium("item31")
    env:persistReady()
    env:scriptAxes(61, 70, 76) -- 三头鲨三同 → 加速药水回投入格
    assert.is_true(env:draw(1, 1))
    local settled = env:messages("LotteryResult")[1]
    -- 中途断线：重进读档，MgrLottery 在就绪后补推唯一结果（只展示，不再结算）
    env:join()
    env:drain()
    local restored = env.players:GetDataInst(env.player)
    env:clearEvents()
    env.lottery:OnPlayerAdded(env.player)
    local recovered = env:messages("LotteryResult")
    assert.same(1, #recovered)
    assert.is_true(recovered[1].recovered)
    assert.same(settled.axes, recovered[1].axes)
    assert.same(settled.prize, recovered[1].prize)
    assert.same(1, restored:ItemCount("item167")) -- 奖品只发过一次
    assert.same(0, restored:ItemCount("item31"))
    assert.same(0, restored.Data.FishCoin)
  end)

  it("test_state_request_entry_pushes_the_same_recovered_result", function()
    -- 客户端主动拉取（LotteryStateRequest 的处理入口）与 OnPlayerAdded 共享同一补推逻辑；
    -- 两个入口都触发时服务端可能各推一次，客户端按 operation.id 去重（见抽奖机界面用例重播用例）
    env:givePremium("item31")
    env:persistReady()
    env:scriptAxes(61, 70, 76) -- 三头鲨三同 → 加速药水回投入格
    assert.is_true(env:draw(1, 1))
    local settled = env:messages("LotteryResult")[1]
    env:join()
    env:drain()
    local restored = env.players:GetDataInst(env.player)
    env:clearEvents()
    env.lottery:PushRecovered(env.player)
    local recovered = env:messages("LotteryResult")
    assert.same(1, #recovered)
    assert.is_true(recovered[1].recovered)
    assert.same(settled.axes, recovered[1].axes)
    assert.same(settled.prize, recovered[1].prize)
    assert.same(1, restored:ItemCount("item167")) -- 只展示，不重复发奖
  end)

  it("test_triple_item_returns_to_the_freed_slot", function()
    env:givePremium("item31")
    env:persistReady()
    env:scriptAxes(61, 70, 76) -- 三头鲨三同 → 加速药水 item167 回投入格
    assert.is_true(env:draw(1, 1))
    local result = env:messages("LotteryResult")[1]
    assert.same("triple", result.outcome)
    assert.same({ kind = "item", itemId = "item167", name = "加速药水" }, result.prize)
    local entry = env.data.Data.Containers[ITEM_BAR][1]
    assert.same("item167", entry.itemId)
    assert.same(1, entry.count)
    assert.same(0, env.data.Data.FishCoin)
  end)

  it("test_triple_weapon_goes_to_weapon_inventory_without_pair_coins", function()
    env:givePremium("item7")
    env:persistReady()
    env:scriptAxes(1, 10, 22, 3) -- 鳄雀鳝三同 → 匕首组五选一第 3 件（黄金匕首 item154）
    assert.is_true(env:draw(1, 1))
    local result = env:messages("LotteryResult")[1]
    assert.same("triple", result.outcome)
    assert.same({ kind = "weapon", itemId = "item154", name = "黄金匕首" }, result.prize)
    assert.is_nil(result.coins) -- 三同不叠加两同金币
    assert.same(0, env.data.Data.FishCoin)
    assert.same(1, env.data:WeaponCount("item154"))
    assert.is_nil(env.data.Data.Containers[ITEM_BAR][1]) -- 武器不占道具格
  end)
end)

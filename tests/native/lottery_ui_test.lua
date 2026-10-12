-- 原生 Busted（#87 迁移自 tests/gameplay/lottery_ui_test.lua 的 TestScreenLottery）。
-- #138 T17 抽奖界面（client/ScreenHandlers/ScreenLottery）失败方式先列：
--   1. 投注框看错格：不用当前选中格，或烤鱼/非极品也显示可投；
--   2. 投注价值显示不含个体倍率（与服务器结算口径不一致）；
--   3. 动画决定奖项：停轴图案来自客户端本地随机而不是服务端回包 axes；
--   4. 停轴顺序错：不是左→右→中，或未到 3 秒就停；
--   5. 动画中重复点抽奖重复发请求；重播回调（同 operation.id）重播动画/重置展示；
--   6. 关窗中断动画后结果丢失；断线恢复（recovered）又播一次动画或提示语不对；
--   7. 失败原因没有对应玩家可读提示。
-- seam：直接调 handler 的 RefreshBet / Draw / NoteResult / UpdateAnim / OpenScreen / CloseScreen，
--   替换 game/REUtil/EUI 边界（与摆渡界面用例同款）；动画用 UpdateAnim(dt) 推进，不用真实计时。
-- 迁移说明：案例按旧 LuaUnit 实际执行序（方法名字典序）逐个 it 注册；
--   lu.assertStrContains(s, sub) 第 3 参省略即 plain 子串查找，映射为 assert.matches(sub, s, 1, true)；
--   旧 tearDown 用 pairs 恢复全局，原本不存在的键会被跳过（假 _G.game 泄漏到后续案例），
--   原生逐例隔离后按键名单 rawset 还回 nil，杜绝泄漏。
local RandomGuard = require("tests.support.random_guard")

local GLOBAL_KEYS = { "game", "Vector2", "Vector3", "Color", "REUtil", "LocalMsgNotice", "MgrGameUI" }
local MODULE_KEYS = {
  "common.GameCfg", "common.REUtil", "common.LotteryEligibility", "client.GameUI",
}

local function signal()
  local listeners = {}
  return {
    Connect = function(_, fn)
      listeners[#listeners + 1] = fn
      return {
        Disconnect = function()
          for i, cb in ipairs(listeners) do
            if cb == fn then
              table.remove(listeners, i)
              break
            end
          end
        end,
      }
    end,
    Fire = function(_, ...)
      for _, fn in ipairs(listeners) do
        fn(...)
      end
    end,
  }
end

--- 搭一次抽奖界面世界；调用方负责 cleanup()。
local function newWorld()
  local env = {}
  env.previous = {}
  for _, key in ipairs(GLOBAL_KEYS) do
    env.previous[key] = rawget(_G, key)
  end
  env.previousLoaded = {}
  for _, name in ipairs(MODULE_KEYS) do
    env.previousLoaded[name] = package.loaded[name]
    package.loaded[name] = nil
  end
  env.cfg = require("common.GameCfg")

  env.nodes = {}
  local world = {}
  function world:CreateUnit(kind, attrs)
    local node = { Kind = kind, OnClicked = signal(), Visible = true }
    for key, value in pairs(attrs) do
      node[key] = value
    end
    if node.Name then
      env.nodes[node.Name] = node
    end
    return node
  end
  function world:FindFirstChild()
    return nil
  end
  local root = { Name = "UIRoot", children = {} }
  function root:FindFirstChild(name)
    return self.children[name]
  end
  env.root = root
  local eui = {
    GetRootNode = function() return root end,
    GetDeviceResolution = function() return { x = 1920, y = 1080 } end,
  }
  env.localPlayer = {
    PlayerGui = { EuiManager = eui }, UserId = 7,
    GetAttribute = function() return 0 end,
  }

  env.commands, env.notices = {}, {}
  _G.LocalMsgNotice = function(msg)
    env.notices[#env.notices + 1] = msg
  end
  _G.Vector2 = { New = function(x, y) return { x = x, y = y } end }
  _G.Vector3 = { New = function(x, y, z) return { x = x, y = y, z = z } end }
  _G.Color = { New = function(...) return { ... } end }
  _G.game = {
    GetService = function(_, name)
      if name == "World" then
        return world
      end
      if name == "Players" then
        return { LocalPlayer = env.localPlayer }
      end
      if name == "RunService" then
        return {
          Heartbeat = signal(),
          IsClient = function() return true end,
          IsServer = function() return false end,
        }
      end
      if name == "Task" then
        return {
          Spawn = function(_, fn) fn() end,
          Wait = function() end,
          Delay = function() end,
        }
      end
    end,
  }
  local reStub = {
    GetRE = function(_, name)
      env.events = env.events or {}
      if not env.events[name] then
        env.events[name] = {
          OnClientEvent = signal(), OnServerEvent = signal(),
          FireServer = function(_, payload)
            env.commands[#env.commands + 1] = { name = name, payload = payload }
          end,
        }
      end
      return env.events[name]
    end,
  }
  package.loaded["common.REUtil"] = reStub
  _G.REUtil = reStub

  env.handler = assert(loadfile("client/ScreenHandlers/ScreenLottery.lua"))()
  env.handler:Start()
  -- Start 会主动拉一次断线恢复（LotteryStateRequest）；用例只关心后续交互，重置计数
  env.startCommands = env.commands
  env.commands = {}

  -- 根节点挂上 UIRoot，MgrGameUI 按名字找得到
  root.children[env.handler.RootNode.Name] = env.handler.RootNode

  -- 构造道具栏快照：selectedSlot 指向 slots 里第 slot 格
  function env:snapshot(slot, entry)
    local state = { slots = {}, slotCount = 2, coin = 0, selectedSlot = slot }
    if entry then
      state.slots[slot] = entry
    end
    self.handler:NoteItemBar(state)
    return state
  end

  function env:premiumEntry(mult, cooked)
    return { itemId = "item7", count = 1, mult = mult, cooked = cooked, containerId = "itemBar" }
  end

  function env:cleanup()
    for _, name in ipairs(MODULE_KEYS) do
      package.loaded[name] = self.previousLoaded[name]
    end
    for _, key in ipairs(GLOBAL_KEYS) do
      rawset(_G, key, self.previous[key])
    end
  end

  return env
end

-- 服务端回包样本：动画与展示只消费这里的 axes / outcome，不由客户端决定奖项。
local function result(axes, outcome, extra)
  local value = {
    ok = true, action = "Draw", slot = 1, itemId = "item7", itemName = "极品罗非鱼",
    betValue = 3, axes = axes, outcome = outcome,
    operation = { id = "7:1", sequence = 1, kind = "lottery" },
  }
  for key, val in pairs(extra or {}) do
    value[key] = val
  end
  return value
end

describe("抽奖机界面表现（ScreenLottery）", function()
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

  it("test_axis_stop_order_follows_config", function()
    -- 停轴顺序消费 GameCfg.Lottery.AxisOrder，不硬编码
    env.cfg.Lottery.AxisOrder = { "middle", "left", "right" }
    env:snapshot(1, env:premiumEntry())
    env.handler:Draw()
    env.handler:NoteResult(result({ 1, 1, 2 }, "pair", { coins = 6, multiplier = 2 }))
    env.handler:UpdateAnim(3.0) -- 第一个停的是中轴
    assert.is_true(env.handler:AxisStopped(1))
    assert.same("小白龙", env.nodes.LabelReelMiddle.Text) -- axes[3]
    assert.is_false(env.handler:AxisStopped(2))
    env.handler:UpdateAnim(0.5) -- 第二个停左轴
    assert.same("鳄雀鳝", env.nodes.LabelReelLeft.Text) -- axes[1]
    env.handler:UpdateAnim(0.5) -- 第三个停右轴
    assert.same("鳄雀鳝", env.nodes.LabelReelRight.Text) -- axes[2]
    assert.matches("6", env.nodes.LabelLotteryResult.Text, 1, true)
  end)

  it("test_bet_box_rejects_cooked_and_ordinary_and_empty", function()
    env:snapshot(1, { itemId = "carp", count = 1, containerId = "itemBar" })
    assert.is_false(env.handler:DrawEnabled())
    env:snapshot(1, env:premiumEntry(nil, 1.5)) -- 烤鱼
    assert.is_false(env.handler:DrawEnabled())
    env:snapshot(1, nil) -- 空槽
    assert.is_false(env.handler:DrawEnabled())
  end)

  it("test_bet_box_shows_selected_premium_with_actual_value", function()
    env:snapshot(1, env:premiumEntry(1.5))
    assert.matches("极品罗非鱼", env.nodes.LabelLotteryBet.Text, 1, true)
    assert.matches("4", env.nodes.LabelLotteryBet.Text, 1, true) -- floor(3 × 1.5)
    assert.is_true(env.handler:DrawEnabled())
  end)

  it("test_close_mid_animation_keeps_the_settled_result", function()
    env:snapshot(1, env:premiumEntry())
    env.handler:Draw()
    local value = result({ 4, 4, 4 }, "triple",
      { prize = { kind = "item", itemId = "item167", name = "加速药水" }, patternName = "三头鲨" })
    env.handler:NoteResult(value)
    env.handler:UpdateAnim(1) -- 动画中途
    env.handler:CloseScreen()
    assert.is_false(env.handler:IsSpinning())
    env.handler:OpenScreen()
    assert.matches("加速药水", env.nodes.LabelLotteryResult.Text, 1, true) -- 重开展示同一结果
    assert.is_false(env.handler:IsSpinning()) -- 不重播动画
  end)

  it("test_draw_sends_slot_and_seq_once_per_click", function()
    env:snapshot(1, env:premiumEntry())
    assert.is_true(env.handler:Draw())
    assert.is_false(env.handler:Draw()) -- 等待结果期间重复点击被忽略
    assert.same(1, #env.commands)
    assert.same("LotteryAction", env.commands[1].name)
    assert.same({ action = "Draw", slot = 1, seq = 1 }, env.commands[1].payload)
  end)

  it("test_failure_reasons_have_readable_notice", function()
    local reasons = { ["not-premium"] = true, cooked = true, range = true, slot = true }
    env:snapshot(1, env:premiumEntry())
    for reason in pairs(reasons) do
      env.handler:NoteResult({ ok = false, reason = reason })
    end
    assert.same(4, #env.notices)
    for _, msg in ipairs(env.notices) do
      assert.is_true(#msg > 0)
    end
  end)

  it("test_reels_stop_left_right_middle_after_spin_seconds", function()
    env:snapshot(1, env:premiumEntry())
    env.handler:Draw()
    env.handler:NoteResult(result({ 1, 1, 2 }, "pair", { coins = 6, multiplier = 2 }))
    local left, right, middle = env.nodes.LabelReelLeft, env.nodes.LabelReelRight, env.nodes.LabelReelMiddle
    env.handler:UpdateAnim(2.9)
    assert.is_false(env.handler:AxisStopped(1))
    env.handler:UpdateAnim(0.1) -- t = 3.0 停左轴
    assert.is_true(env.handler:AxisStopped(1))
    assert.same("鳄雀鳝", left.Text)
    assert.is_false(env.handler:AxisStopped(2))
    env.handler:UpdateAnim(0.5) -- t = 3.5 停右轴
    assert.same("鳄雀鳝", right.Text)
    assert.is_false(env.handler:AxisStopped(3))
    env.handler:UpdateAnim(0.5) -- t = 4.0 停中轴
    assert.same("小白龙", middle.Text)
    assert.matches("6", env.nodes.LabelLotteryResult.Text, 1, true) -- 金币 +6
    assert.is_true(env.handler:DrawEnabled()) -- 结果落定后可继续抽下一件
  end)

  it("test_replay_callback_does_not_restart_animation_or_result", function()
    env:snapshot(1, env:premiumEntry())
    env.handler:Draw()
    local value = result({ 1, 1, 2 }, "pair", { coins = 6, multiplier = 2 })
    env.handler:NoteResult(value)
    env.handler:UpdateAnim(3.0)
    local leftText = env.nodes.LabelReelLeft.Text
    env.handler:NoteResult(value) -- 同 operation.id 重播
    assert.same(1, env.handler.AnimationStarts)
    assert.same(leftText, env.nodes.LabelReelLeft.Text)
    assert.is_true(env.handler:AxisStopped(1))
  end)

  it("test_recovered_result_shows_without_animation", function()
    env:snapshot(1, env:premiumEntry())
    local value = result({ 4, 4, 4 }, "triple",
      { prize = { kind = "item", itemId = "item167", name = "加速药水" }, patternName = "三头鲨" })
    value.recovered = true
    env.handler:NoteResult(value)
    assert.is_false(env.handler:IsSpinning())
    assert.matches("加速药水", env.nodes.LabelLotteryResult.Text, 1, true)
    assert.same("三头鲨", env.nodes.LabelReelLeft.Text) -- 三轴直接落到结果图案
  end)

  it("test_start_requests_recovered_state_once", function()
    -- Start 连上 LotteryResult 回包通道后主动拉一次断线恢复（服务端补推可能早于客户端连接丢失）
    assert.same(1, #env.startCommands)
    assert.same("LotteryStateRequest", env.startCommands[1].name)
  end)

  it("test_triple_shows_jackpot_text_without_coins", function()
    env:snapshot(1, env:premiumEntry())
    env.handler:Draw()
    env.handler:NoteResult(result({ 4, 4, 4 }, "triple",
      { prize = { kind = "item", itemId = "item167", name = "加速药水" }, patternName = "三头鲨" }))
    for _ = 1, 9 do
      env.handler:UpdateAnim(0.5)
    end
    assert.matches("恭喜获得", env.nodes.LabelLotteryResult.Text, 1, true)
    assert.matches("加速药水", env.nodes.LabelLotteryResult.Text, 1, true)
    assert.matches("三头鲨", env.nodes.LabelLotteryResult.Text, 1, true)
  end)

  it("test_awaiting_latch_releases_on_reply_timeout", function()
    -- 审查回归：服务端限频（CheckRECD）与存档 pending 窗口（resolve 返回 nil）都静默丢弃不回包，
    -- Awaiting 闩锁必须有超时兜底，否则界面永久卡死
    env:snapshot(1, env:premiumEntry())
    assert.is_true(env.handler:Draw())
    assert.is_false(env.handler:DrawEnabled())
    assert.is_false(env.handler:Draw()) -- 等待期间重复点击被忽略
    local timeout = env.cfg.Lottery.ResultTimeoutSec
    assert.is_true(timeout and timeout > 0)
    env.handler:UpdateAnim(timeout - 0.1) -- 未到超时仍锁
    assert.is_false(env.handler:DrawEnabled())
    env.handler:UpdateAnim(0.2) -- 越过超时：解锁并提示
    assert.is_true(env.handler:DrawEnabled())
    assert.is_true(#env.notices > 0)
    -- 解锁后能正常再抽（服务端对重发有序号/幂等保护）
    assert.is_true(env.handler:Draw())
  end)
end)

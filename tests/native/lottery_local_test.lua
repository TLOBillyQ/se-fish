-- 原生 Busted（#87 迁移自 tests/gameplay/lottery_local_test.lua 的 TestLocalLottery）。
-- #138 T17 抽奖机入口（client/LocalLottery）失败方式先列：
--   1. 锚点缺失（编辑器还没摆 Z*_Lottery）直接报错中断，而不是只记日志；
--   2. 距离判定错轴（把 y 算进去）或错半径，气泡该显不显；
--   3. 点击气泡不开屏或开错屏；离开所有抽奖机范围不关窗；
--   4. 每次 Update 都重写 Visible（应只在状态变化时写，避免每帧刷节点）。
-- seam：直接调 LocalLottery 的 Start / Update / CreateBubble，替换 game / REUtil / Util /
--   GameUI / MgrGameUI 边界；锚点用假单位，距离用假 LocalPlayer.Character.Position。
-- 迁移说明：案例按旧 LuaUnit 实际执行序（方法名字典序）逐个 it 注册；
--   旧 tearDown 用 pairs 恢复全局，原本为 nil 的键会被跳过（留下假 world），
--   原生逐例隔离后必须显式还回 nil，否则假 _G.game 会泄漏到后续案例。
local GameCfg = require("common.GameCfg")
local RandomGuard = require("tests.support.random_guard")

local GLOBAL_KEYS = { "game", "Vector2", "Vector3", "Color", "REUtil", "GameUI", "MgrGameUI", "print" }

local function signal()
  local listeners = {}
  return {
    Connect = function(_, fn)
      listeners[#listeners + 1] = fn
      return { Disconnect = function() end }
    end,
    Fire = function(_, ...)
      for _, fn in ipairs(listeners) do
        fn(...)
      end
    end,
  }
end

--- 搭一个客户端抽奖机入口的假世界；调用方负责 teardown()。
local function newWorld()
  local env = { nodes = {}, prints = {}, anchors = {}, screens = { open = {}, closed = {}, isOpen = {} } }

  env.previous = {}
  for _, key in ipairs(GLOBAL_KEYS) do
    env.previous[key] = rawget(_G, key)
  end
  env.previousLoaded = {
    util = package.loaded["common.Util"],
    module = package.loaded["client.LocalLottery"],
  }

  package.loaded["common.Util"] = {
    WaitForChild = function(_, _, name)
      return env.anchors[name]
    end,
  }

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
  env.heartbeat = signal()
  env.character = { Position = { x = 0, y = 0, z = 0 } }
  _G.game = {
    GetService = function(_, name)
      if name == "World" then
        return world
      end
      if name == "Players" then
        return { LocalPlayer = { Character = env.character } }
      end
      if name == "RunService" then
        return { Heartbeat = env.heartbeat }
      end
      if name == "Task" then
        return { Spawn = function(_, fn) fn() end, Wait = function() end }
      end
    end,
  }
  _G.Vector2 = { New = function(x, y) return { x = x, y = y } end }
  _G.Vector3 = { New = function(x, y, z) return { x = x, y = y, z = z } end }
  _G.Color = { New = function(...) return { ... } end }
  _G.REUtil = {
    GetRE = function(_, name)
      return { OnClientEvent = signal(), FireServer = function() end }
    end,
  }
  _G.GameUI = {
    CreateSceneNode = function(_, _, anchor)
      return {
        Name = "BubbleNode", Visible = true, Anchor = anchor,
        FindFirstChild = function() return nil end,
      }
    end,
    GetEuiManager = function()
      return {}
    end,
  }
  _G.MgrGameUI = {
    OpenScreen = function(_, name)
      env.screens.open[#env.screens.open + 1] = name
      env.screens.isOpen[name] = true
    end,
    CloseScreen = function(_, name)
      env.screens.closed[#env.screens.closed + 1] = name
      env.screens.isOpen[name] = false
    end,
    IsScreenOpen = function(_, name)
      return env.screens.isOpen[name] == true
    end,
  }

  _G.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do
      parts[#parts + 1] = tostring(select(i, ...))
    end
    env.prints[#env.prints + 1] = table.concat(parts, "\t")
  end

  env.localLottery = assert(loadfile("client/LocalLottery.lua"))()

  function env:anchor(name, x, z)
    self.anchors[name] = { Name = name, Position = { x = x, y = 5, z = z } }
    return self.anchors[name]
  end

  function env:teardown()
    -- 逐个键原样还回，包括原本不存在的（rawget 得到 nil）。
    for _, key in ipairs(GLOBAL_KEYS) do
      rawset(_G, key, self.previous[key])
    end
    package.loaded["common.Util"] = self.previousLoaded.util
    package.loaded["client.LocalLottery"] = self.previousLoaded.module
  end

  return env
end

describe("抽奖机入口表现（client/LocalLottery）", function()
  local env
  before_each(function()
    env = newWorld()
  end)
  after_each(function()
    RandomGuard.restore()
    if env then
      env:teardown()
      env = nil
    end
  end)

  it("test_bubble_per_anchor_and_missing_anchor_only_logs", function()
    local names = GameCfg.Lottery.MachineAnchors()
    assert.is_true(#names >= 1)
    env:anchor(names[1], 0, 0) -- 只摆第一台，其余锚点缺失
    env.localLottery:Start()
    assert.same(1, #env.localLottery.Bubbles)
    local logged = false
    for _, line in ipairs(env.prints) do
      if line:find("LocalLottery") then
        logged = true
        break
      end
    end
    assert.is_true(logged) -- 缺失锚点只记日志
  end)

  it("test_bubble_shows_within_radius_and_hides_outside", function()
    local names = GameCfg.Lottery.MachineAnchors()
    env:anchor(names[1], 0, 0)
    env.localLottery:Start()
    local bubble = env.localLottery.Bubbles[1]
    local radius = GameCfg.Lottery.Radius
    env.character.Position.x = radius + 1
    env.localLottery:Update()
    assert.is_false(bubble.Node.Visible)
    env.character.Position.x = radius - 1
    env.localLottery:Update()
    assert.is_true(bubble.Node.Visible)
    -- y 不参与距离判定：抬高角色不影响显隐
    env.character.Position.y = 999
    env.localLottery:Update()
    assert.is_true(bubble.Node.Visible)
  end)

  it("test_click_opens_screen_and_leaving_range_closes_it", function()
    local names = GameCfg.Lottery.MachineAnchors()
    env:anchor(names[1], 0, 0)
    env.localLottery:Start()
    env.localLottery:Update()
    assert.is_true(env.localLottery.Bubbles[1].Near)
    env.localLottery:Open()
    assert.same({ "ScreenLottery" }, env.screens.open)
    env.character.Position.x = 999
    env.localLottery:Update()
    assert.same({ "ScreenLottery" }, env.screens.closed)
  end)

  it("test_update_does_not_touch_visibility_without_state_change", function()
    local names = GameCfg.Lottery.MachineAnchors()
    env:anchor(names[1], 0, 0)
    env.localLottery:Start()
    local bubble = env.localLottery.Bubbles[1]
    -- 状态未变化时重复 Update 幂等：Near 与 Visible 都保持
    env.character.Position.x = 1
    env.localLottery:Update()
    assert.is_true(bubble.Near)
    local visible = bubble.Node.Visible
    env.localLottery:Update()
    env.localLottery:Update()
    assert.is_true(bubble.Near)
    assert.same(visible, bubble.Node.Visible)
  end)
end)

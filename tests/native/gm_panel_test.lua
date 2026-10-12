-- 迁移自 tests/gameplay/gm_panel_test.lua（#91）。
-- 运行时 GM 面板：分页选鱼、服务端反馈与重建清理。
-- seam：替换 game / Vector2 / Color / client.GameUI / common.REUtil 边界，直接驱动 ScreenGM 的节点事件与 RE 回包。
-- 说明：_G.Color / _G.Vector2 由本夹具显式打桩并在 after_each 还原（原生逐例隔离后不能蹭别处残留全局）。
-- it 名字沿用旧方法名，注册顺序 = LuaUnit sortedPairs 的实际执行顺序。

local GameCfg = require('common.GameCfg')

local globalNames = { 'game', 'Vector2', 'Color' }
local moduleNames = { 'client.GameUI', 'common.REUtil' }

local function signal()
  local listeners = {}
  return {
    Connect = function(_, fn)
      listeners[#listeners + 1] = fn
      return { Disconnect = function()
        for index, callback in ipairs(listeners) do
          if callback == fn then table.remove(listeners, index) break end
        end
      end }
    end,
    Fire = function(_, ...) for _, fn in ipairs(listeners) do fn(...) end end,
    Count = function() return #listeners end,
  }
end

describe('GM 面板（ScreenGM）', function()
  local env
  local restore

  before_each(function()
    -- 快照先于任何改动：夹具中途失败时 after_each 仍能还原已改项。
    restore = { Debug = GameCfg.Debug }
    for _, name in ipairs(globalNames) do
      restore[name] = rawget(_G, name)
    end
    for _, name in ipairs(moduleNames) do
      restore[name] = package.loaded[name]
    end
    GameCfg.Debug = { Enabled = true, InitialGrants = restore.Debug.InitialGrants }
    env = { nodes = {}, requests = {}, events = {}, root = {} }
    local world = { CreateUnit = function(_, kind, props)
      local node = { Kind = kind, OnClicked = signal(), OnDetach = signal(), Destroy = function() end }
      for key, value in pairs(props) do node[key] = value end
      env.nodes[node.Name] = node
      return node
    end }
    rawset(_G, 'game', { GetService = function(_, name)
      if name == 'World' then return world end
      if name == 'Players' then return { LocalPlayer = { UserId = 1 } } end
    end })
    rawset(_G, 'Vector2', { New = function(x, y) return { x = x, y = y } end })
    rawset(_G, 'Color', { New = function(...) return { ... } end })
    package.loaded['client.GameUI'] = { GetEuiManager = function() return {
      GetRootNode = function() return env.root end,
      GetDeviceResolution = function() return { x = 1920, y = 1080 } end,
    } end }
    package.loaded['common.REUtil'] = { GetRE = function(_, name)
      if not env.events[name] then
        env.events[name] = {
          OnClientEvent = signal(),
          FireServer = function(_, payload)
            if name == 'GMAction' then env.requests[#env.requests + 1] = payload end
          end,
        }
      end
      return env.events[name]
    end }
    env.panel = assert(loadfile('client/ScreenHandlers/ScreenGM.lua'))()
    env.panel:Start()
  end)

  after_each(function()
    -- 顺序与旧 tearDown 一致：先送走面板（断连接），再还原配置与模块缓存，最后还原全局。
    if env and env.panel then
      env.panel:Destroy()
    end
    if restore then
      GameCfg.Debug = restore.Debug
      for _, name in ipairs(moduleNames) do
        package.loaded[name] = restore[name]
      end
      for _, name in ipairs(globalNames) do
        rawset(_G, name, restore[name])
      end
    end
    env = nil
    restore = nil
  end)

  it('test_fish_page_selects_id_and_displays_server_result', function()
    assert.is_true(env.panel.Started)
    env.nodes['GM入口'].OnClicked:Fire()
    assert.is_true(env.panel.IsOpen)
    assert.same(GameCfg.Fish.eel.Name, env.nodes['GM操作文字_下一条鱼1'].Text)
    env.nodes['GM操作_下一条鱼1'].OnClicked:Fire()
    assert.same({ action = 'NextFish', fishId = 'eel' }, env.requests[#env.requests])
    env.events.GMResult.OnClientEvent:Fire({ action = 'NextFish', ok = true, target = 1 })
    assert.matches('已设置', env.panel.Feedback.Text, 1, true)
    env.nodes['GM操作_下一条鱼8'].OnClicked:Fire()
    assert.same(2, env.panel.FishPage)
    local label = env.nodes['GM操作文字_下一条鱼1'].Text
    local fishId
    for id, fish in pairs(GameCfg.Fish) do
      if fish.Name == label then fishId = id break end
    end
    assert.is_not_nil(fishId)
    env.nodes['GM操作_下一条鱼1'].OnClicked:Fire()
    assert.same(fishId, env.requests[#env.requests].fishId)
    env.nodes['GM操作_下一条鱼7'].OnClicked:Fire()
    assert.same(1, env.panel.FishPage)
    env.events.GMResult.OnClientEvent:Fire({ action = 'NextFish', ok = false, reason = '调试开关已关闭' })
    assert.matches('调试开关已关闭', env.panel.Feedback.Text, 1, true)
  end)

  it('test_page_bounds_and_existing_buttons', function()
    env.nodes['GM操作_下一条鱼7'].OnClicked:Fire()
    assert.same(1, env.panel.FishPage)
    for _ = 1, 20 do env.nodes['GM操作_下一条鱼8'].OnClicked:Fire() end
    assert.same(math.ceil((function()
      local count = 0
      for _ in pairs(GameCfg.Fish) do count = count + 1 end
      return count
    end)() / 6), env.panel.FishPage)
    env.nodes['GM入口'].OnClicked:Fire()
    local lastPageSlots = (function()
      local count = 0
      for _ in pairs(GameCfg.Fish) do count = count + 1 end
      return (count - 1) % 6 + 1
    end)()
    for index = 1, 6 do
      assert.same(index <= lastPageSlots, env.nodes['GM操作_下一条鱼' .. index].Visible)
      assert.same(index <= lastPageSlots, env.nodes['GM操作文字_下一条鱼' .. index].Visible)
    end
    env.nodes['GM入口'].OnClicked:Fire()
    env.nodes['GM入口'].OnClicked:Fire()
    for index = lastPageSlots + 1, 6 do
      assert.is_false(env.nodes['GM操作_下一条鱼' .. index].Visible)
    end
    env.nodes['GM操作_下一条鱼7'].OnClicked:Fire()
    for index = 1, 6 do
      assert.is_true(env.nodes['GM操作_下一条鱼' .. index].Visible)
      assert.is_true(env.nodes['GM操作文字_下一条鱼' .. index].Visible)
    end
    env.nodes['GM操作_金币1'].OnClicked:Fire()
    assert.same({ action = 'Coin', amount = 100 }, env.requests[#env.requests])
  end)

  it('test_state_fields_show_current_values_and_edited_slot', function()
    env.nodes['GM入口'].OnClicked:Fire()
    env.nodes['GM操作_状态与存档1'].OnClicked:Fire()
    env.events.GMResult.OnClientEvent:Fire({ action = 'GetState', ok = true,
      status = { currentSlot = '', nextSlot = 'qa115', autosavePaused = false },
      snapshot = { coin = 17, upgradeLevel = 0, slotCount = 2, backpackCount = 5,
        slots = { [1] = { itemId = 'starterRod', count = 1 } },
        backpack = { [1] = { itemId = 'tilapia', count = 1, mult = 1.5 } } } })
    assert.matches('当前 17', env.nodes['GM字段名_coin'].Text, 1, true)
    assert.matches('当前 0', env.nodes['GM字段名_upgradeLevel'].Text, 1, true)
    assert.matches('qa115', env.nodes['GM字段名_slot'].Text, 1, true)
    assert.same('EUIImage', env.nodes['GM输入背景_coin'].Kind)
    env.panel.Fields.container.Text = 'backpack'
    env.panel.Fields.index.Text = '1'
    env.panel.Fields.index.OnDetach:Fire('1')
    assert.matches('罗非鱼', env.nodes['GM字段名_itemId'].Text, 1, true)
    assert.matches('1.5', env.nodes['GM字段名_mult'].Text, 1, true)
  end)

  it('test_state_page_acknowledges_refresh_and_apply', function()
    env.nodes['GM入口'].OnClicked:Fire()
    env.nodes['GM操作_状态与存档1'].OnClicked:Fire()
    assert.same({ action = 'GetState' }, env.requests[#env.requests])
    assert.same('等待服务端确认…', env.panel.Feedback.Text)
    env.events.GMResult.OnClientEvent:Fire({ action = 'GetState', ok = true,
      status = { currentSlot = '', nextSlot = '', autosavePaused = false } })
    assert.matches('状态已同步', env.panel.Feedback.Text, 1, true)
    env.panel.Fields.coin.Text = '0'
    env.nodes['GM应用'].OnClicked:Fire()
    assert.same({ action = 'ApplyState', coin = 0 }, env.requests[#env.requests])
    env.events.GMResult.OnClientEvent:Fire({ action = 'ApplyState', ok = true,
      status = { currentSlot = '', nextSlot = '', autosavePaused = true } })
    assert.matches('已应用到本局', env.panel.Feedback.Text, 1, true)
  end)
end)

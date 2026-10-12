-- 原生 Busted（#87 迁移自 tests/gameplay/compendium_test.lua 的 TestCompendium）。
-- #133 图鉴写入基础。失败方式（先列后写）：
--   1. 上岸不写，或同一次上岸（重放 / 写档重试 / 断线重连）被记成两次；
--   2. 更小的个体重量覆盖个人最大重量；条目、次数与总次数对不上；
--   3. 击杀与三份掉落混进钓取纪录；盲盒/抽奖字段被图鉴写入改动；
--   4. 只写内存不落存档，重进后图鉴丢失；
--   5. 写档忙或存档不可用时伪造记录，或把这条上岸直接吞掉。
-- seam：真实 MgrSave 协议 + 真实 PlayerData 迁移，只替换 Task/DataStore 引擎边界。
-- 迁移说明：案例按旧 LuaUnit 实际执行序（方法名字典序）逐个 it 注册；
--   旧套件只快照 _G.game，中途换掉的 _G.REUtil 靠测试体手工还原，一旦断言先失败就会泄漏，
--   原生侧在夹具里一并快照/还原 _G.REUtil（逐案例清理，语义不变）。
local GameCfg = require("common.GameCfg")
local PlayerData = require("server.Data.PlayerData")
local RandomGuard = require("tests.support.random_guard")

local function read(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local text = file:read("*a")
  file:close()
  return text
end

--- 搭一次图鉴写入世界；调用方负责 cleanup()。
local function newWorld()
  local env = {}
  env.oldGame, env.oldRE = _G.game, _G.REUtil
  env.values, env.queue, env.datas = {}, {}, {}
  env.store = {
    GetAsync = function(_, key)
      return env.values[key]
    end,
    UpdateAsync = function(_, key, transform)
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
        return { GetServerTime = function() return 100 end }
      end
      if name == "Players" then
        return { GetPlayers = function() return {} end }
      end
    end,
  }
  env.save = assert(loadfile("server/Mgr/MgrSave.lua"))()
  env.comp = assert(loadfile("server/Mgr/MgrCompendium.lua"))()
  env.comp.Save = env.save
  env.comp.PlayerData = {
    GetDataInst = function(_, player)
      return env.datas[player.UserId]
    end,
  }

  function env:drain()
    while #self.queue > 0 do
      table.remove(self.queue, 1)()
    end
  end

  function env:join(id)
    local player = { UserId = id, SetAttribute = function() end }
    local data = PlayerData.New(player)
    data:Init(true)
    self.datas[id] = data
    self.save:LoadInto(player, data)
    self:drain()
    assert.same("ready", data.LoadState)
    return player, data
  end

  function env:cleanup()
    _G.game = self.oldGame
    _G.REUtil = self.oldRE
  end

  return env
end

describe("图鉴写入（MgrCompendium × MgrSave × PlayerData）", function()
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

  it("test_blindbox_state_stays_separate", function()
    local player, data = env:join(37)
    data.Extra.lottery.pity = 3
    env.comp:RecordLanding(player, { fishId = "goldfish", mult = 2, reelSerial = 1 })
    env:drain()
    assert.same(3, data.Extra.lottery.pity)
    local view = env.comp:Snapshot(player)
    assert.same(1, view.total)
    assert.is_nil(view.catches.lottery)
  end)

  it("test_duplicate_event_is_recorded_once", function()
    local player, data = env:join(31)
    env.comp:RecordLanding(player, { fishId = "goldfish", mult = 2, reelSerial = 5 })
    env:drain()
    local queue = env.comp.Queues[player.UserId]
    assert.is_false(env.comp:RecordLanding(player, { fishId = "goldfish", mult = 2, reelSerial = 5 }))
    assert.same("replay", select(2, env.comp:RecordLanding(player,
      { fishId = "goldfish", mult = 2, reelSerial = 5 })))
    assert.same({}, queue.events)
    env.comp:Update()
    env:drain()
    local view = env.comp:Snapshot(player)
    assert.same({ goldfish = 1 }, view.catches)
    assert.same({ goldfish = 0.2 }, view.weights)
    assert.same(1, view.total)
    assert.same(1, #data:Serialize().meta.operations)
  end)

  it("test_every_species_gets_its_own_entry", function()
    local player = env:join(33)
    local serial = 0
    for fishId in pairs(GameCfg.Fish) do
      serial = serial + 1
      assert.is_true(env.comp:RecordLanding(player, { fishId = fishId, mult = 1, reelSerial = serial }))
      env:drain()
    end
    local view = env.comp:Snapshot(player)
    assert.same(98, view.total)
    local entries = 0
    for fishId, unlocked in pairs(view.unlocked) do
      entries = entries + 1
      assert.is_true(unlocked, fishId)
      assert.same(1, view.catches[fishId], fishId)
      assert.is_not_nil(GameCfg.Fish[fishId])
      assert.is_true(view.weights[fishId] > 0, fishId)
    end
    assert.same(98, entries)
  end)

  it("test_first_landing_unlocks_entry_and_sets_personal_best", function()
    local player = env:join(30)
    assert.is_true(env.comp:RecordLanding(player, { fishId = "goldfish", mult = 1.15, reelSerial = 1 }))
    env:drain()
    local view = env.comp:Snapshot(player)
    assert.same(true, view.unlocked.goldfish)
    assert.same(1, view.catches.goldfish)
    assert.same(0.12, view.weights.goldfish)
    assert.same(1, view.total)
    assert.is_nil(view.unlocked.bass)
  end)

  it("test_kills_and_drops_never_enter_the_compendium", function()
    -- 击杀与三份掉落是 MgrLoot 的事：图鉴只有 RecordLanding 这一个写入口
    for _, path in ipairs({ "server/Mgr/MgrFishUnit.lua", "server/Mgr/MgrLoot.lua" }) do
      assert.is_not_nil(read(path), path)
      assert.is_nil(read(path):find("Compendium", 1, true), path)
    end
  end)

  it("test_personal_best_only_grows", function()
    local player = env:join(32)
    env.comp:RecordLanding(player, { fishId = "goldfish", mult = 2, reelSerial = 1 })
    env:drain()
    env.comp:RecordLanding(player, { fishId = "goldfish", mult = 1.15, reelSerial = 2 })
    env:drain()
    local view = env.comp:Snapshot(player)
    assert.same(0.2, view.weights.goldfish)
    assert.same(2, view.catches.goldfish)
    assert.same(2, view.total)
  end)

  it("test_pond_rare_max_weight_per_id_survives_rejoin", function()
    -- #134 鱼塘极品六条：各自一条个人最大重量，只增不减、重进保留，不与同名普通鱼混账
    --   （失败方式 6. 极品按普通鱼 ID 记账或被较小重量覆盖；7. 极品重量不落存档）
    local player = env:join(38)
    local ids = { "item7", "item8", "item9", "item10", "item11", "item12" }
    local serial = 0
    for _, fishId in ipairs(ids) do
      for _, mult in ipairs({ 1.9, 1.2 }) do
        serial = serial + 1
        assert.is_true(env.comp:RecordLanding(player, { fishId = fishId, mult = mult, reelSerial = serial }))
        env:drain()
      end
    end
    local rejoined = env:join(38)
    local view = env.comp:Snapshot(rejoined)
    assert.same(12, view.total)
    for _, fishId in ipairs(ids) do
      assert.same(2, view.catches[fishId], fishId)
      assert.same(env.comp:Weight(fishId, 1.9), view.weights[fishId], fishId)
    end
    assert.same(0.19, view.weights.item12)
    assert.same(3.8, view.weights.item10)
    assert.is_nil(view.weights.goldfish)
    assert.is_nil(view.weights.catfish)
  end)

  it("test_readonly_request_reports_ready_collection_and_local_completion", function()
    -- #39 失败方式：未加载存档伪装成空图鉴；快照泄漏权威表；盲盒虚构重量；
    -- 本地通关依赖平台 ID；重复请求写档；离场请求状态未清理。
    -- 接缝：MgrCompendium 的公开请求与 Snapshot，真实 PlayerData/MgrSave。
    local player, data = env:join(39)
    data.Extra.collection.unlocked.item7 = true -- 已保存的盲盒收集，不经过上岸入口
    data.Extra.achievements.final = true
    local packets = {}
    local previous = _G.REUtil
    _G.REUtil = {
      GetRE = function(_, name)
        assert.same("CompendiumState", name)
        return {
          FireClient = function(_, target, value)
            assert.same(player, target)
            packets[#packets + 1] = value
          end,
        }
      end,
    }
    env.comp:Handle(player, { seq = 1 })
    env.comp:Handle(player, { seq = 1 })
    _G.REUtil = previous
    assert.same(1, #packets)
    assert.same("ready", packets[1].state)
    assert.is_true(packets[1].completed)
    assert.is_true(packets[1].unlocked.item7)
    assert.is_nil(packets[1].weights.item7)
    assert.is_nil(packets[1].catches.item7)
    packets[1].unlocked.item7 = false
    assert.is_true(env.comp:Snapshot(player).unlocked.item7)
    assert.same(0, #data:Serialize().meta.operations)
  end)

  it("test_records_survive_rejoin", function()
    local player = env:join(34)
    env.comp:RecordLanding(player, { fishId = "goldfish", mult = 2, reelSerial = 1 })
    env:drain()
    local rejoined = env:join(34)
    local view = env.comp:Snapshot(rejoined)
    assert.same(true, view.unlocked.goldfish)
    assert.same(0.2, view.weights.goldfish)
    assert.same(1, view.catches.goldfish)
    assert.same(1, view.total)
    env.comp:RecordLanding(rejoined, { fishId = "goldfish", mult = 1.15, reelSerial = 2 })
    env:drain()
    view = env.comp:Snapshot(rejoined)
    assert.same(2, view.catches.goldfish)
    assert.same(0.2, view.weights.goldfish)
  end)

  it("test_unavailable_save_never_fakes_a_record", function()
    local player = env:join(36)
    env.save.Sessions[player.UserId].State = "failed"
    assert.is_false(env.comp:RecordLanding(player, { fishId = "goldfish", mult = 2, reelSerial = 1 }))
    env:drain()
    env.comp:Update()
    env:drain()
    assert.same(0, env.comp:Snapshot(player).total)
    assert.is_nil(env.values.u36.extra.collection.weights.goldfish)
    assert.same({}, env.comp.Queues[player.UserId].events)
  end)

  it("test_unready_collection_never_presents_default_data_as_saved_progress", function()
    local player, data = env:join(40)
    data.LoadState = "loading"
    assert.same("loading", env.comp:Snapshot(player).state)
    data.LoadState = "failed"
    data.Extra.achievements.final = true
    local state = env.comp:Snapshot(player)
    assert.same("unavailable", state.state)
    assert.is_nil(state.completed)
  end)

  it("test_write_in_flight_defers_instead_of_dropping", function()
    local player, data = env:join(35)
    local operation = env.save:NextOperation(player, "other")
    assert.is_true(env.save:Execute(player, data, operation, function(draft)
      draft:AddCoin(1)
      return { ok = true }
    end, function() end))
    assert.is_true(env.comp:RecordLanding(player, { fishId = "goldfish", mult = 2, reelSerial = 1 }))
    assert.same(0, env.comp:Snapshot(player).total)
    env:drain()
    assert.same(0, env.comp:Snapshot(player).total)
    env.comp:Update()
    env:drain()
    local view = env.comp:Snapshot(player)
    assert.same(1, view.total)
    assert.same(1, view.catches.goldfish)
    assert.same(0.2, view.weights.goldfish)
    assert.same(2, #data:Serialize().meta.operations)
  end)
end)

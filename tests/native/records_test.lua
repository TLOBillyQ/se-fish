-- 原生 Busted（#87 迁移自 tests/gameplay/records_test.lua 的 TestRecordsCore / TestRecordsService /
-- TestRecordsIntegration）。
-- #149 T28 全服纪录。失败方式（先列后写）：
--   1. 重量两位小数被截成整数或写成浮点，放大/还原不对称，误差随写入放大；
--   2. 更小的重量覆盖了更大纪录；同重量两次请求按到达顺序抖动，跨服竞态下谁保持不确定；
--   3. 重量与保持者错配：重量更新了名字还是旧的，或纪录只有重量没有身份；
--   4. 盲盒/抽奖解锁一条鱼也提交纪录；
--   5. 平台失败/限流时把「读不到」当成「没有纪录」，或显示上一次的错值冒充当前值；
--   6. 延迟重试把过期候选盖到更新的纪录上；写频随上岸次数线性增长。
--   7. 平台字符串身份被拒收，读回丢失类型或混合历史数字身份时决胜报错；
--   8. 不同字符串玩家的查询序号/存档串扰，客户端伪造身份或重量污染权威纪录。
-- seam：common/Records 纯逻辑 + MgrRecords 公共接口（注入内存假适配器替换平台边界）+ 客户端数据通道。
-- 迁移说明：三个旧类按 LuaUnit 实际执行序（类名字典序 Core → Integration → Service，
--   类内方法字典序）注册为三个 describe / 逐个 it；lu.assertNotEquals 是深不等，映射为 assert.are_not.same。
local GameCfg = require("common.GameCfg")
local Records = require("common.Records")
local PlayerData = require("server.Data.PlayerData")
local RandomGuard = require("tests.support.random_guard")

local function readSource(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local text = file:read("*a")
  file:close()
  return text
end

describe("全服纪录纯逻辑（common/Records）", function()
  after_each(RandomGuard.restore)

  it("test_entry_keeps_weight_and_holder_together", function()
    -- 身份与重量写在同一条记录里：读回时要么两者都在，要么整条不算纪录
    local entry = Records.Entry(1234, 42, "张三")
    assert.same({ w = 1234, u = 42, n = "张三" }, entry)
    assert.is_nil(Records.Valid({ w = 1234 }))
    assert.is_nil(Records.Valid({ u = 42, n = "张三" }))
    assert.same({ w = 1234, u = "42" }, Records.Valid({ w = 1234, u = "42" }))
    assert.is_nil(Records.Valid("1234"))
    -- 名字超长只降级名字（退兜底），不整条丢掉重量与身份
    local longName = Records.Valid({ w = 1234, u = 42, n = string.rep("x", 200) })
    assert.same({ w = 1234, u = 42, n = nil }, longName)
    local nameless = Records.Valid({ w = 1234, u = 42 })
    assert.is_nil(nameless.n)
    assert.same("玩家42", Records.Holder(nameless), "显示名缺失退成玩家ID，不拿 ID 冒充名字")
    assert.same("张三", Records.Holder(Records.Entry(1234, 42, "张三")))
  end)

  it("test_equal_weight_tiebreak_is_order_independent", function()
    local a = Records.Entry(300, 5, "甲")
    local b = Records.Entry(300, 3, "乙")
    local first = Records.Wins(a, nil) and a or nil
    if Records.Wins(b, first) then
      first = b
    end
    local second = Records.Wins(b, nil) and b or nil
    if Records.Wins(a, second) then
      second = a
    end
    assert.same(3, first.u, "先到 5 后到 3 与先到 3 后到 5 结果必须一致")
    assert.same(first, second)
    assert.same("乙", first.n)
  end)

  it("test_heavier_wins_and_lighter_never_overwrites", function()
    -- 决胜：更大者胜；同重量按 UserID 升序（小者保持）；与到达顺序无关
    local held = Records.Entry(200, 7, "甲")
    assert.is_true(Records.Wins(Records.Entry(201, 9, "乙"), held))
    assert.is_false(Records.Wins(Records.Entry(199, 1, "丙"), held))
    assert.is_false(Records.Wins(Records.Entry(200, 7, "甲"), held))
    assert.is_true(Records.Wins(Records.Entry(200, 7, "甲"), nil))
    assert.is_true(Records.Wins(Records.Entry(200, 7, "甲"), { w = "x" }))
  end)

  it("test_illegal_and_overflow_weights_are_rejected", function()
    -- 非法值不猜：非数字、非正、NaN、无穷与超越上限都拒绝，绝不四舍五入成假纪录
    for _, bad in ipairs({ nil, "x", {}, true, 0, -1, 0 / 0, math.huge, -math.huge }) do
      local scaled, reason = Records.Scale(bad)
      assert.is_nil(scaled, tostring(bad))
      assert.same("invalid", reason, tostring(bad))
    end
    local over = GameCfg.Records.MaxScaled / GameCfg.Records.Scale + 1
    assert.is_nil(Records.Scale(over))
    assert.same("overflow", select(2, Records.Scale(over)))
  end)

  it("test_platform_string_identity_round_trips_without_coercion", function()
    for _, id in ipairs({ "aU5A95JB9rit0DUl", "00042", "9007199254740993", "arxYUgj/dKsUU0QL", "42" }) do
      local entry = Records.Entry(1234, id, nil)
      assert.same({ w = 1234, u = id }, entry)
      assert.same(entry, Records.Valid(entry))
      assert.same(id, Records.State(entry).userId)
      assert.same("玩家" .. id, Records.Holder(entry))
    end
    assert.same({ w = 1234, u = 42 }, Records.Valid({ w = 1234, u = 42 }), "历史数字保持者原样兼容")
    for _, id in ipairs({ "", false, {}, 0, -1, 1.5, 0 / 0, math.huge, -math.huge }) do
      assert.is_nil(Records.Entry(1234, id))
      assert.is_nil(Records.Valid({ w = 1234, u = id }))
    end
  end)

  it("test_state_and_text_never_fabricate_a_record", function()
    -- 文案：有纪录/暂无/暂不可用三态分开，不可用不等于没有纪录
    local ok = Records.State(Records.Entry(1234, 42, "张三"))
    assert.same("ok", ok.state)
    assert.same(12.34, ok.weight)
    assert.same("全服纪录：12.34 kg（张三）", Records.Describe(ok))
    assert.same({ state = "missing" }, Records.State(nil))
    assert.same("全服纪录：暂无", Records.Describe({ state = "missing" }))
    assert.same("全服纪录：暂不可用", Records.Describe({ state = "unavailable" }))
    assert.same("全服纪录：暂不可用", Records.Describe(nil), "未知状态按不可用展示，不当作暂无")
  end)

  it("test_string_and_legacy_identity_tiebreak_has_a_stable_total_order", function()
    -- 历史数字仍按数值升序；数字排在字符串前；字符串按原始字节序，不转换数字串。
    local ids = { 2, 10, "002", "10", "2", "aU5A95JB9rit0DUl", "bU5A95JB9rit0DUl" }
    for i, left in ipairs(ids) do
      for j, right in ipairs(ids) do
        assert.same(i < j, Records.Wins(Records.Entry(300, left), Records.Entry(300, right)))
      end
    end
  end)

  it("test_weight_scales_to_integer_and_round_trips", function()
    -- 重量 → 整数：定标因子 100（两位小数），读出还原后与写入值逐位相等
    -- 期望值取自「两位小数放大 100 倍」的定义，与实现写法无关
    for _, pair in ipairs({
      { 0.01, 1 }, { 0.2, 20 }, { 0.12, 12 }, { 1, 100 }, { 0.5, 50 },
      { 12.34, 1234 }, { 99.99, 9999 }, { 1234.56, 123456 },
    }) do
      assert.same(pair[2], Records.Scale(pair[1]), "重量 " .. tostring(pair[1]))
      assert.same(pair[1], Records.Unscale(pair[2]), "还原必须与写入一致")
    end
    assert.same(100, GameCfg.Records.Scale)
    -- 两位小数是存储精度上限：第三位不参与存储，不产生「读回比写入更精确」的假象
    assert.same(13, Records.Scale(0.125))
  end)
end)

--- 端到端世界：真实 MgrCompendium（上岸入账）+ 真实 MgrRecords + 真实 MgrSave，只换平台适配器。
local function newIntegrationWorld()
  local env = {}
  env.oldGame, env.oldREUtil = _G.game, _G.REUtil
  env.values, env.queue, env.datas, env.sent = {}, {}, {}, {}
  env.clock, env.records, env.calls, env.pending = 100, {}, 0, {}
  env.recordsFail, env.cooldowns = false, {}
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
  env.adapter = {
    Read = function(_, fishId)
      if env.recordsFail then
        return false, nil, "unavailable"
      end
      return true, env.records[fishId], nil
    end,
    Submit = function(_, fishId, decide)
      env.calls = env.calls + 1
      if env.recordsFail then
        return false, nil, nil, "unavailable"
      end
      local next_ = decide(env.records[fishId])
      if not next_ then
        return true, false, env.records[fishId], nil
      end
      env.records[fishId] = next_
      return true, true, next_, nil
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
        return { GetServerTime = function() return env.clock end }
      end
      if name == "Players" then
        return { GetPlayers = function() return {} end }
      end
    end,
  }
  _G.REUtil = {
    GetRE = function(_, name)
      local event = env.pending[name]
      if not event then
        event = { Server = {}, Client = {} }
        event.OnServerEvent = {
          Connect = function(_, fn)
            event.Server[#event.Server + 1] = fn
          end,
        }
        event.OnClientEvent = {
          Connect = function(_, fn)
            event.Client[#event.Client + 1] = fn
          end,
        }
        event.FireServer = function(_, player, payload)
          for _, fn in ipairs(event.Server) do
            fn(player, payload)
          end
        end
        event.FireClient = function(_, player, payload)
          env.sent[#env.sent + 1] = { name = name, player = player, payload = payload }
        end
        env.pending[name] = event
      end
      return event
    end,
    CheckRECD = function(_, _, name, duration)
      local until_ = env.cooldowns and env.cooldowns[name]
      if until_ and until_ > env.clock then
        return true
      end
      env.cooldowns = env.cooldowns or {}
      env.cooldowns[name] = env.clock + (duration or 1)
      return false
    end,
  }
  env.save = assert(loadfile("server/Mgr/MgrSave.lua"))()
  env.comp = assert(loadfile("server/Mgr/MgrCompendium.lua"))()
  env.rec = assert(loadfile("server/Mgr/MgrRecords.lua"))()
  env.rec.Adapter = env.adapter
  env.comp.Save = env.save
  env.comp.Records = env.rec
  env.datas = {}
  local accessor = {
    GetDataInst = function(_, player)
      return env.datas[player.UserId]
    end,
  }
  env.comp.PlayerData, env.rec.PlayerData = accessor, accessor
  env.rec:Start()

  function env:drain()
    while #self.queue > 0 do
      table.remove(self.queue, 1)()
    end
  end

  function env:join(id, name)
    local player = { UserId = id, Name = name, SetAttribute = function() end }
    local data = PlayerData.New(player)
    data:Init(true)
    self.datas[id] = data
    self.save:LoadInto(player, data)
    self:drain()
    return player, data
  end

  function env:window()
    self.clock = self.clock + GameCfg.Records.FlushIntervalSec
    self.rec:Update()
    self:drain()
  end

  function env:cleanup()
    _G.game, _G.REUtil = self.oldGame, self.oldREUtil
  end

  return env
end

describe("全服纪录端到端（MgrRecords × MgrCompendium × MgrSave）", function()
  local env
  before_each(function()
    env = newIntegrationWorld()
  end)
  after_each(function()
    RandomGuard.restore()
    if env then
      env:cleanup()
      env = nil
    end
  end)

  it("test_blindbox_and_kills_have_no_write_path_into_records", function()
    -- 盲盒/击杀/掉落没有进纪录的写通道：唯一入口是「上岸」
    local player = env:join(31, "甲")
    player.Name = "甲"
    env.datas[31].Extra.lottery.pity = 3
    env.comp:RecordLanding(player, { fishId = "carp", mult = 1, reelSerial = 1 })
    env:drain()
    env:window()
    assert.same({ w = 500, u = 31, n = "甲" }, env.records.carp)
    env.calls = 0
    -- 盲盒解锁只动 extra.lottery（图鉴条目与纪录都不碰）
    env.datas[31].Extra.lottery.lastUnlock = "goldfish"
    env.rec:Update()
    env:drain()
    assert.same(0, env.calls)
    assert.is_nil(env.records.goldfish)
    -- 源码级：只有上岸入账调用 NoteLanding，击杀/掉落/商店都不引用纪录
    local callers = {}
    for _, path in ipairs({
      "server/Mgr/MgrCompendium.lua", "server/Mgr/MgrLoot.lua",
      "server/Mgr/MgrShop.lua", "server/Mgr/MgrFishUnit.lua",
    }) do
      local source = readSource(path)
      assert.is_not_nil(source, path)
      if source:find("NoteLanding", 1, true) then
        callers[#callers + 1] = path
      end
    end
    assert.same({ "server/Mgr/MgrCompendium.lua" }, callers)
  end)

  it("test_client_query_replies_with_server_truth", function()
    -- 图鉴查询：只认服务端读到的状态，序号重放不重复回包
    local player = env:join(33, "丙")
    env.records.goldfish = { w = 25, u = 7, n = "甲" }
    local request = _G.REUtil:GetRE("RecordsRequest")
    request.FireServer(request, player, { fishId = "goldfish", seq = 1 })
    env:drain()
    assert.same(1, #env.sent)
    assert.same("RecordsState", env.sent[1].name)
    assert.same(player, env.sent[1].player)
    assert.same("ok", env.sent[1].payload.state)
    assert.same(0.25, env.sent[1].payload.weight)
    assert.same("甲", env.sent[1].payload.holder)
    assert.same(1, env.sent[1].payload.seq)
    -- 同序号重放：不再回包
    env.clock = env.clock + 1
    request.FireServer(request, player, { fishId = "goldfish", seq = 1 })
    env:drain()
    assert.same(1, #env.sent)
    -- 新序号：回包
    env.clock = env.clock + 1
    request.FireServer(request, player, { fishId = "bass", seq = 2 })
    env:drain()
    assert.same(2, #env.sent)
    assert.same("missing", env.sent[2].payload.state)
  end)

  it("test_no_reconcile_while_the_platform_is_unreadable", function()
    -- 平台读不到时不补交：连当前纪录都不知道，不猜、不写
    local player, data = env:join(35, "戊")
    data.Extra.collection.weights.goldfish = 0.5
    env.recordsFail = true
    local request = _G.REUtil:GetRE("RecordsRequest")
    request.FireServer(request, player, { fishId = "goldfish", seq = 1 })
    env:drain()
    assert.same("unavailable", env.sent[1].payload.state)
    env.clock = env.clock + GameCfg.Records.FlushIntervalSec * 2
    env.rec:Update()
    env:drain()
    assert.same(0, env.calls, "读不到当前纪录就不补交")
  end)

  it("test_only_a_landing_that_improves_the_personal_best_submits", function()
    -- 只有刷新了个人最大重量的上岸才提交，且窗口合并后才真的写
    local player = env:join(30, "甲")
    env.comp:RecordLanding(player, { fishId = "goldfish", mult = 2, reelSerial = 1 })
    env:drain()
    assert.same(0, env.calls, "上岸只入队，等合并窗口")
    env:window()
    assert.same({ w = 20, u = 30, n = "甲" }, env.records.goldfish)
    -- 第二次上岸更小：不刷新个人纪录，也就不提交
    env.comp:RecordLanding(player, { fishId = "goldfish", mult = 1.15, reelSerial = 2 })
    env:drain()
    env:window()
    assert.same({ w = 20, u = 30, n = "甲" }, env.records.goldfish)
    assert.same(1, env.calls, "没刷新个人纪录就不提交")
  end)

  it("test_personal_best_scaled_reads_the_collection_weight", function()
    -- 个人最大重量的整数化读数（PlayerData 侧只加读数，不改 #133 的存储语义）
    local _, data = env:join(36, "己")
    assert.is_nil(data:PersonalBestScaled("goldfish"))
    data.Extra.collection.weights.goldfish = 0.12
    assert.same(12, data:PersonalBestScaled("goldfish"))
    assert.is_nil(data:PersonalBestScaled(nil))
    assert.is_nil(data:PersonalBestScaled(1))
  end)

  it("test_platform_failure_keeps_personal_compendium_and_shows_no_fake_record", function()
    -- 平台不可用：个人图鉴照常记账，纪录一律报「暂不可用」，不显示伪纪录
    local player = env:join(32, "乙")
    env.recordsFail = true
    env.comp:RecordLanding(player, { fishId = "goldfish", mult = 2, reelSerial = 1 })
    env:drain()
    local view = env.comp:Snapshot(player)
    assert.same(0.2, view.weights.goldfish, "个人最大重量照常入账")
    assert.same(1, view.catches.goldfish)
    for _ = 1, GameCfg.Records.MaxRetries + 2 do
      env.clock = env.clock + GameCfg.Records.FlushIntervalSec + GameCfg.Records.RetryDelaySec
      env.rec:Update()
      env:drain()
    end
    assert.same({}, env.records, "平台失败一个字节都不写")
    local seen
    env.rec:Read("goldfish", function(state)
      seen = state
    end)
    env:drain()
    assert.same("unavailable", seen.state)
    assert.same("全服纪录：暂不可用", Records.Describe(seen))
    assert.is_nil(seen.scaled)
    -- 个人图鉴的快照不掺全服纪录字段，读不到纪录也不会污染个人数据
    assert.same(1, view.total)
  end)

  it("test_query_reconciles_a_dropped_submission", function()
    -- 对账：个人最大重量高于全服纪录（上次提交被平台丢掉）时补交，且只补更高的
    local player, data = env:join(34, "丁")
    data.Extra.collection.weights.goldfish = 0.5
    env.records.goldfish = { w = 20, u = 9, n = "乙" }
    local request = _G.REUtil:GetRE("RecordsRequest")
    request.FireServer(request, player, { fishId = "goldfish", seq = 1 })
    env:drain()
    assert.same(0.2, env.sent[1].payload.weight, "先回当前真实纪录（补交还没落地）")
    env:window()
    assert.same({ w = 50, u = 34, n = "丁" }, env.records.goldfish)
    -- 个人纪录不高于全服纪录：不补交、不写
    env.clock = env.clock + 1
    env.calls = 0
    data.Extra.collection.weights.bass = 0.2
    env.records.bass = { w = 500, u = 9, n = "乙" }
    request.FireServer(request, player, { fishId = "bass", seq = 2 })
    env:drain()
    env:window()
    assert.same({ w = 500, u = 9, n = "乙" }, env.records.bass)
    assert.same(0, env.calls)
  end)

  it("test_string_players_persist_rejoin_and_query_without_identity_leaks", function()
    local id, otherId = "aU5A95JB9rit0DUl", "bU5A95JB9rit0DUl"
    local player, data = env:join(id, "甲")
    local other, otherData = env:join(otherId, "乙")
    assert.are_not.same(env.save:Key(otherId), env.save:Key(id))
    assert.is_true(env.comp:RecordLanding(player, { fishId = "goldfish", mult = 2, reelSerial = 1 }))
    env:drain()
    env:window()
    assert.same({ w = 20, u = id, n = "甲" }, env.records.goldfish)
    assert.same(20, data:PersonalBestScaled("goldfish"))
    assert.is_nil(otherData:PersonalBestScaled("goldfish"))
    local snapshot = env.values[env.save:Key(id)]
    assert.same(0.2, snapshot.extra.collection.weights.goldfish)
    assert.same(id .. ":", snapshot.meta.operations[#snapshot.meta.operations].id:sub(1, #id + 1))
    env.comp:OnPlayerRemoving(player)
    env.rec:OnPlayerRemoving(player)
    player, data = env:join(id, "甲")
    assert.same(20, data:PersonalBestScaled("goldfish"))
    env.rec.Cache = {}
    env.rec:Handle(player, { fishId = "goldfish", seq = 1, userId = otherId, weight = 99999 })
    env:drain()
    env.rec:Handle(other, { fishId = "goldfish", seq = 1, userId = id })
    env:drain()
    assert.same(2, #env.sent, "同序号的两个字符串玩家分别收到回包")
    assert.same(player, env.sent[1].player)
    assert.same(other, env.sent[2].player)
    assert.same(id, env.sent[1].payload.userId)
    assert.same(20, env.sent[1].payload.scaled, "载荷里伪造的重量与身份不参与纪录")
    env.rec:Handle(player, { fishId = "goldfish", seq = 1 })
    env:drain()
    assert.same(2, #env.sent, "重放只拦当前玩家")
    env.rec:OnPlayerRemoving(player)
    assert.is_nil(env.rec.LastSeq[id])
    assert.same(1, env.rec.LastSeq[otherId])
  end)
end)

--- 服务层世界：真实 MgrRecords，只替换平台适配器（内存假实现，能表达超时/限流/不可用）。
local function newServiceWorld()
  local env = {}
  env.oldGame, env.oldREUtil = _G.game, _G.REUtil
  env.clock, env.queue = 100, {}
  env.store, env.calls, env.writes, env.readCalls = {}, 0, 0, 0
  env.readFail, env.writeFail, env.writeFailRounds = nil, nil, 0
  env.adapter = {
    Read = function(_, fishId)
      env.readCalls = env.readCalls + 1
      if env.readFail then
        return false, nil, env.readFail
      end
      return true, env.store[fishId], nil
    end,
    -- 假适配器的 CAS 语义与真实适配器一致：decide(current) 返回 nil 就一个字节都不写
    Submit = function(_, fishId, decide)
      env.calls = env.calls + 1
      if env.writeFailRounds > 0 then
        env.writeFailRounds = env.writeFailRounds - 1
        return false, nil, env.writeFail or "unavailable"
      end
      local next_ = decide(env.store[fishId])
      if not next_ then
        return true, false, env.store[fishId], nil
      end
      env.store[fishId] = next_
      env.writes = env.writes + 1
      return true, true, next_, nil
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
      if name == "World" then
        return { GetServerTime = function() return env.clock end }
      end
      if name == "Players" then
        return { GetPlayers = function() return {} end }
      end
      if name == "DataStoreService" then
        return { GetDataStore = function() return {} end }
      end
    end,
  }
  env.mgr = assert(loadfile("server/Mgr/MgrRecords.lua"))()
  env.mgr.Adapter = env.adapter

  function env:drain()
    while #self.queue > 0 do
      table.remove(self.queue, 1)()
    end
  end

  function env:advance(seconds)
    self.clock = self.clock + seconds
    self.mgr:Update()
  end

  function env:player(userId, name)
    return { UserId = userId, Name = name }
  end

  function env:cleanup()
    _G.game, _G.REUtil = self.oldGame, self.oldREUtil
  end

  return env
end

describe("全服纪录服务层（MgrRecords × RecordsAdapter）", function()
  local env
  before_each(function()
    env = newServiceWorld()
  end)
  after_each(function()
    RandomGuard.restore()
    if env then
      env:cleanup()
      env = nil
    end
  end)

  it("test_adapter_classifies_platform_failures", function()
    -- 适配器把平台异常翻译成稳定类别，调用方不依赖错误码文本
    local adapter = assert(loadfile("server/Data/RecordsAdapter.lua"))()
    local failure
    local platform = {
      GetAsync = function()
        error(failure)
      end,
    }
    _G.game = {
      GetService = function(_, name)
        if name == "DataStoreService" then
          return { GetDataStore = function() return platform end }
        end
      end,
    }
    for _, pair in ipairs({
      { "Request was throttled", "throttled" },
      { "request limit reached", "throttled" },
      { "connection timed out", "timeout" },
      { "some new platform text", "unknown" },
    }) do
      failure = pair[1]
      assert.same(pair[2], select(3, adapter:Read("goldfish")), pair[1])
    end
    _G.game = {
      GetService = function()
        error("no DataStoreService")
      end,
    }
    adapter.Checked, adapter.Holder = nil, nil
    assert.same("unavailable", select(3, adapter:Read("goldfish")))
  end)

  it("test_concurrent_reads_share_one_platform_call", function()
    -- 同一鱼种的并发读合并成一次平台调用（打开图鉴时几十条一起要）
    local first, second
    env.mgr:Read("goldfish", function(state)
      first = state
    end)
    env.mgr:Read("goldfish", function(state)
      second = state
    end)
    assert.same(0, env.readCalls, "还没进平台调用")
    env:drain()
    assert.same(1, env.readCalls)
    assert.same("missing", first.state)
    assert.same(first, second)
  end)

  it("test_corrupt_stored_value_is_never_shown", function()
    -- 坏数据（缺重量或缺身份）不展示：当作这条还没有纪录，而不是拼一个半截纪录出来
    local adapter = assert(loadfile("server/Data/RecordsAdapter.lua"))()
    local values = {
      corrupt = { w = 25 }, nameless = { u = 7, n = "甲" }, ok = { w = 25, u = 7, n = "甲" },
    }
    local function field(key)
      return values[key:sub(5)]
    end
    local platform = {
      GetAsync = function(_, key)
        return field(key)
      end,
      UpdateAsync = function(_, key, transform)
        local value = transform(field(key))
        if value then
          values[key:sub(5)] = value
        end
        return value
      end,
    }
    _G.game = {
      GetService = function(_, name)
        if name == "DataStoreService" then
          return { GetDataStore = function() return platform end }
        end
        if name == "World" then
          return { GetServerTime = function() return 100 end }
        end
      end,
    }
    local ok, entry = adapter:Read("corrupt")
    assert.is_true(ok, "读成功但值不可信")
    assert.is_nil(entry, "只有重量的半截记录不算纪录")
    assert.is_nil(select(2, adapter:Read("nameless")), "缺重量的记录不算纪录")
    assert.same({ w = 25, u = 7, n = "甲" }, select(2, adapter:Read("ok")))
  end)

  it("test_delayed_retry_never_overwrites_a_newer_record", function()
    env.writeFail, env.writeFailRounds = "timeout", 1
    env.mgr:NoteLanding(env:player(7, "甲"), "bass", 0.5)
    env:advance(GameCfg.Records.FlushIntervalSec)
    env:drain()
    assert.is_nil(env.store.bass, "第一次写超时，什么都没落地")
    assert.same(1, env.mgr.Stats.Failures)
    assert.same(1, env.mgr.Stats.Retries)
    -- 退避等待期间，别的服务器已经把纪录换成更大的（跨服竞态）
    env.store.bass = { w = 90, u = 3, n = "丙" }
    assert.same(1, env.mgr.Pending.bass.attempts)
    env:advance(GameCfg.Records.RetryDelaySec)
    env:drain()
    assert.same({ w = 90, u = 3, n = "丙" }, env.store.bass, "过期候选不许盖掉更新的纪录")
    assert.is_nil(env.mgr.Pending.bass, "过期候选重试后丢弃，不再占写频")
    assert.same(0, env.writes)
  end)

  it("test_equal_weight_keeps_smaller_user_id_whatever_the_order", function()
    env.store.goldfish = { w = 25, u = 7, n = "甲" }
    env.mgr:Read("goldfish", function() end)
    env:drain()
    -- 同重量、UserID 更大：不换人
    env.mgr:NoteLanding(env:player(9, "乙"), "goldfish", 0.25)
    env:advance(GameCfg.Records.FlushIntervalSec)
    env:drain()
    assert.same({ w = 25, u = 7, n = "甲" }, env.store.goldfish)
    -- 同重量、UserID 更小：换人（规则与到达顺序无关）
    env.store.goldfish = { w = 25, u = 7, n = "甲" }
    env.mgr:NoteLanding(env:player(3, "丙"), "goldfish", 0.25)
    env:advance(GameCfg.Records.FlushIntervalSec * 2)
    env:drain()
    assert.same({ w = 25, u = 3, n = "丙" }, env.store.goldfish)
    assert.same("丙", env.mgr:State("goldfish").holder)
  end)

  it("test_failed_read_is_unavailable_not_missing", function()
    -- 读失败：如实说「暂不可用」，不许说成「暂无纪录」，也不许显示数字
    local seen
    env.mgr:Read("goldfish", function(state)
      seen = state
    end)
    env:drain()
    assert.same("missing", seen.state, "服务可用、只是这条鱼还没纪录")
    env.readFail = "throttled"
    env:advance(GameCfg.Records.MissCacheTtlSec + 1)
    env.mgr:Read("goldfish", function(state)
      seen = state
    end)
    env:drain()
    assert.same("unavailable", seen.state)
    assert.is_nil(seen.scaled)
    assert.same("throttled", seen.error)
    assert.same("全服纪录：暂不可用", Records.Describe(seen))
    -- 负缓存：短时间内重复请求不再打平台
    local calls = env.readCalls
    env.mgr:Read("goldfish", function(state)
      seen = state
    end)
    env:drain()
    assert.same(calls, env.readCalls)
    assert.same("unavailable", seen.state)
  end)

  it("test_heavier_landing_updates_record_with_holder_pair", function()
    assert.is_true(env.mgr:NoteLanding(env:player(7, "甲"), "goldfish", 0.25))
    assert.same(0, env.calls, "合并窗口内不发写请求")
    env:advance(GameCfg.Records.FlushIntervalSec)
    env:drain()
    -- 重量与保持者同一条记录、同一次写入
    assert.same({ w = 25, u = 7, n = "甲" }, env.store.goldfish)
    local state = env.mgr:State("goldfish")
    assert.same("ok", state.state)
    assert.same(25, state.scaled)
    assert.same(0.25, state.weight)
    assert.same(7, state.userId)
    assert.same("甲", state.holder)
    assert.same(false, state.stale)
  end)

  it("test_invalid_or_overflowing_weight_is_never_submitted", function()
    assert.is_false(env.mgr:NoteLanding(env:player(7, "甲"), "goldfish", 0))
    assert.is_false(env.mgr:NoteLanding(env:player(7, "甲"), "goldfish", "x"))
    assert.is_false(env.mgr:NoteLanding(env:player(7, "甲"), "noSuchFish", 1))
    assert.is_false(env.mgr:NoteLanding(nil, "goldfish", 1))
    local _, reason = env.mgr:NoteLanding(env:player(7, "甲"), "goldfish",
      GameCfg.Records.MaxScaled / GameCfg.Records.Scale + 1)
    assert.same("overflow", reason)
    env:advance(GameCfg.Records.FlushIntervalSec * 2)
    env:drain()
    assert.same(0, env.calls)
    assert.same({}, env.store)
    assert.same(5, env.mgr.Stats.Rejected)
  end)

  it("test_landings_inside_one_window_merge_into_a_single_write", function()
    for index = 1, 20 do
      env.mgr:NoteLanding(env:player(index, "P" .. index), "carp", 0.01 * index)
    end
    assert.same(0, env.calls)
    env:advance(GameCfg.Records.FlushIntervalSec)
    env:drain()
    assert.same(1, env.calls, "一个窗口内同鱼种只发一次写")
    assert.same({ w = 20, u = 20, n = "P20" }, env.store.carp, "窗口内只保留最大候选")
    env:drain()
    assert.same(1, env.calls)
  end)

  it("test_lighter_landing_never_overwrites_and_costs_no_write", function()
    env.store.goldfish = { w = 25, u = 7, n = "甲" }
    env.mgr:Read("goldfish", function() end)
    env:drain()
    env.calls, env.writes = 0, 0
    assert.is_true(env.mgr:NoteLanding(env:player(9, "乙"), "goldfish", 0.2))
    env:advance(GameCfg.Records.FlushIntervalSec)
    env:drain()
    assert.same({ w = 25, u = 7, n = "甲" }, env.store.goldfish)
    assert.same(0, env.calls, "已知现有纪录更大时一个写请求都不发")
  end)

  it("test_read_failure_keeps_last_known_value_and_marks_it_stale", function()
    -- 读失败不许抹掉上一次可信值：照旧值展示并标 stale
    env.store.goldfish = { w = 25, u = 7, n = "甲" }
    local seen
    env.mgr:Read("goldfish", function(state)
      seen = state
    end)
    env:drain()
    assert.same("ok", seen.state)
    assert.same(false, seen.stale)
    env.readFail = "timeout"
    env:advance(GameCfg.Records.HolderCacheTtlSec + 1)
    env.mgr:Read("goldfish", function(state)
      seen = state
    end)
    env:drain()
    assert.same("ok", seen.state)
    assert.same(0.25, seen.weight, "平台读不到时沿用上一次真实值，不编新值")
    assert.same("甲", seen.holder)
    assert.is_true(seen.stale)
    assert.is_nil(seen.error)
  end)

  it("test_retry_exhaustion_drops_the_candidate_and_logs", function()
    env.writeFail, env.writeFailRounds = "throttled", 99
    env.mgr:NoteLanding(env:player(7, "甲"), "bass", 0.5)
    for _ = 1, GameCfg.Records.MaxRetries + 2 do
      env:advance(GameCfg.Records.FlushIntervalSec + GameCfg.Records.RetryDelaySec)
      env:drain()
    end
    assert.is_nil(env.mgr.Pending.bass)
    assert.same(1, env.mgr.Stats.Dropped)
    assert.same({}, env.store, "一直失败也不许写假值")
  end)

  it("test_state_before_any_read_is_unavailable", function()
    -- 冷启动（还没读过）也按「暂不可用」，绝不当作「暂无纪录」
    assert.same("unavailable", env.mgr:State("goldfish").state)
    assert.same("全服纪录：暂不可用", Records.Describe(env.mgr:State("goldfish")))
  end)
end)

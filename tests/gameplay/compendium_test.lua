-- #133 图鉴写入基础。失败方式（先列后写）：
--   1. 上岸不写，或同一次上岸（重放 / 写档重试 / 断线重连）被记成两次；
--   2. 更小的个体重量覆盖个人最大重量；条目、次数与总次数对不上；
--   3. 击杀与三份掉落混进钓取纪录；盲盒/抽奖字段被图鉴写入改动；
--   4. 只写内存不落存档，重进后图鉴丢失；
--   5. 写档忙或存档不可用时伪造记录，或把这条上岸直接吞掉。
-- seam：真实 MgrSave 协议 + 真实 PlayerData 迁移，只替换 Task/DataStore 引擎边界。
local lu = require('luaunit')
local GameCfg = require('common.GameCfg')
local PlayerData = require('server.Data.PlayerData')

TestCompendium = {}

local function read(path)
    local file = io.open(path, 'r')
    if not file then return nil end
    local text = file:read('*a')
    file:close()
    return text
end

function TestCompendium:setUp()
    self.oldGame = _G.game
    self.values, self.queue, self.datas = {}, {}, {}
    local env = self
    self.store = {
        GetAsync = function(_, key) return env.values[key] end,
        UpdateAsync = function(_, key, transform)
            local value = transform(env.values[key])
            if value then env.values[key] = value end
            return value
        end,
        SetAsync = function(_, key, value) env.values[key] = value end,
    }
    _G.game = { GetService = function(_, name)
        if name == 'Task' then return { Spawn = function(_, fn) env.queue[#env.queue + 1] = fn end,
            Wait = function() end } end
        if name == 'DataStoreService' then return { GetDataStore = function() return env.store end } end
        if name == 'World' then return { GetServerTime = function() return 100 end } end
        if name == 'Players' then return { GetPlayers = function() return {} end } end
    end }
    self.save = assert(loadfile('server/Mgr/MgrSave.lua'))()
    self.comp = assert(loadfile('server/Mgr/MgrCompendium.lua'))()
    self.comp.Save = self.save
    self.comp.PlayerData = { GetDataInst = function(_, player) return env.datas[player.UserId] end }
end

function TestCompendium:tearDown() _G.game = self.oldGame end

function TestCompendium:drain()
    while #self.queue > 0 do table.remove(self.queue, 1)() end
end

function TestCompendium:join(id)
    local player = { UserId = id, SetAttribute = function() end }
    local data = PlayerData.New(player)
    data:Init(true)
    self.datas[id] = data
    self.save:LoadInto(player, data)
    self:drain()
    lu.assertEquals(data.LoadState, 'ready')
    return player, data
end

function TestCompendium:test_first_landing_unlocks_entry_and_sets_personal_best()
    local player = self:join(30)
    lu.assertTrue(self.comp:RecordLanding(player, { fishId = 'goldfish', mult = 1.15, reelSerial = 1 }))
    self:drain()
    local view = self.comp:Snapshot(player)
    lu.assertEquals(view.unlocked.goldfish, true)
    lu.assertEquals(view.catches.goldfish, 1)
    lu.assertEquals(view.weights.goldfish, 0.12)
    lu.assertEquals(view.total, 1)
    lu.assertNil(view.unlocked.bass)
end

function TestCompendium:test_duplicate_event_is_recorded_once()
    local player, data = self:join(31)
    self.comp:RecordLanding(player, { fishId = 'goldfish', mult = 2, reelSerial = 5 })
    self:drain()
    local queue = self.comp.Queues[player.UserId]
    lu.assertFalse(self.comp:RecordLanding(player, { fishId = 'goldfish', mult = 2, reelSerial = 5 }))
    lu.assertEquals(select(2, self.comp:RecordLanding(player, { fishId = 'goldfish', mult = 2, reelSerial = 5 })), 'replay')
    lu.assertEquals(queue.events, {})
    self.comp:Update()
    self:drain()
    local view = self.comp:Snapshot(player)
    lu.assertEquals(view.catches, { goldfish = 1 })
    lu.assertEquals(view.weights, { goldfish = 0.2 })
    lu.assertEquals(view.total, 1)
    lu.assertEquals(#data:Serialize().meta.operations, 1)
end

function TestCompendium:test_personal_best_only_grows()
    local player = self:join(32)
    self.comp:RecordLanding(player, { fishId = 'goldfish', mult = 2, reelSerial = 1 })
    self:drain()
    self.comp:RecordLanding(player, { fishId = 'goldfish', mult = 1.15, reelSerial = 2 })
    self:drain()
    local view = self.comp:Snapshot(player)
    lu.assertEquals(view.weights.goldfish, 0.2)
    lu.assertEquals(view.catches.goldfish, 2)
    lu.assertEquals(view.total, 2)
end

function TestCompendium:test_every_species_gets_its_own_entry()
    local player = self:join(33)
    local serial = 0
    for fishId in pairs(GameCfg.Fish) do
        serial = serial + 1
        lu.assertTrue(self.comp:RecordLanding(player, { fishId = fishId, mult = 1, reelSerial = serial }))
        self:drain()
    end
    local view = self.comp:Snapshot(player)
    lu.assertEquals(view.total, 98)
    local entries = 0
    for fishId, unlocked in pairs(view.unlocked) do
        entries = entries + 1
        lu.assertTrue(unlocked, fishId)
        lu.assertEquals(view.catches[fishId], 1, fishId)
        lu.assertNotNil(GameCfg.Fish[fishId])
        lu.assertTrue(view.weights[fishId] > 0, fishId)
    end
    lu.assertEquals(entries, 98)
end

function TestCompendium:test_records_survive_rejoin()
    local player = self:join(34)
    self.comp:RecordLanding(player, { fishId = 'goldfish', mult = 2, reelSerial = 1 })
    self:drain()
    local rejoined = self:join(34)
    local view = self.comp:Snapshot(rejoined)
    lu.assertEquals(view.unlocked.goldfish, true)
    lu.assertEquals(view.weights.goldfish, 0.2)
    lu.assertEquals(view.catches.goldfish, 1)
    lu.assertEquals(view.total, 1)
    self.comp:RecordLanding(rejoined, { fishId = 'goldfish', mult = 1.15, reelSerial = 2 })
    self:drain()
    view = self.comp:Snapshot(rejoined)
    lu.assertEquals(view.catches.goldfish, 2)
    lu.assertEquals(view.weights.goldfish, 0.2)
end

-- #134 鱼塘极品六条：各自一条个人最大重量，只增不减、重进保留，不与同名普通鱼混账
--   （失败方式 6. 极品按普通鱼 ID 记账或被较小重量覆盖；7. 极品重量不落存档）
function TestCompendium:test_pond_rare_max_weight_per_id_survives_rejoin()
    local player = self:join(38)
    local ids = { 'item7', 'item8', 'item9', 'item10', 'item11', 'item12' }
    local serial = 0
    for _, fishId in ipairs(ids) do
        for _, mult in ipairs({ 1.9, 1.2 }) do
            serial = serial + 1
            lu.assertTrue(self.comp:RecordLanding(player, { fishId = fishId, mult = mult, reelSerial = serial }))
            self:drain()
        end
    end
    local rejoined = self:join(38)
    local view = self.comp:Snapshot(rejoined)
    lu.assertEquals(view.total, 12)
    for _, fishId in ipairs(ids) do
        lu.assertEquals(view.catches[fishId], 2, fishId)
        lu.assertEquals(view.weights[fishId], self.comp:Weight(fishId, 1.9), fishId)
    end
    lu.assertEquals(view.weights.item12, 0.19)
    lu.assertEquals(view.weights.item10, 3.8)
    lu.assertNil(view.weights.goldfish)
    lu.assertNil(view.weights.catfish)
end

function TestCompendium:test_write_in_flight_defers_instead_of_dropping()
    local player, data = self:join(35)
    local operation = self.save:NextOperation(player, 'other')
    lu.assertTrue(self.save:Execute(player, data, operation, function(draft)
        draft:AddCoin(1)
        return { ok = true }
    end, function() end))
    lu.assertTrue(self.comp:RecordLanding(player, { fishId = 'goldfish', mult = 2, reelSerial = 1 }))
    lu.assertEquals(self.comp:Snapshot(player).total, 0)
    self:drain()
    lu.assertEquals(self.comp:Snapshot(player).total, 0)
    self.comp:Update()
    self:drain()
    local view = self.comp:Snapshot(player)
    lu.assertEquals(view.total, 1)
    lu.assertEquals(view.catches.goldfish, 1)
    lu.assertEquals(view.weights.goldfish, 0.2)
    lu.assertEquals(#data:Serialize().meta.operations, 2)
end

function TestCompendium:test_unavailable_save_never_fakes_a_record()
    local player = self:join(36)
    self.save.Sessions[player.UserId].State = 'failed'
    lu.assertFalse(self.comp:RecordLanding(player, { fishId = 'goldfish', mult = 2, reelSerial = 1 }))
    self:drain()
    self.comp:Update()
    self:drain()
    lu.assertEquals(self.comp:Snapshot(player).total, 0)
    lu.assertNil(self.values.u36.extra.collection.weights.goldfish)
    lu.assertEquals(self.comp.Queues[player.UserId].events, {})
end

function TestCompendium:test_blindbox_state_stays_separate()
    local player, data = self:join(37)
    data.Extra.lottery.pity = 3
    self.comp:RecordLanding(player, { fishId = 'goldfish', mult = 2, reelSerial = 1 })
    self:drain()
    lu.assertEquals(data.Extra.lottery.pity, 3)
    local view = self.comp:Snapshot(player)
    lu.assertEquals(view.total, 1)
    lu.assertNil(view.catches.lottery)
end

-- 击杀与三份掉落是 MgrLoot 的事：图鉴只有 RecordLanding 这一个写入口
function TestCompendium:test_kills_and_drops_never_enter_the_compendium()
    for _, path in ipairs({ 'server/Mgr/MgrFishUnit.lua', 'server/Mgr/MgrLoot.lua' }) do
        lu.assertNotNil(read(path), path)
        lu.assertNil(read(path):find('Compendium', 1, true), path)
    end
end

-- #39 失败方式：未加载存档伪装成空图鉴；快照泄漏权威表；盲盒虚构重量；
-- 本地通关依赖平台 ID；重复请求写档；离场请求状态未清理。
-- 接缝：MgrCompendium 的公开请求与 Snapshot，真实 PlayerData/MgrSave。
function TestCompendium:test_readonly_request_reports_ready_collection_and_local_completion()
    local player, data = self:join(39)
    data.Extra.collection.unlocked.item7 = true -- 已保存的盲盒收集，不经过上岸入口
    data.Extra.achievements.final = true
    local packets = {}
    local previous = _G.REUtil
    _G.REUtil = { GetRE = function(_, name)
        lu.assertEquals(name, 'CompendiumState')
        return { FireClient = function(_, target, value)
            lu.assertEquals(target, player)
            packets[#packets + 1] = value
        end }
    end }
    self.comp:Handle(player, { seq = 1 })
    self.comp:Handle(player, { seq = 1 })
    _G.REUtil = previous
    lu.assertEquals(#packets, 1)
    lu.assertEquals(packets[1].state, 'ready')
    lu.assertTrue(packets[1].completed)
    lu.assertTrue(packets[1].unlocked.item7)
    lu.assertNil(packets[1].weights.item7)
    lu.assertNil(packets[1].catches.item7)
    packets[1].unlocked.item7 = false
    lu.assertTrue(self.comp:Snapshot(player).unlocked.item7)
    lu.assertEquals(#data:Serialize().meta.operations, 0)
end

function TestCompendium:test_unready_collection_never_presents_default_data_as_saved_progress()
    local player, data = self:join(40)
    data.LoadState = 'loading'
    lu.assertEquals(self.comp:Snapshot(player).state, 'loading')
    data.LoadState = 'failed'
    data.Extra.achievements.final = true
    local state = self.comp:Snapshot(player)
    lu.assertEquals(state.state, 'unavailable')
    lu.assertNil(state.completed)
end

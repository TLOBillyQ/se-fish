-- #92 存档：序列化往返、读档校验、失败重试、UpdateAsync 记账、体积台账（真 PlayerData + 假 DataStore/Task）。
-- 失败方式（先列后写）：
--   1. 序列化丢信息：金币、道具栏/背包格子位置、个体倍率、鱼饵计数、升级等级、当前区域任一丢失或错位；
--   2. 读档不校验：坏类型、未知物品 id、超容量格位直接灌进内存态，脏存档搞坏游戏；
--   3. 读写不重试：偶发失败一次就放弃；或无限重试不收敛；放弃时动了内存态（内存比存档新却被回滚）；
--   4. 兑换/船票记账不走 UpdateAsync（SetAsync 覆盖 → CAS 冲突丢账、断线重连双份发奖），或记账失败不重试；
--   5. 台账缺失：存档体积、写次数无处可查，压测无法校准；体积估算随字段增多不增长；
--   6. 进图恢复后不同步客户端（栏位恢复了但 HUD 还是开局白送）；
--   7. 写乱序：离场 SetAsync 与兑换 UpdateAsync 并发，旧快照盖掉新账（同玩家写入必须合并+串行）；
--   8. 只有离场才存档：中途掉线/关服丢进度（周期自动存档、BindToClose 兜底）；
--   9. 读档竞态：读档返回前玩家已操作，旧档灌入吞掉新操作（Touched 会话锁）。
local lu = require('luaunit')

TestSave = {}

-- 假 DataStore：内存表 + 可注入失败次数与 CAS 冲突次数
local function fakeStore(env)
    return {
        data = {},
        ops = {},
        GetAsync = function(_, key)
            env.ops[#env.ops + 1] = 'get'
            if env.failGet > 0 then env.failGet = env.failGet - 1 error('GetAsync 限流 301') end
            local v = env.store.data[key]
            return v
        end,
        SetAsync = function(_, key, value)
            env.ops[#env.ops + 1] = 'set'
            if env.failSet > 0 then env.failSet = env.failSet - 1 error('SetAsync 限流 302') end
            env.store.data[key] = value
        end,
        UpdateAsync = function(_, key, transform)
            env.ops[#env.ops + 1] = 'update'
            if env.failUpdate > 0 then env.failUpdate = env.failUpdate - 1 error('UpdateAsync 限流 303') end
            -- CAS：注入冲突时 transform 会被再次调用（拿最新旧值重算）
            local rounds = 1 + env.casConflicts
            env.casConflicts = 0
            local result
            for _ = 1, rounds do result = transform(env.store.data[key]) end
            env.store.data[key] = result
            return result
        end,
    }
end

function TestSave:setUp()
    self.savedGrantDebug = require('common.GameCfg').Debug
    require('common.GameCfg').Debug = { Enabled = true, InitialGrants = self.savedGrantDebug.InitialGrants }
    self.cfg = require('common.GameCfg')
    self.savedGame = rawget(_G, 'game')
    self.ops = {}
    self.failGet, self.failSet, self.failUpdate, self.casConflicts = 0, 0, 0, 0
    self.store = fakeStore(self)
    self.waits = {}
    self.spawned = 0
    self.spawnQueue = {}
    self.deferSpawn = false -- true 时 Spawn 只排队，flushSpawns 才执行（用来观察入队合并）
    self.now = 100
    self.players = {}
    local env = self
    self.task = {
        Spawn = function(_, fn)
            env.spawned = env.spawned + 1
            if env.deferSpawn then env.spawnQueue[#env.spawnQueue + 1] = fn else fn() end
        end,
        Wait = function(_, d) env.waits[#env.waits + 1] = d end,
    }
    _G.game = {
        GetService = function(_, name)
            if name == 'Task' then return env.task end
            if name == 'World' then return { GetServerTime = function() return env.now end } end
            if name == 'Players' then return { GetPlayers = function() return env.players end } end
            if name == 'DataStoreService' then
                return { GetDataStore = function() return env.store end }
            end
        end,
        BindToClose = function(_, cb) env.boundClose = cb end,
    }
    self.saveModule = package.loaded['server.Mgr.MgrSave']
    package.loaded['server.Mgr.MgrSave'] = nil
    self.save = assert(loadfile('server/Mgr/MgrSave.lua'))()
    self.syncs = 0
    self.dataInsts = {}
    self.save.PlayerData = {
        SendItemBar = function() env.syncs = env.syncs + 1 end,
        GetDataInst = function(_, p) return env.dataInsts[p] end,
    }
    local PlayerData = assert(loadfile('server/Data/PlayerData.lua'))()
    self.newData = function(userId)
        local player = { UserId = userId, SetAttribute = function() end }
        local data = PlayerData.New(player)
        data:Init()
        env.dataInsts[player] = data
        return player, data
    end
    self.me, self.data = self.newData(1)
end

function TestSave:flushSpawns()
    while #self.spawnQueue > 0 do
        local fn = table.remove(self.spawnQueue, 1)
        fn()
    end
end

function TestSave:tearDown()
    require('common.GameCfg').Debug = self.savedGrantDebug
    package.loaded['server.Mgr.MgrSave'] = self.saveModule
    _G.game = self.savedGame
end

function TestSave:test_config_has_store_retry_policy()
    local cfg = assert(loadfile('common/GameCfg.lua'))()
    lu.assertEquals(type(cfg.Save.Store), 'string')
    lu.assertEquals(type(cfg.Save.KeyPrefix), 'string')
    lu.assertTrue(cfg.Save.MaxRetries >= 2)
    lu.assertTrue(cfg.Save.RetryDelaySec > 0)
    lu.assertTrue(cfg.Save.AutosaveSec > 0)
end

function TestSave:test_serialize_roundtrip_restores_coin_slots_bait_upgrade_zone()
    local d = self.data
    d.Data.FishCoin = 45
    d.Data.UpgradeLevel = 1
    d.Data.Zone = 'ShrimpPool'
    lu.assertTrue(d:AddItem('duck'))
    lu.assertTrue(d:AddItem('shrimpTicket'))
    lu.assertTrue(d:AddBait('sausage', 3))
    -- 造一个带倍率的鱼获在背包里
    lu.assertTrue(d:AddItem('riverShrimp', 1.14))
    local snapshot = d:Serialize()
    lu.assertEquals(snapshot.v, 1)
    -- 全新玩家读档
    local player2, d2 = self.newData(2)
    lu.assertTrue(d2:ApplySave(snapshot))
    lu.assertEquals(d2.Data.FishCoin, 45)
    lu.assertEquals(d2.Data.UpgradeLevel, 1)
    lu.assertEquals(d2.Data.Zone, 'ShrimpPool')
    lu.assertEquals(d2.Data.Bait.sausage, 3)
    lu.assertEquals(d2.Data.Bait.worm, d.Data.Bait.worm) -- 白送蚯蚓也在
    -- 格子位置逐项一致（含 mult）
    local bar1 = d.Data.Containers.itemBar
    local bar2 = d2.Data.Containers.itemBar
    for i = 1, 8 do
        local a, b = bar1[i], bar2[i]
        if a then
            lu.assertNotNil(b, 'itemBar ' .. i)
            lu.assertEquals({ b.itemId, b.count, b.mult }, { a.itemId, a.count, a.mult })
        else
            lu.assertNil(b, 'itemBar ' .. i)
        end
    end
    local bp1 = d.Data.Containers.backpack
    local bp2 = d2.Data.Containers.backpack
    for i = 1, 10 do
        local a, b = bp1[i], bp2[i]
        if a then
            lu.assertNotNil(b, 'backpack ' .. i)
            lu.assertEquals({ b.itemId, b.count, b.mult }, { a.itemId, a.count, a.mult })
        else
            lu.assertNil(b, 'backpack ' .. i)
        end
    end
    lu.assertEquals(d2:ItemCount('duck'), 1)
    lu.assertEquals(d2:ItemCount('shrimpTicket'), 1)
end

function TestSave:test_apply_save_drops_unknown_items_and_clamps_garbage()
    local _, d2 = self.newData(2)
    lu.assertTrue(d2:ApplySave({
        v = 1, coin = -50, up = 99, zone = 42,
        bar = { { i = 1, id = 'ghostItem', n = 1 }, { i = 99, id = 'duck', n = 1 }, { i = 2, id = 'duck', n = 'x' } },
        bp = { { i = 1, id = 'shrimpTicket', n = 1 } },
        bait = { sausage = 3, ghostBait = 9, worm = -2 },
    }))
    lu.assertEquals(d2.Data.FishCoin, 0)               -- 负数钳到 0
    lu.assertEquals(d2.Data.UpgradeLevel, #self.cfg.Items.UpgradePrices) -- 钳到升满
    lu.assertEquals(d2.Data.Zone, self.cfg.Ferry.HomeZone) -- 非字符串忽略，留默认
    lu.assertEquals(d2:ItemCount('ghostItem'), 0)      -- 未知物品丢弃
    lu.assertEquals(d2:ItemCount('duck'), 0)           -- 越界格 / 坏计数都不进
    lu.assertEquals(d2:ItemCount('shrimpTicket'), 1)
    lu.assertEquals(d2.Data.Bait.sausage, 3)
    lu.assertNil(d2.Data.Bait.ghostBait)               -- 未知鱼饵丢弃
    lu.assertNil(d2.Data.Bait.worm)                    -- 负数鱼饵丢弃（读档不继承白送之外的负值）
end

function TestSave:test_load_retries_then_succeeds_and_gives_up_without_touching_memory()
    self.store.data[self.save:Key(1)] = self.data:Serialize()
    -- 前两次失败第三次成功
    self.failGet = 2
    local loaded = self.save:Load(1)
    lu.assertNotNil(loaded)
    lu.assertEquals(#self.waits, 2) -- 每次失败等 RetryDelaySec
    -- 永远失败：返回 nil，内存态不变；GetAsync 总调用次数 = 3(成功路) + MaxRetries(失败路)
    self.failGet = 99
    self.data.Data.FishCoin = 77
    lu.assertNil(self.save:Load(1))
    lu.assertEquals(self.data.Data.FishCoin, 77)
    lu.assertEquals(#self.ops, 3 + self.cfg.Save.MaxRetries)
end

function TestSave:test_save_failure_keeps_memory_and_reports()
    self.failSet = 99
    self.data.Data.FishCoin = 88
    -- Enqueue 受理即返回 true（写是异步排空）；重试耗尽只丢这次写，不动内存态
    lu.assertTrue(self.save:Save(1, self.data:Serialize(), 'test'))
    lu.assertEquals(self.data.Data.FishCoin, 88)
    lu.assertNil(self.store.data[self.save:Key(1)])
    lu.assertEquals(#self.waits, self.cfg.Save.MaxRetries - 1) -- 每次失败退避一次
    -- 恢复后同一 key 能写进去
    self.failSet = 0
    lu.assertTrue(self.save:Save(1, self.data:Serialize(), 'test'))
    lu.assertNotNil(self.store.data[self.save:Key(1)])
end

function TestSave:test_commit_uses_update_async_and_survives_cas_conflict()
    self.data.Data.FishCoin = 10
    self.casConflicts = 1 -- transform 会被调两次（模拟冲突重算）
    local ok = self.save:Commit(1, self.data:Serialize(), 'exchange:eelHead')
    lu.assertTrue(ok)
    -- 只走 UpdateAsync，不走 SetAsync
    local setOps, updateOps = 0, 0
    for _, op in ipairs(self.ops) do
        if op == 'set' then setOps = setOps + 1 end
        if op == 'update' then updateOps = updateOps + 1 end
    end
    lu.assertEquals(setOps, 0)
    lu.assertTrue(updateOps >= 1)
    lu.assertEquals(self.store.data[self.save:Key(1)].coin, 10)
    -- 记账失败重试：第一次 update 失败也能补上
    self.failUpdate = 1
    self.data.Data.FishCoin = 11
    lu.assertTrue(self.save:Commit(1, self.data:Serialize(), 'ferry:ticket'))
    lu.assertEquals(self.store.data[self.save:Key(1)].coin, 11)
end

function TestSave:test_exchange_snapshot_rejoin_has_no_double_grant()
    -- 兑换落账后（信物扣了、鸭子发了）序列化；重进读档只能看到一份结果
    local d = self.data
    lu.assertTrue(d:AddItem('eelHead'))
    -- 手动复演兑换落账：扣信物、发鸭子
    lu.assertTrue(d:ExchangeSlot(2, 'duck'))
    lu.assertEquals(d:ItemCount('eelHead'), 0)
    lu.assertEquals(d:ItemCount('duck'), 1)
    self.casConflicts = 0
    lu.assertTrue(self.save:Commit(1, d:Serialize(), 'exchange:eelHead'))
    -- 断线重连：新 Data 读档
    local _, d2 = self.newData(1)
    local loaded = self.save:Load(1)
    lu.assertNotNil(loaded)
    lu.assertTrue(d2:ApplySave(loaded))
    lu.assertEquals(d2:ItemCount('duck'), 1)     -- 只有一份鸭子
    lu.assertEquals(d2:ItemCount('eelHead'), 0)  -- 信物不复活
end

function TestSave:test_ledger_tracks_size_and_write_count()
    lu.assertTrue(self.save:Save(1, self.data:Serialize(), 'a'))
    lu.assertTrue(self.save:Save(1, self.data:Serialize(), 'b'))
    local ledger = self.save.Ledger[1]
    lu.assertNotNil(ledger)
    lu.assertEquals(ledger.Writes, 2)
    lu.assertTrue(ledger.Bytes > 0)
    lu.assertNotNil(ledger.LastReason)
    -- 东西越多体积越大
    local small = self.save:EstimateSize(self.data:Serialize())
    lu.assertTrue(self.data:AddItem('duck'))
    lu.assertTrue(self.data:AddItem('shrimpTicket'))
    lu.assertTrue(self.data:AddBait('sausage', 5))
    local big = self.save:EstimateSize(self.data:Serialize())
    lu.assertTrue(big > small)
end

function TestSave:test_load_into_applies_save_and_syncs_client()
    self.data.Data.FishCoin = 66
    lu.assertTrue(self.data:AddItem('duck'))
    self.store.data[self.save:Key(9)] = self.data:Serialize()
    local player9, d9 = self.newData(9)
    self.save:LoadInto(player9, d9)
    lu.assertEquals(d9.Data.FishCoin, 66)
    lu.assertEquals(d9:ItemCount('duck'), 1)
    lu.assertEquals(self.syncs, 1) -- 恢复后推了一次 ItemBarState
    -- 没存档的玩家：不动初始数据，不额外推送
    self.save:LoadInto(self.me, self.data)
    lu.assertEquals(self.syncs, 1)
end

function TestSave:test_unavailable_service_degrades_to_memory_only()
    local env = self
    _G.game = { GetService = function(_, name)
        if name == 'Task' then return env.task end
        if name == 'DataStoreService' then error('service missing') end
    end }
    lu.assertNil(self.save:Load(1))
    lu.assertFalse(self.save:Save(1, self.data:Serialize(), 'x'))
    lu.assertFalse(self.save:Commit(1, self.data:Serialize(), 'x'))
    -- 不抛错、不刷屏重试（服务都没有，谈不上限流重试）
    lu.assertEquals(#self.waits, 0)
end

function TestSave:test_enqueue_merges_to_latest_snapshot_per_player()
    -- 排空任务还没跑就连来两笔：只落最新快照（旧 Set 不会盖新 Commit，反之同理）
    self.deferSpawn = true
    self.data.Data.FishCoin = 10
    lu.assertTrue(self.save:Save(1, self.data:Serialize(), 'a'))
    self.data.Data.FishCoin = 20
    lu.assertTrue(self.save:Commit(1, self.data:Serialize(), 'b'))
    lu.assertEquals(#self.ops, 0) -- 还没排空
    self:flushSpawns()
    local updates = 0
    for _, op in ipairs(self.ops) do
        if op == 'update' then updates = updates + 1 end
        lu.assertNotEquals(op, 'set') -- 旧快照被合并掉了，不会先 set 10
    end
    lu.assertEquals(updates, 1)
    lu.assertEquals(self.store.data[self.save:Key(1)].coin, 20)
    -- 排空后队列清空，后续写入重新起一轮
    lu.assertNil(self.save.Pending[1])
    lu.assertNil(self.save.Flying[1])
end

function TestSave:test_autosave_periodically_saves_online_players()
    self.players = { self.me }
    self.data.Data.FishCoin = 33
    self.save:Update() -- 第一次只定下一次存档时刻
    lu.assertNil(self.store.data[self.save:Key(1)])
    self.now = self.now + self.cfg.Save.AutosaveSec - 1
    self.save:Update() -- 还没到点
    lu.assertNil(self.store.data[self.save:Key(1)])
    self.now = self.now + 1
    self.save:Update() -- 到点：在线玩家落档
    lu.assertEquals(self.store.data[self.save:Key(1)].coin, 33)
    lu.assertEquals(self.save.Ledger[1].LastReason, 'autosave')
    -- 离场（不在线）玩家不自动存
    local stranger = { UserId = 2 }
    self.players = { stranger }
    self.now = self.now + self.cfg.Save.AutosaveSec
    self.save:Update()
    lu.assertNil(self.store.data[self.save:Key(2)])
end

function TestSave:test_bind_to_close_flushes_all_online_players()
    self.save:Start()
    lu.assertNotNil(self.boundClose)
    self.players = { self.me }
    self.data.Data.FishCoin = 44
    self.boundClose()
    lu.assertEquals(self.store.data[self.save:Key(1)].coin, 44)
    lu.assertEquals(self.save.Ledger[1].LastReason, 'shutdown')
end

function TestSave:test_load_into_skips_apply_when_player_touched_data()
    self.data.Data.FishCoin = 66
    self.store.data[self.save:Key(9)] = self.data:Serialize()
    local player9, d9 = self.newData(9)
    d9.Touched = true -- 读档期间玩家已经操作过（喂了鱼/丢格/换区）
    self.save:LoadInto(player9, d9)
    lu.assertEquals(d9.Data.FishCoin, 0) -- 旧档不覆盖新操作
    lu.assertEquals(self.syncs, 0)
end

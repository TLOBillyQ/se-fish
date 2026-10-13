-- #88 迁移：存档序列化与读写（原 tests/gameplay/save_test.lua，16 例）。
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
-- it 按旧 LuaUnit 的方法名字典序注册，保持与旧套件一致的案例顺序。
-- 夹具必须恢复三样：共享配置（GameCfg.Debug / Save.AcceptanceSlot，槽位由 helper 建基线、
-- 案例内改动在本例结束时还原）、模块缓存 package.loaded['server.Mgr.MgrSave']、全局 _G.game。
local GameCfg = require('common.GameCfg')

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

describe('TestSave', function()
    local env, savedDebug, savedSlot, savedGame, savedSaveModule

    -- 逐例夹具：旧 LuaUnit 每例跑 setUp/tearDown，这里同样用 before_each/after_each。
    -- before_each 依次快照 Debug / AcceptanceSlot / _G.game / MgrSave 模块缓存，
    -- 全部保存在改任何状态之前，因此夹具中途抛错时 after_each 仍能逐项还原。
    before_each(function()
        savedDebug = GameCfg.Debug
        savedSlot = GameCfg.Save.AcceptanceSlot
        savedGame = rawget(_G, 'game')
        savedSaveModule = package.loaded['server.Mgr.MgrSave']
        package.loaded['server.Mgr.MgrSave'] = nil
        GameCfg.Debug = { Enabled = true, InitialGrants = savedDebug.InitialGrants }
        GameCfg.Save.AcceptanceSlot = ''
        env = { cfg = GameCfg, ops = {}, waits = {}, players = {}, dataInsts = {}, spawnQueue = {} }
        env.failGet, env.failSet, env.failUpdate, env.casConflicts = 0, 0, 0, 0
        env.store = fakeStore(env)
        env.spawned = 0
        env.deferSpawn = false -- true 时 Spawn 只排队，flushSpawns 才执行（用来观察入队合并）
        env.now = 100
        local function flushSpawns()
            while #env.spawnQueue > 0 do
                local fn = table.remove(env.spawnQueue, 1)
                fn()
            end
        end
        env.flushSpawns = flushSpawns
        env.task = {
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
        env.save = assert(loadfile('server/Mgr/MgrSave.lua'))()
        env.syncs = 0
        env.save.PlayerData = {
            SendItemBar = function() env.syncs = env.syncs + 1 end,
            GetDataInst = function(_, p) return env.dataInsts[p] end,
        }
        local PlayerData = assert(loadfile('server/Data/PlayerData.lua'))()
        env.newData = function(userId)
            local p = { UserId = userId, SetAttribute = function() end }
            local data = PlayerData.New(p)
            data:Init()
            env.dataInsts[p] = data
            return p, data
        end
        env.me, env.data = env.newData(1)
        env.save:LoadInto(env.me, env.data)
        env.ops, env.waits, env.syncs = {}, {}, 0
        env.save.Ledger = {}
    end)
    after_each(function()
        GameCfg.Save.AcceptanceSlot = savedSlot
        GameCfg.Debug = savedDebug
        package.loaded['server.Mgr.MgrSave'] = savedSaveModule
        _G.game = savedGame
        savedDebug, savedSlot, savedGame, savedSaveModule = nil, nil, nil, nil
        env = nil
    end)

    it('test_acceptance_slot_keeps_keys_isolated_and_pinned_for_the_session', function()
        assert.same('u1', env.save:Key(1))
        env.cfg.Save.AcceptanceSlot = 'qa93-first'
        assert.same('u1', env.save:Key(1)) -- 本局内修改配置不改变写入目标
        local another = assert(loadfile('server/Mgr/MgrSave.lua'))()
        assert.same('u1:qa:qa93-first', another:Key(1))
        env.cfg.Save.AcceptanceSlot = 'qa93-second'
        assert.same('u1:qa:qa93-first', another:Key(1))
    end)

    it('test_apply_save_rejects_garbage_without_partial_recovery', function()
        local _, d2 = env.newData(2)
        local before = d2:Serialize()
        assert.is_false(d2:ApplySave({
            v = 1, coin = -50, up = 99, zone = 42,
            bar = { { i = 1, id = 'ghostItem', n = 1 }, { i = 99, id = 'duck', n = 1 }, { i = 2, id = 'duck', n = 'x' } },
            bp = { { i = 1, id = 'shrimpTicket', n = 1 } },
            bait = { sausage = 3, ghostBait = 9, worm = -2 },
        }))
        assert.same(d2:Serialize(), before)
    end)

    it('test_autosave_periodically_saves_online_players', function()
        env.players = { env.me }
        env.data.Data.FishCoin = 33
        env.save:Update() -- 第一次只定下一次存档时刻
        assert.same(0, env.store.data[env.save:Key(1)].coin)
        env.now = env.now + env.cfg.Save.AutosaveSec - 1
        env.save:Update() -- 还没到点
        assert.same(0, env.store.data[env.save:Key(1)].coin)
        env.now = env.now + 1
        env.save:Update() -- 到点：在线玩家落档
        assert.same(33, env.store.data[env.save:Key(1)].coin)
        assert.same('autosave', env.save.Ledger[1].LastReason)
        -- 离场（不在线）玩家不自动存
        local stranger = { UserId = 2 }
        env.players = { stranger }
        env.now = env.now + env.cfg.Save.AutosaveSec
        env.save:Update()
        assert.is_nil(env.store.data[env.save:Key(2)])
    end)

    it('test_bind_to_close_flushes_all_online_players', function()
        env.save:Start()
        assert.is_not_nil(env.boundClose)
        env.players = { env.me }
        env.data.Data.FishCoin = 44
        env.boundClose()
        assert.same(44, env.store.data[env.save:Key(1)].coin)
        assert.same('shutdown', env.save.Ledger[1].LastReason)
    end)

    it('test_commit_uses_update_async_and_survives_cas_conflict', function()
        env.data.Data.FishCoin = 10
        env.casConflicts = 1 -- transform 会被调两次（模拟冲突重算）
        local ok = env.save:Commit(1, env.data:Serialize(), 'exchange:eelHead')
        assert.is_true(ok)
        -- 只走 UpdateAsync，不走 SetAsync
        local setOps, updateOps = 0, 0
        for _, op in ipairs(env.ops) do
            if op == 'set' then setOps = setOps + 1 end
            if op == 'update' then updateOps = updateOps + 1 end
        end
        assert.same(0, setOps)
        assert.is_true(updateOps >= 1)
        assert.same(10, env.store.data[env.save:Key(1)].coin)
        -- 记账失败重试：第一次 update 失败也能补上
        env.failUpdate = 1
        env.data.Data.FishCoin = 11
        assert.is_true(env.save:Commit(1, env.data:Serialize(), 'ferry:ticket'))
        assert.same(11, env.store.data[env.save:Key(1)].coin)
    end)

    it('test_config_has_store_retry_policy', function()
        local cfg = assert(loadfile('common/GameCfg.lua'))()
        assert.same('string', type(cfg.Save.Store))
        assert.same('string', type(cfg.Save.KeyPrefix))
        assert.is_true(cfg.Save.MaxRetries >= 2)
        assert.is_true(cfg.Save.RetryDelaySec > 0)
        assert.is_true(cfg.Save.AutosaveSec > 0)
    end)

    it('test_enqueue_merges_to_latest_snapshot_per_player', function()
        -- 排空任务还没跑就连来两笔：只落最新快照（旧 Set 不会盖新 Commit，反之同理）
        env.deferSpawn = true
        env.data.Data.FishCoin = 10
        assert.is_true(env.save:Save(1, env.data:Serialize(), 'a'))
        env.data.Data.FishCoin = 20
        assert.is_true(env.save:Commit(1, env.data:Serialize(), 'b'))
        assert.same(0, #env.ops) -- 还没排空
        env.flushSpawns()
        local updates = 0
        for _, op in ipairs(env.ops) do
            if op == 'update' then updates = updates + 1 end
            assert.not_same('set', op) -- 旧快照被合并掉了，不会先 set 10
        end
        assert.same(1, updates)
        assert.same(20, env.store.data[env.save:Key(1)].coin)
        -- 排空后队列清空，后续写入重新起一轮
        assert.is_nil(env.save.Pending[1])
        assert.is_nil(env.save.Flying[1])
    end)

    it('test_exchange_snapshot_rejoin_has_no_double_grant', function()
        -- 兑换落账后（信物扣了、鸭子发了）序列化；重进读档只能看到一份结果
        local d = env.data
        assert.is_true(d:AddItem('eelHead'))
        -- 手动复演兑换落账：扣信物、发鸭子
        assert.is_true(d:ExchangeSlot(2, 'duck'))
        assert.same(0, d:ItemCount('eelHead'))
        assert.same(1, d:ItemCount('duck'))
        env.casConflicts = 0
        assert.is_true(env.save:Commit(1, d:Serialize(), 'exchange:eelHead'))
        -- 断线重连：新 Data 读档
        local _, d2 = env.newData(1)
        local loaded = env.save:Load(1)
        assert.is_not_nil(loaded)
        assert.is_true(d2:ApplySave(loaded))
        assert.same(1, d2:ItemCount('duck'))     -- 只有一份鸭子
        assert.same(0, d2:ItemCount('eelHead'))  -- 信物不复活
    end)

    it('test_invalid_acceptance_slot_fails_before_any_key_is_used', function()
        env.cfg.Save.AcceptanceSlot = false
        local another = assert(loadfile('server/Mgr/MgrSave.lua'))()
        assert.has_error(function() another:Key(1) end)
        env.cfg.Save.AcceptanceSlot = '../unsafe'
        assert.has_error(function() another:Key(1) end)
    end)

    it('test_ledger_tracks_size_and_write_count', function()
        assert.is_true(env.save:Save(1, env.data:Serialize(), 'a'))
        assert.is_true(env.save:Save(1, env.data:Serialize(), 'b'))
        local ledger = env.save.Ledger[1]
        assert.is_not_nil(ledger)
        assert.same(2, ledger.Writes)
        assert.is_true(ledger.Bytes > 0)
        assert.is_not_nil(ledger.LastReason)
        -- 东西越多体积越大
        local small = env.save:EstimateSize(env.data:Serialize())
        assert.is_true(env.data:AddItem('duck'))
        assert.is_true(env.data:AddItem('shrimpTicket'))
        assert.is_true(env.data:AddBait('sausage', 5))
        local big = env.save:EstimateSize(env.data:Serialize())
        assert.is_true(big > small)
    end)

    it('test_load_into_applies_save_and_syncs_client', function()
        env.data.Data.FishCoin = 66
        assert.is_true(env.data:AddItem('duck'))
        env.store.data[env.save:Key(9)] = env.data:Serialize()
        local player9, d9 = env.newData(9)
        env.save:LoadInto(player9, d9)
        assert.same(66, d9.Data.FishCoin)
        assert.same(1, d9:ItemCount('duck'))
        assert.same(1, env.syncs) -- 恢复后推了一次 ItemBarState
        -- 新档同样发送 ready 快照。
        env.save:LoadInto(env.me, env.data)
        assert.same(2, env.syncs)
    end)

    it('test_load_into_never_discards_old_property_because_of_touched_flag', function()
        env.data.Data.FishCoin = 66
        env.store.data[env.save:Key(9)] = env.data:Serialize()
        local player9, d9 = env.newData(9)
        d9.Touched = true
        env.save:LoadInto(player9, d9)
        assert.same(66, d9.Data.FishCoin)
        assert.same(1, env.syncs)
    end)

    it('test_load_retries_then_succeeds_and_gives_up_without_touching_memory', function()
        env.store.data[env.save:Key(1)] = env.data:Serialize()
        -- 前两次失败第三次成功
        env.failGet = 2
        local loaded = env.save:Load(1)
        assert.is_not_nil(loaded)
        assert.same(2, #env.waits) -- 每次失败等 RetryDelaySec
        -- 永远失败：返回 nil，内存态不变；GetAsync 总调用次数 = 3(成功路) + MaxRetries(失败路)
        env.failGet = 99
        env.data.Data.FishCoin = 77
        assert.is_nil(env.save:Load(1))
        assert.same(77, env.data.Data.FishCoin)
        assert.same(3 + env.cfg.Save.MaxRetries, #env.ops)
    end)

    it('test_save_failure_keeps_memory_and_reports', function()
        env.failUpdate = 99
        env.data.Data.FishCoin = 88
        -- 失败保留原 job 与写身份，恢复后 Update 再排空。
        assert.is_true(env.save:Save(1, env.data:Serialize(), 'test'))
        assert.same(88, env.data.Data.FishCoin)
        assert.same(0, env.store.data[env.save:Key(1)].coin)
        assert.same(env.cfg.Save.MaxRetries - 1, #env.waits)
        env.failUpdate = 0
        env.save:Update()
        assert.same(88, env.store.data[env.save:Key(1)].coin)
    end)

    it('test_serialize_roundtrip_restores_coin_slots_bait_upgrade_zone', function()
        local d = env.data
        d.Data.FishCoin = 45
        d.Data.UpgradeLevel = 1
        d.Data.Zone = 'ShrimpPool'
        assert.is_true(d:AddItem('duck'))
        assert.is_true(d:AddItem('shrimpTicket'))
        assert.is_true(d:AddBait('sausage', 3))
        -- 造一个带倍率的鱼获在背包里
        assert.is_true(d:AddItem('riverShrimp', 1.14))
        local snapshot = d:Serialize()
        assert.same(2, snapshot.v)
        -- 全新玩家读档
        local player2, d2 = env.newData(2)
        assert.is_true(d2:ApplySave(snapshot))
        assert.same(45, d2.Data.FishCoin)
        assert.same(1, d2.Data.UpgradeLevel)
        assert.same('ShrimpPool', d2.Data.Zone)
        assert.same(3, d2.Data.Bait.sausage)
        assert.same(d.Data.Bait.worm, d2.Data.Bait.worm) -- 白送蚯蚓也在
        -- 格子位置逐项一致（含 mult）
        local bar1 = d.Data.Containers.itemBar
        local bar2 = d2.Data.Containers.itemBar
        for i = 1, 8 do
            local a, b = bar1[i], bar2[i]
            if a then
                assert.message('itemBar ' .. i).is_not_nil(b)
                assert.same({ a.itemId, a.count, a.mult }, { b.itemId, b.count, b.mult })
            else
                assert.message('itemBar ' .. i).is_nil(b)
            end
        end
        local bp1 = d.Data.Containers.backpack
        local bp2 = d2.Data.Containers.backpack
        for i = 1, 10 do
            local a, b = bp1[i], bp2[i]
            if a then
                assert.message('backpack ' .. i).is_not_nil(b)
                assert.same({ a.itemId, a.count, a.mult }, { b.itemId, b.count, b.mult })
            else
                assert.message('backpack ' .. i).is_nil(b)
            end
        end
        assert.same(1, d2:ItemCount('duck'))
        assert.same(1, d2:ItemCount('shrimpTicket'))
    end)

    it('test_unavailable_service_closes_persistence', function()
        env.save.StoreChecked, env.save.Store = false, nil
        _G.game = { GetService = function(_, name)
            if name == 'Task' then return env.task end
            if name == 'DataStoreService' then error('service missing') end
        end }
        assert.is_nil(env.save:Load(1))
        assert.is_false(env.save:Save(1, env.data:Serialize(), 'x'))
        assert.is_false(env.save:Commit(1, env.data:Serialize(), 'x'))
        -- 不抛错、不刷屏重试（服务都没有，谈不上限流重试）
        assert.same(0, #env.waits)
    end)
end)

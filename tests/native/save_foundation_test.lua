-- #88 迁移：存档地基（原 tests/gameplay/save_foundation_test.lua，9 例）。
-- #123 失败方式先列：pending/failed 可变操作与空档写；v1 财产/实例丢失；坏档或未知版本被洗白；
-- 写成功回包丢失、重试重复扣费；旧会话回调覆盖新会话；操作日志清理后重放；离场/关服漏写。
-- seam：真实 PlayerData 迁移与 MgrSave 公共接口；只替换 Task/DataStore 引擎边界。
-- it 按旧 LuaUnit 的方法名字典序注册，保持与旧套件一致的案例顺序。
-- 引擎边界替身必须写真实全局（_G.game）：MgrSave 由 loadfile 得到独立 chunk，
-- 其 _ENV 是真实 _G，Busted 的逐文件沙箱里裸赋值只改沙箱、模块读不到。
local PlayerData = require('server.Data.PlayerData')

describe('TestSaveFoundation', function()
    local env, savedGame

    -- 逐例夹具：旧 LuaUnit 每例都跑 setUp/tearDown，这里同样用 before_each/after_each。
    -- before_each 第一步保存 _G.game 原值，因此夹具中途抛错时 after_each 仍能恢复全局。
    before_each(function()
        savedGame = rawget(_G, 'game')
        env = { values = {}, queue = {} }
        env.store = {
            GetAsync = function(_, key)
                if env.readFailure then error('读档失败') end
                return env.values[key]
            end,
            UpdateAsync = function(_, key, transform)
                if env.writeFailure then error('写档失败') end
                local value = transform(env.values[key])
                if value then env.values[key] = value end
                if env.loseReply then env.loseReply = false error('写成功但回包丢失') end
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
        env.save = assert(loadfile('server/Mgr/MgrSave.lua'))()
    end)
    after_each(function()
        _G.game = savedGame
        savedGame = nil
        env = nil
    end)

    local function drain()
        while #env.queue > 0 do table.remove(env.queue, 1)() end
    end

    local function join(id)
        local player = { UserId = id, SetAttribute = function() end }
        local data = PlayerData.New(player)
        data:Init(true)
        env.save:LoadInto(player, data)
        return player, data
    end

    it('test_callback_failure_does_not_block_following_write', function()
        local player, data = join(61)
        drain()
        local op = env.save:NextOperation(player, 'bonus')
        assert.is_true(env.save:Execute(player, data, op, function(draft)
            draft:AddCoin(1)
            return { paid = 1 }
        end, function() error('回包失败') end))
        drain()
        assert.is_true(data:AddCoin(1))
        assert.is_true(env.save:Save(61, data:Serialize(), 'next'))
        drain()
        assert.same(2, env.values.u61.coin)
    end)

    it('test_corrupt_selection_and_oversized_save_never_claim_ready', function()
        local player, data = join(70)
        drain()
        local save = data:Serialize()
        save.extra.inventory.selection = nil
        assert.is_false(data:ApplySave(save))
        assert.same('ready', data.LoadState)
        data.Extra.story.read.huge = string.rep('中', 90000)
        assert.is_false(env.save:Save(70, data:Serialize(), 'oversized'))
        assert.is_nil(env.values.u70.extra.story.read.huge)
    end)

    it('test_failed_load_never_becomes_new_save_and_old_callback_cannot_publish', function()
        env.readFailure = true
        local player, data = join(20)
        drain()
        assert.same('failed', data.LoadState)
        assert.is_false(env.save:Save(20, { v = 1, coin = 0 }, 'leave'))
        assert.is_nil(env.values.u20)
        env.readFailure = false
        local _, stale = join(21)
        local _, current = join(21)
        drain()
        assert.is_false(stale.Inited)
        assert.same('ready', current.LoadState)
        assert.is_not_nil(current:Serialize().meta.session)
    end)

    it('test_log_is_bounded_and_cleaned_identity_cannot_replay', function()
        local player, data = join(41)
        drain()
        local first
        for i = 1, 65 do
            local op = env.save:NextOperation(player, 'reward')
            first = first or op
            assert.is_true(env.save:Execute(player, data, op, function(draft)
                draft:AddCoin(1)
                return { coin = i }
            end, function() end))
            drain()
        end
        assert.same(65, data.Data.FishCoin)
        assert.same(64, #data:Serialize().meta.operations)
        local ok, reason = env.save:Execute(player, data, first, function() error('不能重新执行') end, function() end)
        assert.is_false(ok)
        assert.same('expired', reason)
    end)

    it('test_operation_lost_reply_retry_rejoin_and_expired_identity_never_double_charge', function()
        local player, data = join(30)
        drain()
        data:AddCoin(100)
        local op = env.save:NextOperation(player, 'buy-rod')
        local result
        env.loseReply = true
        local function buy(draft)
            if not draft:SpendCoin(5, nil, 'buy-rod') then return nil, 'coin' end
            draft:GrantItem('starterRod', 1)
            return { paid = 5, item = 'starterRod' }
        end
        assert.is_true(env.save:Execute(player, data, op, buy, function(ok, value) result = { ok, value } end))
        assert.is_false(data:AddCoin(999))
        drain()
        assert.is_true(result[1])
        assert.same(95, data.Data.FishCoin)
        local count = data:ItemCount('starterRod')
        local _, rejoined = join(30)
        drain()
        assert.is_true(env.save:Execute(rejoined.Player, rejoined, op, buy, function(ok, value) result = { ok, value } end))
        drain()
        assert.same(95, rejoined.Data.FishCoin)
        assert.same(count, rejoined:ItemCount('starterRod'))
        assert.same(5, result[2].paid)
        assert.same(1, #rejoined:Serialize().meta.operations)
    end)

    it('test_pending_rejects_mutation_and_snapshot_until_explicit_new_save', function()
        local data = PlayerData.New({ UserId = 123, SetAttribute = function() end })
        data:Init(true)
        assert.same('pending', data.LoadState)
        assert.is_false(data:AddCoin(10))
        assert.is_false(data:AddBait('worm', 1))
        assert.is_nil(data:Serialize())
        assert.is_true(data:CompleteLoad(nil))
        assert.same('ready', data.LoadState)
        assert.is_true(data:AddCoin(10))
        assert.same(10, data:Serialize().coin)
    end)

    it('test_resolve_request_replays_only_exact_identity_after_rejoin', function()
        local player, data = join(60)
        drain()
        local op, mode = env.save:ResolveRequest(player, data, 'shop', 7)
        assert.same('new', mode)
        local result
        assert.is_true(env.save:Execute(player, data, op, function(draft)
            draft:AddCoin(9)
            return { awarded = 9 }
        end, function(ok, value) result = value end))
        drain()
        assert.same(9, result.awarded)
        local nextPlayer, nextData = join(60)
        drain()
        local replay, replayMode = env.save:ResolveRequest(nextPlayer, nextData, 'shop', op)
        assert.same('replay', replayMode)
        assert.same(op.requestKey, replay.requestKey)
        op.id = '60:999'
        assert.is_nil(env.save:ResolveRequest(nextPlayer, nextData, 'shop', op))
    end)

    it('test_retry_queue_preserves_operation_and_rejects_old_session_write', function()
        local player, data = join(40)
        drain()
        data:AddCoin(20)
        local op = env.save:NextOperation(player, 'ticket')
        env.writeFailure = true
        local replies = 0
        assert.is_true(env.save:Execute(player, data, op, function(draft)
            draft:SpendCoin(7)
            draft.Extra.recovery.ticket = { operation = op.id, destination = 'shrimpPond', state = 'pending' }
            return { paid = 7 }
        end, function() replies = replies + 1 end))
        drain()
        assert.same(0, replies)
        assert.is_false(data.Inited)
        env.writeFailure = false
        env.save:Update()
        drain()
        assert.same(1, replies)
        assert.same(13, data.Data.FishCoin)
        assert.same('40:1', data:Serialize().extra.recovery.ticket.operation)
        local stale = data:Serialize()
        local _, current = join(40)
        drain()
        assert.is_false(env.save:Save(40, stale, 'old-session'))
        assert.is_false(data:AddCoin(1))
        assert.same(13, current.Data.FishCoin)
    end)

    it('test_v1_migrates_every_instance_and_bad_save_is_atomic', function()
        local data = PlayerData.New({ UserId = 124, SetAttribute = function() end })
        data:Init(true)
        local old = { v = 1, coin = 730, up = 1, zone = 'ShrimpPool', bait = { worm = 9 },
            bar = { { i = 2, id = 'eelHead', n = 1, m = 1.75 } },
            bp = { { i = 8, id = 'riverShrimp', n = 1, m = 1.14 } } }
        assert.is_true(data:CompleteLoad(old))
        local saved = data:Serialize()
        assert.same(2, saved.v)
        assert.same(730, saved.coin)
        assert.same(1.75, saved.bar[1].m)
        assert.same(8, saved.bp[1].i)
        assert.same(1.14, saved.bp[1].m)
        assert.same('ShrimpPool', saved.zone)
        assert.same(300, saved.extra.survival.health)
        assert.same({}, saved.extra.inventory.weapons)
        assert.same(1, old.v)
        saved.v = 500
        assert.is_false(data:ApplySave(saved))
        assert.same(730, data.Data.FishCoin)
        old.bar[1].m = 0 / 0
        assert.is_false(data:ApplySave(old))
        assert.same(1, data:ItemCount('eelHead'))
    end)
end)

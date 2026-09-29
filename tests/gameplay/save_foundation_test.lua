-- #123 失败方式先列：pending/failed 可变操作与空档写；v1 财产/实例丢失；坏档或未知版本被洗白；
-- 写成功回包丢失、重试重复扣费；旧会话回调覆盖新会话；操作日志清理后重放；离场/关服漏写。
-- seam：真实 PlayerData 迁移与 MgrSave 公共接口；只替换 Task/DataStore 引擎边界。
local lu = require('luaunit')
local PlayerData = require('server.Data.PlayerData')
TestSaveFoundation = {}

function TestSaveFoundation:setUp()
    self.oldGame = _G.game
    self.values, self.queue = {}, {}
    local env = self
    self.store = {
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
    self.save = assert(loadfile('server/Mgr/MgrSave.lua'))()
end

function TestSaveFoundation:tearDown() _G.game = self.oldGame end
function TestSaveFoundation:drain()
    while #self.queue > 0 do table.remove(self.queue, 1)() end
end
function TestSaveFoundation:join(id)
    local player = { UserId = id, SetAttribute = function() end }
    local data = PlayerData.New(player)
    data:Init(true)
    self.save:LoadInto(player, data)
    return player, data
end

function TestSaveFoundation:test_failed_load_never_becomes_new_save_and_old_callback_cannot_publish()
    self.readFailure = true
    local player, data = self:join(20)
    self:drain()
    lu.assertEquals(data.LoadState, 'failed')
    lu.assertFalse(self.save:Save(20, { v = 1, coin = 0 }, 'leave'))
    lu.assertNil(self.values.u20)
    self.readFailure = false
    local _, stale = self:join(21)
    local _, current = self:join(21)
    self:drain()
    lu.assertFalse(stale.Inited)
    lu.assertEquals(current.LoadState, 'ready')
    lu.assertNotNil(current:Serialize().meta.session)
end

function TestSaveFoundation:test_operation_lost_reply_retry_rejoin_and_expired_identity_never_double_charge()
    local player, data = self:join(30)
    self:drain()
    data:AddCoin(100)
    local op = self.save:NextOperation(player, 'buy-rod')
    local result
    self.loseReply = true
    local function buy(draft)
        if not draft:SpendCoin(5, nil, 'buy-rod') then return nil, 'coin' end
        draft:GrantItem('starterRod', 1)
        return { paid = 5, item = 'starterRod' }
    end
    lu.assertTrue(self.save:Execute(player, data, op, buy, function(ok, value) result = { ok, value } end))
    lu.assertFalse(data:AddCoin(999))
    self:drain()
    lu.assertTrue(result[1])
    lu.assertEquals(data.Data.FishCoin, 95)
    local count = data:ItemCount('starterRod')
    local _, rejoined = self:join(30)
    self:drain()
    lu.assertTrue(self.save:Execute(rejoined.Player, rejoined, op, buy, function(ok, value) result = { ok, value } end))
    self:drain()
    lu.assertEquals(rejoined.Data.FishCoin, 95)
    lu.assertEquals(rejoined:ItemCount('starterRod'), count)
    lu.assertEquals(result[2].paid, 5)
    lu.assertEquals(#rejoined:Serialize().meta.operations, 1)
end

function TestSaveFoundation:test_retry_queue_preserves_operation_and_rejects_old_session_write()
    local player, data = self:join(40)
    self:drain()
    data:AddCoin(20)
    local op = self.save:NextOperation(player, 'ticket')
    self.writeFailure = true
    local replies = 0
    lu.assertTrue(self.save:Execute(player, data, op, function(draft)
        draft:SpendCoin(7)
        draft.Extra.recovery.ticket = { operation = op.id, destination = 'shrimpPond', state = 'pending' }
        return { paid = 7 }
    end, function() replies = replies + 1 end))
    self:drain()
    lu.assertEquals(replies, 0)
    lu.assertFalse(data.Inited)
    self.writeFailure = false
    self.save:Update()
    self:drain()
    lu.assertEquals(replies, 1)
    lu.assertEquals(data.Data.FishCoin, 13)
    lu.assertEquals(data:Serialize().extra.recovery.ticket.operation, '40:1')
    local stale = data:Serialize()
    local _, current = self:join(40)
    self:drain()
    lu.assertFalse(self.save:Save(40, stale, 'old-session'))
    lu.assertFalse(data:AddCoin(1))
    lu.assertEquals(current.Data.FishCoin, 13)
end

function TestSaveFoundation:test_log_is_bounded_and_cleaned_identity_cannot_replay()
    local player, data = self:join(41)
    self:drain()
    local first
    for i = 1, 65 do
        local op = self.save:NextOperation(player, 'reward')
        first = first or op
        lu.assertTrue(self.save:Execute(player, data, op, function(draft)
            draft:AddCoin(1)
            return { coin = i }
        end, function() end))
        self:drain()
    end
    lu.assertEquals(data.Data.FishCoin, 65)
    lu.assertEquals(#data:Serialize().meta.operations, 64)
    local ok, reason = self.save:Execute(player, data, first, function() error('不能重新执行') end, function() end)
    lu.assertFalse(ok)
    lu.assertEquals(reason, 'expired')
end

function TestSaveFoundation:test_resolve_request_replays_only_exact_identity_after_rejoin()
    local player, data = self:join(60)
    self:drain()
    local op, mode = self.save:ResolveRequest(player, data, 'shop', 7)
    lu.assertEquals(mode, 'new')
    local result
    lu.assertTrue(self.save:Execute(player, data, op, function(draft)
        draft:AddCoin(9)
        return { awarded = 9 }
    end, function(ok, value) result = value end))
    self:drain()
    lu.assertEquals(result.awarded, 9)
    local nextPlayer, nextData = self:join(60)
    self:drain()
    local replay, replayMode = self.save:ResolveRequest(nextPlayer, nextData, 'shop', op)
    lu.assertEquals(replayMode, 'replay')
    lu.assertEquals(replay.requestKey, op.requestKey)
    op.id = '60:999'
    lu.assertNil(self.save:ResolveRequest(nextPlayer, nextData, 'shop', op))
end

function TestSaveFoundation:test_callback_failure_does_not_block_following_write()
    local player, data = self:join(61)
    self:drain()
    local op = self.save:NextOperation(player, 'bonus')
    lu.assertTrue(self.save:Execute(player, data, op, function(draft)
        draft:AddCoin(1)
        return { paid = 1 }
    end, function() error('回包失败') end))
    self:drain()
    lu.assertTrue(data:AddCoin(1))
    lu.assertTrue(self.save:Save(61, data:Serialize(), 'next'))
    self:drain()
    lu.assertEquals(self.values.u61.coin, 2)
end

function TestSaveFoundation:test_corrupt_selection_and_oversized_save_never_claim_ready()
    local player, data = self:join(70)
    self:drain()
    local save = data:Serialize()
    save.extra.inventory.selection = nil
    lu.assertFalse(data:ApplySave(save))
    lu.assertEquals(data.LoadState, 'ready')
    data.Extra.story.read.huge = string.rep('中', 90000)
    lu.assertFalse(self.save:Save(70, data:Serialize(), 'oversized'))
    lu.assertNil(self.values.u70.extra.story.read.huge)
end

function TestSaveFoundation:test_pending_rejects_mutation_and_snapshot_until_explicit_new_save()
    local data = PlayerData.New({ UserId = 123, SetAttribute = function() end })
    data:Init(true)
    lu.assertEquals(data.LoadState, 'pending')
    lu.assertFalse(data:AddCoin(10))
    lu.assertFalse(data:AddBait('worm', 1))
    lu.assertNil(data:Serialize())
    lu.assertTrue(data:CompleteLoad(nil))
    lu.assertEquals(data.LoadState, 'ready')
    lu.assertTrue(data:AddCoin(10))
    lu.assertEquals(data:Serialize().coin, 10)
end

function TestSaveFoundation:test_v1_migrates_every_instance_and_bad_save_is_atomic()
    local data = PlayerData.New({ UserId = 124, SetAttribute = function() end })
    data:Init(true)
    local old = { v = 1, coin = 730, up = 1, zone = 'ShrimpPool', bait = { worm = 9 },
        bar = { { i = 2, id = 'eelHead', n = 1, m = 1.75 } },
        bp = { { i = 8, id = 'riverShrimp', n = 1, m = 1.14 } } }
    lu.assertTrue(data:CompleteLoad(old))
    local saved = data:Serialize()
    lu.assertEquals(saved.v, 2)
    lu.assertEquals(saved.coin, 730)
    lu.assertEquals(saved.bar[1].m, 1.75)
    lu.assertEquals(saved.bp[1].i, 8)
    lu.assertEquals(saved.bp[1].m, 1.14)
    lu.assertEquals(saved.zone, 'ShrimpPool')
    lu.assertEquals(saved.extra.survival.health, 300)
    lu.assertEquals(saved.extra.inventory.weapons, {})
    lu.assertEquals(old.v, 1)
    saved.v = 500
    lu.assertFalse(data:ApplySave(saved))
    lu.assertEquals(data.Data.FishCoin, 730)
    old.bar[1].m = 0/0
    lu.assertFalse(data:ApplySave(old))
    lu.assertEquals(data:ItemCount('eelHead'), 1)
end

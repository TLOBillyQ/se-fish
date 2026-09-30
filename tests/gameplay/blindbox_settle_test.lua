-- #147 T26 盲盒服务端结算（server/Mgr/MgrBlindbox.lua）失败方式先列：
--   1. 校验漏洞：payload 畸形（无 action/seq）、count 不是 1 或 10、同 seq 重复点击被接受；
--   2. 扣费顺序错：没等平台购买成功就抽（先发货后扣费）；购买取消/失败/超时却照发奖或动了保底计数；
--   3. 保底衔接错：Extra.lottery.pity 没进 draft（十连跨保底线不触发）、落账后 pity 写不回存档；
--   4. 满格落地错：无空格时抽中物消失（没走 Loot:SpawnItem）、或重放结果时重复落地；
--   5. 幂等错：同 seq 重试重复扣费/重复发奖；重进后 pity 丢失、State 握手不回包；
--   6. 生产守卫漏：Debug 关 + 商品未配置时仍放行（应明确 unavailable 不发付费权益）；
--   7. 并发错：购买 flow 在飞时第二抽被接受（应 busy）；flow 结算串到别的请求。
-- seam：MgrBlindbox:Handle / Settle / PushState / OnPlayerAdded；真实 MgrSave + MgrPlayerData +
--   MgrPlatform（#123 持久操作协议），替换引擎边界（game / REUtil / DataStore / 时钟）；
--   随机数经 MgrBlindbox.Random 注入（脚本化序列锁定权重区间与保底时机）；Loot 替身记录落地。
local lu = require('luaunit')
local GameCfg = require('common.GameCfg')

TestBlindboxSettle = {}

local function signal()
    local s = { handlers = {} }
    function s:Connect(fn)
        self.handlers[#self.handlers + 1] = fn
        return { Disconnect = function() end }
    end
    function s:Fire(...) for _, fn in ipairs(self.handlers) do fn(...) end end
    return s
end

function TestBlindboxSettle:setUp()
    self.oldGame, self.oldRE = _G.game, _G.REUtil
    self.oldDebug = GameCfg.Debug
    self.oldGoodsIds = {}
    for key, row in pairs(GameCfg.Platform.Goods) do self.oldGoodsIds[key] = row.goodsId end
    GameCfg.Debug = { Enabled = true } -- 未配置商品走 pending flow + 测试驱动器
    self.now = 1000
    self.values, self.queue, self.events = {}, {}, {}
    local env = self
    self.spawned = {} -- Loot 替身落地记录
    self.goodsSignal = signal()
    local store = {
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
        if name == 'DataStoreService' then return { GetDataStore = function() return store end } end
        if name == 'World' then return { GetServerTime = function() return env.now end } end
        if name == 'Players' then return { GetPlayers = function() return {} end } end
        if name == 'CommodityService' then return {
            ShowGoodsPurchasePanel = function() end,
            GoodsPurchaseCompleted = env.goodsSignal,
        } end
    end }
    _G.REUtil = { GetRE = function(_, name) return { FireClient = function(_, player, value)
        env.events[#env.events + 1] = { name = name, player = player, value = value }
    end, OnServerEvent = signal() } end,
        CheckRECD = function() return false end }
    self.save = assert(loadfile('server/Mgr/MgrSave.lua'))()
    self.players = assert(loadfile('server/Mgr/MgrPlayerData.lua'))()
    self.platform = assert(loadfile('server/Mgr/MgrPlatform.lua'))()
    self.blindbox = assert(loadfile('server/Mgr/MgrBlindbox.lua'))()
    self.players.Save, self.save.PlayerData = self.save, self.players
    self.platform.Save, self.platform.PlayerData = self.save, self.players
    self.blindbox.Save, self.blindbox.PlayerData, self.blindbox.Platform = self.save, self.players, self.platform
    self.blindbox.Loot = { DeliveryEpoch = 'test-world', SpawnDelivery = function(_, key, itemId, mult, cooked, pos)
        env.delivered = env.delivered or {}
        if env.delivered[key] then return env.delivered[key] end
        local loot = env.blindbox.Loot:SpawnItem(itemId, mult, cooked, pos)
        env.delivered[key] = loot
        return loot
    end, SpawnItem = function(_, itemId, mult, cooked, pos)
        env.spawned[#env.spawned + 1] = { itemId = itemId, mult = mult, cooked = cooked, pos = pos }
        return { Id = 'loot' .. #env.spawned }
    end }
    self.rolls = {}
    self.blindbox.Random = function()
        local roll = table.remove(env.rolls, 1)
        assert(roll, '测试脚本 RNG 序列耗尽')
        return roll
    end
    self.platform.Now = function() return env.now end
    self.platform:Start()
    self.blindbox:Start()
    self.player = { UserId = 1472, Character = { Position = { x = 3, y = 0, z = 5 } },
        CharacterAdded = signal(), CharacterRemoving = signal(), SetAttribute = function() end }
    self.players:OnPlayerAdded(self.player)
    self:drain()
    self.data = self.players:GetDataInst(self.player)
    self:persistReady()
end

function TestBlindboxSettle:tearDown()
    _G.game, _G.REUtil = self.oldGame, self.oldRE
    GameCfg.Debug = self.oldDebug
    for key, row in pairs(GameCfg.Platform.Goods) do row.goodsId = self.oldGoodsIds[key] end
end

function TestBlindboxSettle:drain()
    while #self.queue > 0 do table.remove(self.queue, 1)() end
end

function TestBlindboxSettle:messages(name)
    local values = {}
    for _, event in ipairs(self.events) do if event.name == name then values[#values + 1] = event.value end end
    return values
end

function TestBlindboxSettle:persistReady()
    lu.assertTrue(self.save:SaveExplicit(self.player.UserId, self.data, function(ok) lu.assertTrue(ok) end))
    self:drain()
    self.events = {}
end

-- 脚本化抽一发（count=1 或 10）：发起 → 驱动购买成功 → 跑完持久队列
function TestBlindboxSettle:draw(count, seq, outcome)
    local accepted = self.blindbox:Handle(self.player,
        { action = 'Draw', count = count, seq = seq })
    self:drain() -- 支付意图先持久化，再建立测试 flow
    if accepted and outcome then
        lu.assertTrue(self.platform:HandleTestAction(self.player,
            { action = 'ResolveFlow', outcome = outcome }))
        self:drain()
    end
    return accepted
end

function TestBlindboxSettle:lastResult()
    local results = self:messages('BlindboxResult')
    return results[#results]
end

-- 校验：畸形 payload / 非法 count / 非法 seq 一律拒绝，不建 flow、不回包
function TestBlindboxSettle:test_malformed_payloads_rejected()
    lu.assertFalse(self.blindbox:Handle(self.player, nil))
    lu.assertFalse(self.blindbox:Handle(self.player, { action = 'Peek', count = 1, seq = 1 }))
    lu.assertFalse(self.blindbox:Handle(self.player, { action = 'Draw', count = 3, seq = 1 }))
    lu.assertFalse(self.blindbox:Handle(self.player, { action = 'Draw', count = '10', seq = 1 }))
    lu.assertFalse(self.blindbox:Handle(self.player, { action = 'Draw', count = 1 }))
    lu.assertFalse(self.blindbox:Handle(self.player, { action = 'Draw', count = 1, seq = 0 }))
    lu.assertFalse(self.blindbox:Handle(self.player, { action = 'Draw', count = 1, seq = 1.5 }))
    lu.assertFalse(self.platform:HasFlow(self.player))
    lu.assertEquals(self:messages('BlindboxResult'), {})
end

-- 单抽：购买成功后抽中物进道具栏，pity 落账，回包带逐抽明细
function TestBlindboxSettle:test_single_draw_grants_after_payment_success()
    self.rolls = { 1000 } -- 末权重：极品罗非鱼
    lu.assertTrue(self:draw(1, 1, 'success'))
    lu.assertEquals(self.data:ItemCount('item7'), 1)
    lu.assertEquals(self.data.Extra.lottery.pity, 1)
    local result = self:lastResult()
    lu.assertTrue(result.ok)
    lu.assertEquals(result.count, 1)
    lu.assertEquals(#result.draws, 1)
    lu.assertEquals(result.draws[1].itemKey, 'item7')
    lu.assertFalse(result.draws[1].jackpot)
    lu.assertEquals(result.pityBefore, 0)
    lu.assertEquals(result.pityAfter, 1)
    lu.assertEquals(self.spawned, {})
end

-- 取消/失败/超时：不发奖、不动 pity，回包带原因；同一 seq 可以重试（未落账不记账）
function TestBlindboxSettle:test_failed_payment_grants_nothing_and_keeps_pity()
    for index, outcome in ipairs({ 'cancel', 'fail', 'timeout' }) do
        self.events = {}
        if outcome == 'timeout' then
            lu.assertTrue(self.blindbox:Handle(self.player, { action = 'Draw', count = 1, seq = index }))
            self:drain()
            self.now = self.now + GameCfg.Platform.FlowTimeoutSec
            self.platform:Update()
            self:drain()
        else
            lu.assertTrue(self:draw(1, index, outcome))
        end
        local result = self:lastResult()
        lu.assertFalse(result.ok)
        lu.assertEquals(result.reason, outcome)
    end
    lu.assertEquals(self.data:ItemCount('item7'), 0)
    lu.assertEquals(self.data.Extra.lottery.pity, 0)
end

-- 十连跨保底线：存档 pity=45 进场，第 5 抽（累计第 50 次）保底大奖，pity 落账归零后重计
function TestBlindboxSettle:test_ten_draws_settle_pity_across_the_line()
    self.data.Extra.lottery.pity = 45
    self:persistReady()
    self.rolls = { 1000, 1000, 1000, 1000, 2, 1000, 1000, 1000, 1000, 1000 }
    lu.assertTrue(self:draw(10, 1, 'success'))
    local result = self:lastResult()
    lu.assertTrue(result.ok)
    lu.assertEquals(#result.draws, 10)
    lu.assertEquals(result.pityBefore, 45)
    lu.assertTrue(result.draws[5].guaranteed)
    lu.assertEquals(result.draws[5].itemKey, 'item107') -- 保底二选一第二件：极品蛇颈龙
    lu.assertEquals(result.draws[5].pityAfter, 0)
    lu.assertEquals(result.pityAfter, 5)
    lu.assertEquals(self.data.Extra.lottery.pity, 5) -- 落账后与结果一致
    -- 初始容量只有 2+5=7 格：保底大奖 + 6 件入库，余 3 件按区落地
    lu.assertEquals(self.data:ItemCount('item107'), 1)
    lu.assertEquals(self.data:ItemCount('item7'), 6)
    lu.assertEquals(result.grounded, 3)
    lu.assertEquals(#self.spawned, 3)
    for _, drop in ipairs(self.spawned) do lu.assertEquals(drop.itemId, 'item7') end
end

-- 自然中大奖：pity 立即归零落账
function TestBlindboxSettle:test_natural_jackpot_resets_persisted_pity()
    self.data.Extra.lottery.pity = 30
    self:persistReady()
    self.rolls = { 3 } -- 极品美人鱼权重区
    lu.assertTrue(self:draw(1, 1, 'success'))
    local result = self:lastResult()
    lu.assertTrue(result.draws[1].jackpot)
    lu.assertFalse(result.draws[1].guaranteed)
    lu.assertEquals(self.data.Extra.lottery.pity, 0)
    lu.assertEquals(self.data:ItemCount('item108'), 1)
end

-- 满格按区落地：道具栏+背包全满时抽中物落地（Loot:SpawnItem），回包带 landed 标记
function TestBlindboxSettle:test_full_inventory_lands_on_ground()
    while self.data:AddItem('carp') do end -- 填满全部格位
    self:persistReady()
    self.rolls = { 1000 }
    lu.assertTrue(self:draw(1, 1, 'success'))
    local result = self:lastResult()
    lu.assertTrue(result.ok)
    lu.assertTrue(result.draws[1].landed)
    lu.assertEquals(result.grounded, 1)
    lu.assertEquals(#self.spawned, 1)
    lu.assertEquals(self.spawned[1].itemId, 'item7')
    lu.assertEquals(self.spawned[1].mult, 1) -- 盲盒倍率固定 1
    lu.assertEquals(self.data.Extra.lottery.pity, 1) -- 落地也算抽过，计数照常推进
end

-- 同 seq 重试：只回放原结果，不重复扣费（不再建 flow）、不重复发奖、不重复落地
function TestBlindboxSettle:test_retry_replays_result_without_double_grant()
    while self.data:AddItem('carp') do end
    self:persistReady()
    self.rolls = { 1000 }
    lu.assertTrue(self:draw(1, 7, 'success'))
    lu.assertEquals(#self.spawned, 1)
    self.events = {}
    lu.assertTrue(self.blindbox:Handle(self.player, { action = 'Draw', count = 1, seq = 7 }))
    self:drain()
    lu.assertFalse(self.platform:HasFlow(self.player)) -- 重试不再发起购买
    local replay = self:lastResult()
    lu.assertTrue(replay.ok)
    lu.assertEquals(replay.draws[1].itemKey, 'item7')
    lu.assertEquals(#self.spawned, 1) -- 不重复落地
    lu.assertEquals(self.data.Extra.lottery.pity, 1) -- 计数不重复推进
end

-- 重进：pity 从存档恢复，State 握手回包当前计数
function TestBlindboxSettle:test_pity_survives_reconnect_and_state_sync()
    self.rolls = { 1000, 1000, 1000 }
    lu.assertTrue(self:draw(1, 1, 'success'))
    lu.assertTrue(self:draw(1, 2, 'success'))
    lu.assertTrue(self:draw(1, 3, 'success'))
    lu.assertEquals(self.data.Extra.lottery.pity, 3)
    self.events = {}
    self.players:OnPlayerAdded(self.player) -- 重进读档
    self:drain()
    local restored = self.players:GetDataInst(self.player)
    lu.assertEquals(restored.Extra.lottery.pity, 3)
    self.blindbox:OnPlayerAdded(restored and self.player or self.player)
    local state = self:lastResult()
    lu.assertTrue(state.ok)
    lu.assertEquals(state.action, 'State')
    lu.assertEquals(state.pity, 3)
end

-- 生产守卫：Debug 关 + goodsId 未配置 → 明确 unavailable，不建 flow 不发奖
function TestBlindboxSettle:test_production_build_rejects_unconfigured_goods()
    GameCfg.Debug = { Enabled = false }
    lu.assertTrue(self.blindbox:Handle(self.player, { action = 'Draw', count = 1, seq = 1 }))
    self:drain()
    local result = self:lastResult()
    lu.assertFalse(result.ok)
    lu.assertEquals(result.reason, 'unavailable')
    lu.assertEquals(self.data:ItemCount('item7'), 0)
    lu.assertEquals(self.data.Extra.lottery.pity, 0)
    lu.assertFalse(self.platform:HasFlow(self.player))
end

-- 并发：购买 flow 在飞时第二抽 busy 拒绝；第一个 flow 不受影响正常结算
function TestBlindboxSettle:test_second_draw_busy_while_payment_in_flight()
    self.rolls = { 1000 }
    lu.assertTrue(self.blindbox:Handle(self.player, { action = 'Draw', count = 1, seq = 1 }))
    self:drain()
    lu.assertTrue(self.platform:HasFlow(self.player))
    self.events = {}
    lu.assertTrue(self.blindbox:Handle(self.player, { action = 'Draw', count = 1, seq = 2 }))
    local busy = self:lastResult()
    lu.assertFalse(busy.ok)
    lu.assertEquals(busy.reason, 'busy')
    lu.assertTrue(self.platform:HandleTestAction(self.player, { action = 'ResolveFlow', outcome = 'success' }))
    self:drain()
    lu.assertEquals(self.data:ItemCount('item7'), 1) -- 只有第一抽发货
    lu.assertEquals(self.data.Extra.lottery.pity, 1)
end

-- 单抽 10 金豆、十连 90 金豆：价目来自 GameCfg.Platform.Goods（goodsId 未交付走测试 flow）
function TestBlindboxSettle:test_pricing_uses_configured_goods()
    lu.assertEquals(GameCfg.Platform.Goods.blindboxSingle.beans, 10)
    lu.assertEquals(GameCfg.Platform.Goods.blindboxTen.beans, 90)
end

-- 审查失败方式：支付等待期别的操作推进sequence；Execute同步拒绝；落地失败/无角色；
-- 落地成功确认写失败后重进；盲盒收集解锁不改钓取纪录。
function TestBlindboxSettle:test_payment_wait_does_not_reserve_sequence()
    self.rolls = { 1000 }
    self:draw(1, 1)
    self:drain()
    local op = assert(self.save:ResolveRequest(self.player, self.data, 'other', 1))
    lu.assertTrue(self.save:Execute(self.player, self.data, op, function(draft)
        draft:AddFishCoin(1)
        return { ok = true }
    end, function() end))
    self:drain()
    lu.assertTrue(self.platform:HandleTestAction(self.player, { action = 'ResolveFlow', outcome = 'success' }))
    self:drain()
    self.blindbox:Update()
    self:drain()
    lu.assertEquals(self.data:ItemCount('item7'), 1)
    lu.assertTrue(self:lastResult().ok)
end

function TestBlindboxSettle:test_failed_ground_delivery_survives_reconnect()
    while self.data:AddItem('carp') do end
    self:persistReady()
    self.blindbox.Loot.SpawnDelivery = function() return nil, 'spawn-failed' end
    self.blindbox.Loot.DeliveryEpoch = 'test-world'
    self.rolls = { 1000 }
    self:draw(1, 1, 'success')
    self.blindbox:Update(); self:drain()
    lu.assertTrue(self:lastResult().deliveryPending)
    self.players:OnPlayerAdded(self.player); self:drain()
    self.data = self.players:GetDataInst(self.player)
    local spawned = 0
    self.blindbox.Loot.SpawnDelivery = function() spawned = spawned + 1 return { Id = 'once' } end
    self.blindbox:OnPlayerAdded(self.player)
    self.blindbox:Update(); self:drain()
    lu.assertEquals(spawned, 1)
    lu.assertEquals(next(self.data.Extra.lottery.deliveries), nil)
    self.blindbox:Update(); self:drain()
    lu.assertEquals(spawned, 1)
end

function TestBlindboxSettle:test_collection_unlock_without_catch_record()
    self.rolls = { 1000 }
    self:draw(1, 1, 'success'); self:drain()
    lu.assertTrue(self.data.Extra.collection.unlocked['item7'])
    lu.assertEquals(self.data.Extra.collection.weights, {})
    lu.assertEquals(self.data.Extra.collection.catches or {}, {})
    lu.assertEquals(self.data.Extra.collection.total or 0, 0)
    self.players:OnPlayerAdded(self.player); self:drain()
    lu.assertTrue(self.players:GetDataInst(self.player).Extra.collection.unlocked['item7'])
end

function TestBlindboxSettle:test_delivery_confirmation_rejected_then_reconnect_does_not_duplicate()
    while self.data:AddItem('carp') do end
    self:persistReady()
    local execute = self.save.Execute
    self.save.Execute = function(mgr, player, data, op, transform, done)
        if op.kind == 'blindbox:delivery' then return false, 'pending' end
        return execute(mgr, player, data, op, transform, done)
    end
    self.rolls = { 1000 }
    self:draw(1, 1, 'success')
    lu.assertEquals(#self.spawned, 1)
    lu.assertNotNil(next(self.data.Extra.lottery.deliveries))
    self.save.Execute = execute
    self.players:OnPlayerAdded(self.player); self:drain()
    self.data = self.players:GetDataInst(self.player)
    self.blindbox:OnPlayerAdded(self.player); self:drain()
    lu.assertEquals(#self.spawned, 1)
    lu.assertNil(next(self.data.Extra.lottery.deliveries))
end

function TestBlindboxSettle:test_paid_write_sync_rejection_keeps_recoverable_intent()
    self.rolls = { 1000 }
    self:draw(1, 1); self:drain()
    local execute = self.save.Execute
    self.save.Execute = function(mgr, player, data, op, transform, done)
        if op.kind == 'blindbox' then return false, 'expired' end
        return execute(mgr, player, data, op, transform, done)
    end
    self.platform:HandleTestAction(self.player, { action = 'ResolveFlow', outcome = 'success' })
    self:drain()
    lu.assertEquals(self:lastResult().reason, 'expired')
    lu.assertTrue(self:lastResult().deliveryPending)
    self.save.Execute = execute
    self.players:OnPlayerAdded(self.player); self:drain()
    self.data = self.players:GetDataInst(self.player)
    self.blindbox:OnPlayerAdded(self.player); self:drain()
    lu.assertEquals(self.data:ItemCount('item7'), 1)
end

function TestBlindboxSettle:test_no_character_preserves_delivery_and_unlocks_without_record()
    while self.data:AddItem('carp') do end
    self.data.Extra.collection.unlocked.item7 = true
    self.data.Extra.collection.weights.item7 = 12.34
    self:persistReady()
    local character = self.player.Character
    self.player.Character = nil
    self.rolls = { 1000 }
    self:draw(1, 1, 'success')
    lu.assertEquals(#self.spawned, 0)
    lu.assertTrue(self:lastResult().deliveryPending)
    lu.assertTrue(self.data.Extra.collection.unlocked.item7)
    lu.assertEquals(self.data.Extra.collection.weights.item7, 12.34)
    self.player.Character = character
    self.blindbox:Update(); self:drain()
    lu.assertEquals(#self.spawned, 1)
    self.blindbox:Handle(self.player, { action = 'Draw', count = 1, seq = 1 }); self:drain()
    lu.assertEquals(#self.spawned, 1)
    lu.assertEquals(self.data.Extra.collection.weights.item7, 12.34)
end

function TestBlindboxSettle:test_unknown_previous_world_delivery_requires_reconciliation()
    while self.data:AddItem('carp') do end
    self:persistReady()
    self.blindbox.Loot.SpawnDelivery = function() return nil end
    self.rolls = { 1000 }; self:draw(1, 1, 'success')
    self.blindbox.Loot.DeliveryEpoch = 'new-world'
    self.blindbox.Loot.SpawnDelivery = function() error('不得盲目补发旧世界交付') end
    self.blindbox:Update(); self:drain()
    lu.assertNotNil(next(self.data.Extra.lottery.deliveries))
end

function TestBlindboxSettle:test_loot_delivery_key_remains_consumed_after_entity_disappears()
    local loot = assert(loadfile('server/Mgr/MgrLoot.lua'))()
    local calls = 0
    loot.SpawnItem = function() calls = calls + 1; return { Id = 99 } end
    lu.assertEquals(loot:SpawnDelivery('paid:1', 'item7', 1, nil, {}), { Id = 99 })
    loot.Loots[99] = nil -- 已被拾取/回收，不能因实体消失重发
    lu.assertEquals(loot:SpawnDelivery('paid:1', 'item7', 1, nil, {}), { Id = 99 })
    lu.assertEquals(calls, 1)
end

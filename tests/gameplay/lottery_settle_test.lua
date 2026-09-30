-- #138 T17 抽奖机服务端结算（MgrLottery）失败方式先列：
--   1. 资格漏洞：非极品食物、烤鱼、烤过信物、背包物品、空槽或越界格号被接受；
--   2. 投注价值错：不用实际价值（个体倍率丢失）或误用烤熟价；
--   3. 结算错：两同金币倍数错位、三同叠加两同金币、无中奖发奖或多扣；
--   4. 落位错：占格大奖没回投入格、武器占了道具格而不是独立库存；
--   5. 幂等错：同 seq 重复点击双扣、operation 重放重发奖、断线重进恢复时又发一次；
--   6. 持久化错：写库失败却把结果发布给玩家；结果未先落账就回包；
--   7. 校验缺失：不在抽奖机旁也能抽；payload 畸形导致报错而不是拒绝。
-- seam：MgrLottery:Handle / OnPlayerAdded；真实 PlayerData、MgrPlayerData、MgrSave、MgrInteract，
--   替换引擎边界（game / REUtil / DataStore）；随机数经 MgrLottery.Random 注入（系统边界）。
local lu = require('luaunit')
local GameCfg = require('common.GameCfg')

TestLotterySettle = {}

local ITEM_BAR = GameCfg.Items.ContainerId.ItemBar

function TestLotterySettle:setUp()
    self.oldGame, self.oldRE = _G.game, _G.REUtil
    self.oldDebug = GameCfg.Debug
    GameCfg.Debug = { Enabled = false }
    self.values, self.queue, self.events = {}, {}, {}
    self.readFailure, self.writeFailure = false, false
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
            return value
        end,
        SetAsync = function(_, key, value) env.values[key] = value end,
    }
    self.anchor = { Position = { x = 0, y = 0, z = 0 } }
    _G.game = { GetService = function(_, name)
        if name == 'Task' then return { Spawn = function(_, fn) env.queue[#env.queue + 1] = fn end,
            Wait = function() end } end
        if name == 'DataStoreService' then return { GetDataStore = function() return env.store end } end
        if name == 'World' then return { GetServerTime = function() return 100 end,
            FindFirstChild = function() return env.anchor end } end
        if name == 'Players' then return { GetPlayers = function() return { env.player } end } end
    end }
    _G.REUtil = { GetRE = function(_, name) return { FireClient = function(_, player, value)
        env.events[#env.events + 1] = { name = name, player = player, value = value }
    end } end }
    self.save = assert(loadfile('server/Mgr/MgrSave.lua'))()
    self.players = assert(loadfile('server/Mgr/MgrPlayerData.lua'))()
    self.interact = assert(loadfile('server/Mgr/MgrInteract.lua'))()
    self.lottery = assert(loadfile('server/Mgr/MgrLottery.lua'))()
    self.players.Save, self.save.PlayerData = self.save, self.players
    self.interact.PlayerData, self.interact.Save = self.players, self.save
    self.lottery.PlayerData, self.lottery.Save, self.lottery.Interact = self.players, self.save, self.interact
    self.rolls = {}
    self.lottery.Random = function()
        local roll = table.remove(self.rolls, 1)
        assert(roll, '测试脚本 RNG 序列耗尽')
        return roll
    end
    self:join()
    self:drain()
    self.data = self.players:GetDataInst(self.player)
    self:clearEvents()
end

function TestLotterySettle:tearDown()
    _G.game, _G.REUtil = self.oldGame, self.oldRE
    GameCfg.Debug = self.oldDebug
end

function TestLotterySettle:join()
    local signal = { Connect = function() return { Disconnect = function() end } end }
    self.player = { UserId = 777, Character = { Position = { x = 0, y = 0, z = 0 } },
        CharacterAdded = signal, CharacterRemoving = signal, SetAttribute = function() end }
    self.players:OnPlayerAdded(self.player)
end

function TestLotterySettle:drain()
    while #self.queue > 0 do table.remove(self.queue, 1)() end
end

function TestLotterySettle:clearEvents() self.events = {} end

function TestLotterySettle:messages(name)
    local values = {}
    for _, event in ipairs(self.events) do if event.name == name then values[#values + 1] = event.value end end
    return values
end

-- 发一件极品食物到道具栏；返回格号。item7 极品罗非鱼基础价 3，item31 虾尾（信物）基础价 50
function TestLotterySettle:givePremium(itemId, mult, cooked)
    lu.assertTrue(self.data:AddItem(itemId, mult, cooked))
    return 1
end

-- 脚本化 RNG：先三轴（各取 1..100），武器组三同再取一次组内（1..5）
function TestLotterySettle:scriptAxes(a, b, c, weaponPick)
    self.rolls = { a, b, c }
    if weaponPick then self.rolls[4] = weaponPick end
end

function TestLotterySettle:draw(slot, seq)
    local accepted = self.lottery:Handle(self.player, { action = 'Draw', slot = slot, seq = seq })
    self:drain()
    return accepted
end

function TestLotterySettle:test_pair_pays_actual_bet_value_times_multiplier_and_consumes_one()
    self:givePremium('item7', 1.5) -- 实际价值 floor(3 × 1.5) = 4
    self:persistReady()
    self:scriptAxes(1, 22, 23) -- 鳄雀鳝 / 鳄雀鳝 / 小白龙 → 恰两同鳄雀鳝 ×2
    lu.assertTrue(self:draw(1, 1))
    local result = self:messages('LotteryResult')[1]
    lu.assertTrue(result.ok)
    lu.assertEquals(result.outcome, 'pair')
    lu.assertEquals(result.betValue, 4)
    lu.assertEquals(result.multiplier, 2)
    lu.assertEquals(result.coins, 8)
    lu.assertEquals(result.axes, { 1, 1, 2 })
    lu.assertEquals(self.data.Data.FishCoin, 8)
    lu.assertNil(self.data.Data.Containers[ITEM_BAR][1])
    lu.assertEquals(result.coinBefore, 0)
    lu.assertEquals(result.coinAfter, 8)
end

function TestLotterySettle:test_bet_value_uses_individual_mult_and_never_cooked_price()
    self:givePremium('item31', 2) -- 信物虾尾：实际价值 floor(50 × 2) = 100
    self:persistReady()
    self:scriptAxes(96, 100, 5) -- 哥斯拉 / 哥斯拉 / 鳄雀鳝 → 恰两同哥斯拉 ×20
    lu.assertTrue(self:draw(1, 1))
    local result = self:messages('LotteryResult')[1]
    lu.assertEquals(result.betValue, 100)
    lu.assertEquals(result.coins, 2000)
    lu.assertEquals(self.data.Data.FishCoin, 2000)
end

function TestLotterySettle:test_triple_weapon_goes_to_weapon_inventory_without_pair_coins()
    self:givePremium('item7')
    self:persistReady()
    self:scriptAxes(1, 10, 22, 3) -- 鳄雀鳝三同 → 匕首组五选一第 3 件（黄金匕首 item154）
    lu.assertTrue(self:draw(1, 1))
    local result = self:messages('LotteryResult')[1]
    lu.assertEquals(result.outcome, 'triple')
    lu.assertEquals(result.prize, { kind = 'weapon', itemId = 'item154', name = '黄金匕首' })
    lu.assertNil(result.coins) -- 三同不叠加两同金币
    lu.assertEquals(self.data.Data.FishCoin, 0)
    lu.assertEquals(self.data:WeaponCount('item154'), 1)
    lu.assertNil(self.data.Data.Containers[ITEM_BAR][1]) -- 武器不占道具格
end

function TestLotterySettle:test_triple_item_returns_to_the_freed_slot()
    self:givePremium('item31')
    self:persistReady()
    self:scriptAxes(61, 70, 76) -- 三头鲨三同 → 加速药水 item167 回投入格
    lu.assertTrue(self:draw(1, 1))
    local result = self:messages('LotteryResult')[1]
    lu.assertEquals(result.outcome, 'triple')
    lu.assertEquals(result.prize, { kind = 'item', itemId = 'item167', name = '加速药水' })
    local entry = self.data.Data.Containers[ITEM_BAR][1]
    lu.assertEquals(entry.itemId, 'item167')
    lu.assertEquals(entry.count, 1)
    lu.assertEquals(self.data.Data.FishCoin, 0)
end

function TestLotterySettle:test_no_pair_consumes_only_the_bet()
    self:givePremium('item7')
    self:persistReady()
    self:scriptAxes(1, 23, 43) -- 鳄雀鳝/小白龙/蟹老板 → 无两同
    lu.assertTrue(self:draw(1, 1))
    local result = self:messages('LotteryResult')[1]
    lu.assertTrue(result.ok)
    lu.assertEquals(result.outcome, 'none')
    lu.assertNil(result.coins)
    lu.assertNil(result.prize)
    lu.assertEquals(self.data.Data.FishCoin, 0)
    lu.assertNil(self.data.Data.Containers[ITEM_BAR][1])
end

function TestLotterySettle:test_non_premium_cooked_and_grilled_token_are_rejected()
    self.data.Data.UpgradeLevel = 1 -- 道具栏升到 3 格，三件拒绝样本同栏摆放
    lu.assertTrue(self.data:AddItem('carp')) -- 普通食物
    lu.assertTrue(self.data:AddItem('item7', nil, 1.5)) -- 烤鱼（烤制倍率字段，#137 最小约定）
    lu.assertTrue(self.data:AddItem('item31'))
    -- 烤过信物：存档格位的 saved.cooked 布尔标记（同 MgrInteract 权威口径）
    self.data.Data.Containers[ITEM_BAR][3].saved = { cooked = true }
    self:persistReady()
    for slot, reason in ipairs({ 'not-premium', 'cooked', 'cooked' }) do
        self:draw(slot, slot) -- 业务拒绝：受理与否看回包 reason（与商店/喂食同口径）
        local result = self:messages('LotteryResult')[slot]
        lu.assertFalse(result.ok)
        lu.assertEquals(result.reason, reason)
    end
    lu.assertEquals(self.data:ItemCount('carp'), 1)
    lu.assertEquals(self.data:ItemCount('item7'), 1)
    lu.assertEquals(self.data:ItemCount('item31'), 1)
    lu.assertEquals(self.data.Data.FishCoin, 0)
    lu.assertEquals(self.data:Serialize().meta.sequence, 0)
end

function TestLotterySettle:test_range_and_bad_slot_are_rejected_without_mutation()
    self:givePremium('item7')
    self:persistReady()
    self:scriptAxes(1, 1, 23)
    self.player.Character.Position.x = 999 -- 不在任何抽奖机旁
    self:draw(1, 1)
    local range = self:messages('LotteryResult')[1]
    lu.assertFalse(range.ok)
    lu.assertEquals(range.reason, 'range')
    lu.assertEquals(self.data:ItemCount('item7'), 1)
    self.player.Character.Position.x = 0
    for _, slot in ipairs({ 0, 100, 2, 'x', 1.5 }) do
        lu.assertFalse(self.lottery:Handle(self.player, { action = 'Draw', slot = slot, seq = 10 }))
    end
    self:drain()
    lu.assertEquals(self.data:ItemCount('item7'), 1)
    lu.assertEquals(self.data.Data.FishCoin, 0)
    lu.assertEquals(self.data:Serialize().meta.sequence, 0)
end

function TestLotterySettle:test_duplicate_seq_and_operation_replay_return_the_unique_result()
    self:givePremium('item7')
    self:persistReady()
    self:scriptAxes(1, 22, 23)
    lu.assertTrue(self:draw(1, 1))
    local first = self:messages('LotteryResult')[1]
    self:clearEvents()
    -- 同 seq 重发：日志未淘汰时按重放处理，回原结果、不重复结算（#123 协议）
    lu.assertTrue(self.lottery:Handle(self.player, { action = 'Draw', slot = 1, seq = 1 }))
    self:drain()
    local seqReplay = self:messages('LotteryResult')
    lu.assertEquals(#seqReplay, 1)
    lu.assertEquals(seqReplay[1].coins, first.coins)
    self:clearEvents()
    lu.assertTrue(self.lottery:Handle(self.player,
        { action = 'Draw', slot = 1, seq = 2, operation = first.operation }))
    self:drain()
    local replayed = self:messages('LotteryResult')
    lu.assertEquals(#replayed, 1)
    lu.assertEquals(replayed[1].coins, first.coins)
    lu.assertEquals(replayed[1].operation.id, first.operation.id)
    lu.assertEquals(self.data.Data.FishCoin, 6) -- 不重复发奖（本用例投注价值 3 × 2 倍）
    lu.assertEquals(self.data:ItemCount('item7'), 0) -- 不重复扣物
end

function TestLotterySettle:test_reconnect_recovers_the_same_result_without_double_grant()
    self:givePremium('item31')
    self:persistReady()
    self:scriptAxes(61, 70, 76) -- 三头鲨三同 → 加速药水回投入格
    lu.assertTrue(self:draw(1, 1))
    local settled = self:messages('LotteryResult')[1]
    -- 中途断线：重进读档，MgrLottery 在就绪后补推唯一结果（只展示，不再结算）
    self:join()
    self:drain()
    local restored = self.players:GetDataInst(self.player)
    self:clearEvents()
    self.lottery:OnPlayerAdded(self.player)
    local recovered = self:messages('LotteryResult')
    lu.assertEquals(#recovered, 1)
    lu.assertTrue(recovered[1].recovered)
    lu.assertEquals(recovered[1].axes, settled.axes)
    lu.assertEquals(recovered[1].prize, settled.prize)
    lu.assertEquals(restored:ItemCount('item167'), 1) -- 奖品只发过一次
    lu.assertEquals(restored:ItemCount('item31'), 0)
    lu.assertEquals(restored.Data.FishCoin, 0)
end

-- 客户端主动拉取（LotteryStateRequest 的处理入口）与 OnPlayerAdded 共享同一补推逻辑；
-- 两个入口都触发时服务端可能各推一次，客户端按 operation.id 去重（见 lottery_ui_test 重播用例）
function TestLotterySettle:test_state_request_entry_pushes_the_same_recovered_result()
    self:givePremium('item31')
    self:persistReady()
    self:scriptAxes(61, 70, 76) -- 三头鲨三同 → 加速药水回投入格
    lu.assertTrue(self:draw(1, 1))
    local settled = self:messages('LotteryResult')[1]
    self:join()
    self:drain()
    local restored = self.players:GetDataInst(self.player)
    self:clearEvents()
    self.lottery:PushRecovered(self.player)
    local recovered = self:messages('LotteryResult')
    lu.assertEquals(#recovered, 1)
    lu.assertTrue(recovered[1].recovered)
    lu.assertEquals(recovered[1].axes, settled.axes)
    lu.assertEquals(recovered[1].prize, settled.prize)
    lu.assertEquals(restored:ItemCount('item167'), 1) -- 只展示，不重复发奖
end

function TestLotterySettle:test_failed_write_never_publishes_the_result()
    self:givePremium('item7')
    self:persistReady()
    self:scriptAxes(1, 22, 23)
    self.writeFailure = true
    lu.assertTrue(self:draw(1, 1))
    for _ = 1, 4 do self.save:Update() self:drain() end
    lu.assertNil(self.players:GetDataInst(self.player)) -- 写档重试耗尽，读写屏障关闭
    lu.assertEquals(self.data.Data.FishCoin, 0)
    -- 会话关闭后 ItemCount 走 Inited 短路，直接读 Data 核对库存未被 draft 污染
    local kept = self.data.Data.Containers[ITEM_BAR][1]
    lu.assertNotNil(kept)
    lu.assertEquals(kept.itemId, 'item7')
    lu.assertEquals(self:messages('ItemBarState'), {})
    local result = self:messages('LotteryResult')[1]
    lu.assertFalse(result.ok)
end

-- 连续抽奖：上一次结果落定后不必关窗即可再投下一件
function TestLotterySettle:test_consecutive_draws_settle_independently()
    self:givePremium('item7', 1.5)
    lu.assertTrue(self.data:AddItem('item31'))
    self:persistReady()
    self:scriptAxes(1, 22, 23)
    lu.assertTrue(self:draw(1, 1))
    self:scriptAxes(96, 96, 1) -- 哥斯拉两同 ×20，投注价值 50
    lu.assertTrue(self:draw(2, 2))
    local results = self:messages('LotteryResult')
    lu.assertEquals(#results, 2)
    lu.assertEquals(results[2].coins, 1000)
    lu.assertEquals(self.data.Data.FishCoin, 1008)
    lu.assertEquals(self.data:ItemCount('item7'), 0)
    lu.assertEquals(self.data:ItemCount('item31'), 0)
end

function TestLotterySettle:persistReady()
    lu.assertTrue(self.save:SaveExplicit(self.player.UserId, self.data, function(ok) lu.assertTrue(ok) end))
    self:drain()
    self:clearEvents()
end

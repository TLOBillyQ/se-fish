-- #123 失败方式先列：持久化前扣发/回包/任务/动画；写失败或回包丢失重复结算；
-- pending/failed 可操作；同身份重放改变结果；重连 seq 复位串账；日志淘汰后旧身份重新发奖；
-- 兑换满格、购买余额不足、扩容上限被绕过；Save 注入后遗漏现有业务校验。
-- seam：Interact/Shop:Handle；真实 PlayerData、MgrPlayerData、MgrSave、MgrQuest，替换引擎边界。
local lu = require('luaunit')
local GameCfg = require('common.GameCfg')
TestEconomyPersistence = {}

function TestEconomyPersistence:setUp()
    self.oldGame, self.oldRE, self.oldPlayerData = _G.game, _G.REUtil, _G.MgrPlayerData
    self.oldDebug, self.oldQuest = GameCfg.Debug, GameCfg.Quest
    self.oldAnimation = GameCfg.Interact.Fisherman.EatAnimation
    GameCfg.Debug = { Enabled = false }
    GameCfg.Interact.Fisherman.EatAnimation = 'eat'
    GameCfg.Quest = { Steps = { { Kind = 'Buy', ItemId = 'worm', Need = 3, Text = '购买鱼饵' } },
        Title = '任务', DoneText = '完成', NextNotice = '%s' }
    self.values, self.queue, self.events, self.plays = {}, {}, {}, 0
    self.readFailure, self.writeFailure, self.loseReply = false, false, false
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
    self.anchor = { Position = { x = 0, y = 0, z = 0 },
        PlayAnimation = function() env.plays = env.plays + 1 end }
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
    self.shop = assert(loadfile('server/Mgr/MgrShop.lua'))()
    self.quest = assert(loadfile('server/Mgr/MgrQuest.lua'))()
    self.players.Save, self.save.PlayerData = self.save, self.players
    self.interact.PlayerData, self.interact.Save, self.interact.Quest = self.players, self.save, self.quest
    self.shop.PlayerData, self.shop.Save, self.shop.Quest = self.players, self.save, self.quest
    self.shop.Interact = self.interact
    self:join()
    self:drain()
    self.data = self.players:GetDataInst(self.player)
    self:clearEvents()
end

function TestEconomyPersistence:tearDown()
    _G.game, _G.REUtil, _G.MgrPlayerData = self.oldGame, self.oldRE, self.oldPlayerData
    GameCfg.Debug, GameCfg.Quest = self.oldDebug, self.oldQuest
    GameCfg.Interact.Fisherman.EatAnimation = self.oldAnimation
end
function TestEconomyPersistence:join()
    local signal = { Connect = function() return { Disconnect = function() end } end }
    self.player = { UserId = 321, Character = { Position = { x = 0, y = 0, z = 0 } },
        CharacterAdded = signal, CharacterRemoving = signal, SetAttribute = function() end }
    self.players:OnPlayerAdded(self.player)
    self.quest:OnPlayerAdded(self.player)
end
function TestEconomyPersistence:drain()
    while #self.queue > 0 do table.remove(self.queue, 1)() end
end
function TestEconomyPersistence:clearEvents() self.events, self.plays = {}, 0 end
function TestEconomyPersistence:messages(name)
    local values = {}
    for _, event in ipairs(self.events) do if event.name == name then values[#values + 1] = event.value end end
    return values
end
function TestEconomyPersistence:persistSetup()
    lu.assertTrue(self.save:SaveExplicit(self.player.UserId, self.data, function(ok) lu.assertTrue(ok) end))
    self:drain()
    self:clearEvents()
end

function TestEconomyPersistence:test_malformed_operation_cannot_replace_valid_sequence()
    self.data:AddCoin(5)
    self.data:AddBait('worm', 1)
    self.data:SelectBait('worm')
    self:persistSetup()
    for _, operation in ipairs({ 1, false, '1', {}, { kind = 'shop', sequence = 1 } }) do
        lu.assertFalse(self.shop:Handle(self.player, { action = 'Buy', itemId = 'worm', operation = operation }))
        lu.assertFalse(self.interact:Handle(self.player, { target = 'fisherman', action = 'Feed', operation = operation }))
    end
    lu.assertEquals(self.events, {})
    lu.assertEquals(self.data.Data.FishCoin, 5)
    lu.assertEquals(self.data.Data.Bait.worm, 1)
    lu.assertEquals(self.data:Serialize().meta.sequence, 0)
end

function TestEconomyPersistence:test_expired_and_forged_identity_cannot_buy_again()
    self.data:AddCoin(100)
    self:persistSetup()
    local first
    for seq = 1, 65 do
        lu.assertTrue(self.shop:Handle(self.player, { action = 'Buy', itemId = 'worm', seq = seq }))
        self:drain()
        first = first or self:messages('ShopResult')[1].operation
    end
    lu.assertEquals(self.data.Data.FishCoin, 35)
    lu.assertEquals(self.data.Data.Bait.worm, 65)
    self:clearEvents()
    lu.assertFalse(self.shop:Handle(self.player, { action = 'Buy', itemId = 'worm', seq = 1 }))
    lu.assertFalse(self.shop:Handle(self.player, { action = 'Buy', seq = 66, operation = first }))
    local forged = { id = first.id, sequence = first.sequence, kind = first.kind, requestKey = '伪造' }
    lu.assertFalse(self.shop:Handle(self.player, { action = 'Buy', seq = 66, operation = forged }))
    lu.assertEquals(self.events, {})
    lu.assertEquals(self.data.Data.FishCoin, 35)
    lu.assertEquals(self.data.Data.Bait.worm, 65)
end

function TestEconomyPersistence:test_failed_write_exhaustion_and_failed_load_never_grant()
    self.data:AddCoin(20)
    self:persistSetup()
    self.writeFailure = true
    lu.assertTrue(self.shop:Handle(self.player, { action = 'Buy', itemId = 'worm', seq = 1 }))
    self:drain()
    for _ = 1, 4 do self.save:Update() self:drain() end
    lu.assertNil(self.players:GetDataInst(self.player))
    lu.assertEquals(self.data.Data.FishCoin, 20)
    lu.assertEquals(self.data.Data.Bait.worm or 0, 0)
    lu.assertEquals(self:messages('ItemBarState'), {})
    lu.assertEquals(#self:messages('ShopResult'), 1)
    lu.assertFalse(self:messages('ShopResult')[1].ok)
    lu.assertEquals(self.quest:GetState(self.player).count, 0)
    self.readFailure, self.writeFailure = true, false
    self:join()
    self:clearEvents()
    lu.assertFalse(self.shop:Handle(self.player, { action = 'UpgradeStorage', seq = 2 }))
    lu.assertFalse(self.interact:Handle(self.player, { target = 'fisherman', action = 'Feed', seq = 2 }))
    self:drain()
    lu.assertNil(self.players:GetDataInst(self.player))
    lu.assertFalse(self.shop:Handle(self.player, { action = 'Buy', itemId = 'worm', seq = 3 }))
    lu.assertEquals(self.events, {})
end

function TestEconomyPersistence:test_save_injection_preserves_business_rejection_without_mutation()
    self.data:AddCoin(4)
    self.data:AddItem('garHead')
    self.data:SelectSlot(1)
    while self.data:AddItem('carp') do end
    self:persistSetup()
    local before = self.data:GetItemBarSnapshot()
    self.shop:Handle(self.player, { action = 'Buy', itemId = 'starterRod', seq = 1 })
    lu.assertEquals(self:messages('ShopResult')[1].reason, 'full')
    self.shop:Handle(self.player, { action = 'UpgradeStorage', seq = 2 })
    lu.assertEquals(self:messages('ShopResult')[2].reason, 'coin')
    self.interact:Handle(self.player, { target = 'fisherman', action = 'Feed', seq = 1 })
    lu.assertEquals(self:messages('InteractResult')[1].reason, 'full')
    self.shop:Handle(self.player, { action = 'Buy', itemId = 'gold', seq = 3 })
    lu.assertEquals(self:messages('ShopResult')[3].reason, 'item')
    self.player.Character.Position.x = 999
    self.shop:Handle(self.player, { action = 'Buy', itemId = 'worm', seq = 4 })
    lu.assertEquals(self:messages('ShopResult')[4].reason, 'range')
    lu.assertFalse(self.interact:Handle(self.player, { target = 'fisherman', action = 'Feed', seq = 2 }))
    lu.assertEquals(self.data:GetItemBarSnapshot(), before)
    lu.assertEquals(self:messages('ItemBarState'), {})
    lu.assertEquals(self.plays, 0)
    lu.assertEquals(self.data:Serialize().meta.sequence, 0)
end

function TestEconomyPersistence:test_old_session_pending_write_cannot_publish_to_rejoined_player()
    self.data:AddCoin(20)
    self:persistSetup()
    self.writeFailure = true
    self.shop:Handle(self.player, { action = 'Buy', itemId = 'worm', seq = 1 })
    self:drain()
    self.writeFailure = false
    self:join()
    self:drain()
    self:clearEvents()
    self.save:Update()
    self:drain()
    lu.assertEquals(self.events, {})
    local restored = self.players:GetDataInst(self.player)
    lu.assertEquals(restored.Data.FishCoin, 20)
    lu.assertEquals(restored.Data.Bait.worm or 0, 0)
    lu.assertEquals(self.quest:GetState(self.player).count, 0)
end

function TestEconomyPersistence:test_original_identity_alone_replays_upgrade_and_exchange()
    self.data:AddCoin(100)
    self.data:AddItem('garHead')
    self.data:SelectSlot(1)
    self:persistSetup()
    lu.assertTrue(self.shop:Handle(self.player, { action = 'UpgradeStorage', seq = 1 }))
    self:drain()
    local upgrade = self:messages('ShopResult')[1]
    lu.assertTrue(self.interact:Handle(self.player, { target = 'fisherman', action = 'Feed', seq = 1 }))
    self:drain()
    local exchange = self:messages('InteractResult')[1]
    self:clearEvents()
    lu.assertTrue(self.shop:Handle(self.player, { action = 'UpgradeStorage', operation = upgrade.operation }))
    lu.assertTrue(self.interact:Handle(self.player, { target = 'fisherman', action = 'Feed', operation = exchange.operation }))
    lu.assertEquals(self:messages('ShopResult'), { upgrade })
    lu.assertEquals(self:messages('InteractResult'), { exchange })
    lu.assertEquals(self:messages('ItemBarState'), {})
    lu.assertEquals(self.plays, 0)
    lu.assertEquals(self.data.Data.UpgradeLevel, 1)
    lu.assertEquals(self.data:ItemCount('shrimpTicket'), 1)
end

function TestEconomyPersistence:test_feed_replays_after_selection_changes_without_eating_again()
    lu.assertTrue(self.data:AddBait('worm', 3))
    lu.assertTrue(self.data:SelectBait('worm'))
    self:persistSetup()
    local request = { target = 'fisherman', action = 'Feed', seq = 1 }
    lu.assertTrue(self.interact:Handle(self.player, request))
    self:drain()
    local original = self:messages('InteractResult')[1]
    lu.assertNotNil(original.operation)
    self.data:SelectBait(nil)
    self:clearEvents()
    lu.assertTrue(self.interact:Handle(self.player, request))
    lu.assertEquals(self:messages('InteractResult'), { original })
    lu.assertEquals(self:messages('ItemBarState'), {})
    lu.assertEquals(self.plays, 0)
    lu.assertEquals(self.data.Data.FishCoin, 1)
    lu.assertEquals(self.data.Data.Bait.worm, 2)
    self.interact:OnPlayerRemoving(self.player)
    self:join()
    self:drain()
    self.player.Character.Position.x = 999
    self:clearEvents()
    request.operation = original.operation
    lu.assertTrue(self.interact:Handle(self.player, request))
    lu.assertEquals(self:messages('InteractResult'), { original })
    lu.assertEquals(self:messages('ItemBarState'), {})
    lu.assertEquals(self.plays, 0)
end

function TestEconomyPersistence:test_shop_replays_original_result_and_reconnect_seq_starts_new_request()
    self.data:AddCoin(20)
    self:persistSetup()
    local request = { action = 'Buy', itemId = 'worm', seq = 1 }
    lu.assertTrue(self.shop:Handle(self.player, request))
    self:drain()
    local original = self:messages('ShopResult')[1]
    lu.assertNotNil(original.operation)
    self:clearEvents()
    -- 已成功的同一通道 seq 即使改成扩容，也只能回原购买结果。
    lu.assertTrue(self.shop:Handle(self.player, { action = 'UpgradeStorage', seq = 1 }))
    lu.assertEquals(self:messages('ShopResult'), { original })
    lu.assertEquals(self:messages('ItemBarState'), {})
    lu.assertEquals(self.quest:GetState(self.player).count, 1)
    lu.assertEquals(self.data.Data.FishCoin, 19)
    self.shop:OnPlayerRemoving(self.player)
    self.quest:OnPlayerRemoving(self.player)
    self:join()
    self:drain()
    self.data = self.players:GetDataInst(self.player)
    self:clearEvents()
    lu.assertTrue(self.shop:Handle(self.player, request))
    self:drain()
    lu.assertEquals(self.data.Data.FishCoin, 18)
    lu.assertEquals(self.data.Data.Bait.worm, 2)
    lu.assertNotEquals(self:messages('ShopResult')[1].operation.id, original.operation.id)
    self:clearEvents()
    self.player.Character.Position.x = 999
    lu.assertTrue(self.shop:Handle(self.player, { action = 'Buy', seq = 99, operation = original.operation }))
    lu.assertEquals(self:messages('ShopResult'), { original })
    lu.assertEquals(self:messages('ItemBarState'), {})
    lu.assertEquals(self.data.Data.FishCoin, 18)
    lu.assertEquals(self.quest:GetState(self.player).count, 1)
end

function TestEconomyPersistence:test_exchange_keeps_token_until_write_and_publishes_product_after_retry()
    lu.assertTrue(self.data:AddItem('garHead'))
    lu.assertTrue(self.data:SelectSlot(1))
    self:persistSetup()
    self.writeFailure = true
    lu.assertTrue(self.interact:Handle(self.player, { target = 'fisherman', action = 'Feed', seq = 1 }))
    lu.assertEquals(self.data.Data.Containers.itemBar[1].itemId, 'garHead')
    self:drain()
    lu.assertEquals(self.events, {})
    lu.assertEquals(self.plays, 0)
    self.writeFailure, self.loseReply = false, true
    self.save:Update()
    self:drain()
    lu.assertEquals(self.data:ItemCount('garHead'), 0)
    lu.assertEquals(self.data:ItemCount('shrimpTicket'), 1)
    lu.assertEquals(self.data.Data.FishCoin, 0)
    lu.assertEquals(self:messages('InteractResult')[1].exchange, { from = 'garHead', to = 'shrimpTicket' })
    lu.assertEquals(self.plays, 1)
    lu.assertEquals(self.quest:GetState(self.player).count, 0)
    self:join()
    self:drain()
    lu.assertEquals(self.players:GetDataInst(self.player):ItemCount('shrimpTicket'), 1)
end

function TestEconomyPersistence:test_feed_selected_fish_waits_for_write_before_coins_animation_and_quest()
    GameCfg.Quest.Steps[1] = { Kind = 'Feed', Category = 'fish', Need = 3, Text = '喂食鱼获' }
    lu.assertTrue(self.data:AddItem('bass', 1.99))
    lu.assertTrue(self.data:SelectSlot(1))
    self:persistSetup()
    -- 当前基线从 Serialize 恢复选中态；cherry-pick impl-123 的选择态持久化提交后仍由真实入口重选，seam 不变。
    if self.data.Data.SelectedSlot ~= 1 then self.data:SelectSlot(1) end
    self:clearEvents()
    local request = { target = 'fisherman', action = 'Feed', seq = 1 }
    self.writeFailure = true
    lu.assertTrue(self.interact:Handle(self.player, request))
    lu.assertEquals(self.data.Data.FishCoin, 0)
    lu.assertEquals(self.data.Data.Containers.itemBar[1].itemId, 'bass')
    lu.assertNil(self.players:GetDataInst(self.player))
    self:drain()
    lu.assertEquals(self.events, {})
    lu.assertEquals(self.plays, 0)
    lu.assertEquals(self.quest:GetState(self.player).count, 0)
    self.writeFailure = false
    self.save:Update()
    self:drain()
    lu.assertEquals(self.data.Data.FishCoin, 11)
    lu.assertEquals(self.data:ItemCount('bass'), 0)
    lu.assertEquals(self:messages('InteractResult')[1].coins, 11)
    lu.assertEquals(self.plays, 1)
    lu.assertEquals(self.quest:GetState(self.player).count, 1)
    self:join()
    self:drain()
    lu.assertEquals(self.players:GetDataInst(self.player).Data.FishCoin, 11)
    lu.assertEquals(self.players:GetDataInst(self.player):ItemCount('bass'), 0)
end

function TestEconomyPersistence:test_upgrade_waits_for_persistence()
    self.data:AddCoin(100)
    self:persistSetup()
    lu.assertTrue(self.shop:Handle(self.player, { action = 'UpgradeStorage', seq = 1, price = 0 }))
    lu.assertEquals(self.data.Data.FishCoin, 100)
    lu.assertEquals(self.data:ItemBarCapacity(), 2)
    lu.assertEquals(self.events, {})
    self:drain()
    lu.assertEquals(self.data.Data.FishCoin, 0)
    lu.assertEquals(self.data:ItemBarCapacity(), 3)
    lu.assertEquals(self:messages('ShopResult')[1].price, 100)
    lu.assertEquals(self:messages('ShopResult')[1].action, 'UpgradeStorage')
    self:join()
    self:drain()
    lu.assertEquals(self.players:GetDataInst(self.player):ItemBarCapacity(), 3)
end

function TestEconomyPersistence:test_buy_waits_for_persistence_and_retries_without_double_charge()
    self.data:AddCoin(10)
    self:persistSetup()
    self.writeFailure = true
    local request = { action = 'Buy', itemId = 'worm', seq = 1 }
    lu.assertTrue(self.shop:Handle(self.player, request))
    lu.assertEquals(self.data.Data.FishCoin, 10)
    lu.assertEquals(self.data.Data.Bait.worm or 0, 0)
    lu.assertNil(self.players:GetDataInst(self.player))
    self:drain()
    lu.assertEquals(self.events, {})
    lu.assertEquals(self.quest:GetState(self.player).count, 0)
    lu.assertFalse(self.shop:Handle(self.player, request))
    self.writeFailure, self.loseReply = false, true
    self.save:Update()
    self:drain()
    lu.assertEquals(self.data.Data.FishCoin, 9)
    lu.assertEquals(self.data.Data.Bait.worm, 1)
    lu.assertEquals(#self:messages('ShopResult'), 1)
    lu.assertTrue(self:messages('ShopResult')[1].ok)
    lu.assertTrue(#self:messages('ItemBarState') > 0)
    lu.assertEquals(self.quest:GetState(self.player).count, 1)
    self:join()
    self:drain()
    local restored = self.players:GetDataInst(self.player)
    lu.assertEquals(restored.Data.FishCoin, 9)
    lu.assertEquals(restored.Data.Bait.worm, 1)
end

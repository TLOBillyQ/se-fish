-- #88 迁移：经济与持久化（原 tests/gameplay/economy_persistence_test.lua，18 例）。
-- #123 失败方式先列：持久化前扣发/回包/任务/动画；写失败或回包丢失重复结算；
-- pending/failed 可操作；同身份重放改变结果；重连 seq 复位串账；日志淘汰后旧身份重新发奖；
-- 兑换满格、购买余额不足、扩容上限被绕过；Save 注入后遗漏现有业务校验。
-- seam：Interact/Shop:Handle；真实 PlayerData、MgrPlayerData、MgrSave、MgrQuest，替换引擎边界。
-- it 按旧 LuaUnit 的方法名字典序注册，保持与旧套件一致的案例顺序。
-- 断言映射：assertEquals 的 table 深比较由 assert.same 承接（标量退化为 ==，与旧实现一致）；
-- assertTrue/assertFalse 严格 true/false → is_true/is_false；assertNil/assertNotNil → is_nil/is_not_nil；
-- assertNotEquals 是深不等 → not_same；带第 3 参消息的 assertEquals 用 assert.message(...) 前缀承载。
-- 不使用 LuaUnit 断言桥。业务模块经 loadfile 加载，其 _ENV 是真实 _G，
-- 故 Busted 逐文件沙箱下必须写 _G.game / _G.REUtil 而不是裸赋值。
local GameCfg = require('common.GameCfg')

describe('TestEconomyPersistence', function()
    local env
    local saved = {}

    -- 类内辅助（旧 TestEconomyPersistence:join / :drain / :clearEvents / :messages / :persistSetup）
    -- 改为闭包 env 的本地函数，避免在 describe 加载期往尚未赋值的 env 上挂方法。
    local function join()
        local signal = { Connect = function() return { Disconnect = function() end } end }
        env.player = { UserId = 321, Character = { Position = { x = 0, y = 0, z = 0 } },
            CharacterAdded = signal, CharacterRemoving = signal, SetAttribute = function() end }
        env.players:OnPlayerAdded(env.player)
        env.quest:OnPlayerAdded(env.player)
    end

    local function drain()
        while #env.queue > 0 do table.remove(env.queue, 1)() end
    end

    local function clearEvents() env.events, env.plays = {}, 0 end

    local function messages(name)
        local values = {}
        for _, event in ipairs(env.events) do if event.name == name then values[#values + 1] = event.value end end
        return values
    end

    local function persistSetup()
        assert.is_true(env.save:SaveExplicit(env.player.UserId, env.data, function(ok) assert.is_true(ok) end))
        drain()
        clearEvents()
    end

    -- 逐例夹具：旧 LuaUnit 每例跑 setUp/tearDown，这里同样用 before_each/after_each。
    -- 第一步把 7 项被改状态（game / REUtil / MgrPlayerData / Debug / Quest / EatAnimation / Shop.Stands）
    -- 全部存进 saved，之后才动任何全局与配置，因此夹具中途抛错时 after_each 仍能完整还原。
    -- Shop.Stands 在旧套件里是案例体末尾手工还原；改由 after_each 统一还原，
    -- 使「断言失败也不把配置泄漏给后续案例」，与其余配置项的清理口径一致。
    -- GameCfg.Save.AcceptanceSlot 由 helper 的根级 before_each/after_each 建基线并逐例恢复。
    before_each(function()
        saved.game, saved.REUtil, saved.MgrPlayerData = rawget(_G, 'game'), rawget(_G, 'REUtil'), rawget(_G, 'MgrPlayerData')
        saved.Debug, saved.Quest = GameCfg.Debug, GameCfg.Quest
        saved.EatAnimation = GameCfg.Interact.Fisherman.EatAnimation
        saved.Stands = GameCfg.Shop.Stands
        GameCfg.Debug = { Enabled = false }
        GameCfg.Interact.Fisherman.EatAnimation = 'eat'
        GameCfg.Quest = { Steps = { { Kind = 'Buy', ItemId = 'worm', Need = 3, Text = '购买鱼饵' } },
            Title = '任务', DoneText = '完成', NextNotice = '%s' }
        env = { values = {}, queue = {}, events = {}, plays = 0 }
        env.readFailure, env.writeFailure, env.loseReply = false, false, false
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
        env.anchor = { Position = { x = 0, y = 0, z = 0 },
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
        env.save = assert(loadfile('server/Mgr/MgrSave.lua'))()
        env.players = assert(loadfile('server/Mgr/MgrPlayerData.lua'))()
        env.interact = assert(loadfile('server/Mgr/MgrInteract.lua'))()
        env.shop = assert(loadfile('server/Mgr/MgrShop.lua'))()
        env.quest = assert(loadfile('server/Mgr/MgrQuest.lua'))()
        env.players.Save, env.save.PlayerData = env.save, env.players
        env.interact.PlayerData, env.interact.Save, env.interact.Quest = env.players, env.save, env.quest
        env.shop.PlayerData, env.shop.Save, env.shop.Quest = env.players, env.save, env.quest
        env.shop.Interact = env.interact
        join()
        drain()
        env.data = env.players:GetDataInst(env.player)
        clearEvents()
    end)
    after_each(function()
        _G.game, _G.REUtil, _G.MgrPlayerData = saved.game, saved.REUtil, saved.MgrPlayerData
        GameCfg.Debug, GameCfg.Quest = saved.Debug, saved.Quest
        GameCfg.Interact.Fisherman.EatAnimation = saved.EatAnimation
        GameCfg.Shop.Stands = saved.Stands
        saved = {}
        env = nil
    end)

    it('test_backpack_upgrade_row_drives_storage_level_and_persists', function()
        -- #130 背包升级行（编号 33）并入升级页：走 Save 协议并复用 Data.UpgradeLevel
        env.data:AddCoin(1000)
        persistSetup()
        assert.is_true(env.shop:Handle(env.player, { action = 'Buy', number = 33, seq = 1 })) -- 背包升级1，100 金
        drain()
        assert.same(900, env.data.Data.FishCoin)
        assert.same(1, env.data.Data.UpgradeLevel)
        assert.same(3, env.data:ItemBarCapacity())
        assert.same(10, env.data:BackpackCapacity())
        assert.same(1, env.data:PurchaseCount(33))
        join()
        drain()
        local restored = env.players:GetDataInst(env.player)
        assert.same(1, restored.Data.UpgradeLevel)
        assert.same(1, restored:ShopUpgradeLevel('backpack'))
        assert.same(3, restored:ItemBarCapacity())
        assert.same(1, restored:PurchaseCount(33))
    end)

    it('test_buy_waits_for_persistence_and_retries_without_double_charge', function()
        env.data:AddCoin(10)
        persistSetup()
        env.writeFailure = true
        local request = { action = 'Buy', itemId = 'worm', seq = 1 }
        assert.is_true(env.shop:Handle(env.player, request))
        assert.same(10, env.data.Data.FishCoin)
        assert.same(0, env.data.Data.Bait.worm or 0)
        assert.is_nil(env.players:GetDataInst(env.player))
        drain()
        assert.same({}, env.events)
        assert.same(0, env.quest:GetState(env.player).count)
        assert.is_false(env.shop:Handle(env.player, request))
        env.writeFailure, env.loseReply = false, true
        env.save:Update()
        drain()
        assert.same(9, env.data.Data.FishCoin)
        assert.same(1, env.data.Data.Bait.worm)
        assert.same(1, #messages('ShopResult'))
        assert.is_true(messages('ShopResult')[1].ok)
        assert.is_true(#messages('ItemBarState') > 0)
        assert.same(1, env.quest:GetState(env.player).count)
        join()
        drain()
        local restored = env.players:GetDataInst(env.player)
        assert.same(9, restored.Data.FishCoin)
        assert.same(1, restored.Data.Bait.worm)
    end)

    it('test_exchange_keeps_token_until_write_and_publishes_product_after_retry', function()
        assert.is_true(env.data:AddItem('garHead'))
        assert.is_true(env.data:SelectSlot(1))
        persistSetup()
        env.writeFailure = true
        assert.is_true(env.interact:Handle(env.player, { target = 'fisherman', action = 'Feed', seq = 1 }))
        assert.same('garHead', env.data.Data.Containers.itemBar[1].itemId)
        drain()
        assert.same({}, env.events)
        assert.same(0, env.plays)
        env.writeFailure, env.loseReply = false, true
        env.save:Update()
        drain()
        assert.same(0, env.data:ItemCount('garHead'))
        assert.same(1, env.data:ItemCount('shrimpTicket'))
        assert.same(0, env.data.Data.FishCoin)
        assert.same({ from = 'garHead', to = 'shrimpTicket' }, messages('InteractResult')[1].exchange)
        assert.same(1, env.plays)
        assert.same(0, env.quest:GetState(env.player).count)
        join()
        drain()
        assert.same(1, env.players:GetDataInst(env.player):ItemCount('shrimpTicket'))
    end)

    it('test_exchange_replay_after_rejoin_grants_product_once', function()
        -- #127 验收 (c)：重进地图后用响应里的完整 operation 重试，只回原结果，产物不重复发放
        assert.is_true(env.data:AddItem('garHead'))
        assert.is_true(env.data:SelectSlot(1))
        persistSetup()
        assert.is_true(env.interact:Handle(env.player, { target = 'fisherman', action = 'Feed', seq = 1 }))
        drain()
        local original = messages('InteractResult')[1]
        assert.is_not_nil(original.operation)
        env.interact:OnPlayerRemoving(env.player)
        join()
        drain()
        env.data = env.players:GetDataInst(env.player)
        clearEvents()
        -- 重进后位置可以完全不同（回放不看距离），但只回原结果
        env.player.Character.Position.x = 999
        assert.is_true(env.interact:Handle(env.player,
            { target = 'fisherman', action = 'Feed', seq = 1, operation = original.operation }))
        drain()
        assert.same({ original }, messages('InteractResult'))
        assert.same(0, env.data:ItemCount('garHead'))
        assert.same(1, env.data:ItemCount('shrimpTicket'))
    end)

    it('test_exchange_uses_released_slot_when_storage_is_full', function()
        -- #127 容量口径：Save 注入下满格也能兑换——先交付选中信物释放该格，再按交付后的容量发放产物
        assert.is_true(env.data:AddItem('garHead'))
        assert.is_true(env.data:SelectSlot(1))
        while env.data:AddItem('tilapia') do end
        assert.message('前置：道具栏与背包都满了').is_false(env.data:AddItem('tilapia'))
        persistSetup()
        assert.is_true(env.interact:Handle(env.player, { target = 'fisherman', action = 'Feed', seq = 1 }))
        drain()
        assert.same(0, env.data:ItemCount('garHead'))
        assert.same(1, env.data:ItemCount('shrimpTicket'))
        assert.same('shrimpTicket', env.data.Data.Containers.itemBar[1].itemId)
        assert.same(0, env.data.Data.FishCoin)
        assert.same({ from = 'garHead', to = 'shrimpTicket' }, messages('InteractResult')[1].exchange)
    end)

    it('test_expired_and_forged_identity_cannot_buy_again', function()
        env.data:AddCoin(100)
        persistSetup()
        local first
        for seq = 1, 65 do
            assert.is_true(env.shop:Handle(env.player, { action = 'Buy', itemId = 'worm', seq = seq }))
            drain()
            first = first or messages('ShopResult')[1].operation
        end
        assert.same(35, env.data.Data.FishCoin)
        assert.same(65, env.data.Data.Bait.worm)
        clearEvents()
        assert.is_false(env.shop:Handle(env.player, { action = 'Buy', itemId = 'worm', seq = 1 }))
        assert.is_false(env.shop:Handle(env.player, { action = 'Buy', seq = 66, operation = first }))
        local forged = { id = first.id, sequence = first.sequence, kind = first.kind, requestKey = '伪造' }
        assert.is_false(env.shop:Handle(env.player, { action = 'Buy', seq = 66, operation = forged }))
        assert.same({}, env.events)
        assert.same(35, env.data.Data.FishCoin)
        assert.same(65, env.data.Data.Bait.worm)
    end)

    it('test_failed_write_exhaustion_and_failed_load_never_grant', function()
        env.data:AddCoin(20)
        persistSetup()
        env.writeFailure = true
        assert.is_true(env.shop:Handle(env.player, { action = 'Buy', itemId = 'worm', seq = 1 }))
        drain()
        for _ = 1, 4 do env.save:Update() drain() end
        assert.is_nil(env.players:GetDataInst(env.player))
        assert.same(20, env.data.Data.FishCoin)
        assert.same(0, env.data.Data.Bait.worm or 0)
        assert.same({}, messages('ItemBarState'))
        assert.same(1, #messages('ShopResult'))
        assert.is_false(messages('ShopResult')[1].ok)
        assert.same(0, env.quest:GetState(env.player).count)
        env.readFailure, env.writeFailure = true, false
        join()
        clearEvents()
        assert.is_false(env.shop:Handle(env.player, { action = 'UpgradeStorage', seq = 2 }))
        assert.is_false(env.interact:Handle(env.player, { target = 'fisherman', action = 'Feed', seq = 2 }))
        drain()
        assert.is_nil(env.players:GetDataInst(env.player))
        assert.is_false(env.shop:Handle(env.player, { action = 'Buy', itemId = 'worm', seq = 3 }))
        assert.same({}, env.events)
    end)

    it('test_feed_replays_after_selection_changes_without_eating_again', function()
        assert.is_true(env.data:AddBait('worm', 3))
        assert.is_true(env.data:SelectBait('worm'))
        persistSetup()
        local request = { target = 'fisherman', action = 'Feed', seq = 1 }
        assert.is_true(env.interact:Handle(env.player, request))
        drain()
        local original = messages('InteractResult')[1]
        assert.is_not_nil(original.operation)
        env.data:SelectBait(nil)
        clearEvents()
        assert.is_true(env.interact:Handle(env.player, request))
        assert.same({ original }, messages('InteractResult'))
        assert.same({}, messages('ItemBarState'))
        assert.same(0, env.plays)
        assert.same(1, env.data.Data.FishCoin)
        assert.same(2, env.data.Data.Bait.worm)
        env.interact:OnPlayerRemoving(env.player)
        join()
        drain()
        env.player.Character.Position.x = 999
        clearEvents()
        request.operation = original.operation
        assert.is_true(env.interact:Handle(env.player, request))
        assert.same({ original }, messages('InteractResult'))
        assert.same({}, messages('ItemBarState'))
        assert.same(0, env.plays)
    end)

    it('test_feed_selected_fish_waits_for_write_before_coins_animation_and_quest', function()
        GameCfg.Quest.Steps[1] = { Kind = 'Feed', Category = 'fish', Need = 3, Text = '喂食鱼获' }
        assert.is_true(env.data:AddItem('bass', 1.99))
        assert.is_true(env.data:SelectSlot(1))
        persistSetup()
        -- 当前基线从 Serialize 恢复选中态；cherry-pick impl-123 的选择态持久化提交后仍由真实入口重选，seam 不变。
        if env.data.Data.SelectedSlot ~= 1 then env.data:SelectSlot(1) end
        clearEvents()
        local request = { target = 'fisherman', action = 'Feed', seq = 1 }
        env.writeFailure = true
        assert.is_true(env.interact:Handle(env.player, request))
        assert.same(0, env.data.Data.FishCoin)
        assert.same('bass', env.data.Data.Containers.itemBar[1].itemId)
        assert.is_nil(env.players:GetDataInst(env.player))
        drain()
        assert.same({}, env.events)
        assert.same(0, env.plays)
        assert.same(0, env.quest:GetState(env.player).count)
        env.writeFailure = false
        env.save:Update()
        drain()
        assert.same(11, env.data.Data.FishCoin)
        assert.same(0, env.data:ItemCount('bass'))
        assert.same(11, messages('InteractResult')[1].coins)
        assert.same(1, env.plays)
        assert.same(1, env.quest:GetState(env.player).count)
        join()
        drain()
        assert.same(11, env.players:GetDataInst(env.player).Data.FishCoin)
        assert.same(0, env.players:GetDataInst(env.player):ItemCount('bass'))
    end)

    it('test_malformed_operation_cannot_replace_valid_sequence', function()
        env.data:AddCoin(5)
        env.data:AddBait('worm', 1)
        env.data:SelectBait('worm')
        persistSetup()
        for _, operation in ipairs({ 1, false, '1', {}, { kind = 'shop', sequence = 1 } }) do
            assert.is_false(env.shop:Handle(env.player, { action = 'Buy', itemId = 'worm', operation = operation }))
            assert.is_false(env.interact:Handle(env.player, { target = 'fisherman', action = 'Feed', operation = operation }))
        end
        assert.same({}, env.events)
        assert.same(5, env.data.Data.FishCoin)
        assert.same(1, env.data.Data.Bait.worm)
        assert.same(0, env.data:Serialize().meta.sequence)
    end)

    it('test_old_session_pending_write_cannot_publish_to_rejoined_player', function()
        env.data:AddCoin(20)
        persistSetup()
        env.writeFailure = true
        env.shop:Handle(env.player, { action = 'Buy', itemId = 'worm', seq = 1 })
        drain()
        env.writeFailure = false
        join()
        drain()
        clearEvents()
        env.save:Update()
        drain()
        assert.same({}, env.events)
        local restored = env.players:GetDataInst(env.player)
        assert.same(20, restored.Data.FishCoin)
        assert.same(0, restored.Data.Bait.worm or 0)
        assert.same(0, env.quest:GetState(env.player).count)
    end)

    it('test_original_identity_alone_replays_upgrade_and_exchange', function()
        env.data:AddCoin(100)
        env.data:AddItem('garHead')
        env.data:SelectSlot(1)
        persistSetup()
        assert.is_true(env.shop:Handle(env.player, { action = 'UpgradeStorage', seq = 1 }))
        drain()
        local upgrade = messages('ShopResult')[1]
        assert.is_true(env.interact:Handle(env.player, { target = 'fisherman', action = 'Feed', seq = 1 }))
        drain()
        local exchange = messages('InteractResult')[1]
        clearEvents()
        assert.is_true(env.shop:Handle(env.player, { action = 'UpgradeStorage', operation = upgrade.operation }))
        assert.is_true(env.interact:Handle(env.player, { target = 'fisherman', action = 'Feed', operation = exchange.operation }))
        assert.same({ upgrade }, messages('ShopResult'))
        assert.same({ exchange }, messages('InteractResult'))
        assert.same({}, messages('ItemBarState'))
        assert.same(0, env.plays)
        assert.same(1, env.data.Data.UpgradeLevel)
        assert.same(1, env.data:ItemCount('shrimpTicket'))
    end)

    it('test_save_injection_preserves_business_rejection_without_mutation', function()
        env.data:AddCoin(4)
        env.data:AddItem('garHead')
        env.data:SelectSlot(1)
        while env.data:AddItem('carp') do end
        persistSetup()
        local before = env.data:GetItemBarSnapshot()
        env.shop:Handle(env.player, { action = 'Buy', itemId = 'starterRod', seq = 1 })
        assert.same('full', messages('ShopResult')[1].reason)
        env.shop:Handle(env.player, { action = 'UpgradeStorage', seq = 2 })
        assert.same('coin', messages('ShopResult')[2].reason)
        -- #127 起满格不再是喂食的业务拒绝：信物兑换先交付选中格、再按交付后的容量校验，
        -- 满格也能用本次交付释放出的格位成交；钓鱼佬侧仍然真实的业务拒绝是「选中格为空」。
        -- 取消选中是本次用例的输入，不算「被拒绝的请求改动了数据」。
        env.data.Data.SelectedSlot = nil
        before.selectedSlot = nil
        env.interact:Handle(env.player, { target = 'fisherman', action = 'Feed', seq = 1 })
        assert.same('nothing', messages('InteractResult')[1].reason)
        env.shop:Handle(env.player, { action = 'Buy', itemId = 'gold', seq = 3 })
        assert.same('item', messages('ShopResult')[3].reason)
        env.player.Character.Position.x = 999
        env.shop:Handle(env.player, { action = 'Buy', itemId = 'worm', seq = 4 })
        assert.same('range', messages('ShopResult')[4].reason)
        assert.is_false(env.interact:Handle(env.player, { target = 'fisherman', action = 'Feed', seq = 2 }))
        assert.same(env.data:GetItemBarSnapshot(), before)
        assert.same({}, messages('ItemBarState'))
        assert.same(0, env.plays)
        assert.same(0, env.data:Serialize().meta.sequence)
    end)

    it('test_shop_replays_original_result_and_reconnect_seq_starts_new_request', function()
        env.data:AddCoin(20)
        persistSetup()
        local request = { action = 'Buy', itemId = 'worm', seq = 1 }
        assert.is_true(env.shop:Handle(env.player, request))
        drain()
        local original = messages('ShopResult')[1]
        assert.is_not_nil(original.operation)
        clearEvents()
        -- 已成功的同一通道 seq 即使改成扩容，也只能回原购买结果。
        assert.is_true(env.shop:Handle(env.player, { action = 'UpgradeStorage', seq = 1 }))
        assert.same({ original }, messages('ShopResult'))
        assert.same({}, messages('ItemBarState'))
        assert.same(1, env.quest:GetState(env.player).count)
        assert.same(19, env.data.Data.FishCoin)
        env.shop:OnPlayerRemoving(env.player)
        env.quest:OnPlayerRemoving(env.player)
        join()
        drain()
        env.data = env.players:GetDataInst(env.player)
        clearEvents()
        assert.is_true(env.shop:Handle(env.player, request))
        drain()
        assert.same(18, env.data.Data.FishCoin)
        assert.same(2, env.data.Data.Bait.worm)
        assert.not_same(messages('ShopResult')[1].operation.id, original.operation.id)
        clearEvents()
        env.player.Character.Position.x = 999
        assert.is_true(env.shop:Handle(env.player, { action = 'Buy', seq = 99, operation = original.operation }))
        assert.same({ original }, messages('ShopResult'))
        assert.same({}, messages('ItemBarState'))
        assert.same(18, env.data.Data.FishCoin)
        assert.same(1, env.quest:GetState(env.player).count)
    end)

    it('test_skip_level_rejected_before_persisting', function()
        -- #130 越级购买在持久前被拒绝：不产生操作、不扣钱、计数为零
        GameCfg.Shop.Stands = { { AnchorName = 'TGUnitShop', Level = 7 } }
        env.data:AddCoin(1000)
        persistSetup()
        env.shop:Handle(env.player, { action = 'Buy', number = 50, seq = 1 }) -- 近战 2 级，未买过 1 级
        assert.same('level', messages('ShopResult')[1].reason)
        drain()
        assert.same(1000, env.data.Data.FishCoin)
        assert.same(0, env.data:ShopUpgradeLevel('melee'))
        assert.same(0, env.data:PurchaseCount(50))
        assert.same(0, env.data:Serialize().meta.sequence)
    end)

    it('test_upgrade_row_persists_and_replays_without_double_charge', function()
        -- #130 升级行购买走 Save 协议：先持久后生效、同键重放不重复、限购与强化重进保持
        env.data:AddCoin(1000)
        persistSetup()
        local request = { action = 'Buy', number = 51, seq = 1 } -- 近战武器升级1，50 金
        assert.is_true(env.shop:Handle(env.player, request))
        assert.same(0, env.data:ShopUpgradeLevel('melee')) -- 落账前不生效
        assert.same({}, env.events)
        drain()
        assert.same(950, env.data.Data.FishCoin)
        assert.same(1, env.data:ShopUpgradeLevel('melee'))
        assert.same(1, env.data:PurchaseCount(51))
        local result = messages('ShopResult')[1]
        assert.is_true(result.ok)
        assert.same('近战武器升级1', result.name)
        assert.same('melee', result.kind)
        assert.is_not_nil(result.operation)
        -- 同身份重放：只回历史结果，不重复扣款/升级/计数
        clearEvents()
        assert.is_true(env.shop:Handle(env.player, { action = 'Buy', number = 51, seq = 1 }))
        assert.same({ result }, messages('ShopResult'))
        assert.same({}, messages('ItemBarState'))
        assert.same(950, env.data.Data.FishCoin)
        assert.same(1, env.data:ShopUpgradeLevel('melee'))
        assert.same(1, env.data:PurchaseCount(51))
        -- 重进保持：强化等级与购买计数都在存档里
        join()
        drain()
        local restored = env.players:GetDataInst(env.player)
        assert.same(1, restored:ShopUpgradeLevel('melee'))
        assert.same(1, restored:PurchaseCount(51))
        assert.same(950, restored.Data.FishCoin)
        -- 重进后重复购买：限购拒绝且不扣钱
        clearEvents()
        assert.is_false(env.shop:Handle(env.player, { action = 'Buy', number = 51, seq = 2 }))
        assert.same('limit', messages('ShopResult')[1].reason)
        assert.same(950, restored.Data.FishCoin)
        assert.same(1, restored:ShopUpgradeLevel('melee'))
    end)

    it('test_upgrade_waits_for_persistence', function()
        env.data:AddCoin(100)
        persistSetup()
        assert.is_true(env.shop:Handle(env.player, { action = 'UpgradeStorage', seq = 1, price = 0 }))
        assert.same(100, env.data.Data.FishCoin)
        assert.same(2, env.data:ItemBarCapacity())
        assert.same({}, env.events)
        drain()
        assert.same(0, env.data.Data.FishCoin)
        assert.same(3, env.data:ItemBarCapacity())
        assert.same(100, messages('ShopResult')[1].price)
        assert.same('UpgradeStorage', messages('ShopResult')[1].action)
        join()
        drain()
        assert.same(3, env.players:GetDataInst(env.player):ItemBarCapacity())
    end)

    it('test_upgrade_write_failure_keeps_state_and_single_settlement_after_retry', function()
        -- #130 写失败：金币、等级、计数都不变；恢复后重试只结算一次，重进保持
        env.data:AddCoin(1000)
        persistSetup()
        env.writeFailure = true
        local request = { action = 'Buy', number = 51, seq = 1 }
        assert.is_true(env.shop:Handle(env.player, request))
        assert.same(1000, env.data.Data.FishCoin)
        assert.same(0, env.data:ShopUpgradeLevel('melee'))
        drain()
        assert.same({}, env.events)
        assert.is_false(env.shop:Handle(env.player, request))
        env.writeFailure, env.loseReply = false, true
        env.save:Update()
        drain()
        assert.same(950, env.data.Data.FishCoin)
        assert.same(1, env.data:ShopUpgradeLevel('melee'))
        assert.same(1, env.data:PurchaseCount(51))
        assert.same(1, #messages('ShopResult'))
        assert.is_true(messages('ShopResult')[1].ok)
        join()
        drain()
        local restored = env.players:GetDataInst(env.player)
        assert.same(1, restored:ShopUpgradeLevel('melee'))
        assert.same(1, restored:PurchaseCount(51))
        assert.same(950, restored.Data.FishCoin)
    end)
end)

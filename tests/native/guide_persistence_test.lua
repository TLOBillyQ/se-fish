-- #88 迁移：新手引导持久化（原 tests/gameplay/guide_persistence_test.lua，14 例）。
-- #40 失败方式（编码前列出）：
-- 读档未 ready 就重置任务或播剧情；写失败提前发布；队列中的重复事实二次计数；
-- 每步中途退出丢计数/去重、提前事实跳步、跨玩家串进度、进度写入附带奖励；
-- 正式结束/跳过未写已读、其他 Story 信号误写已读、已读回流重播；
-- 兜底仅瞬时公告而无法阅读/确认；旧玩家迟到回调影响重进的新玩家；
-- 持久化事实序号重置后误去重；未 ready 的首次 UI 请求永远失联；
-- 七区说明与兑换配置不一致、烤制/抽奖资格及满格结果误导玩家。
-- 接缝：公开 Notify/GetState/Begin/OnSignal/Complete、状态 RE、真实 PlayerData/Save；
-- 替换的边界只有 Task/DataStore/StoryService/RemoteEvent/玩家引擎对象。
-- it 按旧 LuaUnit 的方法名字典序注册，保持与旧套件一致的案例顺序。
-- assertStrContains / assertNotStrContains 均未传 isPattern，即 plain 子串，映射 matches 的第 4 参 true。
local GameCfg = require('common.GameCfg')

describe('TestGuidePersistence', function()
    local env
    local saved = {}

    -- 类内辅助（旧 TestGuidePersistence:join / :drain / :rejoin / :messages / :fact）
    -- 改为接收闭包 env 的本地函数，避免在 describe 加载期往尚未赋值的 env 上挂方法。
    local function join(userId)
        env.player = { UserId = userId or 4040, CharacterAdded = env.signal, CharacterRemoving = env.signal,
            SetAttribute = function() end }
        env.players:OnPlayerAdded(env.player)
    end

    local function drain()
        while #env.tasks > 0 do table.remove(env.tasks, 1)() end
    end

    local function rejoin()
        env.quest:OnPlayerRemoving(env.player)
        env.story:OnPlayerRemoving(env.player)
        env.players:OnPlayerRemoving(env.player)
        drain()
        join()
        drain()
    end

    local function messages(name)
        local out = {}
        for _, e in ipairs(env.events) do if e.name == name then out[#out + 1] = e.payload end end
        return out
    end

    local function fact(kind, id, itemId, category)
        return env.quest:Notify(kind, env.player, { eventId = id, itemId = itemId, category = category })
    end

    -- 逐例夹具：旧 LuaUnit 每例跑 setUp/tearDown，这里同样用 before_each/after_each。
    -- 第一步保存 4 项被改状态（game / REUtil / Debug / Story）后才动任何全局与配置，
    -- 夹具中途抛错时 after_each 仍能完整还原；GameCfg.Save.AcceptanceSlot 由 helper 的
    -- 根级 before_each/after_each 建基线并逐例恢复，本批不在案例内改它。
    before_each(function()
        saved.game, saved.REUtil = rawget(_G, 'game'), rawget(_G, 'REUtil')
        saved.Debug, saved.Story = GameCfg.Debug, GameCfg.Story
        GameCfg.Debug = { Enabled = false }
        env = { values = {}, tasks = {}, events = {}, failWrite = false }
        local signal = { Connect = function() return { Disconnect = function() end } end }
        env.signal = signal
        env.store = {
            GetAsync = function(_, key) return env.values[key] end,
            UpdateAsync = function(_, key, transform)
                if env.failWrite then error('写档失败') end
                local value = transform(env.values[key])
                local operations = value and value.meta and value.meta.operations or {}
                if env.failQuestWrite and operations[#operations]
                    and operations[#operations].kind == 'quest-fact' then error('任务写档失败') end
                if value then env.values[key] = value end
                return value
            end,
        }
        _G.game = { GetService = function(_, name)
            if name == 'Task' then return { Spawn = function(_, fn) env.tasks[#env.tasks + 1] = fn end,
                Wait = function() end } end
            if name == 'DataStoreService' then return { GetDataStore = function() return env.store end } end
            if name == 'World' then return { GetServerTime = function() return 100 end } end
            if name == 'Players' then return { GetPlayers = function() return { env.player } end } end
        end }
        _G.REUtil = { GetRE = function(_, name) return {
            OnServerEvent = signal, FireClient = function(_, p, payload)
                env.events[#env.events + 1] = { name = name, player = p, payload = payload }
            end,
        } end }
        env.save = assert(loadfile('server/Mgr/MgrSave.lua'))()
        env.players = assert(loadfile('server/Mgr/MgrPlayerData.lua'))()
        env.quest = assert(loadfile('server/Mgr/MgrQuest.lua'))()
        env.story = assert(loadfile('server/Mgr/MgrStory.lua'))()
        env.players.Save, env.save.PlayerData = env.save, env.players
        env.quest.PlayerData, env.quest.Save = env.players, env.save
        env.story.PlayerData, env.story.Save = env.players, env.save
        env.save.OnReady = function(p)
            env.quest:OnPlayerAdded(p)
            if env.story.OnPlayerAdded then env.story:OnPlayerAdded(p) end
        end
        join()
    end)
    after_each(function()
        _G.game, _G.REUtil = saved.game, saved.REUtil
        GameCfg.Debug, GameCfg.Story = saved.Debug, saved.Story
        saved = {}
        env = nil
    end)

    it('test_fallback_dialogue_requires_explicit_read_and_survives_rejoin', function()
        drain()
        GameCfg.Story = { StoryId = nil, ReadKey = 'opening', StartTimeoutSec = 3,
            FallbackText = '欢迎来到钓场！', Lines = { '钓鱼佬什么都吃。', '跟着新手任务开始。' } }
        env.story:Begin(env.player)
        local notice = messages('StoryNotice')[1]
        assert.same({ '钓鱼佬什么都吃。', '跟着新手任务开始。' }, notice.lines)
        assert.is_false(env.players:GetDataInst(env.player).Extra.story.read.opening == true)
        rejoin()
        env.events = {}
        env.story:Begin(env.player)
        assert.same(1, #messages('StoryNotice'))
        assert.is_true(env.story:Complete(env.player, 'opening', 'read'))
        drain()
        rejoin()
        env.events = {}
        env.story:Begin(env.player)
        assert.same({}, messages('StoryNotice'))
        assert.is_true(env.players:GetDataInst(env.player).Extra.story.read.opening)
    end)

    it('test_feeding_consumption_coins_and_progress_share_one_commit', function()
        -- 五次蚯蚓喂食的金币和计数必须同键确认，最后一只不能消失而任务仍停在四只。
        drain()
        for i = 1, 5 do fact('PickBait', 'worm:' .. i, 'worm'); drain() end
        local data = env.players:GetDataInst(env.player)
        env.save:Execute(env.player, data, env.save:NextOperation(env.player, 'seed-bait'), function(draft)
            draft:AddBait('worm', 5)
            draft:SelectBait('worm')
            return {}
        end, function() end)
        drain()
        local interact = assert(loadfile('server/Mgr/MgrInteract.lua'))()
        interact.Save, interact.PlayerData, interact.Quest = env.save, env.players, env.quest
        env.failQuestWrite = true
        for i = 1, 5 do
            assert.is_true(interact:Feed(env.player, data, {}, GameCfg.Interact.Fisherman, i,
                env.save:NextOperation(env.player, 'interact')))
            drain()
        end
        env.failQuestWrite = false
        rejoin()
        data = env.players:GetDataInst(env.player)
        assert.same(0, data.Data.Bait.worm)
        assert.same(5, data.Data.FishCoin)
        assert.same(3, env.quest:GetState(env.player).step)
    end)

    it('test_formal_end_and_skip_persist_only_the_matching_opening', function()
        drain()
        GameCfg.Story = { StoryId = 'actual-opening', ReadKey = 'opening', StartTimeoutSec = 3 }
        local started = 0
        env.story.Service = { StartStory = function() started = started + 1 end }
        env.story:Begin(env.player)
        env.story:OnSignal('OnStoryEnd', env.player, 'other-story')
        assert.is_false(env.players:GetDataInst(env.player).Extra.story.read.opening == true)
        env.story:OnSignal('OnStoryStart', env.player, 'actual-opening')
        env.story:OnSignal('OnStorySkip', env.player, 'actual-opening')
        drain()
        assert.is_true(env.players:GetDataInst(env.player).Extra.story.read.opening)
        rejoin()
        env.story:Begin(env.player)
        assert.same(1, started)
        -- 另一玩家的独立存档走正式结束，不由本玩家已读污染。
        env.quest:OnPlayerRemoving(env.player)
        env.story:OnPlayerRemoving(env.player)
        env.players:OnPlayerRemoving(env.player)
        drain()
        join(4041)
        drain()
        env.story:Begin(env.player)
        env.story:OnSignal('OnStoryEnd', env.player, 'actual-opening')
        drain()
        assert.is_true(env.players:GetDataInst(env.player).Extra.story.read.opening)
    end)

    it('test_landing_collection_and_guide_progress_commit_together', function()
        -- 上岸图鉴的持久结果与任务不能分开，否则图鉴已确认而断线后任务仍要求重新上岸。
        drain()
        for i = 1, 5 do fact('PickBait', 'worm:' .. i, 'worm'); drain() end
        for i = 1, 5 do fact('Feed', 'feed:' .. i, 'worm'); drain() end
        for _, f in ipairs({ { 'Buy', 'buy', 'starterRod' }, { 'EquipBait', 'equip', 'worm' },
            { 'CastWater', 'cast' } }) do fact(table.unpack(f)); drain() end
        local compendium = assert(loadfile('server/Mgr/MgrCompendium.lua'))()
        compendium.Save, compendium.PlayerData, compendium.Quest = env.save, env.players, env.quest
        env.failQuestWrite = true
        assert.is_true(compendium:RecordLanding(env.player, { fishId = 'bass', mult = 1, reelSerial = 77 }))
        fact('Land', 'reel:77', 'bass')
        drain()
        env.quest:Update()
        drain()
        env.failQuestWrite = false
        rejoin()
        assert.same(1, compendium:Snapshot(env.player).total)
        assert.same(7, env.quest:GetState(env.player).step)
    end)

    it('test_leaving_waits_for_all_accepted_facts_before_destroying_player_data', function()
        drain()
        fact('PickBait', 'loot:1', 'worm')
        fact('PickBait', 'loot:2', 'worm')
        local removed = false
        assert.is_true(env.quest:FlushBeforeLeave(env.player, function()
            removed = true
            env.quest:OnPlayerRemoving(env.player)
            env.story:OnPlayerRemoving(env.player)
            env.players:OnPlayerRemoving(env.player)
        end))
        assert.is_false(removed)
        drain()
        assert.is_true(removed)
        join()
        drain()
        assert.same(2, env.quest:GetState(env.player).count)
    end)

    it('test_nine_steps_resume_and_pending_duplicates_do_not_skip_or_reward', function()
        drain()
        assert.is_true(fact('PickBait', 'loot:1', 'worm'))
        assert.is_false(fact('PickBait', 'loot:1', 'worm'))
        assert.is_true(fact('PickBait', 'loot:2', 'worm'))
        assert.is_false(fact('Buy', 'early', 'starterRod'))
        drain()
        rejoin()
        assert.same(2, env.quest:GetState(env.player).count)
        -- 新会话里合法的 loot:1 不应撞上上一轮的运行时序号。
        for i = 1, 3 do fact('PickBait', 'loot:' .. i, 'worm') drain() end
        assert.same(2, env.quest:GetState(env.player).step)
        for i = 1, 5 do fact('Feed', 'feed:' .. i, 'worm') drain() end
        local facts = {
            { 'Buy', 'buy', 'starterRod' }, { 'EquipBait', 'equip', 'worm' },
            { 'CastWater', 'cast' }, { 'Land', 'land', 'bass' },
            { 'DropShore', 'drop', 'bass' }, { 'Kill', 'kill', 'bass' },
            { 'Feed', 'feed-fish', 'bass', 'fish' },
        }
        for i, f in ipairs(facts) do
            rejoin()
            assert.same(i + 2, env.quest:GetState(env.player).step)
            assert.is_true(fact(table.unpack(f)))
            drain()
        end
        rejoin()
        assert.same(10, env.quest:GetState(env.player).step)
        local qs = messages('QuestState')
        assert.is_true(qs[#qs].done)
        local data = env.players:GetDataInst(env.player)
        assert.same(0, data.Data.FishCoin)
        assert.same({}, data:GetItemBarSnapshot().slots)
    end)

    it('test_not_ready_request_retries_and_failed_write_publishes_no_progress_or_read', function()
        GameCfg.Story = { StoryId = nil, ReadKey = 'opening', FallbackText = '欢迎来到钓场', StartTimeoutSec = 3 }
        env.quest:OnPlayerAdded(env.player)
        env.story:Begin(env.player)
        assert.is_nil(env.quest:GetState(env.player))
        assert.same({}, messages('StoryNotice'))
        drain()
        assert.same(1, #messages('StoryNotice'))
        env.events = {}
        env.failWrite = true
        fact('PickBait', 'loot:failed', 'worm')
        drain()
        for _ = 1, 4 do env.save:Update() drain() end
        assert.same(0, env.quest:GetState(env.player).count)
        assert.same({}, messages('QuestState'))
        assert.same({}, messages('StoryState'))
    end)

    it('test_pause_after_leaving_started_releases_pending_fact_barrier', function()
        -- 已进入离场屏障后才暂停存档，也必须释放回调，不能依赖再调用 Flush。
        drain()
        local data = env.players:GetDataInst(env.player)
        assert.is_true(env.save:Save(env.player.UserId, data:Serialize(), 'autosave'))
        assert.is_true(env.save:ApplyTemporary(env.player.UserId, data, { coin = 0 }, function() end))
        fact('PickBait', 'paused-later', 'worm')
        local removed = false
        assert.is_true(env.quest:FlushBeforeLeave(env.player, function()
            removed = true
            env.quest:OnPlayerRemoving(env.player)
            env.players:OnPlayerRemoving(env.player)
        end))
        drain()
        env.quest:Update()
        assert.is_true(removed)
        join()
        drain()
        assert.same(0, env.quest:GetState(env.player).count)
    end)

    it('test_pause_after_story_leave_started_releases_unconfirmed_read', function()
        drain()
        local data = env.players:GetDataInst(env.player)
        env.story:Begin(env.player)
        env.save:Save(env.player.UserId, data:Serialize(), 'autosave')
        env.save:ApplyTemporary(env.player.UserId, data, { coin = 0 }, function() end)
        env.story:Complete(env.player, 'opening', 'read')
        local removed = false
        assert.is_true(env.story:FlushBeforeLeave(env.player, function()
            removed = true
            env.story:OnPlayerRemoving(env.player)
            env.players:OnPlayerRemoving(env.player)
        end))
        drain()
        env.story:Update()
        assert.is_true(removed)
        join()
        drain()
        assert.is_false(env.players:GetDataInst(env.player).Extra.story.read.opening == true)
    end)

    it('test_paused_save_releases_guide_leave_barriers_without_claiming_commit', function()
        -- GM 暂停保存后没有可用 operation；离场不能永久等待任务/剧情内存队列。
        drain()
        local data = env.players:GetDataInst(env.player)
        assert.is_true(env.save:ApplyTemporary(env.player.UserId, data, { coin = 0 }, function() end))
        assert.is_true(env.save:Status(env.player.UserId).autosavePaused)
        fact('PickBait', 'paused-loot', 'worm')
        env.story:Begin(env.player)
        env.story:Complete(env.player, 'opening', 'read')
        local called = false
        assert.is_false(env.quest:FlushBeforeLeave(env.player, function() called = true end))
        assert.is_false(env.story:FlushBeforeLeave(env.player, function() called = true end))
        assert.is_false(called)
        rejoin()
        assert.same(0, env.quest:GetState(env.player).count)
        assert.is_false(env.players:GetDataInst(env.player).Extra.story.read.opening == true)
    end)

    it('test_purchase_and_quest_progress_commit_together_without_a_second_write', function()
        -- 购买已落账后独立任务写失败，会留下有竿却仍要求重复买竿的不可恢复状态。
        drain()
        for i = 1, 5 do fact('PickBait', 'worm:' .. i, 'worm'); drain() end
        for i = 1, 5 do fact('Feed', 'feed:' .. i, 'worm'); drain() end
        local data = env.players:GetDataInst(env.player)
        local op = env.save:NextOperation(env.player, 'seed-coins')
        env.save:Execute(env.player, data, op, function(draft)
            draft:AddCoin(5, nil, 'test')
            return {}
        end, function() end)
        drain()
        local shop = assert(loadfile('server/Mgr/MgrShop.lua'))()
        shop.Save, shop.PlayerData, shop.Quest = env.save, env.players, env.quest
        shop.Interact = { InRange = function() return true end }
        env.failQuestWrite = true
        assert.is_true(shop:Buy(env.player, data, 'starterRod', nil, 1,
            env.save:NextOperation(env.player, 'shop')))
        drain()
        env.failQuestWrite = false
        rejoin()
        assert.same(1, env.players:GetDataInst(env.player):ItemCount('starterRod'))
        assert.same(4, env.quest:GetState(env.player).step)
    end)

    it('test_quest_restores_partial_count_and_never_publishes_before_commit', function()
        drain()
        env.events = {}
        assert.is_true(fact('PickBait', 'loot:1', 'worm'))
        assert.same(0, env.quest:GetState(env.player).count)
        assert.same({}, messages('QuestState'))
        drain()
        assert.same(1, env.quest:GetState(env.player).count)
        rejoin()
        assert.same(1, env.quest:GetState(env.player).count)
        assert.same(0, env.players:GetDataInst(env.player).Data.FishCoin)
    end)

    it('test_read_waiting_for_another_write_finishes_before_leaving', function()
        drain()
        env.story:Begin(env.player)
        fact('PickBait', 'loot:1', 'worm')
        assert.is_true(env.story:Complete(env.player, 'opening', 'read'))
        local removed = false
        assert.is_true(env.story:FlushBeforeLeave(env.player, function()
            removed = true
            env.quest:OnPlayerRemoving(env.player)
            env.story:OnPlayerRemoving(env.player)
            env.players:OnPlayerRemoving(env.player)
        end))
        drain()
        env.story:Update()
        drain()
        assert.is_true(removed)
        join()
        drain()
        assert.is_true(env.players:GetDataInst(env.player).Extra.story.read.opening)
    end)

    it('test_seven_npc_dialogues_describe_real_exchange_and_cooked_full_rules', function()
        local dialogue = require('common.NpcDialogue')
        local pond = dialogue.Describe('fishPond')
        assert.matches('电鳗头', pond, 1, true)
        assert.matches('鸭子', pond, 1, true)
        assert.matches('虾池', pond, 1, true)
        local volcano = dialogue.Describe('volcanoIsland')
        assert.matches('核废料桶', volcano, 1, true)
        assert.matches('哥斯拉头', volcano, 1, true)
        assert.matches('烤制后', volcano, 1, true)
        assert.matches('三同图案', volcano, 1, true)
        assert.matches('释放的格位', volcano, 1, true)
        for _, zone in ipairs(GameCfg.Zones) do
            assert.is_not_nil(dialogue.Describe(zone.Id))
            assert.is_not_matches('技能', dialogue.Describe(zone.Id), 1, true)
        end
    end)
end)

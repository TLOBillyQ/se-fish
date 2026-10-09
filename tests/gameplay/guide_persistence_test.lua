-- #40 失败方式（编码前列出）：
-- 读档未 ready 就重置任务或播剧情；写失败提前发布；队列中的重复事实二次计数；
-- 每步中途退出丢计数/去重、提前事实跳步、跨玩家串进度、进度写入附带奖励；
-- 正式结束/跳过未写已读、其他 Story 信号误写已读、已读回流重播；
-- 兜底仅瞬时公告而无法阅读/确认；旧玩家迟到回调影响重进的新玩家；
-- 持久化事实序号重置后误去重；未 ready 的首次 UI 请求永远失联；
-- 七区说明与兑换配置不一致、烤制/抽奖资格及满格结果误导玩家。
-- 接缝：公开 Notify/GetState/Begin/OnSignal/Complete、状态 RE、真实 PlayerData/Save；
-- 替换的边界只有 Task/DataStore/StoryService/RemoteEvent/玩家引擎对象。
local lu = require('luaunit')
local GameCfg = require('common.GameCfg')
TestGuidePersistence = {}

function TestGuidePersistence:setUp()
    self.oldGame, self.oldRE = _G.game, _G.REUtil
    self.oldDebug, self.oldStory = GameCfg.Debug, GameCfg.Story
    GameCfg.Debug = { Enabled = false }
    self.values, self.tasks, self.events, self.failWrite = {}, {}, {}, false
    local env = self
    local signal = { Connect = function() return { Disconnect = function() end } end }
    self.signal = signal
    self.store = {
        GetAsync = function(_, key) return env.values[key] end,
        UpdateAsync = function(_, key, transform)
            if env.failWrite then error('写档失败') end
            local value = transform(env.values[key])
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
        OnServerEvent = signal, FireClient = function(_, player, payload)
            env.events[#env.events + 1] = { name = name, player = player, payload = payload }
        end,
    } end }
    self.save = assert(loadfile('server/Mgr/MgrSave.lua'))()
    self.players = assert(loadfile('server/Mgr/MgrPlayerData.lua'))()
    self.quest = assert(loadfile('server/Mgr/MgrQuest.lua'))()
    self.story = assert(loadfile('server/Mgr/MgrStory.lua'))()
    self.players.Save, self.save.PlayerData = self.save, self.players
    self.quest.PlayerData, self.quest.Save = self.players, self.save
    self.story.PlayerData, self.story.Save = self.players, self.save
    self.save.OnReady = function(player)
        env.quest:OnPlayerAdded(player)
        if env.story.OnPlayerAdded then env.story:OnPlayerAdded(player) end
    end
    self:join()
end

function TestGuidePersistence:tearDown()
    _G.game, _G.REUtil = self.oldGame, self.oldRE
    GameCfg.Debug, GameCfg.Story = self.oldDebug, self.oldStory
end
function TestGuidePersistence:join(userId)
    self.player = { UserId = userId or 4040, CharacterAdded = self.signal, CharacterRemoving = self.signal,
        SetAttribute = function() end }
    self.players:OnPlayerAdded(self.player)
end
function TestGuidePersistence:drain()
    while #self.tasks > 0 do table.remove(self.tasks, 1)() end
end
function TestGuidePersistence:rejoin()
    self.quest:OnPlayerRemoving(self.player)
    self.story:OnPlayerRemoving(self.player)
    self.players:OnPlayerRemoving(self.player)
    self:drain()
    self:join()
    self:drain()
end
function TestGuidePersistence:messages(name)
    local out = {}
    for _, e in ipairs(self.events) do if e.name == name then out[#out + 1] = e.payload end end
    return out
end
function TestGuidePersistence:fact(kind, id, itemId, category)
    return self.quest:Notify(kind, self.player, { eventId = id, itemId = itemId, category = category })
end

function TestGuidePersistence:test_quest_restores_partial_count_and_never_publishes_before_commit()
    self:drain()
    self.events = {}
    lu.assertTrue(self:fact('PickBait', 'loot:1', 'worm'))
    lu.assertEquals(self.quest:GetState(self.player).count, 0)
    lu.assertEquals(self:messages('QuestState'), {})
    self:drain()
    lu.assertEquals(self.quest:GetState(self.player).count, 1)
    self:rejoin()
    lu.assertEquals(self.quest:GetState(self.player).count, 1)
    lu.assertEquals(self.players:GetDataInst(self.player).Data.FishCoin, 0)
end

function TestGuidePersistence:test_nine_steps_resume_and_pending_duplicates_do_not_skip_or_reward()
    self:drain()
    lu.assertTrue(self:fact('PickBait', 'loot:1', 'worm'))
    lu.assertFalse(self:fact('PickBait', 'loot:1', 'worm'))
    lu.assertTrue(self:fact('PickBait', 'loot:2', 'worm'))
    lu.assertFalse(self:fact('Buy', 'early', 'starterRod'))
    self:drain()
    self:rejoin()
    lu.assertEquals(self.quest:GetState(self.player).count, 2)
    -- 新会话里合法的 loot:1 不应撞上上一轮的运行时序号。
    for i = 1, 3 do self:fact('PickBait', 'loot:' .. i, 'worm') self:drain() end
    lu.assertEquals(self.quest:GetState(self.player).step, 2)
    for i = 1, 5 do self:fact('Feed', 'feed:' .. i, 'worm') self:drain() end
    local facts = {
        { 'Buy', 'buy', 'starterRod' }, { 'EquipBait', 'equip', 'worm' },
        { 'CastWater', 'cast' }, { 'Land', 'land', 'bass' },
        { 'DropShore', 'drop', 'bass' }, { 'Kill', 'kill', 'bass' },
        { 'Feed', 'feed-fish', 'bass', 'fish' },
    }
    for i, f in ipairs(facts) do
        self:rejoin()
        lu.assertEquals(self.quest:GetState(self.player).step, i + 2)
        lu.assertTrue(self:fact(table.unpack(f)))
        self:drain()
    end
    self:rejoin()
    lu.assertEquals(self.quest:GetState(self.player).step, 10)
    lu.assertTrue(self:messages('QuestState')[#self:messages('QuestState')].done)
    local data = self.players:GetDataInst(self.player)
    lu.assertEquals(data.Data.FishCoin, 0)
    lu.assertEquals(data:GetItemBarSnapshot().slots, {})
end

function TestGuidePersistence:test_fallback_dialogue_requires_explicit_read_and_survives_rejoin()
    self:drain()
    GameCfg.Story = { StoryId = nil, ReadKey = 'opening', StartTimeoutSec = 3,
        FallbackText = '欢迎来到钓场！', Lines = { '钓鱼佬什么都吃。', '跟着新手任务开始。' } }
    self.story:Begin(self.player)
    local notice = self:messages('StoryNotice')[1]
    lu.assertEquals(notice.lines, { '钓鱼佬什么都吃。', '跟着新手任务开始。' })
    lu.assertFalse(self.players:GetDataInst(self.player).Extra.story.read.opening == true)
    self:rejoin()
    self.events = {}
    self.story:Begin(self.player)
    lu.assertEquals(#self:messages('StoryNotice'), 1)
    lu.assertTrue(self.story:Complete(self.player, 'opening', 'read'))
    self:drain()
    self:rejoin()
    self.events = {}
    self.story:Begin(self.player)
    lu.assertEquals(self:messages('StoryNotice'), {})
    lu.assertTrue(self.players:GetDataInst(self.player).Extra.story.read.opening)
end

function TestGuidePersistence:test_formal_end_and_skip_persist_only_the_matching_opening()
    self:drain()
    GameCfg.Story = { StoryId = 'actual-opening', ReadKey = 'opening', StartTimeoutSec = 3 }
    local started = 0
    self.story.Service = { StartStory = function() started = started + 1 end }
    self.story:Begin(self.player)
    self.story:OnSignal('OnStoryEnd', self.player, 'other-story')
    lu.assertFalse(self.players:GetDataInst(self.player).Extra.story.read.opening == true)
    self.story:OnSignal('OnStoryStart', self.player, 'actual-opening')
    self.story:OnSignal('OnStorySkip', self.player, 'actual-opening')
    self:drain()
    lu.assertTrue(self.players:GetDataInst(self.player).Extra.story.read.opening)
    self:rejoin()
    self.story:Begin(self.player)
    lu.assertEquals(started, 1)
    -- 另一玩家的独立存档走正式结束，不由本玩家已读污染。
    self.quest:OnPlayerRemoving(self.player)
    self.story:OnPlayerRemoving(self.player)
    self.players:OnPlayerRemoving(self.player)
    self:drain()
    self:join(4041)
    self:drain()
    self.story:Begin(self.player)
    self.story:OnSignal('OnStoryEnd', self.player, 'actual-opening')
    self:drain()
    lu.assertTrue(self.players:GetDataInst(self.player).Extra.story.read.opening)
end

function TestGuidePersistence:test_not_ready_request_retries_and_failed_write_publishes_no_progress_or_read()
    GameCfg.Story = { StoryId = nil, ReadKey = 'opening', FallbackText = '欢迎来到钓场', StartTimeoutSec = 3 }
    self.quest:OnPlayerAdded(self.player)
    self.story:Begin(self.player)
    lu.assertNil(self.quest:GetState(self.player))
    lu.assertEquals(self:messages('StoryNotice'), {})
    self:drain()
    lu.assertEquals(#self:messages('StoryNotice'), 1)
    self.events = {}
    self.failWrite = true
    self:fact('PickBait', 'loot:failed', 'worm')
    self:drain()
    for _ = 1, 4 do self.save:Update() self:drain() end
    lu.assertEquals(self.quest:GetState(self.player).count, 0)
    lu.assertEquals(self:messages('QuestState'), {})
    lu.assertEquals(self:messages('StoryState'), {})
end

function TestGuidePersistence:test_leaving_waits_for_all_accepted_facts_before_destroying_player_data()
    self:drain()
    self:fact('PickBait', 'loot:1', 'worm')
    self:fact('PickBait', 'loot:2', 'worm')
    local removed = false
    lu.assertTrue(self.quest:FlushBeforeLeave(self.player, function()
        removed = true
        self.quest:OnPlayerRemoving(self.player)
        self.story:OnPlayerRemoving(self.player)
        self.players:OnPlayerRemoving(self.player)
    end))
    lu.assertFalse(removed)
    self:drain()
    lu.assertTrue(removed)
    self:join()
    self:drain()
    lu.assertEquals(self.quest:GetState(self.player).count, 2)
end

function TestGuidePersistence:test_read_waiting_for_another_write_finishes_before_leaving()
    self:drain()
    self.story:Begin(self.player)
    self:fact('PickBait', 'loot:1', 'worm')
    lu.assertTrue(self.story:Complete(self.player, 'opening', 'read'))
    local removed = false
    lu.assertTrue(self.story:FlushBeforeLeave(self.player, function()
        removed = true
        self.quest:OnPlayerRemoving(self.player)
        self.story:OnPlayerRemoving(self.player)
        self.players:OnPlayerRemoving(self.player)
    end))
    self:drain()
    self.story:Update()
    self:drain()
    lu.assertTrue(removed)
    self:join()
    self:drain()
    lu.assertTrue(self.players:GetDataInst(self.player).Extra.story.read.opening)
end

function TestGuidePersistence:test_seven_npc_dialogues_describe_real_exchange_and_cooked_full_rules()
    local dialogue = require('common.NpcDialogue')
    local pond = dialogue.Describe('fishPond')
    lu.assertStrContains(pond, '电鳗头')
    lu.assertStrContains(pond, '鸭子')
    lu.assertStrContains(pond, '虾池')
    local volcano = dialogue.Describe('volcanoIsland')
    lu.assertStrContains(volcano, '核废料桶')
    lu.assertStrContains(volcano, '哥斯拉头')
    lu.assertStrContains(volcano, '烤制后')
    lu.assertStrContains(volcano, '三同图案')
    lu.assertStrContains(volcano, '释放的格位')
    for _, zone in ipairs(GameCfg.Zones) do
        lu.assertNotNil(dialogue.Describe(zone.Id))
        lu.assertNotStrContains(dialogue.Describe(zone.Id), '技能')
    end
end

return TestGuidePersistence

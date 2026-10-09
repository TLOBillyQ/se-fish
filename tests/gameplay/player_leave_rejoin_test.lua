-- #56 失败方式（先列后写）：
-- 任务事实/剧情已读未落账就替换会话；旧死亡状态和角色连接残留；最终离场快照被新认领取消；
-- 重复离场/迟到清理误删新会话；等待玩家已离开或被再次重进替换仍被接纳；跨玩家阻塞；失败后卡住。
-- 接缝：真实 main/Save/PlayerData/Quest/Story/Vitals；替换引擎边界和无关管理器。
local lu = require('luaunit')
local GameCfg = require('common.GameCfg')
TestPlayerLeaveRejoin = {}

local function signal()
    local s = { handlers = {} }
    function s:Connect(fn)
        self.handlers[#self.handlers + 1] = fn
        return { Disconnect = function()
            for i, handler in ipairs(s.handlers) do
                if handler == fn then table.remove(s.handlers, i) return end
            end
        end }
    end
    function s:Fire(...)
        for _, fn in ipairs({ table.unpack(self.handlers) }) do fn(...) end
    end
    return s
end

local function player(id)
    local p = { UserId = id, attrs = {}, CharacterAdded = signal(), CharacterRemoving = signal() }
    function p:SetAttribute(key, value) self.attrs[key] = value end
    local c = { Health = 300, MaxHealth = 300, HealthChanged = signal(), Died = signal(), OnReborn = signal() }
    function c:TakeDamage(amount)
        self.Health = math.max(0, self.Health - amount)
        self.HealthChanged:Fire(self.Health)
        if self.Health == 0 then self.Died:Fire() end
    end
    p.Character = { Controller = c }
    return p
end

function TestPlayerLeaveRejoin:setUp()
    self.oldGame, self.oldRE, self.oldMgrUtil, self.oldPlayers = _G.game, _G.REUtil, _G.MgrUtil, _G.MgrPlayerData
    self.oldDebug, self.oldSlot = GameCfg.Debug, GameCfg.Save.AcceptanceSlot
    GameCfg.Debug, GameCfg.Save.AcceptanceSlot = { Enabled = false }, ''
    self.tasks, self.values, self.errors, self.cleanups = {}, {}, {}, {}
    local env = self
    self.players = { PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end }
    self.heartbeat = signal()
    self.store = {
        GetAsync = function(_, key) return env.values[key] end,
        UpdateAsync = function(_, key, transform)
            local value = transform(env.values[key])
            if env.failWrite and value and value.meta.session == env.failedToken then error('测试写档失败') end
            if value then env.values[key] = value end
            return value
        end,
    }
    _G.game = {
        BindToClose = function() end,
        GetService = function(_, name)
            if name == 'Task' then return {
                Spawn = function(_, fn) env.tasks[#env.tasks + 1] = fn end, Wait = function() end,
            } end
            if name == 'Players' then return env.players end
            if name == 'RunService' then return { Heartbeat = env.heartbeat } end
            if name == 'World' then return { GetServerTime = function() return 100 end } end
            if name == 'DataStoreService' then return { GetDataStore = function() return env.store end } end
        end,
    }
    _G.REUtil = { GetRE = function() return {
        OnServerEvent = signal(), FireClient = function() end,
    } end }
    self.mgrs = {}
    for _, name in ipairs({ 'MgrSave', 'MgrPlayerData', 'MgrQuest', 'MgrStory', 'MgrVitals' }) do
        self.mgrs[name] = assert(loadfile('server/Mgr/' .. name .. '.lua'))()
    end
    self.save, self.data, self.quest, self.story, self.vitals =
        self.mgrs.MgrSave, self.mgrs.MgrPlayerData, self.mgrs.MgrQuest, self.mgrs.MgrStory, self.mgrs.MgrVitals
    local sandbox = setmetatable({
        print = function(...)
            local parts = { ... }
            if parts[1] == '[server.main]' then env.errors[#env.errors + 1] = parts end
        end,
        require = function(path)
            if path == 'server.MgrUtil' then return { Start = function() end } end
            local name = path:match('^server%.Mgr%.(.*)$')
            if not name then return require(path) end
            if not env.mgrs[name] then
                env.mgrs[name] = {
                    OnPlayerRemoving = function(_, p)
                        env.cleanups[#env.cleanups + 1] = { name = name, player = p }
                    end,
                }
            end
            return env.mgrs[name]
        end,
    }, { __index = _G })
    -- 仅为与本问题无关的生命/属性/能力接缝提供确定返回值。
    self.mgrs.MgrSurvival = { Hooks = function() return {} end }
    self.mgrs.MgrAbility = { IsParalyzed = function() return false end }
    self.mgrs.MgrAttr = {
        MaxHealth = function() return 300 end,
        ProjectHunger = function(_, _, value) return true, value end,
    }
    assert(loadfile('server/main.lua', 't', sandbox))()
    self.a = self:join(560)
    self:drain()
end

function TestPlayerLeaveRejoin:tearDown()
    _G.game, _G.REUtil, _G.MgrUtil, _G.MgrPlayerData = self.oldGame, self.oldRE, self.oldMgrUtil, self.oldPlayers
    GameCfg.Debug, GameCfg.Save.AcceptanceSlot = self.oldDebug, self.oldSlot
end

function TestPlayerLeaveRejoin:join(id)
    local p = player(id)
    self.players.PlayerAdded:Fire(p)
    return p
end

function TestPlayerLeaveRejoin:drain()
    local count = 0
    while #self.tasks > 0 do
        count = count + 1
        assert(count < 100, '异步队列未收敛')
        table.remove(self.tasks, 1)()
    end
    lu.assertEquals(self.errors, {})
end

function TestPlayerLeaveRejoin:fact(id)
    lu.assertTrue(self.quest:Notify('PickBait', self.a, { itemId = 'worm', eventId = id }))
end

function TestPlayerLeaveRejoin:assertRejoined(p)
    lu.assertEquals(p.attrs.SaveState, 'ready')
    lu.assertNotNil(self.data:GetDataInst(p))
    local state = self.vitals:GetState(p)
    lu.assertIs(state.player, p)
    lu.assertTrue(state.bound)
    lu.assertEquals(#p.Character.Controller.Died.handlers, 1)
    lu.assertEquals(#self.a.CharacterAdded.handlers, 0)
    lu.assertEquals(#self.a.Character.Controller.Died.handlers, 0)
end

function TestPlayerLeaveRejoin:test_quest_queue_keeps_old_session_until_committed_then_rebinds()
    self:fact('worm:1')
    self:fact('worm:2')
    local old = self.save.Sessions[self.a.UserId]
    self.players.PlayerRemoving:Fire(self.a)
    local late = self.quest.Queues[self.a.UserId].leave
    local b = self:join(self.a.UserId)
    lu.assertIs(self.save.Sessions[self.a.UserId], old)
    lu.assertEquals(b.attrs.SaveState, 'pending')
    self:drain()
    self:assertRejoined(b)
    lu.assertEquals(self.quest:GetState(b).count, 2)
    lu.assertEquals(self.values.u560.extra.quest.count, 2)
    local current = self.save.Sessions[b.UserId]
    late()
    self.players.PlayerRemoving:Fire(self.a)
    lu.assertIs(self.save.Sessions[b.UserId], current)
    self:assertRejoined(b)
end

function TestPlayerLeaveRejoin:test_dead_old_vitals_does_not_block_new_living_player()
    self.a.Character.Controller:TakeDamage(300)
    lu.assertFalse(self.vitals:CanAct(self.a))
    self:fact('worm:dead')
    self.players.PlayerRemoving:Fire(self.a)
    local b = self:join(self.a.UserId)
    self:drain()
    self:assertRejoined(b)
    lu.assertTrue(self.vitals:CanAct(b))
end

function TestPlayerLeaveRejoin:test_story_read_waiting_for_quest_survives_rejoin()
    self.story:Begin(self.a)
    self:fact('worm:story')
    lu.assertTrue(self.story:Complete(self.a, self.story.States[self.a.UserId].readKey, 'read'))
    self.players.PlayerRemoving:Fire(self.a)
    local b = self:join(self.a.UserId)
    self:drain()
    self:assertRejoined(b)
    local restored = self.data:GetDataInst(b)
    lu.assertEquals(restored.Extra.quest.count, 1)
    lu.assertTrue(restored.Extra.story.read[GameCfg.Story.ReadKey or 'opening'])
    lu.assertTrue(self.values.u560.extra.story.read[GameCfg.Story.ReadKey or 'opening'])
end

function TestPlayerLeaveRejoin:test_final_leave_snapshot_is_drained_before_new_claim()
    self.data:GetDataInst(self.a):AddCoin(17)
    self.players.PlayerRemoving:Fire(self.a)
    local b = self:join(self.a.UserId)
    lu.assertEquals(b.attrs.SaveState, 'pending')
    self:drain()
    self:assertRejoined(b)
    lu.assertEquals(self.data:GetDataInst(b).Data.FishCoin, 17)
    lu.assertEquals(self.values.u560.coin, 17)
end

function TestPlayerLeaveRejoin:test_waiting_player_removed_and_only_latest_rejoin_is_admitted()
    self:fact('worm:waiting')
    self.players.PlayerRemoving:Fire(self.a)
    local b = self:join(self.a.UserId)
    self.players.PlayerRemoving:Fire(b)
    self:drain()
    lu.assertNil(self.data:GetDataInst(b))
    lu.assertNil(self.save.Sessions[b.UserId])
    lu.assertNil(self.vitals:GetState(b))
    local c = self:join(self.a.UserId)
    self:drain()
    self.a = c
    self:fact('worm:latest')
    self.players.PlayerRemoving:Fire(c)
    local d = self:join(c.UserId)
    local e = self:join(c.UserId)
    self.players.PlayerRemoving:Fire(d)
    self:drain()
    self:assertRejoined(e)
    lu.assertNil(self.data:GetDataInst(d))
    lu.assertEquals(self.quest:GetState(e).count, 2)
end

function TestPlayerLeaveRejoin:test_retry_failure_finishes_without_blocking_other_user()
    self:fact('worm:failure')
    self.failedToken = self.save.Sessions[self.a.UserId].Token
    self.players.PlayerRemoving:Fire(self.a)
    local b = self:join(self.a.UserId)
    self.failWrite = true
    self:drain()
    self.failWrite = false
    local other = self:join(561)
    self:drain()
    lu.assertEquals(other.attrs.SaveState, 'ready')
    lu.assertEquals(b.attrs.SaveState, 'pending')
    self.failWrite = true
    for _ = 1, 3 do self.save:Update() self:drain() end
    self.failWrite = false
    self:drain()
    -- 旧写失败关闭屏障，新玩家仍可从最后确认的存档恢复。
    self:assertRejoined(b)
    lu.assertEquals(self.quest:GetState(b).count, 0)
end

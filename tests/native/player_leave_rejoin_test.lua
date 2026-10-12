-- #88 迁移：玩家离场与重进（原 tests/gameplay/player_leave_rejoin_test.lua，6 例）。
-- #56 失败方式（先列后写）：
-- 任务事实/剧情已读未落账就替换会话；旧死亡状态和角色连接残留；最终离场快照被新认领取消；
-- 重复离场/迟到清理误删新会话；等待玩家已离开或被再次重进替换仍被接纳；跨玩家阻塞；失败后卡住。
-- 接缝：真实 main/Save/PlayerData/Quest/Story/Vitals；替换引擎边界和无关管理器。
-- it 按旧 LuaUnit 的方法名字典序注册，保持与旧套件一致的案例顺序。
-- assertIs(state.player, p) 要求对象身份：全仓无 __eq 元方法（已检索确认），故 Lua 的 == 即身份，映射 are.equal。
local GameCfg = require('common.GameCfg')

local function signal()
    local s = { handlers = {} }
    function s:Connect(fn)
        self.handlers[#self.handlers + 1] = fn
        return { Disconnect = function()
            for i, handler in ipairs(self.handlers) do
                if handler == fn then table.remove(self.handlers, i) return end
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

describe('TestPlayerLeaveRejoin', function()
    local env
    local saved = {}

    -- 类内辅助（旧 TestPlayerLeaveRejoin:join / :drain / :fact / :assertRejoined）改为接收 env 的本地函数，
    -- 避免在 describe 加载期就往尚未赋值的 env 上挂方法。
    local function join(id)
        local p = player(id)
        env.players.PlayerAdded:Fire(p)
        return p
    end

    local function drain()
        local count = 0
        while #env.tasks > 0 do
            count = count + 1
            assert(count < 100, '异步队列未收敛')
            table.remove(env.tasks, 1)()
        end
        assert.same({}, env.errors)
    end

    local function fact(id)
        assert.is_true(env.quest:Notify('PickBait', env.a, { itemId = 'worm', eventId = id }))
    end

    local function assertRejoined(p)
        assert.same('ready', p.attrs.SaveState)
        assert.is_not_nil(env.data:GetDataInst(p))
        local state = env.vitals:GetState(p)
        assert.are.equal(p, state.player)
        assert.is_true(state.bound)
        assert.same(1, #p.Character.Controller.Died.handlers)
        assert.same(0, #env.a.CharacterAdded.handlers)
        assert.same(0, #env.a.Character.Controller.Died.handlers)
    end

    -- 逐例夹具：旧 LuaUnit 每例跑 setUp/tearDown，这里同样用 before_each/after_each。
    -- 第一步把所有被改状态（4 个全局 + Debug + AcceptanceSlot）存进 saved，之后才改任何东西，
    -- 因此夹具中途抛错时 after_each 仍能完整还原，不把失败泄漏给后续案例。
    before_each(function()
        saved.game, saved.REUtil = rawget(_G, 'game'), rawget(_G, 'REUtil')
        saved.MgrUtil, saved.MgrPlayerData = rawget(_G, 'MgrUtil'), rawget(_G, 'MgrPlayerData')
        saved.Debug, saved.slot = GameCfg.Debug, GameCfg.Save.AcceptanceSlot
        GameCfg.Debug, GameCfg.Save.AcceptanceSlot = { Enabled = false }, ''
        env = { tasks = {}, values = {}, errors = {}, cleanups = {}, mgrs = {} }
        env.players = { PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end }
        env.heartbeat = signal()
        env.store = {
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
        for _, name in ipairs({ 'MgrSave', 'MgrPlayerData', 'MgrQuest', 'MgrStory', 'MgrVitals' }) do
            env.mgrs[name] = assert(loadfile('server/Mgr/' .. name .. '.lua'))()
        end
        env.save, env.data, env.quest, env.story, env.vitals =
            env.mgrs.MgrSave, env.mgrs.MgrPlayerData, env.mgrs.MgrQuest, env.mgrs.MgrStory, env.mgrs.MgrVitals
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
        env.mgrs.MgrSurvival = { Hooks = function() return {} end }
        env.mgrs.MgrAbility = { IsParalyzed = function() return false end }
        env.mgrs.MgrAttr = {
            MaxHealth = function() return 300 end,
            ProjectHunger = function(_, _, value) return true, value end,
        }
        assert(loadfile('server/main.lua', 't', sandbox))()
        env.a = join(560)
        drain()
    end)
    after_each(function()
        _G.game, _G.REUtil, _G.MgrUtil, _G.MgrPlayerData = saved.game, saved.REUtil, saved.MgrUtil, saved.MgrPlayerData
        GameCfg.Debug, GameCfg.Save.AcceptanceSlot = saved.Debug, saved.slot
        saved = {}
        env = nil
    end)

    it('test_dead_old_vitals_does_not_block_new_living_player', function()
        env.a.Character.Controller:TakeDamage(300)
        assert.is_false(env.vitals:CanAct(env.a))
        fact('worm:dead')
        env.players.PlayerRemoving:Fire(env.a)
        local b = join(env.a.UserId)
        drain()
        assertRejoined(b)
        assert.is_true(env.vitals:CanAct(b))
    end)

    it('test_final_leave_snapshot_is_drained_before_new_claim', function()
        env.data:GetDataInst(env.a):AddCoin(17)
        env.players.PlayerRemoving:Fire(env.a)
        local b = join(env.a.UserId)
        assert.same('pending', b.attrs.SaveState)
        drain()
        assertRejoined(b)
        assert.same(17, env.data:GetDataInst(b).Data.FishCoin)
        assert.same(17, env.values.u560.coin)
    end)

    it('test_quest_queue_keeps_old_session_until_committed_then_rebinds', function()
        fact('worm:1')
        fact('worm:2')
        local old = env.save.Sessions[env.a.UserId]
        env.players.PlayerRemoving:Fire(env.a)
        local late = env.quest.Queues[env.a.UserId].leave
        local b = join(env.a.UserId)
        assert.are.equal(old, env.save.Sessions[env.a.UserId])
        assert.same('pending', b.attrs.SaveState)
        drain()
        assertRejoined(b)
        assert.same(2, env.quest:GetState(b).count)
        assert.same(2, env.values.u560.extra.quest.count)
        local current = env.save.Sessions[b.UserId]
        late()
        env.players.PlayerRemoving:Fire(env.a)
        assert.are.equal(current, env.save.Sessions[b.UserId])
        assertRejoined(b)
    end)

    it('test_retry_failure_finishes_without_blocking_other_user', function()
        fact('worm:failure')
        env.failedToken = env.save.Sessions[env.a.UserId].Token
        env.players.PlayerRemoving:Fire(env.a)
        local b = join(env.a.UserId)
        env.failWrite = true
        drain()
        env.failWrite = false
        local other = join(561)
        drain()
        assert.same('ready', other.attrs.SaveState)
        assert.same('pending', b.attrs.SaveState)
        env.failWrite = true
        for _ = 1, 3 do env.save:Update() drain() end
        env.failWrite = false
        drain()
        -- 旧写失败关闭屏障，新玩家仍可从最后确认的存档恢复。
        assertRejoined(b)
        assert.same(0, env.quest:GetState(b).count)
    end)

    it('test_story_read_waiting_for_quest_survives_rejoin', function()
        env.story:Begin(env.a)
        fact('worm:story')
        assert.is_true(env.story:Complete(env.a, env.story.States[env.a.UserId].readKey, 'read'))
        env.players.PlayerRemoving:Fire(env.a)
        local b = join(env.a.UserId)
        drain()
        assertRejoined(b)
        local restored = env.data:GetDataInst(b)
        assert.same(1, restored.Extra.quest.count)
        assert.is_true(restored.Extra.story.read[GameCfg.Story.ReadKey or 'opening'])
        assert.is_true(env.values.u560.extra.story.read[GameCfg.Story.ReadKey or 'opening'])
    end)

    it('test_waiting_player_removed_and_only_latest_rejoin_is_admitted', function()
        fact('worm:waiting')
        env.players.PlayerRemoving:Fire(env.a)
        local b = join(env.a.UserId)
        env.players.PlayerRemoving:Fire(b)
        drain()
        assert.is_nil(env.data:GetDataInst(b))
        assert.is_nil(env.save.Sessions[b.UserId])
        assert.is_nil(env.vitals:GetState(b))
        local c = join(env.a.UserId)
        drain()
        env.a = c
        fact('worm:latest')
        env.players.PlayerRemoving:Fire(c)
        local d = join(c.UserId)
        local e = join(c.UserId)
        env.players.PlayerRemoving:Fire(d)
        drain()
        assertRejoined(e)
        assert.is_nil(env.data:GetDataInst(d))
        assert.same(2, env.quest:GetState(e).count)
    end)
end)


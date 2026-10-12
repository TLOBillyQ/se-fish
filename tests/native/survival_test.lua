-- #89 迁移（原 tests/gameplay/survival_test.lua，#131 T10 生存恢复 + #139 成长后复活口径）：
-- 濒死、免费虚弱复活与离线恢复（server/Mgr/MgrSurvival.lua + MgrVitals 接管）。
-- 数值来源：策划案--渔力全开.docx 濒死/复活段（15 秒抢救、30 秒倒计时、10% 血、虚弱 1 分钟半速、
-- 肾上腺素恢复 10%）与物品表 item171；验收清单见 issue #131。
-- 失败方式（先列后写）：
--   1. 致命伤害不锁 1 血直接死亡，或锁血后濒死中还能被扣血（连续攻击越过濒死）；
--   2. 濒死 15 秒不到就转死亡 / 到了不转；死亡 30 秒不到就复活 / 到了不复活；虚弱 60 秒提前结束；
--   3. 虚弱复活血量不是 10%（30）、饥饿低于 30、没进虚弱、虚弱没半速、结束没恢复；
--   4. 濒死/死亡中饥饿照走、能吃、能抛竿（CanAct 失守）；濒死不断钓鱼、不放举着的鱼；
--   5. 肾上腺素：非濒死也能用、没物品也复活、并发双击多扣、消耗成功不复活；
--   6. 离线：濒死/死亡退出重进不是 10% 血加虚弱；虚弱退出剩余时间不对；旧回调覆盖新状态；
--   7. 原生 Died/Reborn 与轮询兜底同时触发时重复复活；MgrVitals 兜底 Reborn 在接管期抢跑；
--   8. 抢救接缝：非濒死能救、救后血量不是 10%；状态泄漏到其他玩家；离开后状态残留。
-- 接缝：真实 MgrVitals + MgrSurvival + 真实 MgrSave/PlayerData（Task 排队、DataStore 内存桶），
--   REUtil 桩收广播；modifier 走 tests/tooling/modifier_runtime，成长侧用 SpeedWriter 桩注入。
-- 迁移说明：旧套件用「类方法委托」（TestSurvivalRevive.setUp = TestSurvivalDowned.setUp 等）共享夹具，
--   原生侧逐例 before_each/after_each 各自调用同一个 build()/teardown()，恢复面一致：
--   替换的模块缓存 common.REUtil 与（attachSave 的类）_G.game 无条件写回原值（含 nil），
--   after_each 对未完成的 before_each 幂等。describe/it 名沿用旧类名与方法名，
--   案例顺序沿用旧 LuaUnit 的字典序执行序（类名与类内方法名均按字典序）。
local GameCfg = require('common.GameCfg')
local PlayerData = require('server.Data.PlayerData')

-- 假玩家 / 假 Controller（沿用 combat_base_test 模式）；WalkSpeed 供虚弱半速断言
local function signal()
    local s = { handlers = {} }
    function s:Connect(fn)
        self.handlers[#self.handlers + 1] = fn
        return { Disconnect = function() end }
    end
    function s:Fire(...) for _, fn in ipairs(self.handlers) do fn(...) end end
    return s
end

local function newPlayer(id)
    local c = { Health = 300, MaxHealth = 300, WalkSpeed = 10, HealthChanged = signal(),
        Died = signal(), OnReborn = signal(), diedCount = 0, reborns = 0 }
    function c:TakeDamage(n)
        self.Health = math.max(0, self.Health - n)
        self.HealthChanged:Fire(self.Health)
        if self.Health <= 0 then self.diedCount = self.diedCount + 1 self.Died:Fire() end
    end
    function c:Reborn() self.reborns = self.reborns + 1 self.Health = self.MaxHealth self.OnReborn:Fire() end
    local p = { UserId = id, Name = 'p' .. id, attrs = {}, CharacterAdded = signal(),
        Character = { Controller = c, Position = { x = id, y = 0, z = 0 }, Size = { y = 2 } } }
    function p:SetAttribute(k, v) self.attrs[k] = v end
    return p
end

-- 真实 MgrSave + PlayerData（沿用 save_foundation_test 的引擎边界替身：Task 排队执行、DataStore 内存桶）。
-- 落账回调在 drain() 时才到达，用来观察「先持久后生效」与在飞窗口。
local function attachSave(env)
    env.oldGame = rawget(_G, 'game')
    env.values, env.queue, env.writeFailure = {}, {}, nil -- 每个案例都是全新夹具，标志每例复位
    env.store = {
        GetAsync = function(_, key) return env.values[key] end,
        UpdateAsync = function(_, key, transform)
            if env.writeFailure then error('写档失败') end
            local value = transform(env.values[key])
            if value then env.values[key] = value end
            return value
        end,
        SetAsync = function(_, key, value) env.values[key] = value end,
    }
    _G.game = { GetService = function(_, name)
        if name == 'Task' then
            return { Spawn = function(_, fn) env.queue[#env.queue + 1] = fn end, Wait = function() end }
        end
        if name == 'DataStoreService' then return { GetDataStore = function() return env.store end } end
        if name == 'World' then return { GetServerTime = function() return env.now end } end
        if name == 'Players' then return { GetPlayers = function() return {} end } end
    end }
    env.save = assert(loadfile('server/Mgr/MgrSave.lua'))()
    function env:drain()
        while #self.queue > 0 do table.remove(self.queue, 1)() end
    end
end

local function joinData(env, player)
    local data = PlayerData.New(player)
    data:Init(true)
    env.save:LoadInto(player, data)
    env:drain()
    assert.same('ready', data.LoadState)
    return data
end

-- 不经 ItemCount（Inited=false 时恒为 0）直接数容器里的件数，读档屏障关闭后也能看物品还在不在
local function rawCount(data, itemId)
    local total = 0
    for _, container in pairs(data.Data.Containers) do
        for _, entry in pairs(container) do
            if entry.itemId == itemId and entry.count > 0 then total = total + entry.count end
        end
    end
    return total
end

-- 旧 TestSurvivalDowned:setUp 的夹具本体；各派生类在旧套件里委托同一份实现，原生侧同样共用。
local function build()
    local env = {
        now = 100,
        messages = {},
        events = {}, -- 按名缓存：服务端 Start 里连的 OnServerEvent 与测试触发的是同一个信号
        savedRE = package.loaded['common.REUtil'],
        savedGame = rawget(_G, 'game'),
    }
    package.loaded['common.REUtil'] = {
        GetRE = function(_, name)
            env.messages[name] = env.messages[name] or {}
            env.events[name] = env.events[name] or {
                FireClient = function(_, player, value)
                    table.insert(env.messages[name], { player = player, value = value })
                end,
                FireAllClients = function(_, value)
                    table.insert(env.messages[name], { player = 'all', value = value })
                end,
                OnServerEvent = signal(),
            }
            return env.events[name]
        end,
        CheckRECD = function() return false end,
    }
    env.v = assert(loadfile('server/Mgr/MgrVitals.lua'))()
    env.v.Now = function() return env.now end
    env.s = assert(loadfile('server/Mgr/MgrSurvival.lua'))()
    env.s.Now = function() return env.now end
    require('tests.tooling.modifier_runtime').AttachSurvival(env.s, function() return env.now end)
    env.s.Vitals = env.v
    env.v:SetLifeHooks(env.s:Hooks())
    env.a, env.b = newPlayer(1), newPlayer(2)
    env.v:OnPlayerAdded(env.a)
    env.v:OnPlayerAdded(env.b)
    env.s:OnPlayerAdded(env.a)
    env.s:OnPlayerAdded(env.b)
    function env:ctrl(p) return (p or self.a).Character.Controller end
    function env:enterDowned()
        self:ctrl().Health = 50
        local ok, actual = self.v:ApplyHit(self.v:NewHit(self.b, 'fishAttack'), self.a, 100)
        assert.is_true(ok)
        assert.same(49, actual)
    end
    function env:enterDead()
        self:enterDowned() -- now=100 进濒死
        self.now = 115
        self.s:Update()
        assert.same('dead', self.v:LifeStatus(self.a))
    end
    function env:tick(seconds, step)
        step = step or 0.5
        local target = self.now + seconds
        while self.now + 1e-9 < target do
            self.now = math.min(target, self.now + step)
            self.v:Update()
            self.s:Update()
        end
    end
    return env
end

-- 旧 tearDown 链：attachSave 的类先还原 _G.game，再还原 common.REUtil。
-- 两者都读 before_each 抓好的原值，nil 也写回（不留残留桩）。
local function teardown(env)
    if not env then return end
    if env.oldGame ~= nil or rawget(_G, 'game') ~= nil then
        _G.game = env.oldGame
    end
    package.loaded['common.REUtil'] = env.savedRE
end

-- #139 审查失败方式：成长后免费复活/抢救仍按300恢复30；同角色复活无CharacterAdded，成长漏重套。
local function installGrowth(env)
    env.growthCalls = 0
    env.v.MaxHealthProvider = function() return 900 end
    env.v:RefreshMaxHealth(env.a)
    env.s.SpeedWriter = {
        RefreshMoveSpeed = function(_, p)
            p.Character.Controller.WalkSpeed = env.s.Modifier:GetRemaining(p, 'weak') > 0 and 10.5 or 21
            return true
        end,
        ApplyGrowth = function(_, p)
            env.growthCalls = env.growthCalls + 1
            env.v:RefreshMaxHealth(p)
            p.Character.Controller.WalkSpeed = env.s.Modifier:GetRemaining(p, 'weak') > 0 and 10.5 or 21
            return { Ok = true }
        end,
    }
end

describe('TestSurvivalAdrenaline', function()
    local ctx

    before_each(function()
        ctx = build()
        attachSave(ctx)
        ctx.data = joinData(ctx, ctx.a)
        local env = ctx
        ctx.s.Save = ctx.save
        ctx.s.PlayerData = { GetDataInst = function(_, p) return p == env.a and env.data or nil end }
        ctx.s:Start() -- 连上 SurvivalAction 上行事件
    end)

    after_each(function() teardown(ctx) end)

    local function give(n)
        for _ = 1, n do assert.is_true(ctx.data:GrantItem('item171', 1)) end
    end

    local function use(seq)
        ctx.events.SurvivalAction.OnServerEvent:Fire(ctx.a, { action = 'UseAdrenaline', seq = seq })
    end

    local function result()
        local sent = ctx.messages.SurvivalResult
        return sent[#sent].value
    end

    -- 并发双击：第一次落账未确认时的重复点击回 busy，已救起后的迟到点击回 not-downed，恰好扣 1 件
    it('test_concurrent_clicks_consume_exactly_one', function()
        give(2)
        ctx:enterDowned()
        use(1)
        use(2) -- 第一次落账未确认时的并发点击
        assert.same('busy', result().reason)
        ctx:drain()
        use(3) -- 已救起后的迟到点击
        ctx:drain()
        assert.same('not-downed', result().reason)
        assert.same(1, ctx.data:ItemCount('item171'))
        assert.same(1, #ctx.data:Serialize().meta.operations)
    end)

    -- 已付出的自救不能被倒计时抢先转死亡而白扣物品
    it('test_downed_countdown_waits_for_the_in_flight_adrenaline', function()
        give(1)
        ctx:enterDowned() -- 100 进濒死，截止点 115
        use(1)
        ctx.now = 116 -- 落账未回，截止点已过
        ctx.s:Update()
        assert.is_true(ctx.v:IsDowned(ctx.a))
        ctx:drain()
        assert.same('alive', ctx.v:LifeStatus(ctx.a))
        assert.same(0, ctx.data:ItemCount('item171'))
        assert.same(30, ctx:ctrl().Health)
    end)

    -- 坏请求号最先拒：不弹商店、不建操作
    it('test_non_numeric_seq_rejected_before_any_precheck_or_side_effect', function()
        local opened = {}
        ctx.s.Platform = { OpenAdrenalineShop = function(_, p) opened[#opened + 1] = p end }
        ctx:enterDowned()
        ctx.events.SurvivalAction.OnServerEvent:Fire(ctx.a, { action = 'UseAdrenaline', seq = 'abc' })
        assert.same('invalid', result().reason)
        assert.same(0, #opened) -- 没物品也不弹商店：坏请求号最先拒
        assert.same(0, #ctx.data:Serialize().meta.operations)
    end)

    -- 重进后旧请求的落账回调不能改新状态：既不替它救起，也不留在飞标记
    it('test_old_callback_cannot_touch_the_state_of_a_rejoined_player', function()
        give(1)
        ctx:enterDowned()
        use(1)
        local old = ctx.s:GetState(ctx.a)
        ctx.s:OnPlayerRemoving(ctx.a)
        ctx.s:OnPlayerAdded(ctx.a) -- 重进：全新的活动状态
        local new = ctx.s:GetState(ctx.a)
        assert.are_not.equal(new, old)
        ctx:drain() -- 旧请求的落账回调此刻到达
        -- 存档里带着濒死标记，重进后的新状态在等离线恢复落账；旧回调既不能替它救起也不能留在飞标记
        assert.same('dead', new.phase)
        assert.is_nil(new.adrenalineFlying)
        assert.same(1, ctx:ctrl().Health) -- 旧回调没有对新状态执行救起
    end)

    -- 只有濒死可用；活动中与已转死亡都被拒，物品不扣
    it('test_only_downed_players_can_use_and_the_item_is_kept', function()
        give(1)
        use(1) -- 活动中
        ctx:drain()
        assert.same('not-downed', result().reason)
        ctx:enterDowned()
        ctx.now = 115
        ctx.s:Update() -- 15 秒到转死亡
        use(2)
        ctx:drain()
        assert.same('not-downed', result().reason)
        assert.same(1, ctx.data:ItemCount('item171'))
        assert.same('dead', ctx.v:LifeStatus(ctx.a))
    end)

    -- 写档失败：物品仍在、不留在飞标记、不救起
    it('test_persist_failure_keeps_item_and_does_not_rescue', function()
        give(1)
        ctx:enterDowned()
        ctx.writeFailure = true
        use(1)
        for _ = 1, 6 do -- 写档重试耗尽后关闭会话，回调收到失败
            ctx.save:Update()
            ctx:drain()
        end
        assert.is_false(result().ok)
        assert.same(1, rawCount(ctx.data, 'item171')) -- 物品仍在
        assert.is_nil(ctx.s:GetState(ctx.a).adrenalineFlying)
        assert.same(1, ctx:ctrl().Health)
        assert.is_true(ctx.v:IsDowned(ctx.a)) -- 失败不救起
    end)

    -- 预检看到有物品但结算扣不到（内存与草稿不一致的防御分支）：拒绝、无副作用、不留在飞标记
    it('test_rejected_settlement_leaves_no_flight_marker_or_side_effects', function()
        ctx.data.ItemCount = function() return 1 end
        ctx:enterDowned()
        use(1)
        assert.same('no-adrenaline', result().reason)
        assert.is_nil(ctx.s:GetState(ctx.a).adrenalineFlying)
        assert.is_true(ctx.v:IsDowned(ctx.a))
        assert.same(0, #ctx.data:Serialize().meta.operations)
        ctx.now = 115 -- 标记没残留：倒计时照常转死亡
        ctx.s:Update()
        assert.same('dead', ctx.v:LifeStatus(ctx.a))
    end)

    -- 救起成功后同一请求号重放只回 'replay'，不能被 'not-downed' 预检拦截
    it('test_replay_after_successful_rescue_answers_replay_not_precheck', function()
        give(1)
        ctx:enterDowned()
        use(1)
        ctx:drain() -- 自救落账成功，已救起回活动
        assert.same('alive', ctx.v:LifeStatus(ctx.a))
        use(1) -- 同一请求号重放
        assert.same('replay', result().reason)
        assert.same(0, ctx.data:ItemCount('item171')) -- 不重复扣物
        assert.same(1, #ctx.data:Serialize().meta.operations)
    end)

    -- 同一请求号重放：只回放记录，不再扣物、不再救起；新请求号才是新的一次自救
    it('test_same_request_replay_never_charges_or_rescues_twice', function()
        give(2)
        ctx:enterDowned()
        use(1)
        ctx:drain()
        ctx.now = 110
        assert.is_true(ctx.v:ApplyHit(ctx.v:NewHit(ctx.b, 'fishAttack'), ctx.a, 100)) -- 30 血再次致命
        assert.is_true(ctx.v:IsDowned(ctx.a))
        use(1) -- 同一请求号重放
        ctx:drain()
        assert.same('replay', result().reason)
        assert.same(1, ctx.data:ItemCount('item171'))
        assert.is_true(ctx.v:IsDowned(ctx.a))
        assert.same(1, ctx:ctrl().Health)
        use(2) -- 新请求号才是新的一次自救
        ctx:drain()
        assert.same(0, ctx.data:ItemCount('item171'))
        assert.same('alive', ctx.v:LifeStatus(ctx.a))
        assert.same(30, ctx:ctrl().Health)
    end)

    -- 自救结算进行中队友抢救让位，否则物品白扣
    it('test_teammate_rescue_cannot_race_the_in_flight_adrenaline', function()
        give(1)
        ctx:enterDowned()
        use(1)
        assert.is_false(ctx.v:Rescue(ctx.a, ctx.b))
        ctx:drain()
        assert.same(30, ctx:ctrl().Health)
        assert.same(0, ctx.data:ItemCount('item171'))
    end)

    -- 先持久后生效：落账成功才扣 1 件并救起，操作记进 #123 操作日志
    it('test_use_consumes_one_item_and_rescues_only_after_persist', function()
        give(2)
        ctx:enterDowned() -- now=100
        use(1)
        -- 持久成功前不生效：血仍锁 1，物品仍在，倒计时仍是濒死
        assert.is_true(ctx.v:IsDowned(ctx.a))
        assert.same(1, ctx:ctrl().Health)
        assert.same(2, rawCount(ctx.data, 'item171')) -- 在飞期间读档屏障关闭，直接数容器
        ctx:drain()
        assert.same(1, ctx.data:ItemCount('item171')) -- 恰好扣 1 件
        assert.same('alive', ctx.v:LifeStatus(ctx.a))
        assert.same(30, ctx:ctrl().Health) -- 恢复 10% × 300
        assert.same(10, ctx:ctrl().WalkSpeed) -- 自救不带虚弱
        assert.is_true(result().ok)
        local operations = ctx.data:Serialize().meta.operations
        assert.same(1, #operations)
        assert.same('survival:adrenaline', operations[1].kind)
    end)

    -- 没物品：打开 T26 平台购买接缝，什么都不改；接缝缺席只回包不报错
    it('test_without_item_opens_platform_purchase_seam_and_changes_nothing', function()
        local opened = {}
        ctx.s.Platform = { OpenAdrenalineShop = function(_, p) opened[#opened + 1] = p end }
        ctx:enterDowned()
        use(1)
        ctx:drain()
        assert.same({ ctx.a }, opened) -- T26 平台购买入口接缝
        assert.is_false(result().ok)
        assert.same('no-adrenaline', result().reason)
        assert.is_true(ctx.v:IsDowned(ctx.a))
        assert.same(1, ctx:ctrl().Health)
        assert.same(0, #ctx.data:Serialize().meta.operations) -- 没建操作、没落账
        ctx.s.Platform = nil -- 接缝缺席（T26 未接）：只回包不报错
        use(2)
        assert.same('no-adrenaline', result().reason)
    end)
end)

describe('TestSurvivalConfig', function()
    -- 配置数值逐条对策划案与验收清单
    it('test_values_match_design_doc', function()
        local cfg = GameCfg.Survival
        assert.is_not_nil(cfg)
        assert.same(15, cfg.DownedSec)             -- 策划案：十五秒之内可以抢救
        assert.same(30, cfg.DeadSec)               -- 策划案：30 秒倒计时结束虚弱复活
        assert.same(10, cfg.ReviveHealthPercent)   -- 策划案：复活血量 10%
        assert.same(10, cfg.ReviveHungerPercent)   -- 验收：无付费复活饥饿至少 30（300×10%）
        assert.same(60, cfg.WeakSec)               -- 策划案：虚弱持续 1 分钟
        assert.same(0.5, cfg.WeakSpeedScale)       -- 策划案：移动速度下降 50%
        assert.same('item171', cfg.AdrenalineItemId) -- 物品表 R172 肾上腺素（自救道具）
    end)
end)

describe('TestSurvivalDowned', function()
    local ctx

    before_each(function() ctx = build() end)

    after_each(function() teardown(ctx) end)

    -- 濒死期间对连续攻击免疫：锁血不被越过，饥饿伤害同样不能越过
    it('test_downed_is_invincible_to_repeated_attacks', function()
        ctx:enterDowned()
        for _ = 1, 3 do
            assert.is_false(ctx.v:ApplyHit(ctx.v:NewHit(ctx.b, 'fishAttack'), ctx.a, 50))
        end
        assert.same(1, ctx:ctrl().Health)
        local state = ctx.v:GetState(ctx.a)
        state.hunger = 0
        state.lastSec = math.floor(ctx.now) - 1
        ctx.v:UpdateState(state, ctx.now)
        assert.same(1, ctx:ctrl().Health)
    end)

    -- 濒死恰好在 15 秒整转死亡；死亡后仍不可行动、仍可锁 1 血
    it('test_downed_turns_dead_exactly_after_15_seconds', function()
        ctx:enterDowned()
        ctx.now = 114.9
        ctx.s:Update()
        assert.is_true(ctx.v:IsDowned(ctx.a))
        ctx.now = 115
        ctx.s:Update()
        assert.same('dead', ctx.v:LifeStatus(ctx.a))
        assert.is_false(ctx.v:CanAct(ctx.a))
        assert.is_false(ctx.v:ApplyHit(ctx.v:NewHit(ctx.b, 'fishAttack'), ctx.a, 50))
        assert.same(1, ctx:ctrl().Health)
    end)

    -- 致命伤害锁 1 血进濒死：引擎死亡未发生、旧死亡流程未介入、不泄漏到其他玩家
    it('test_lethal_damage_locks_one_health_and_enters_downed', function()
        ctx:enterDowned()
        assert.same(1, ctx:ctrl().Health)
        assert.is_true(ctx.v:IsDowned(ctx.a))
        assert.is_false(ctx.v:CanAct(ctx.a))
        assert.same(0, ctx:ctrl().diedCount) -- 锁血拦截，引擎死亡未发生
        assert.is_false(ctx.v:GetState(ctx.a).dead) -- 旧死亡流程未介入
        assert.is_false(ctx.v:IsDowned(ctx.b)) -- 不泄漏到其他玩家
    end)

    -- 虚弱期间二次死亡：baseSpeed 必须仍是全速基准，两轮虚弱不能叠成 2.5
    it('test_second_death_during_weak_does_not_compound_slow', function()
        ctx:enterDowned() -- 100 进濒死
        ctx.now = 115
        ctx.s:Update() -- 死亡
        ctx.now = 145
        ctx.s:Update() -- 虚弱复活：半速，weakUntil=205
        assert.same(5, ctx:ctrl().WalkSpeed)
        ctx.now = 150
        ctx:ctrl().Health = 30 -- 虚弱中可被攻击
        assert.is_true(ctx.v:ApplyHit(ctx.v:NewHit(ctx.b, 'fishAttack'), ctx.a, 100))
        assert.is_true(ctx.v:IsDowned(ctx.a))
        ctx.now = 165
        ctx.s:Update() -- 第二轮死亡
        ctx.now = 195
        ctx.s:Update() -- 第二轮虚弱复活
        assert.same(5, ctx:ctrl().WalkSpeed)
        assert.same(255, ctx.s:GetState(ctx.a).weakUntil)
        ctx.now = 255
        ctx.s:Update() -- 虚弱结束恢复全速
        assert.same(10, ctx:ctrl().WalkSpeed)
    end)
end)

describe('TestSurvivalFishing', function()
    local ctx

    before_each(function()
        ctx = build()
        ctx.fishCalls, ctx.reelCalls = {}, {}
        local env = ctx
        ctx.s.FishUnit = { OnDied = function(_, p) env.fishCalls[#env.fishCalls + 1] = p end }
        ctx.s.ReelIn = { Interrupt = function(_, p) env.reelCalls[#env.reelCalls + 1] = p end }
    end)

    after_each(function() teardown(ctx) end)

    -- 进濒死：释放举鱼 + 断抛竿会话复用 MgrFishUnit:OnDied；收线会话走 MgrReelIn:Interrupt
    it('test_entering_downed_releases_fish_and_breaks_fishing', function()
        ctx:enterDowned()
        assert.same({ ctx.a }, ctx.fishCalls)
        assert.same({ ctx.a }, ctx.reelCalls)
    end)
end)

describe('TestSurvivalHelp', function()
    local ctx

    before_each(function()
        ctx = build()
        ctx.c = newPlayer(3)
        ctx.c.Character.Position = { x = 100, y = 0, z = 0 } -- 远在 30 米外
        ctx.v:OnPlayerAdded(ctx.c)
        ctx.s:OnPlayerAdded(ctx.c)
        ctx.s:Start()
    end)

    after_each(function() teardown(ctx) end)

    local function call()
        ctx.events.SurvivalAction.OnServerEvent:Fire(ctx.a, { action = 'CallHelp' })
    end

    local function helpFor(player)
        local out = {}
        for _, message in ipairs(ctx.messages.SurvivalHelp or {}) do
            if message.player == player then out[#out + 1] = message.value end
        end
        return out
    end

    -- 呼救 1 秒冷却内被吞，冷却后按顺序轮换呼救文本
    it('test_call_help_is_rate_limited_and_cycles_the_cries', function()
        local cries = GameCfg.Survival.HelpCries
        ctx:enterDowned()
        call()
        ctx.now = 100.5
        call() -- 1 秒冷却内
        assert.same(1, #helpFor(ctx.b))
        ctx.now = 101
        call()
        local heard = helpFor(ctx.b)
        assert.same(2, #heard)
        assert.same(cries[2], heard[2].text)
    end)

    -- 呼救只到达 30 米内的队友：活动中无效、不给自己、不给远处
    it('test_call_help_reaches_only_nearby_teammates_while_downed', function()
        call() -- 活动中呼救无效
        assert.same(0, #(ctx.messages.SurvivalHelp or {}))
        ctx:enterDowned()
        call()
        local heard = helpFor(ctx.b)
        assert.same(1, #heard) -- b 在 30 米内
        assert.same('p1', heard[1].name)
        assert.same(GameCfg.Survival.HelpCries[1], heard[1].text)
        assert.same(0, #helpFor(ctx.c)) -- c 在 30 米外
        assert.same(0, #helpFor(ctx.a)) -- 不回给自己
    end)
end)

describe('TestSurvivalOffline', function()
    local ctx

    before_each(function()
        ctx = build()
        attachSave(ctx)
        ctx.data = joinData(ctx, ctx.a)
        local env = ctx
        ctx.s.Save = ctx.save
        ctx.s.PlayerData = { GetDataInst = function(_, p) return p == env.a and env.data or nil end }
        ctx.s:Start()
    end)

    after_each(function() teardown(ctx) end)

    local function mark() return ctx.data.Extra.survival end

    -- 退出再重进：服务端 Survival 状态随玩家清掉，存档 Extra.survival 里的离线标记是唯一凭据
    local function rejoin()
        ctx.s:BeforeLeave(ctx.a)
        ctx.s.Modifier:OnPlayerRemoving(ctx.a)
        ctx.s:OnPlayerRemoving(ctx.a)
        ctx:ctrl().WalkSpeed = 10 -- 新会话的角色是默认速度
        ctx.s.Modifier:OnPlayerAdded(ctx.a)
        ctx.s:OnPlayerAdded(ctx.a)
    end

    -- 退出前把剩余秒数写进离线标记（濒死/死亡各一个口径）
    it('test_downed_and_dead_mark_remaining_before_leaving', function()
        ctx:enterDowned() -- 100 进濒死
        ctx.now = 105
        ctx.s:BeforeLeave(ctx.a)
        assert.is_true(mark().dying)
        assert.is_false(mark().dead)
        assert.same(10, mark().dyingRemaining)
        ctx.now = 115
        ctx.s:Update() -- 转死亡
        ctx.now = 120
        ctx.s:BeforeLeave(ctx.a)
        assert.is_true(mark().dead)
        assert.is_false(mark().dying)
        assert.same(25, mark().deadRemaining)
    end)

    -- 再次重进：旧离线恢复回调不能碰新状态，旧状态也没被改动
    it('test_old_recover_callback_cannot_touch_a_newer_state', function()
        ctx:enterDowned()
        rejoin() -- 落账在飞
        local old = ctx.s:GetState(ctx.a)
        ctx.s:OnPlayerRemoving(ctx.a)
        ctx.s:OnPlayerAdded(ctx.a) -- 再次重进（存档标记仍是濒死）
        local new = ctx.s:GetState(ctx.a)
        assert.are_not.equal(new, old)
        ctx:drain()
        assert.are_not.equal(ctx.s:GetState(ctx.a), old)
        assert.is_nil(old.weakUntil) -- 旧状态没被旧回调改动
    end)

    -- 写档失败：没确认落账就不放行，玩家保持不可行动
    it('test_persist_failure_keeps_player_out_of_action', function()
        ctx:enterDowned()
        ctx.writeFailure = true
        rejoin()
        for _ = 1, 6 do
            ctx.save:Update()
            ctx:drain()
        end
        assert.are_not.same('alive', ctx.v:LifeStatus(ctx.a)) -- 没确认落账就不放行
        assert.same(1, ctx:ctrl().Health)
    end)

    -- 濒死/死亡退出重进都是 10% 血 + 半速虚弱，标记清零、各落一次恢复操作
    it('test_rejoin_after_downed_or_dead_gives_ten_percent_health_and_weak', function()
        for _, phase in ipairs({ 'downed', 'dead' }) do
            ctx.now = 200
            ctx:enterDowned()
            if phase == 'dead' then ctx.now = 215 ctx.s:Update() end
            rejoin()
            assert.same('dead', ctx.v:LifeStatus(ctx.a)) -- 落账确认前不放行
            assert.same(1, ctx:ctrl().Health)
            ctx:drain()
            assert.same('alive', ctx.v:LifeStatus(ctx.a))
            assert.same(30, ctx:ctrl().Health)
            assert.is_true(ctx.v:GetState(ctx.a).hunger >= 30)
            assert.same(5, ctx:ctrl().WalkSpeed) -- 半速虚弱
            assert.same(ctx.now + 60, ctx.s:GetState(ctx.a).weakUntil)
            assert.is_false(mark().dying)
            assert.is_false(mark().dead)
            assert.same(60, mark().weakRemaining)
            ctx.now = ctx.now + 60
            ctx.s:Update() -- 收尾：清虚弱，进入下一轮
            assert.same(10, ctx:ctrl().WalkSpeed)
        end
        local recover = 0
        for _, op in ipairs(ctx.data:Serialize().meta.operations) do
            if op.kind == 'survival:recover' then recover = recover + 1 end
        end
        assert.same(2, recover) -- 两次重进各落一次
    end)

    -- 没有离线标记的重进什么都不改
    it('test_rejoin_with_nothing_pending_changes_nothing', function()
        rejoin()
        ctx:drain()
        assert.same('alive', ctx.s:Phase(ctx.a))
        assert.is_nil(ctx.s:GetState(ctx.a).weakUntil)
        assert.same(0, #ctx.data:Serialize().meta.operations)
        assert.same(300, ctx:ctrl().Health)
    end)

    -- 虚弱中重生（CharacterAdded）后引擎给默认速度，服务端按虚弱重新压回半速
    it('test_respawn_keeps_weak_speed', function()
        ctx:enterDowned()
        ctx.now = 130
        ctx.s:Update()
        ctx.now = 160
        ctx.s:Update()
        ctx:ctrl().WalkSpeed = 10 -- 重生后引擎给了默认速度
        ctx.a.CharacterAdded:Fire(ctx.a.Character)
        assert.same(5, ctx:ctrl().WalkSpeed)
    end)

    -- 虚弱剩余时间跟随时钟：轮询镜像、退出终镜像、重进后按剩余继续走
    it('test_weak_remaining_follows_the_clock_and_survives_rejoin', function()
        ctx:enterDowned()
        ctx.now = 130
        ctx.s:Update() -- 死亡
        ctx.now = 160
        ctx.s:Update() -- 30 秒到，虚弱复活，weakUntil=220
        assert.same('alive', ctx.s:Phase(ctx.a))
        ctx.now = 180
        ctx.s:Update()
        assert.same(40, mark().weakRemaining) -- 轮询镜像
        ctx.now = 190
        rejoin() -- 退出时终镜像剩 30 秒
        assert.same(30, mark().weakRemaining)
        assert.same('alive', ctx.s:Phase(ctx.a))
        assert.same(5, ctx:ctrl().WalkSpeed)
        ctx.now = 219
        ctx.s:Update()
        assert.same(5, ctx:ctrl().WalkSpeed)
        ctx.now = 220
        ctx.s:Update()
        assert.same(10, ctx:ctrl().WalkSpeed)
        assert.same(0, mark().weakRemaining)
    end)
end)

describe('TestSurvivalRescue', function()
    local ctx

    before_each(function() ctx = build() end)

    after_each(function() teardown(ctx) end)

    -- #139 成长后抢救：按 900 上限恢复 10%，并重新套一次成长（无 CharacterAdded 也不漏）
    it('test_grown_rescue_uses_900_health_and_reapplies_growth', function()
        installGrowth(ctx)
        ctx:enterDowned()
        assert.is_true(ctx.v:Rescue(ctx.a, ctx.b))
        assert.same(90, ctx:ctrl().Health)
        assert.same(21, ctx:ctrl().WalkSpeed)
        assert.same(1, ctx.growthCalls)
    end)

    -- 饥饿从救起那一刻恢复推进，不补濒死期间暂停的秒数
    it('test_hunger_resumes_from_rescue_second_without_catching_up', function()
        local state = ctx.v:GetState(ctx.a)
        state.hunger = 100
        state.lastSec = math.floor(ctx.now)
        ctx:enterDowned()
        ctx.now = 108
        ctx.v:Update()
        assert.same(100, state.hunger) -- 濒死期间暂停
        assert.is_true(ctx.v:Rescue(ctx.a, ctx.b))
        ctx.now = 109
        ctx.v:Update()
        assert.same(99, state.hunger) -- 只走救起后的 1 秒，不补濒死期间的 8 秒
    end)

    -- 旧截止点绝不套用到被救起或再次濒死的玩家：每轮从当次起算满 15 秒
    it('test_old_deadline_never_applies_to_rescued_or_redowned_player', function()
        ctx:enterDowned() -- 100 进濒死，旧截止点 115
        ctx.now = 105
        assert.is_true(ctx.v:Rescue(ctx.a, ctx.b))
        ctx.now = 110
        assert.is_true(ctx.v:ApplyHit(ctx.v:NewHit(ctx.b, 'fishAttack'), ctx.a, 100)) -- 30 血再次致命
        assert.is_true(ctx.v:IsDowned(ctx.a))
        ctx.now = 115 -- 第一次濒死的旧截止点：新一轮不能被旧计时结束
        ctx.s:Update()
        assert.is_true(ctx.v:IsDowned(ctx.a))
        ctx.now = 124.9
        ctx.s:Update()
        assert.is_true(ctx.v:IsDowned(ctx.a))
        ctx.now = 125 -- 新一轮从 110 起算满 15 秒
        ctx.s:Update()
        assert.same('dead', ctx.v:LifeStatus(ctx.a))
    end)

    -- 抢救只作用于目标本人，不泄漏到其他玩家
    it('test_rescue_does_not_touch_other_players', function()
        ctx:enterDowned()
        assert.is_false(ctx.v:Rescue(ctx.b, ctx.a)) -- b 没濒死
        assert.same(300, ctx:ctrl(ctx.b).Health)
        assert.is_true(ctx.v:IsDowned(ctx.a))
        assert.same(1, ctx:ctrl().Health)
    end)

    -- 只有濒死可救：活动中不能救成 30 血，15 秒到转死亡后窗口关闭
    it('test_rescue_only_works_while_downed', function()
        assert.is_false(ctx.v:Rescue(ctx.a, ctx.b)) -- 活动中不能被「救」成 30 血
        assert.same(300, ctx:ctrl().Health)
        ctx:enterDowned()
        ctx.now = 115
        ctx.s:Update() -- 15 秒到转死亡，抢救窗口关闭
        assert.is_false(ctx.v:Rescue(ctx.a, ctx.b))
        assert.same('dead', ctx.v:LifeStatus(ctx.a))
        assert.same(1, ctx:ctrl().Health)
    end)

    -- 抢救恢复 10% 血且不带虚弱（虚弱只属于死亡后的虚弱复活）
    it('test_rescue_restores_ten_percent_health_without_weak', function()
        ctx:enterDowned() -- now=100 进濒死
        ctx.now = 105
        assert.is_true(ctx.v:Rescue(ctx.a, ctx.b))
        assert.same(30, ctx:ctrl().Health) -- 10% × 300
        assert.same(30, ctx.a.attrs.Health) -- 客户端 HUD 属性同步
        assert.same('alive', ctx.v:LifeStatus(ctx.a))
        assert.is_true(ctx.v:CanAct(ctx.a))
        assert.same(10, ctx:ctrl().WalkSpeed) -- 抢救不带虚弱
        assert.same(0, ctx:ctrl().diedCount)
        local sent = ctx.messages.SurvivalState
        assert.same('alive', sent[#sent].value.phase) -- 客户端撤掉濒死蒙版
    end)
end)

describe('TestSurvivalRevive', function()
    local ctx

    before_each(function() ctx = build() end)

    after_each(function() teardown(ctx) end)

    -- 死亡原地复活：恰好在 30 秒整，10% 血 + 饥饿下限 + 虚弱半速，位置不动、不调引擎 Reborn
    it('test_dead_revives_in_place_after_30_seconds_with_weak', function()
        ctx:enterDead()
        ctx.v:GetState(ctx.a).hunger = 10 -- 复活前饥饿低于下限
        ctx.now = 144.9
        ctx.s:Update()
        assert.same('dead', ctx.v:LifeStatus(ctx.a))
        ctx.now = 145
        ctx.s:Update()
        assert.same('alive', ctx.v:LifeStatus(ctx.a))
        assert.is_true(ctx.v:CanAct(ctx.a))
        assert.same(30, ctx:ctrl().Health) -- 10% × 300
        assert.same(30, ctx.v:GetState(ctx.a).hunger) -- 饥饿至少 10% × 300
        assert.same(5, ctx:ctrl().WalkSpeed) -- 虚弱半速（10 × 0.5）
        assert.same(0, ctx:ctrl().reborns) -- 原地复活：不走引擎 Reborn
        assert.same({ x = 1, y = 0, z = 0 }, ctx.a.Character.Position) -- 位置不动
    end)

    -- #139 成长后免费复活：按 900 上限恢复 10%，同角色无 CharacterAdded 也重新套成长
    it('test_grown_free_revive_uses_900_health_and_reapplies_growth_without_character_event', function()
        installGrowth(ctx)
        ctx:enterDead()
        ctx.now = 145; ctx.s:Update()
        assert.same(90, ctx:ctrl().Health)
        assert.same(900, ctx:ctrl().MaxHealth)
        assert.same(1, ctx.growthCalls)
        assert.same(10.5, ctx:ctrl().WalkSpeed)
        ctx.now = 205; ctx.s:Update()
        assert.same(21, ctx:ctrl().WalkSpeed)
        assert.same(900, ctx:ctrl().MaxHealth)
        assert.same(0, ctx:ctrl().reborns)
    end)

    -- 复活只在饥饿低于下限时抬到下限，已有的高饥饿保留
    it('test_revive_keeps_higher_hunger', function()
        ctx:enterDead()
        ctx.v:GetState(ctx.a).hunger = 200
        ctx.now = 145
        ctx.s:Update()
        assert.same(200, ctx.v:GetState(ctx.a).hunger)
        assert.same(30, ctx:ctrl().Health)
    end)

    -- 虚弱恰好在 60 秒整结束并恢复全速
    it('test_weak_recovers_full_speed_exactly_after_60_seconds', function()
        ctx:enterDead()
        ctx.now = 145
        ctx.s:Update()
        assert.same(5, ctx:ctrl().WalkSpeed)
        ctx.now = 204.9
        ctx.s:Update()
        assert.same(5, ctx:ctrl().WalkSpeed)
        ctx.now = 205
        ctx.s:Update()
        assert.same(10, ctx:ctrl().WalkSpeed)
    end)
end)

describe('TestSurvivalTakeover', function()
    local ctx

    before_each(function() ctx = build() end)

    after_each(function() teardown(ctx) end)

    -- 编辑器死亡规则抢先满血复活：状态机发现后立即修正为虚弱复活，且只修正一次
    it('test_engine_revive_during_dead_is_corrected_once', function()
        ctx:ctrl().Health = 0
        ctx:ctrl().Died:Fire() -- now=100 漏网死亡
        ctx.now = 105
        ctx:ctrl():Reborn() -- 编辑器死亡规则 5 秒自动满血复活（OnReborn → 旧 Revive 满血满饥饿）
        assert.same(300, ctx:ctrl().Health)
        ctx.s:Update() -- 状态机发现引擎抢先复活，立即修正为虚弱复活
        assert.same(30, ctx:ctrl().Health)
        assert.same(5, ctx:ctrl().WalkSpeed)
        assert.same('alive', ctx.v:LifeStatus(ctx.a))
        ctx.s:Update() -- 幂等：不重复结算
        assert.same(30, ctx:ctrl().Health)
        assert.same(1, ctx:ctrl().reborns) -- 只有引擎那一次
        ctx:tick(60) -- 虚弱结束恢复全速
        assert.same(10, ctx:ctrl().WalkSpeed)
    end)

    -- 濒死/死亡期间饥饿暂停，复活后恢复推进；复活血量 10%
    it('test_hunger_pauses_while_downed_and_dead', function()
        local state = ctx.v:GetState(ctx.a)
        state.hunger = 100
        state.lastSec = math.floor(ctx.now)
        ctx:enterDowned() -- now=100 进濒死
        ctx:tick(44.9) -- 100 → 144.9：濒死 15 秒 + 死亡 29.9 秒
        assert.same(100, state.hunger) -- 全程暂停
        assert.same('dead', ctx.v:LifeStatus(ctx.a))
        ctx:tick(0.1) -- 145：虚弱复活
        assert.same(100, state.hunger) -- 高于下限不压低
        assert.same(30, ctx:ctrl().Health)
        ctx:tick(1) -- 复活后恢复推进
        assert.same(99, state.hunger)
    end)

    -- 运行时接线守卫（#128 同款源码断言）：缺一条 LifeHooks 就不接管
    it('test_server_main_wires_survival', function()
        local f = assert(io.open('server/main.lua', 'r'))
        local src = f:read('*a')
        f:close()
        assert.matches('MgrSurvival = require("server.Mgr.MgrSurvival")', src, nil, true)
        assert.matches('MgrMap.MgrSurvival.Vitals = MgrMap.MgrVitals', src, nil, true)
        assert.matches('MgrMap.MgrSurvival.FishUnit = MgrMap.MgrFishUnit', src, nil, true)
        assert.matches('MgrMap.MgrSurvival.ReelIn = MgrMap.MgrReelIn', src, nil, true)
        assert.matches('MgrMap.MgrSurvival.PlayerData = MgrMap.MgrPlayerData', src, nil, true)
        assert.matches('MgrMap.MgrSurvival.Save = MgrMap.MgrSave', src, nil, true)
        assert.matches('MgrMap.MgrVitals:SetLifeHooks(MgrMap.MgrSurvival:Hooks())', src, nil, true)
        -- 就绪批次与离开顺序：Survival 紧随 Vitals；终镜像先于 SaveLeaving 序列化
        assert.matches("'MgrAttr', 'MgrPlayer', 'MgrVitals', 'MgrModifier', 'MgrSurvival', 'MgrAbility', 'MgrFishUnit'", src, nil, true)
        assert.matches([[invoke('MgrSurvival', MgrMap.MgrSurvival, 'BeforeLeave', player)]], src, nil, true)
    end)

    -- 漏网死亡：MgrVitals 的旧兜底 Reborn 在接管期不得抢跑，30 秒由 MgrSurvival 虚弱复活
    it('test_vitals_fallback_reborn_does_not_fire_during_takeover', function()
        ctx:ctrl().Health = 0
        ctx:ctrl().Died:Fire()
        assert.is_true(ctx.v:GetState(ctx.a).dead)
        assert.same('dead', ctx.v:LifeStatus(ctx.a)) -- OnDied 通知纳入状态机
        ctx:tick(7.5) -- 超过 ReviveDelaySec+ReviveGraceSec=7：旧兜底不得抢跑
        assert.same(0, ctx:ctrl().reborns)
        ctx:tick(22.5) -- 到 30 秒：MgrSurvival 虚弱复活
        assert.same(30, ctx:ctrl().Health)
        assert.same(5, ctx:ctrl().WalkSpeed)
        assert.same(0, ctx:ctrl().reborns) -- 全程没调引擎 Reborn
        assert.is_false(ctx.v:GetState(ctx.a).dead) -- 死亡标记已清
    end)
end)

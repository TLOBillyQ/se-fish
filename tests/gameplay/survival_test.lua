-- #131 T10 生存恢复：濒死、免费虚弱复活与离线恢复（server/Mgr/MgrSurvival.lua + MgrVitals 接管）。
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
local lu = require('luaunit')
local PlayerData = require('server.Data.PlayerData')

TestSurvivalConfig = {}

function TestSurvivalConfig:test_values_match_design_doc()
    local cfg = require('common.GameCfg').Survival
    lu.assertNotNil(cfg)
    lu.assertEquals(cfg.DownedSec, 15)             -- 策划案：十五秒之内可以抢救
    lu.assertEquals(cfg.DeadSec, 30)               -- 策划案：30 秒倒计时结束虚弱复活
    lu.assertEquals(cfg.ReviveHealthPercent, 10)   -- 策划案：复活血量 10%
    lu.assertEquals(cfg.ReviveHungerPercent, 10)   -- 验收：无付费复活饥饿至少 30（300×10%）
    lu.assertEquals(cfg.WeakSec, 60)               -- 策划案：虚弱持续 1 分钟
    lu.assertEquals(cfg.WeakSpeedScale, 0.5)       -- 策划案：移动速度下降 50%
    lu.assertEquals(cfg.AdrenalineItemId, 'item171') -- 物品表 R172 肾上腺素（自救道具）
end

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
    env.oldGame = _G.game
    env.values, env.queue, env.writeFailure = {}, {}, nil -- luaunit 各用例共用同一个 self，标志必须每次复位
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
    lu.assertEquals(data.LoadState, 'ready')
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

TestSurvivalDowned = {}

function TestSurvivalDowned:setUp()
    local env = self
    self.now = 100
    self.messages = {}
    self.events = {} -- 按名缓存：服务端 Start 里连的 OnServerEvent 与测试触发的是同一个信号
    self.savedRE = package.loaded['common.REUtil']
    package.loaded['common.REUtil'] = {
        GetRE = function(_, name)
            self.messages[name] = self.messages[name] or {}
            self.events[name] = self.events[name] or {
                FireClient = function(_, player, value)
                    table.insert(env.messages[name], { player = player, value = value })
                end,
                FireAllClients = function(_, value)
                    table.insert(env.messages[name], { player = 'all', value = value })
                end,
                OnServerEvent = signal(),
            }
            return self.events[name]
        end,
        CheckRECD = function() return false end,
    }
    self.v = assert(loadfile('server/Mgr/MgrVitals.lua'))()
    self.v.Now = function() return env.now end
    self.s = assert(loadfile('server/Mgr/MgrSurvival.lua'))()
    self.s.Now = function() return env.now end
    self.s.Vitals = self.v
    self.v:SetLifeHooks(self.s:Hooks())
    self.a, self.b = newPlayer(1), newPlayer(2)
    self.v:OnPlayerAdded(self.a)
    self.v:OnPlayerAdded(self.b)
    self.s:OnPlayerAdded(self.a)
    self.s:OnPlayerAdded(self.b)
end

function TestSurvivalDowned:tearDown()
    package.loaded['common.REUtil'] = self.savedRE
end

function TestSurvivalDowned:ctrl(p) return (p or self.a).Character.Controller end

function TestSurvivalDowned:enterDowned()
    self:ctrl().Health = 50
    local ok, actual = self.v:ApplyHit(self.v:NewHit(self.b, 'fishAttack'), self.a, 100)
    lu.assertTrue(ok)
    lu.assertEquals(actual, 49)
end

function TestSurvivalDowned:test_lethal_damage_locks_one_health_and_enters_downed()
    self:enterDowned()
    lu.assertEquals(self:ctrl().Health, 1)
    lu.assertTrue(self.v:IsDowned(self.a))
    lu.assertFalse(self.v:CanAct(self.a))
    lu.assertEquals(self:ctrl().diedCount, 0) -- 锁血拦截，引擎死亡未发生
    lu.assertFalse(self.v:GetState(self.a).dead) -- 旧死亡流程未介入
    lu.assertFalse(self.v:IsDowned(self.b)) -- 不泄漏到其他玩家
end

function TestSurvivalDowned:test_downed_is_invincible_to_repeated_attacks()
    self:enterDowned()
    for _ = 1, 3 do
        lu.assertFalse(self.v:ApplyHit(self.v:NewHit(self.b, 'fishAttack'), self.a, 50))
    end
    lu.assertEquals(self:ctrl().Health, 1)
    -- 饥饿伤害同样不能越过锁血
    local state = self.v:GetState(self.a)
    state.hunger = 0
    state.lastSec = math.floor(self.now) - 1
    self.v:UpdateState(state, self.now)
    lu.assertEquals(self:ctrl().Health, 1)
end

function TestSurvivalDowned:test_downed_turns_dead_exactly_after_15_seconds()
    self:enterDowned()
    self.now = 114.9
    self.s:Update()
    lu.assertTrue(self.v:IsDowned(self.a))
    self.now = 115
    self.s:Update()
    lu.assertEquals(self.v:LifeStatus(self.a), 'dead')
    lu.assertFalse(self.v:CanAct(self.a))
    lu.assertFalse(self.v:ApplyHit(self.v:NewHit(self.b, 'fishAttack'), self.a, 50))
    lu.assertEquals(self:ctrl().Health, 1)
end

TestSurvivalRevive = {}

function TestSurvivalRevive:setUp()
    TestSurvivalDowned.setUp(self)
end

function TestSurvivalRevive:tearDown()
    TestSurvivalDowned.tearDown(self)
end

function TestSurvivalRevive:ctrl(p) return (p or self.a).Character.Controller end

function TestSurvivalRevive:enterDead()
    TestSurvivalDowned.enterDowned(self) -- now=100 进濒死
    self.now = 115
    self.s:Update()
    lu.assertEquals(self.v:LifeStatus(self.a), 'dead')
end

function TestSurvivalRevive:test_dead_revives_in_place_after_30_seconds_with_weak()
    self:enterDead()
    self.v:GetState(self.a).hunger = 10 -- 复活前饥饿低于下限
    self.now = 144.9
    self.s:Update()
    lu.assertEquals(self.v:LifeStatus(self.a), 'dead')
    self.now = 145
    self.s:Update()
    lu.assertEquals(self.v:LifeStatus(self.a), 'alive')
    lu.assertTrue(self.v:CanAct(self.a))
    lu.assertEquals(self:ctrl().Health, 30) -- 10% × 300
    lu.assertEquals(self.v:GetState(self.a).hunger, 30) -- 饥饿至少 10% × 300
    lu.assertEquals(self:ctrl().WalkSpeed, 5) -- 虚弱半速（10 × 0.5）
    lu.assertEquals(self:ctrl().reborns, 0) -- 原地复活：不走引擎 Reborn
    lu.assertEquals(self.a.Character.Position, { x = 1, y = 0, z = 0 }) -- 位置不动
end

function TestSurvivalRevive:test_revive_keeps_higher_hunger()
    self:enterDead()
    self.v:GetState(self.a).hunger = 200
    self.now = 145
    self.s:Update()
    lu.assertEquals(self.v:GetState(self.a).hunger, 200)
    lu.assertEquals(self:ctrl().Health, 30)
end

function TestSurvivalRevive:test_weak_recovers_full_speed_exactly_after_60_seconds()
    self:enterDead()
    self.now = 145
    self.s:Update()
    lu.assertEquals(self:ctrl().WalkSpeed, 5)
    self.now = 204.9
    self.s:Update()
    lu.assertEquals(self:ctrl().WalkSpeed, 5)
    self.now = 205
    self.s:Update()
    lu.assertEquals(self:ctrl().WalkSpeed, 10)
end

TestSurvivalTakeover = {}

function TestSurvivalTakeover:setUp()
    TestSurvivalDowned.setUp(self)
end

function TestSurvivalTakeover:tearDown()
    TestSurvivalDowned.tearDown(self)
end

function TestSurvivalTakeover:ctrl(p) return (p or self.a).Character.Controller end

-- 接线守卫（#128 同款源码断言）：运行时依赖在 server/main.lua 里完成，缺一条 LifeHooks 就不接管
function TestSurvivalTakeover:test_server_main_wires_survival()
    local f = assert(io.open('server/main.lua', 'r'))
    local src = f:read('*a')
    f:close()
    lu.assertStrContains(src, 'MgrSurvival = require("server.Mgr.MgrSurvival")')
    lu.assertStrContains(src, 'MgrMap.MgrSurvival.Vitals = MgrMap.MgrVitals')
    lu.assertStrContains(src, 'MgrMap.MgrSurvival.FishUnit = MgrMap.MgrFishUnit')
    lu.assertStrContains(src, 'MgrMap.MgrSurvival.ReelIn = MgrMap.MgrReelIn')
    lu.assertStrContains(src, 'MgrMap.MgrSurvival.PlayerData = MgrMap.MgrPlayerData')
    lu.assertStrContains(src, 'MgrMap.MgrSurvival.Save = MgrMap.MgrSave')
    lu.assertStrContains(src, 'MgrMap.MgrVitals:SetLifeHooks(MgrMap.MgrSurvival:Hooks())')
    -- 就绪批次与离开顺序：Survival 紧随 Vitals；终镜像先于 SaveLeaving 序列化
    lu.assertStrContains(src, "'MgrPlayer', 'MgrVitals', 'MgrSurvival', 'MgrAbility', 'MgrFishUnit'")
    lu.assertStrContains(src, [[invoke('MgrSurvival', MgrMap.MgrSurvival, 'BeforeLeave', player)]])
end

function TestSurvivalTakeover:tick(seconds, step)
    step = step or 0.5
    local target = self.now + seconds
    while self.now + 1e-9 < target do
        self.now = math.min(target, self.now + step)
        self.v:Update()
        self.s:Update()
    end
end

function TestSurvivalTakeover:test_hunger_pauses_while_downed_and_dead()
    local state = self.v:GetState(self.a)
    state.hunger = 100
    state.lastSec = math.floor(self.now)
    TestSurvivalDowned.enterDowned(self) -- now=100 进濒死
    self:tick(44.9) -- 100 → 144.9：濒死 15 秒 + 死亡 29.9 秒
    lu.assertEquals(state.hunger, 100) -- 全程暂停
    lu.assertEquals(self.v:LifeStatus(self.a), 'dead')
    self:tick(0.1) -- 145：虚弱复活
    lu.assertEquals(state.hunger, 100) -- 高于下限不压低
    lu.assertEquals(self:ctrl().Health, 30)
    self:tick(1) -- 复活后恢复推进
    lu.assertEquals(state.hunger, 99)
end

function TestSurvivalTakeover:test_vitals_fallback_reborn_does_not_fire_during_takeover()
    -- 漏网死亡：外部直接把 Controller 打死（绕过 OnBeforeDamage 的引擎路径）
    self:ctrl().Health = 0
    self:ctrl().Died:Fire()
    lu.assertTrue(self.v:GetState(self.a).dead)
    lu.assertEquals(self.v:LifeStatus(self.a), 'dead') -- OnDied 通知纳入状态机
    self:tick(7.5) -- 超过 ReviveDelaySec+ReviveGraceSec=7：旧兜底不得抢跑
    lu.assertEquals(self:ctrl().reborns, 0)
    self:tick(22.5) -- 到 30 秒：MgrSurvival 虚弱复活
    lu.assertEquals(self:ctrl().Health, 30)
    lu.assertEquals(self:ctrl().WalkSpeed, 5)
    lu.assertEquals(self:ctrl().reborns, 0) -- 全程没调引擎 Reborn
    lu.assertFalse(self.v:GetState(self.a).dead) -- 死亡标记已清
end

function TestSurvivalTakeover:test_engine_revive_during_dead_is_corrected_once()
    self:ctrl().Health = 0
    self:ctrl().Died:Fire() -- now=100 漏网死亡
    self.now = 105
    self:ctrl():Reborn() -- 编辑器死亡规则 5 秒自动满血复活（OnReborn → 旧 Revive 满血满饥饿）
    lu.assertEquals(self:ctrl().Health, 300)
    self.s:Update() -- 状态机发现引擎抢先复活，立即修正为虚弱复活
    lu.assertEquals(self:ctrl().Health, 30)
    lu.assertEquals(self:ctrl().WalkSpeed, 5)
    lu.assertEquals(self.v:LifeStatus(self.a), 'alive')
    self.s:Update() -- 幂等：不重复结算
    lu.assertEquals(self:ctrl().Health, 30)
    lu.assertEquals(self:ctrl().reborns, 1) -- 只有引擎那一次
    self:tick(60) -- 虚弱结束恢复全速
    lu.assertEquals(self:ctrl().WalkSpeed, 10)
end

TestSurvivalFishing = {}

function TestSurvivalFishing:setUp()
    TestSurvivalDowned.setUp(self)
    self.fishCalls = {}
    self.reelCalls = {}
    self.s.FishUnit = { OnDied = function(_, p) self.fishCalls[#self.fishCalls + 1] = p end }
    self.s.ReelIn = { Interrupt = function(_, p) self.reelCalls[#self.reelCalls + 1] = p end }
end

function TestSurvivalFishing:ctrl(p) return (p or self.a).Character.Controller end

function TestSurvivalFishing:tearDown()
    TestSurvivalDowned.tearDown(self)
end

function TestSurvivalFishing:test_entering_downed_releases_fish_and_breaks_fishing()
    TestSurvivalDowned.enterDowned(self)
    -- 释放举鱼 + 断抛竿会话复用 MgrFishUnit:OnDied；收线会话走 MgrReelIn:Interrupt
    lu.assertEquals(self.fishCalls, { self.a })
    lu.assertEquals(self.reelCalls, { self.a })
end

TestSurvivalRescue = {}

function TestSurvivalRescue:setUp()
    TestSurvivalDowned.setUp(self)
end

function TestSurvivalRescue:tearDown()
    TestSurvivalDowned.tearDown(self)
end

function TestSurvivalRescue:ctrl(p) return (p or self.a).Character.Controller end

function TestSurvivalRescue:test_rescue_restores_ten_percent_health_without_weak()
    TestSurvivalDowned.enterDowned(self) -- now=100 进濒死
    self.now = 105
    lu.assertTrue(self.v:Rescue(self.a, self.b))
    lu.assertEquals(self:ctrl().Health, 30) -- 10% × 300
    lu.assertEquals(self.a.attrs.Health, 30) -- 客户端 HUD 属性同步
    lu.assertEquals(self.v:LifeStatus(self.a), 'alive')
    lu.assertTrue(self.v:CanAct(self.a))
    lu.assertEquals(self:ctrl().WalkSpeed, 10) -- 抢救不带虚弱（虚弱只属于死亡后的虚弱复活）
    lu.assertEquals(self:ctrl().diedCount, 0)
    local sent = self.messages.SurvivalState
    lu.assertEquals(sent[#sent].value.phase, 'alive') -- 客户端撤掉濒死蒙版
end

function TestSurvivalRescue:test_rescue_only_works_while_downed()
    lu.assertFalse(self.v:Rescue(self.a, self.b)) -- 活动中不能被「救」成 30 血
    lu.assertEquals(self:ctrl().Health, 300)
    TestSurvivalDowned.enterDowned(self)
    self.now = 115
    self.s:Update() -- 15 秒到转死亡，抢救窗口关闭
    lu.assertFalse(self.v:Rescue(self.a, self.b))
    lu.assertEquals(self.v:LifeStatus(self.a), 'dead')
    lu.assertEquals(self:ctrl().Health, 1)
end

function TestSurvivalRescue:test_rescue_does_not_touch_other_players()
    TestSurvivalDowned.enterDowned(self)
    lu.assertFalse(self.v:Rescue(self.b, self.a)) -- b 没濒死
    lu.assertEquals(self:ctrl(self.b).Health, 300)
    lu.assertTrue(self.v:IsDowned(self.a))
    lu.assertEquals(self:ctrl().Health, 1)
end

function TestSurvivalRescue:test_hunger_resumes_from_rescue_second_without_catching_up()
    local state = self.v:GetState(self.a)
    state.hunger = 100
    state.lastSec = math.floor(self.now)
    TestSurvivalDowned.enterDowned(self)
    self.now = 108
    self.v:Update()
    lu.assertEquals(state.hunger, 100) -- 濒死期间暂停
    lu.assertTrue(self.v:Rescue(self.a, self.b))
    self.now = 109
    self.v:Update()
    lu.assertEquals(state.hunger, 99) -- 只走救起后的 1 秒，不补濒死期间的 8 秒
end

function TestSurvivalRescue:test_old_deadline_never_applies_to_rescued_or_redowned_player()
    TestSurvivalDowned.enterDowned(self) -- 100 进濒死，旧截止点 115
    self.now = 105
    lu.assertTrue(self.v:Rescue(self.a, self.b))
    self.now = 110
    lu.assertTrue(self.v:ApplyHit(self.v:NewHit(self.b, 'fishAttack'), self.a, 100)) -- 30 血再次致命
    lu.assertTrue(self.v:IsDowned(self.a))
    self.now = 115 -- 第一次濒死的旧截止点：新一轮濒死不能被旧计时结束
    self.s:Update()
    lu.assertTrue(self.v:IsDowned(self.a))
    self.now = 124.9
    self.s:Update()
    lu.assertTrue(self.v:IsDowned(self.a))
    self.now = 125 -- 新一轮从 110 起算满 15 秒
    self.s:Update()
    lu.assertEquals(self.v:LifeStatus(self.a), 'dead')
end

TestSurvivalAdrenaline = {}

function TestSurvivalAdrenaline:setUp()
    TestSurvivalDowned.setUp(self)
    attachSave(self)
    self.data = joinData(self, self.a)
    local env = self
    self.s.Save = self.save
    self.s.PlayerData = { GetDataInst = function(_, p) return p == env.a and env.data or nil end }
    self.s:Start() -- 连上 SurvivalAction 上行事件
end

function TestSurvivalAdrenaline:tearDown()
    _G.game = self.oldGame
    TestSurvivalDowned.tearDown(self)
end

function TestSurvivalAdrenaline:ctrl(p) return (p or self.a).Character.Controller end

function TestSurvivalAdrenaline:give(n)
    for _ = 1, n do lu.assertTrue(self.data:GrantItem('item171', 1)) end
end

function TestSurvivalAdrenaline:use(seq)
    self.events.SurvivalAction.OnServerEvent:Fire(self.a, { action = 'UseAdrenaline', seq = seq })
end

function TestSurvivalAdrenaline:result()
    local sent = self.messages.SurvivalResult
    return sent[#sent].value
end

function TestSurvivalAdrenaline:test_use_consumes_one_item_and_rescues_only_after_persist()
    self:give(2)
    TestSurvivalDowned.enterDowned(self) -- now=100
    self:use(1)
    -- 持久成功前不生效：血仍锁 1，物品仍在，倒计时仍是濒死
    lu.assertTrue(self.v:IsDowned(self.a))
    lu.assertEquals(self:ctrl().Health, 1)
    lu.assertEquals(rawCount(self.data, 'item171'), 2) -- 在飞期间读档屏障关闭，直接数容器
    self:drain()
    lu.assertEquals(self.data:ItemCount('item171'), 1) -- 恰好扣 1 件
    lu.assertEquals(self.v:LifeStatus(self.a), 'alive')
    lu.assertEquals(self:ctrl().Health, 30) -- 恢复 10% × 300
    lu.assertEquals(self:ctrl().WalkSpeed, 10) -- 自救不带虚弱
    lu.assertTrue(self:result().ok)
    local operations = self.data:Serialize().meta.operations
    lu.assertEquals(#operations, 1)
    lu.assertEquals(operations[1].kind, 'survival:adrenaline') -- 落进 #123 操作日志
end

function TestSurvivalAdrenaline:test_without_item_opens_platform_purchase_seam_and_changes_nothing()
    local opened = {}
    self.s.Platform = { OpenAdrenalineShop = function(_, p) opened[#opened + 1] = p end }
    TestSurvivalDowned.enterDowned(self)
    self:use(1)
    self:drain()
    lu.assertEquals(opened, { self.a }) -- T26 平台购买入口接缝
    lu.assertFalse(self:result().ok)
    lu.assertEquals(self:result().reason, 'no-adrenaline')
    lu.assertTrue(self.v:IsDowned(self.a))
    lu.assertEquals(self:ctrl().Health, 1)
    lu.assertEquals(#self.data:Serialize().meta.operations, 0) -- 没建操作、没落账
    self.s.Platform = nil -- 接缝缺席（T26 未接）：只回包不报错
    self:use(2)
    lu.assertEquals(self:result().reason, 'no-adrenaline')
end

function TestSurvivalAdrenaline:test_concurrent_clicks_consume_exactly_one()
    self:give(2)
    TestSurvivalDowned.enterDowned(self)
    self:use(1)
    self:use(2) -- 第一次落账未确认时的并发点击
    lu.assertEquals(self:result().reason, 'busy')
    self:drain()
    self:use(3) -- 已救起后的迟到点击
    self:drain()
    lu.assertEquals(self:result().reason, 'not-downed')
    lu.assertEquals(self.data:ItemCount('item171'), 1)
    lu.assertEquals(#self.data:Serialize().meta.operations, 1)
end

function TestSurvivalAdrenaline:test_same_request_replay_never_charges_or_rescues_twice()
    self:give(2)
    TestSurvivalDowned.enterDowned(self)
    self:use(1)
    self:drain()
    self.now = 110
    lu.assertTrue(self.v:ApplyHit(self.v:NewHit(self.b, 'fishAttack'), self.a, 100)) -- 30 血再次致命
    lu.assertTrue(self.v:IsDowned(self.a))
    self:use(1) -- 同一请求号重放：只回放记录，不再扣物、不再救起
    self:drain()
    lu.assertEquals(self:result().reason, 'replay')
    lu.assertEquals(self.data:ItemCount('item171'), 1)
    lu.assertTrue(self.v:IsDowned(self.a))
    lu.assertEquals(self:ctrl().Health, 1)
    self:use(2) -- 新请求号才是新的一次自救
    self:drain()
    lu.assertEquals(self.data:ItemCount('item171'), 0)
    lu.assertEquals(self.v:LifeStatus(self.a), 'alive')
    lu.assertEquals(self:ctrl().Health, 30)
end

function TestSurvivalAdrenaline:test_only_downed_players_can_use_and_the_item_is_kept()
    self:give(1)
    self:use(1) -- 活动中
    self:drain()
    lu.assertEquals(self:result().reason, 'not-downed')
    TestSurvivalDowned.enterDowned(self)
    self.now = 115
    self.s:Update() -- 15 秒到转死亡
    self:use(2)
    self:drain()
    lu.assertEquals(self:result().reason, 'not-downed')
    lu.assertEquals(self.data:ItemCount('item171'), 1)
    lu.assertEquals(self.v:LifeStatus(self.a), 'dead')
end

function TestSurvivalAdrenaline:test_downed_countdown_waits_for_the_in_flight_adrenaline()
    self:give(1)
    TestSurvivalDowned.enterDowned(self) -- 100 进濒死，截止点 115
    self:use(1)
    self.now = 116 -- 落账未回，截止点已过
    self.s:Update()
    lu.assertTrue(self.v:IsDowned(self.a)) -- 已付出的自救不能被倒计时抢先转死亡而白扣物品
    self:drain()
    lu.assertEquals(self.v:LifeStatus(self.a), 'alive')
    lu.assertEquals(self.data:ItemCount('item171'), 0)
    lu.assertEquals(self:ctrl().Health, 30)
end

function TestSurvivalAdrenaline:test_teammate_rescue_cannot_race_the_in_flight_adrenaline()
    self:give(1)
    TestSurvivalDowned.enterDowned(self)
    self:use(1)
    lu.assertFalse(self.v:Rescue(self.a, self.b)) -- 自救结算进行中队友抢救让位，否则物品白扣
    self:drain()
    lu.assertEquals(self:ctrl().Health, 30)
    lu.assertEquals(self.data:ItemCount('item171'), 0)
end

function TestSurvivalAdrenaline:test_old_callback_cannot_touch_the_state_of_a_rejoined_player()
    self:give(1)
    TestSurvivalDowned.enterDowned(self)
    self:use(1)
    local old = self.s:GetState(self.a)
    self.s:OnPlayerRemoving(self.a)
    self.s:OnPlayerAdded(self.a) -- 重进：全新的活动状态
    local new = self.s:GetState(self.a)
    lu.assertNotIs(new, old)
    self:drain() -- 旧请求的落账回调此刻到达
    -- 存档里带着濒死标记，重进后的新状态在等离线恢复落账；旧回调既不能替它救起也不能留在飞标记
    lu.assertEquals(new.phase, 'dead')
    lu.assertNil(new.adrenalineFlying)
    lu.assertEquals(self:ctrl().Health, 1) -- 旧回调没有对新状态执行救起
end

function TestSurvivalAdrenaline:test_rejected_settlement_leaves_no_flight_marker_or_side_effects()
    -- 预检看到有物品但结算时扣不到（内存与草稿不一致的防御分支）：拒绝、无副作用、不留在飞标记
    self.data.ItemCount = function() return 1 end
    TestSurvivalDowned.enterDowned(self)
    self:use(1)
    lu.assertEquals(self:result().reason, 'no-adrenaline')
    lu.assertNil(self.s:GetState(self.a).adrenalineFlying)
    lu.assertTrue(self.v:IsDowned(self.a))
    lu.assertEquals(#self.data:Serialize().meta.operations, 0)
    self.now = 115 -- 标记没残留：倒计时照常转死亡
    self.s:Update()
    lu.assertEquals(self.v:LifeStatus(self.a), 'dead')
end

function TestSurvivalAdrenaline:test_persist_failure_keeps_item_and_does_not_rescue()
    self:give(1)
    TestSurvivalDowned.enterDowned(self)
    self.writeFailure = true
    self:use(1)
    for _ = 1, 6 do -- 写档重试耗尽后关闭会话，回调收到失败
        self.save:Update()
        self:drain()
    end
    lu.assertFalse(self:result().ok)
    lu.assertEquals(rawCount(self.data, 'item171'), 1) -- 物品仍在
    lu.assertNil(self.s:GetState(self.a).adrenalineFlying)
    lu.assertEquals(self:ctrl().Health, 1)
    lu.assertTrue(self.v:IsDowned(self.a)) -- 失败不救起
end

TestSurvivalHelp = {}

function TestSurvivalHelp:setUp()
    TestSurvivalDowned.setUp(self)
    self.c = newPlayer(3)
    self.c.Character.Position = { x = 100, y = 0, z = 0 } -- 远在 30 米外
    self.v:OnPlayerAdded(self.c)
    self.s:OnPlayerAdded(self.c)
    self.s:Start()
end

function TestSurvivalHelp:tearDown()
    TestSurvivalDowned.tearDown(self)
end

function TestSurvivalHelp:ctrl(p) return (p or self.a).Character.Controller end

function TestSurvivalHelp:call()
    self.events.SurvivalAction.OnServerEvent:Fire(self.a, { action = 'CallHelp' })
end

function TestSurvivalHelp:helpFor(player)
    local out = {}
    for _, message in ipairs(self.messages.SurvivalHelp or {}) do
        if message.player == player then out[#out + 1] = message.value end
    end
    return out
end

function TestSurvivalHelp:test_call_help_reaches_only_nearby_teammates_while_downed()
    self:call() -- 活动中呼救无效
    lu.assertEquals(#(self.messages.SurvivalHelp or {}), 0)
    TestSurvivalDowned.enterDowned(self)
    self:call()
    local heard = self:helpFor(self.b)
    lu.assertEquals(#heard, 1) -- b 在 30 米内
    lu.assertEquals(heard[1].name, 'p1')
    lu.assertEquals(heard[1].text, require('common.GameCfg').Survival.HelpCries[1])
    lu.assertEquals(#self:helpFor(self.c), 0) -- c 在 30 米外
    lu.assertEquals(#self:helpFor(self.a), 0) -- 不回给自己
end

function TestSurvivalHelp:test_call_help_is_rate_limited_and_cycles_the_cries()
    local cries = require('common.GameCfg').Survival.HelpCries
    TestSurvivalDowned.enterDowned(self)
    self:call()
    self.now = 100.5
    self:call() -- 1 秒冷却内
    lu.assertEquals(#self:helpFor(self.b), 1)
    self.now = 101
    self:call()
    local heard = self:helpFor(self.b)
    lu.assertEquals(#heard, 2)
    lu.assertEquals(heard[2].text, cries[2])
end

TestSurvivalOffline = {}

function TestSurvivalOffline:setUp()
    TestSurvivalDowned.setUp(self)
    attachSave(self)
    self.data = joinData(self, self.a)
    local env = self
    self.s.Save = self.save
    self.s.PlayerData = { GetDataInst = function(_, p) return p == env.a and env.data or nil end }
    self.s:Start()
end

function TestSurvivalOffline:tearDown()
    _G.game = self.oldGame
    TestSurvivalDowned.tearDown(self)
end

function TestSurvivalOffline:ctrl(p) return (p or self.a).Character.Controller end

function TestSurvivalOffline:mark() return self.data.Extra.survival end

-- 退出再重进：服务端 Survival 状态随玩家清掉，存档 Extra.survival 里的离线标记是唯一凭据
function TestSurvivalOffline:rejoin()
    self.s:BeforeLeave(self.a)
    self.s:OnPlayerRemoving(self.a)
    self:ctrl().WalkSpeed = 10 -- 新会话的角色是默认速度
    self.s:OnPlayerAdded(self.a)
end

function TestSurvivalOffline:test_downed_and_dead_mark_remaining_before_leaving()
    TestSurvivalDowned.enterDowned(self) -- 100 进濒死
    self.now = 105
    self.s:BeforeLeave(self.a)
    lu.assertTrue(self:mark().dying)
    lu.assertFalse(self:mark().dead)
    lu.assertEquals(self:mark().dyingRemaining, 10)
    self.now = 115
    self.s:Update() -- 转死亡
    self.now = 120
    self.s:BeforeLeave(self.a)
    lu.assertTrue(self:mark().dead)
    lu.assertFalse(self:mark().dying)
    lu.assertEquals(self:mark().deadRemaining, 25)
end

function TestSurvivalOffline:test_rejoin_after_downed_or_dead_gives_ten_percent_health_and_weak()
    for _, phase in ipairs({ 'downed', 'dead' }) do
        self.now = 200
        TestSurvivalDowned.enterDowned(self)
        if phase == 'dead' then self.now = 215 self.s:Update() end
        self:rejoin()
        lu.assertEquals(self.v:LifeStatus(self.a), 'dead') -- 落账确认前不放行
        lu.assertEquals(self:ctrl().Health, 1)
        self:drain()
        lu.assertEquals(self.v:LifeStatus(self.a), 'alive')
        lu.assertEquals(self:ctrl().Health, 30)
        lu.assertTrue(self.v:GetState(self.a).hunger >= 30)
        lu.assertEquals(self:ctrl().WalkSpeed, 5) -- 半速虚弱
        lu.assertEquals(self.s:GetState(self.a).weakUntil, self.now + 60)
        lu.assertFalse(self:mark().dying)
        lu.assertFalse(self:mark().dead)
        lu.assertEquals(self:mark().weakRemaining, 60)
        self.now = self.now + 60
        self.s:Update() -- 收尾：清虚弱，进入下一轮
        lu.assertEquals(self:ctrl().WalkSpeed, 10)
    end
    local recover = 0
    for _, op in ipairs(self.data:Serialize().meta.operations) do
        if op.kind == 'survival:recover' then recover = recover + 1 end
    end
    lu.assertEquals(recover, 2) -- 两次重进各落一次
end

function TestSurvivalOffline:test_rejoin_with_nothing_pending_changes_nothing()
    self:rejoin()
    self:drain()
    lu.assertEquals(self.s:Phase(self.a), 'alive')
    lu.assertNil(self.s:GetState(self.a).weakUntil)
    lu.assertEquals(#self.data:Serialize().meta.operations, 0)
    lu.assertEquals(self:ctrl().Health, 300)
end

function TestSurvivalOffline:test_weak_remaining_follows_the_clock_and_survives_rejoin()
    TestSurvivalDowned.enterDowned(self)
    self.now = 130
    self.s:Update() -- 死亡
    self.now = 160
    self.s:Update() -- 30 秒到，虚弱复活，weakUntil=220
    lu.assertEquals(self.s:Phase(self.a), 'alive')
    self.now = 180
    self.s:Update()
    lu.assertEquals(self:mark().weakRemaining, 40) -- 轮询镜像
    self.now = 190
    self:rejoin() -- 退出时终镜像剩 30 秒
    lu.assertEquals(self:mark().weakRemaining, 30)
    lu.assertEquals(self.s:Phase(self.a), 'alive')
    lu.assertEquals(self:ctrl().WalkSpeed, 5)
    self.now = 219
    self.s:Update()
    lu.assertEquals(self:ctrl().WalkSpeed, 5)
    self.now = 220
    self.s:Update()
    lu.assertEquals(self:ctrl().WalkSpeed, 10)
    lu.assertEquals(self:mark().weakRemaining, 0)
end

function TestSurvivalOffline:test_respawn_keeps_weak_speed()
    TestSurvivalDowned.enterDowned(self)
    self.now = 130
    self.s:Update()
    self.now = 160
    self.s:Update()
    self:ctrl().WalkSpeed = 10 -- 重生后引擎给了默认速度
    self.a.CharacterAdded:Fire(self.a.Character)
    lu.assertEquals(self:ctrl().WalkSpeed, 5)
end

function TestSurvivalOffline:test_persist_failure_keeps_player_out_of_action()
    TestSurvivalDowned.enterDowned(self)
    self.writeFailure = true
    self:rejoin()
    for _ = 1, 6 do
        self.save:Update()
        self:drain()
    end
    lu.assertNotEquals(self.v:LifeStatus(self.a), 'alive') -- 没确认落账就不放行
    lu.assertEquals(self:ctrl().Health, 1)
end

function TestSurvivalOffline:test_old_recover_callback_cannot_touch_a_newer_state()
    TestSurvivalDowned.enterDowned(self)
    self:rejoin() -- 落账在飞
    local old = self.s:GetState(self.a)
    self.s:OnPlayerRemoving(self.a)
    self.s:OnPlayerAdded(self.a) -- 再次重进（存档标记仍是濒死）
    local new = self.s:GetState(self.a)
    lu.assertNotIs(new, old)
    self:drain()
    lu.assertNotIs(self.s:GetState(self.a), old)
    lu.assertNil(old.weakUntil) -- 旧状态没被旧回调改动
end

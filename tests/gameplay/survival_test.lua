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

TestSurvivalDowned = {}

function TestSurvivalDowned:setUp()
    local env = self
    self.now = 100
    self.messages = {}
    self.savedRE = package.loaded['common.REUtil']
    package.loaded['common.REUtil'] = {
        GetRE = function(_, name)
            self.messages[name] = self.messages[name] or {}
            return { FireClient = function(_, player, value)
                table.insert(self.messages[name], { player = player, value = value })
            end, FireAllClients = function(_, value)
                table.insert(self.messages[name], { player = 'all', value = value })
            end, OnServerEvent = signal() }
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

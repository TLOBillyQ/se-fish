-- 生存恢复状态机（#131，T10；策划案「濒死/复活」段）：活动 → 1 血濒死 15 秒 → 死亡 30 秒 →
-- 原地虚弱复活（10% 血、饥饿至少 10%、60 秒半速虚弱）。经 #128 预留的 MgrVitals LifeHooks
-- 接管致命伤害与生命状态（SetLifeHooks 装配在 server/main.lua），不改 ApplyDamage/ApplyHit 单点。
-- 濒死/死亡：锁血无敌（CanTakeDamage 拒）、拒绝普通动作（CanAct 经 LifeStatus）、暂停饥饿、
-- 断开钓鱼并释放举鱼；死亡倒计时结束虚弱复活。肾上腺素自救与离线恢复见对应小节注释。
-- 计时沿用 MgrVitals 的 Update 轮询（World:GetServerTime()），不另起 Timer。
local GameCfg = require('common.GameCfg')
local REUtil = require('common.REUtil')

local Mgr = { States = {} }

local function cfg()
    return GameCfg.Survival
end

function Mgr:Now()
    self.World = self.World or game:GetService('World')
    return self.World:GetServerTime()
end

function Mgr:GetState(player)
    return player and self.States[player.UserId]
end

function Mgr:Phase(player)
    local state = self:GetState(player)
    return state and state.phase or nil
end

local function controllerOf(player)
    local character = player and player.Character
    return character and character.Controller
end

local function healthOf(player)
    local controller = controllerOf(player)
    local ok, health = pcall(function() return controller and controller.Health end)
    return ok and tonumber(health) or nil
end

-- 状态下发（客户端蒙版，ScreenSurvival）：phase + 倒计时终点；endsAt 用服务器时刻。
function Mgr:SendState(state)
    local c = cfg()
    local payload = { phase = state.phase }
    if state.phase == 'downed' then payload.endsAt = state.downedAt + c.DownedSec
    elseif state.phase == 'dead' then payload.endsAt = state.deadAt + c.DeadSec end
    if state.weakUntil then payload.weakUntil = state.weakUntil end
    REUtil:GetRE('SurvivalState'):FireClient(state.player, payload)
end

-- 进入濒死（致命伤害被 OnBeforeDamage 拦截时）：锁 1 血、断开钓鱼、释放举鱼、通知客户端。
-- 断开放鱼复用 MgrFishUnit:OnDied（放下举鱼 + 打断抛竿会话）；收线会话由 MgrReelIn:Interrupt 断开。
function Mgr:EnterDowned(state, vitalState)
    state.phase = 'downed'
    state.downedAt = self:Now()
    if self.Vitals then self.Vitals:SetControllerHealth(vitalState, 1) end
    if self.FishUnit and self.FishUnit.OnDied then
        local ok, err = pcall(self.FishUnit.OnDied, self.FishUnit, state.player)
        if not ok then print('[MgrSurvival] 濒死放鱼失败', state.player.UserId, tostring(err)) end
    end
    if self.ReelIn and self.ReelIn.Interrupt then
        local ok, err = pcall(self.ReelIn.Interrupt, self.ReelIn, state.player)
        if not ok then print('[MgrSurvival] 濒死断线失败', state.player.UserId, tostring(err)) end
    end
    print('[MgrSurvival] 濒死', state.player.UserId)
    self:SendState(state)
end

-- #128 生命接缝：状态查询 / 锁血 / 致命拦截 / 抢救 / 漏网死亡通知。
function Mgr:Hooks()
    return {
        LifeStatus = function(vitalState)
            local state = self.States[vitalState.player.UserId]
            return state and state.phase or nil
        end,
        CanTakeDamage = function(vitalState)
            local state = self.States[vitalState.player.UserId]
            if not state then return not vitalState.dead end
            return state.phase == 'alive'
        end,
        OnBeforeDamage = function(vitalState, amount)
            local state = self.States[vitalState.player.UserId]
            if not state or state.phase ~= 'alive' then return false end
            local health = healthOf(vitalState.player)
            if not health or health - amount > 0 then return false end
            self:EnterDowned(state, vitalState)
            return true
        end,
    }
end

-- 虚弱（策划案：虚弱复活后 1 分钟移速减半）：进入时记当前 WalkSpeed 为基准并乘 WeakSpeedScale，
-- 结束恢复基准值。与加速技能（speed_add 锚点）叠加时的恢复顺序是已知边界，见 issue 评论。
function Mgr:ApplyWeak(state, seconds)
    state.weakUntil = self:Now() + seconds
    local controller = controllerOf(state.player)
    if not controller then return end
    local ok, speed = pcall(function() return controller.WalkSpeed end)
    if ok and type(speed) == 'number' then
        state.baseSpeed = speed
        pcall(function() controller.WalkSpeed = speed * cfg().WeakSpeedScale end)
    end
end

function Mgr:ClearWeak(state)
    local controller = controllerOf(state.player)
    if controller and state.baseSpeed then
        pcall(function() controller.WalkSpeed = state.baseSpeed end)
    end
    state.weakUntil, state.baseSpeed = nil, nil
end

-- 虚弱复活（死亡倒计时结束或引擎抢先复活的修正）：10% 血、饥饿至少 10%、60 秒虚弱；
-- 原地结算，不调引擎 Reborn（位置不动）。结算经 MgrVitals:ApplyRevive 单点落地。
function Mgr:WeakRevive(state)
    if state.phase ~= 'dead' then return end
    local vitalState = self.Vitals and self.Vitals:GetState(state.player)
    if not vitalState then return end
    local c = cfg()
    local health = math.floor(GameCfg.Vitals.MaxHealth * c.ReviveHealthPercent / 100)
    local minHunger = math.floor(GameCfg.Vitals.MaxHunger * c.ReviveHungerPercent / 100)
    if not self.Vitals:ApplyRevive(vitalState, health, minHunger) then return end
    state.phase = 'alive'
    state.deadAt = nil
    self:ApplyWeak(state, c.WeakSec)
    print('[MgrSurvival] 虚弱复活', state.player.UserId, 'health=' .. tostring(health),
        'hunger=' .. tostring(vitalState.hunger))
    self:SendState(state)
end

function Mgr:OnPlayerAdded(player)
    if not player or self.States[player.UserId] then return end
    self.States[player.UserId] = { player = player, phase = 'alive' }
end

function Mgr:OnPlayerRemoving(player)
    local state = self:GetState(player)
    if not state or state.player ~= player then return end
    self.States[player.UserId] = nil
end

-- 状态推进：濒死倒计时到转死亡；死亡倒计时到按虚弱复活结算一次。
-- 引擎抢先复活修正：仅当真死过（MgrVitals state.dead=true 的漏网死亡）且血量回正才提前结算——
-- 锁血路径下 Controller 停在 1 血，health>0 不等于复活，不能误判。
function Mgr:Update()
    local now = self:Now()
    local c = cfg()
    for _, state in pairs(self.States) do
        if state.phase == 'downed' and now - state.downedAt >= c.DownedSec then
            state.phase = 'dead'
            state.downedAt = nil
            state.deadAt = now
            print('[MgrSurvival] 死亡', state.player.UserId)
            self:SendState(state)
        elseif state.phase == 'dead' then
            local vitalState = self.Vitals and self.Vitals:GetState(state.player)
            local health = vitalState and vitalState.dead and healthOf(state.player) or nil
            if (health and health > 0) or now - state.deadAt >= c.DeadSec then
                self:WeakRevive(state)
            end
        elseif state.phase == 'alive' and state.weakUntil and now >= state.weakUntil then
            self:ClearWeak(state)
            self:SendState(state)
        end
    end
end

function Mgr:Start()
    self.World = game:GetService('World')
end

return Mgr

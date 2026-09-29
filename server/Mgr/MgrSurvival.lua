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

function Mgr:OnPlayerAdded(player)
    if not player or self.States[player.UserId] then return end
    self.States[player.UserId] = { player = player, phase = 'alive' }
end

function Mgr:OnPlayerRemoving(player)
    local state = self:GetState(player)
    if not state or state.player ~= player then return end
    self.States[player.UserId] = nil
end

-- 状态推进：濒死倒计时到转死亡。
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
        end
    end
end

function Mgr:Start()
    self.World = game:GetService('World')
end

return Mgr

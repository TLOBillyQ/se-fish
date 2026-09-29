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
    state.episode = (state.episode or 0) + 1
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

-- 抢救（濒死中被救起；队友抢救接缝与肾上腺素自救共用）：恢复 ReviveHealthPercent% 血量回到活动，
-- 不带虚弱（虚弱只属于死亡后的虚弱复活）。饥饿沿用——濒死期间已暂停，ApplyRevive 让它从这一秒
-- 重新计时，不补濒死期间的秒数。结算经 MgrVitals:ApplyRevive 单点，phase 守卫保证每轮濒死只结算一次。
function Mgr:RescueDowned(state, vitalState)
    if not state or state.phase ~= 'downed' or not self.Vitals then return false end
    local health = math.floor(GameCfg.Vitals.MaxHealth * cfg().ReviveHealthPercent / 100)
    if not self.Vitals:ApplyRevive(vitalState, health) then return false end
    state.phase = 'alive'
    state.downedAt = nil
    print('[MgrSurvival] 抢救', state.player.UserId, 'health=' .. tostring(health))
    self:SendState(state)
    return true
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
        Rescue = function(vitalState)
            local state = self.States[vitalState.player.UserId]
            if state and state.adrenalineFlying then return false end -- 自救落账中让位
            return self:RescueDowned(self.States[vitalState.player.UserId], vitalState)
        end,
        -- 漏网死亡（绕过致命拦截的引擎死亡）：纳入状态机按死亡处理。断开放鱼由
        -- MgrFishUnit / MgrReelIn 既有的 Controller.Died 订阅负责，这里不重复。
        OnDied = function(vitalState)
            local state = self.States[vitalState.player.UserId]
            if not state or state.phase == 'dead' then return end
            state.phase = 'dead'
            state.downedAt = nil
            state.deadAt = self:Now()
            state.engineDeath = true
            print('[MgrSurvival] 漏网死亡纳入状态机', state.player.UserId)
            self:SendState(state)
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
    state.engineDeath = nil
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
-- 漏网死亡（engineDeath）额外盯引擎抢先复活：Vitals 死亡标记已消（旧 Revive 跑过）或血量回正，
-- 立即修正为虚弱复活——原生自动复活一旦发生，不能留下满血。锁血路径血停在 1，不看血量。
function Mgr:Update()
    local now = self:Now()
    local c = cfg()
    for _, state in pairs(self.States) do
        if state.phase == 'downed' and not state.adrenalineFlying and now - state.downedAt >= c.DownedSec then
            state.phase = 'dead'
            state.downedAt = nil
            state.deadAt = now
            print('[MgrSurvival] 死亡', state.player.UserId)
            self:SendState(state)
        elseif state.phase == 'dead' then
            local due = now - state.deadAt >= c.DeadSec
            local engineRevived = false
            if state.engineDeath and self.Vitals then
                local vitalState = self.Vitals:GetState(state.player)
                local health = healthOf(state.player)
                engineRevived = vitalState ~= nil and vitalState.dead == false
                    or (health ~= nil and health > 1)
            end
            if due or engineRevived then self:WeakRevive(state) end
        elseif state.phase == 'alive' and state.weakUntil and now >= state.weakUntil then
            self:ClearWeak(state)
            self:SendState(state)
        end
    end
end

function Mgr:Reply(player, payload)
    REUtil:GetRE('SurvivalResult'):FireClient(player, payload)
end

-- 肾上腺素自救（策划案：消耗一个恢复 10%；没有则拉起平台购买入口）。
-- 预检（濒死 / 无在飞 / 有物品）→ #123 持久操作：物品扣除与操作日志同键落账，落账确认后才救起。
-- 在飞期间濒死倒计时冻结、队友抢救让位，避免「已扣物品却被转死亡 / 抢先救起」；
-- 回调按 state 对象与 episode 双重核对，旧请求不会落到重进或再次濒死的新状态上。
function Mgr:UseAdrenaline(player, payload)
    local seq = type(payload) == 'table' and payload.seq or nil
    local function fail(reason)
        self:Reply(player, { seq = seq, ok = false, reason = reason })
        return false
    end
    local state = self:GetState(player)
    if not state or state.phase ~= 'downed' then return fail('not-downed') end
    if state.adrenalineFlying then return fail('busy') end
    local data = self.PlayerData and self.PlayerData:GetDataInst(player)
    if not data or not self.Save then return fail('unavailable') end
    local itemId = cfg().AdrenalineItemId
    if data:ItemCount(itemId) < 1 then
        if self.Platform and self.Platform.OpenAdrenalineShop then
            local ok, err = pcall(self.Platform.OpenAdrenalineShop, self.Platform, player)
            if not ok then print('[MgrSurvival] 平台购买入口失败', player.UserId, tostring(err)) end
        end
        return fail('no-adrenaline')
    end
    local operation, mode = self.Save:ResolveRequest(player, data, 'survival:adrenaline', seq)
    if not operation then return fail(mode) end
    if mode == 'replay' then return fail('replay') end -- 同请求号只回放记录，不再扣物、不再救起
    local episode = state.episode
    state.adrenalineFlying = true
    local accepted, why = self.Save:Execute(player, data, operation, function(draft)
        if not draft:ConsumeItem(itemId) then return nil, 'no-adrenaline' end
        return { ok = true, seq = seq }
    end, function(written, result)
        if self.States[player.UserId] ~= state then return end -- 已离开 / 重进：旧回调作废
        state.adrenalineFlying = nil
        if not written then return fail(tostring(result)) end
        local vitalState = self.Vitals and self.Vitals:GetState(player)
        if state.phase ~= 'downed' or state.episode ~= episode or not vitalState
            or not self:RescueDowned(state, vitalState) then
            return fail('not-downed')
        end
        if self.PlayerData and self.PlayerData.SendItemBar then self.PlayerData:SendItemBar(player) end
        print('[MgrSurvival] 肾上腺素自救', player.UserId, operation.id)
        self:Reply(player, { seq = seq, ok = true })
    end)
    if not accepted then
        state.adrenalineFlying = nil
        return fail(why or 'pending')
    end
    return true
end

local function distance(a, b)
    local ok, d = pcall(function()
        local dx, dy, dz = a.x - b.x, (a.y or 0) - (b.y or 0), (a.z or 0) - (b.z or 0)
        return math.sqrt(dx * dx + dy * dy + dz * dz)
    end)
    return ok and d or math.huge
end

-- 呼救（策划案 30 米内队友能看到呼救气泡）：只在濒死时有效，1 秒冷却，台词循环。
function Mgr:CallHelp(player)
    local state = self:GetState(player)
    if not state or state.phase ~= 'downed' then return false end
    local c, now = cfg(), self:Now()
    if state.lastHelp and now - state.lastHelp < c.HelpCooldownSec then return false end
    state.lastHelp = now
    state.helpIndex = (state.helpIndex or 0) % #c.HelpCries + 1
    local origin = player.Character and player.Character.Position
    local re = REUtil:GetRE('SurvivalHelp')
    for _, other in pairs(self.States) do
        if other ~= state and other.player.Character
            and distance(origin, other.player.Character.Position) <= c.HelpRadius then
            re:FireClient(other.player, { userId = player.UserId, name = player.Name,
                text = c.HelpCries[state.helpIndex] })
        end
    end
    return true
end

function Mgr:OnAction(player, payload)
    if type(payload) ~= 'table' then return end
    if payload.action == 'UseAdrenaline' then
        if REUtil:CheckRECD(player, 'SurvivalAction', 0.2) then return end
        self:UseAdrenaline(player, payload)
    elseif payload.action == 'CallHelp' then
        self:CallHelp(player)
    end
end

function Mgr:Start()
    local ok, world = pcall(function() return game:GetService('World') end)
    if ok then self.World = world end
    REUtil:GetRE('SurvivalAction').OnServerEvent:Connect(function(player, payload)
        self:OnAction(player, payload)
    end)
end

return Mgr

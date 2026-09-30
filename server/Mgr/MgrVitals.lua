-- 血量、饥饿、死亡与复活（#53，#40 规格）：服务端唯一权威，配置见 GameCfg.Vitals。
-- 血量宿主是角色的 Controller（M0 台账 §4）；饥饿是本管理器的单局内存态。两者写进玩家属性
-- Health / MaxHealth / Hunger / MaxHunger 给客户端 HUD 读：血量随 HealthChanged 写，饥饿只在整秒变化时写。
-- 饥饿按 World:GetServerTime() 的整秒推进（common/Vitals.lua），不按帧累加。
-- 所有掉血只走 ApplyDamage(player, amount) 单点（饥饿伤害与 GM 调低血量是当前调用方，日后濒死锁血在此拦截）。
-- 死亡：订阅 Controller.Died，Update 里轮询 Health ≤ 0 兜底，两条路只记一次；死亡期间饥饿不推进、不掉血、不能吃。
-- 复活：引擎复活不换角色、不触发 CharacterAdded，所以复活判定选「Update 轮询同一 Controller 的 Health 从 0 回到 > 0」，
-- 另接 Controller.OnReborn 作同一入口的第二来源；复活时两项回满 300。超过 ReviveDelaySec + ReviveGraceSec
-- 仍没复活，兜底调一次 Controller:Reborn()。死亡时松手放鱼、断开收线由 MgrFishUnit / MgrReelIn 既有的 Died 订阅负责。
local GameCfg = require('common.GameCfg')
local Vitals = require('common.Vitals')
local DamageNotice = require('common.DamageNotice')

local Mgr = { States = {} }

local function cfg()
    return GameCfg.Vitals
end

local function isInt(n)
    return type(n) == 'number' and n == math.floor(n)
end

function Mgr:Now()
    self.World = self.World or game:GetService('World')
    return self.World:GetServerTime()
end

function Mgr:GetState(player)
    return player and self.States[player.UserId]
end

function Mgr:IsDead(player)
    local state = self:GetState(player)
    return state ~= nil and state.dead
end

function Mgr:PlayerFromUnit(unit)
    for _, state in pairs(self.States) do
        if state.player == unit or state.player.Character == unit then return state.player end
    end
end

-- #128 统一伤害：每个服务端判定段由 NewHit 颁发一次命中身份；同一身份对同一目标只结算一次，
-- 同帧重复碰撞 / 回调重放不会双扣。DOT 的下一 tick 或下一次范围判定必须重新 NewHit。
-- source 接受玩家、角色或权威鱼记录；玩家来源在这里落成服务端登记身份，不能由客户端自报。
function Mgr:NewHit(source, category)
    self.NextHitId = (self.NextHitId or 0) + 1
    return { id = self.NextHitId, source = source, category = category,
        sourcePlayer = self:PlayerFromUnit(source), targets = {} }
end

function Mgr:ResolveHitSource(hit)
    return type(hit) == 'table' and hit.sourcePlayer or nil
end

local function validAmount(amount)
    return type(amount) == 'number' and amount > 0 and amount == amount
        and amount ~= math.huge and amount ~= -math.huge
end

-- T08 接缝：后续濒死模块在这里接管致命伤害、濒死状态与抢救；本单默认语义保持原死亡流程。
function Mgr:SetLifeHooks(hooks)
    self.LifeHooks = type(hooks) == 'table' and hooks or nil
end

function Mgr:LifeStatus(player)
    local state = self:GetState(player)
    if not state then return nil end
    local hooks = self.LifeHooks
    if hooks and type(hooks.LifeStatus) == 'function' then
        local ok, status = pcall(hooks.LifeStatus, state)
        if ok and type(status) == 'string' then return status end
    end
    return state.dead and 'dead' or 'alive'
end

function Mgr:IsDowned(player)
    return self:LifeStatus(player) == 'downed'
end

function Mgr:CanAct(player)
    if self:LifeStatus(player) ~= 'alive' then return false end
    -- #139 行动闸门（麻痹统一封锁攻击/投掷/钓鱼/进食，main.lua 注入「非麻痹」）；
    -- 闸门故障 fail-open 并记日志，与生命接缝同策略（不把全服锁死）。
    if self.ActGuard then
        local ok, allowed = pcall(self.ActGuard, player)
        if not ok then print('[MgrVitals] 行动闸门失败', player.UserId, tostring(allowed)) return true end
        if not allowed then return false end
    end
    return true
end

-- #139 按玩家的血量上限：变大药水成长经 MaxHealthProvider（main.lua 注入 MgrAbility:MaxHealth），
-- 缺省回落全局 cfg().MaxHealth（无注入时保持 #53 旧行为）。
function Mgr:MaxHealthOf(player)
    if self.MaxHealthProvider then
        local ok, max = pcall(self.MaxHealthProvider, player)
        if ok and type(max) == 'number' and max >= 1 then return max end
        if not ok then print('[MgrVitals] 血量上限查询失败', player and player.UserId, tostring(max)) end
    end
    return cfg().MaxHealth
end

function Mgr:CanTakeDamage(player, hit)
    local state = self:GetState(player)
    if not state then return false end
    local hooks = self.LifeHooks
    if hooks and type(hooks.CanTakeDamage) == 'function' then
        local ok, allowed = pcall(hooks.CanTakeDamage, state, hit)
        if ok then return allowed == true end
    end
    return not state.dead
end

function Mgr:Rescue(player, rescuer)
    local state = self:GetState(player)
    local hooks = self.LifeHooks
    if not state or not self:IsDowned(player) or not hooks or type(hooks.Rescue) ~= 'function' then return false end
    local ok, result = pcall(hooks.Rescue, state, rescuer)
    if not ok then print('[MgrVitals] 抢救接缝失败', player.UserId, tostring(result)) return false end
    if result == true then self:WriteHealth(state) end
    return result == true
end

local function controllerOf(state)
    local character = state.player.Character
    return character and character.Controller
end

local function healthOf(state)
    local controller = controllerOf(state)
    local ok, health = pcall(function() return controller and controller.Health end)
    return ok and tonumber(health) or nil
end

-- #139 血量上限刷新口（喝变大药水后由 MgrAbility:ApplyGrowth 调一次）：
-- 提上限不自动回血；降上限（理论路径）把当前血夹到新上限；HUD 属性始终写玩家上限。
function Mgr:RefreshMaxHealth(player)
    local state = self:GetState(player)
    if not state then return false end
    local maxHealth = self:MaxHealthOf(player)
    local controller = controllerOf(state)
    if controller then
        pcall(function()
            controller.MaxHealth = maxHealth
            local health = controller.Health
            if type(health) == 'number' and health > maxHealth then controller.Health = maxHealth end
        end)
        state.baseline = healthOf(state)
    end
    self:WriteHealth(state)
    return true, maxHealth
end

local function isBadNumber(v)
    return type(v) ~= 'number' or v ~= v or v == math.huge or v == -math.huge
end

local function readPosition(unit)
    if not unit then return nil end
    local ok, pos = pcall(function() return unit.Position end)
    if ok and pos and not isBadNumber(pos.x) and not isBadNumber(pos.y) and not isBadNumber(pos.z) then
        return pos
    end
end

local function characterHeight(state)
    local ok, size = pcall(function() return state.player.Character.Size end)
    if ok and size and type(size.y) == 'number' and size.y > 0 and size.y < math.huge then
        return size.y
    end
end

local function write(player, key, value)
    pcall(function() player:SetAttribute(key, value) end)
end

function Mgr:WriteHealth(state)
    local health = healthOf(state)
    if health then write(state.player, 'Health', math.max(0, math.floor(health))) end
    write(state.player, 'MaxHealth', self:MaxHealthOf(state.player)) -- #139 按玩家上限
end

function Mgr:WriteHunger(state)
    write(state.player, 'Hunger', state.hunger)
    write(state.player, 'MaxHunger', cfg().MaxHunger)
end

-- 跳字观察（#118）：以 state.baseline 为结算前血量，HealthChanged / Died 两路统一走这里。
-- 引擎致命一击可能只发 Died 不发 HealthChanged（鱼侧实测），所以 OnDied 也要记录；
-- 同一次伤害两路都到时，第一路记录后同步基线，第二路差额为 0 自然去重。
function Mgr:RecordHealth(state)
    if not state.bound then return end
    local health = healthOf(state)
    if not health then return end
    local previous = state.baseline
    local position = readPosition(state.player.Character)
    if position then
        state.LastPosition = { x = position.x, y = position.y, z = position.z }
    else
        position = state.LastPosition
    end
    state.baseline = health
    if not previous or health >= previous or not position then return end
    local payload = DamageNotice.FromHealth(state.player.UserId, previous, health, position,
        nil, 'player', characterHeight(state))
    if payload then
        print('[MgrVitals] 实际扣血', state.player.UserId, previous, health, payload.amount)
        local sent, err = pcall(self.DamagePublisher or DamageNotice.Publish, payload)
        if not sent then print('[MgrVitals] 伤害通知失败', state.player.UserId, tostring(err)) end
    end
end

function Mgr:SetControllerHealth(state, value)
    local controller = controllerOf(state)
    if not controller then return false end
    local ok = pcall(function() controller.Health = value end)
    state.baseline = healthOf(state)
    self:WriteHealth(state)
    return ok
end

function Mgr:Unbind(state)
    for key, link in pairs(state.controllerLinks or {}) do
        link:Disconnect()
        state.controllerLinks[key] = nil
    end
end

-- 绑定角色的 Controller：设上限，第一次绑定时回满，订阅血量变化 / 死亡 / 复活
function Mgr:Bind(state, character)
    self:Unbind(state)
    local controller = character and character.Controller
    if not controller then return end
    state.controllerLinks = {}
    pcall(function()
        controller.MaxHealth = self:MaxHealthOf(state.player) -- #139 按玩家上限
        if not state.bound then controller.Health = self:MaxHealthOf(state.player) end
    end)
    state.bound = true
    state.baseline = healthOf(state)
    local links = state.controllerLinks
    if controller.HealthChanged then
        links.HealthChanged = controller.HealthChanged:Connect(function()
            self:RecordHealth(state)
            self:WriteHealth(state)
        end)
    end
    if controller.Died then
        links.Died = controller.Died:Connect(function() self:OnDied(state) end)
    end
    if controller.OnReborn then
        links.OnReborn = controller.OnReborn:Connect(function() self:Revive(state, 'OnReborn') end)
    end
    self:WriteHealth(state)
end

function Mgr:OnDied(state)
    if state.dead or self.States[state.player.UserId] ~= state then return end
    self:RecordHealth(state)
    state.dead = true
    state.deadAt = self:Now()
    state.rebornCalled = false
    self:WriteHealth(state)
    print('[MgrVitals] 死亡', state.player.UserId, 'hunger=' .. tostring(state.hunger))
    -- T10（#131）：漏网死亡通知生命接缝（MgrSurvival 纳入状态机）；接缝内部只做状态记录，不复活
    local hooks = self.LifeHooks
    if hooks and type(hooks.OnDied) == 'function' then
        local ok, err = pcall(hooks.OnDied, state)
        if not ok then print('[MgrVitals] 死亡通知接缝失败', state.player.UserId, tostring(err)) end
    end
end

-- 复活的唯一入口（轮询 / OnReborn 两个来源，幂等）：两项回满，饥饿从这一秒重新计时
function Mgr:Revive(state, source)
    if not state.dead or self.States[state.player.UserId] ~= state then return end
    state.dead = false
    state.deadAt = nil
    state.hunger = cfg().MaxHunger
    state.lastSec = math.floor(self:Now())
    self:SetControllerHealth(state, self:MaxHealthOf(state.player)) -- #139 按玩家上限回满
    self:WriteHunger(state)
    print('[MgrVitals] 复活', state.player.UserId, source, 'health=' .. tostring(healthOf(state)),
        'hunger=' .. tostring(state.hunger))
end

-- T10（#131）复活结算入口：MgrSurvival 状态机的复活/离线恢复都经这里落地。清死亡标记
-- （漏网死亡时 state.dead 可能为 true）、血量设为 health、饥饿至少 minHunger 并从这一秒重新计时。
-- 与 Revive（引擎路径，满血满饥饿）语义分开；不影响 ApplyDamage/ApplyHit 单点。
function Mgr:ApplyRevive(state, health, minHunger)
    if not state or self.States[state.player.UserId] ~= state then return false end
    if not isInt(health) or health < 1 or health > self:MaxHealthOf(state.player) then return false end -- #139 按玩家上限
    state.dead, state.deadAt, state.rebornCalled = false, nil, false
    if isInt(minHunger) and state.hunger < minHunger then state.hunger = minHunger end
    state.lastSec = math.floor(self:Now())
    self:SetControllerHealth(state, health)
    self:WriteHunger(state)
    return true
end

-- 掉血单点；扣成功返回 true 与实际扣血量（过量伤害只计剩余生命）
function Mgr:ApplyDamage(player, amount, hit)
    local state = self:GetState(player)
    if not state or not self:CanTakeDamage(player, hit) or not validAmount(amount) then return false end
    local controller = controllerOf(state)
    if not controller then return false end
    local before = healthOf(state)
    local intercepted = false
    local hooks = self.LifeHooks
    if hooks and type(hooks.OnBeforeDamage) == 'function' then
        local ok, handled = pcall(hooks.OnBeforeDamage, state, amount, hit)
        if ok then intercepted = handled == true
        else print('[MgrVitals] 生命接缝失败', player.UserId, tostring(handled)) end
    end
    local applied, applyErr = true, nil
    if not intercepted then
        applied, applyErr = pcall(function() controller:TakeDamage(amount) end)
        if not applied then print('[MgrVitals] 扣血失败', player.UserId, tostring(applyErr)) end
    end
    local health = healthOf(state)
    self:WriteHealth(state)
    if health and health <= 0 and not intercepted then self:OnDied(state) end
    if not applied or not before or not health or health >= before then return false end
    return true, before - health
end

-- 目标可以是玩家或角色；结算的是角色 Controller，仇恨键始终用 Player 身份。
-- 返回已结算、实际扣血量；同一命中重复 / 目标死亡 / 非法数值一律 false 且不通知。
function Mgr:ApplyHit(hit, target, amount)
    if type(hit) ~= 'table' or type(hit.id) ~= 'number' or type(hit.targets) ~= 'table' then return false end
    if not validAmount(amount) then return false end
    local carrier
    if self.FishCarrier and type(self.FishCarrier.ResolveCarrier) == 'function' then
        local ok, found = pcall(self.FishCarrier.ResolveCarrier, self.FishCarrier, target)
        if ok then carrier = found else print('[MgrVitals] 鱼目标解析失败', tostring(found)) end
    end
    if carrier then
        -- 去重键：活鱼记录用鱼 Id，裸受击体用载体身体 UnitId，最后兜底表地址
        local key
        if target and target.Carrier == carrier and target.Id then
            key = 'fish:' .. tostring(target.Id)
        elseif carrier.Body and carrier.Body.UnitId then
            key = 'carrier:' .. tostring(carrier.Body.UnitId)
        else
            key = tostring(carrier)
        end
        if hit.targets[key] then return false end
        local ok, actual = self.FishCarrier:Damage(carrier, amount, hit)
        if ok then hit.targets[key] = true end
        return ok, actual
    end
    local player = target
    if not self:GetState(player) then player = self:PlayerFromUnit(target) or player end
    if not self:GetState(player) or hit.targets[player.UserId] then return false end
    local sourceState = hit.sourcePlayer and self:GetState(hit.sourcePlayer)
    if hit.sourcePlayer and (not sourceState or sourceState.player ~= hit.sourcePlayer) then return false end
    if self.DamageFilter then
        local filterOk, allowed = pcall(self.DamageFilter, hit, player)
        if not filterOk then print('[MgrVitals] 伤害过滤失败', player.UserId, tostring(allowed)) end
        if not filterOk or allowed ~= true then return false end
    end
    local ok, actual = self:ApplyDamage(player, amount, hit)
    if ok then hit.targets[player.UserId] = true end
    return ok, actual
end

function Mgr:CanEat(player, itemId)
    local state = self:GetState(player)
    local definition = type(itemId) == 'string' and GameCfg.Items.Definitions[itemId]
    return state ~= nil and self:CanAct(player) and definition ~= nil and type(definition.EatPercent) == 'number'
end

-- 吃一件：血量与饥饿各恢复「食用恢复百分比 × 上限」，不超上限；库存由调用方先扣。
-- #128：负食用（如核废料桶 item126）是伤害，走 ApplyDamage 统一入口，类别 eat，不绕过濒死锁血。
-- #137：烤制倍率（烧烤取出时的曲线值）同乘恢复量——烤熟 1.5 倍恢复 +50%，下降段打折；
-- 非法倍率（nil/0/负数/NaN/Inf）按未烤处理。
function Mgr:Eat(player, itemId, cookRate)
    if not self:CanEat(player, itemId) then return false end
    local state = self:GetState(player)
    local c = cfg()
    local rate = 1
    if type(cookRate) == 'number' and cookRate > 0 and cookRate == cookRate and cookRate < math.huge then
        rate = cookRate
    end
    local percent = GameCfg.Items.Definitions[itemId].EatPercent * rate
    state.hunger = Vitals.Restore(state.hunger, c.MaxHunger, percent)
    self:WriteHunger(state)
    if percent < 0 then
        local damage = math.floor(self:MaxHealthOf(player) * -percent / 100) -- #139 按玩家上限
        if damage > 0 then
            self:ApplyDamage(player, damage, self:NewHit(player, 'eat'))
        end
    else
        local health = healthOf(state)
        if health then self:SetControllerHealth(state, Vitals.Restore(math.floor(health), self:MaxHealthOf(player), percent)) end -- #139 按玩家上限
    end
    print('[MgrVitals] 吃', player.UserId, itemId, 'health=' .. tostring(healthOf(state)),
        'hunger=' .. tostring(state.hunger))
    return true
end

-- GM（#53）：设饥饿度，饥饿从这一秒重新计时
function Mgr:SetHunger(player, value)
    local state = self:GetState(player)
    if not state or state.dead or not isInt(value) or value < 0 or value > cfg().MaxHunger then return false end
    state.hunger = value
    state.lastSec = math.floor(self:Now())
    self:WriteHunger(state)
    return true
end

-- GM（#53）：设血量；调低走 ApplyDamage 单点（设 0 即走权威死亡），调高直接写 Controller
function Mgr:SetHealth(player, value)
    local state = self:GetState(player)
    if not state or state.dead or not isInt(value) or value < 0 or value > self:MaxHealthOf(player) then return false end -- #139 按玩家上限
    local health = healthOf(state)
    if not health then return false end
    if value < health then return self:ApplyDamage(player, health - value, self:NewHit(nil, 'gm')) end
    if value > health then return self:SetControllerHealth(state, value) end
    return true
end

function Mgr:OnPlayerAdded(player)
    if not player or self.States[player.UserId] then return end
    local state = { player = player, hunger = cfg().MaxHunger, lastSec = math.floor(self:Now()), dead = false }
    self.States[player.UserId] = state
    self:WriteHunger(state)
    if player.CharacterAdded then
        state.added = player.CharacterAdded:Connect(function(character) self:Bind(state, character) end)
    end
    self:Bind(state, player.Character)
end

function Mgr:OnPlayerRemoving(player)
    local state = self:GetState(player)
    if not state then return end
    self:Unbind(state)
    if state.added then state.added:Disconnect() end
    self.States[player.UserId] = nil
end

function Mgr:UpdateState(state, now)
    -- T10（#131）：生命接缝接管（濒死/死亡）时让位——暂停饥饿推进、不做复活轮询与兜底 Reborn，
    -- 复活结算归 MgrSurvival（虚弱复活）。无接缝或未接管时保持 #53 原流程。
    local hooks = self.LifeHooks
    if hooks and type(hooks.LifeStatus) == 'function' then
        local ok, status = pcall(hooks.LifeStatus, state)
        if ok and (status == 'downed' or status == 'dead') then return end
    end
    local c = cfg()
    local health = healthOf(state)
    if state.dead then
        if health and health > 0 then
            self:Revive(state, 'poll')
        elseif not state.rebornCalled and now - state.deadAt >= c.ReviveDelaySec + c.ReviveGraceSec then
            state.rebornCalled = true
            local controller = controllerOf(state)
            local ok, err = pcall(function() controller:Reborn() end)
            print('[MgrVitals] 引擎未按时复活，兜底 Reborn', state.player.UserId, ok, err)
        end
        return
    end
    if health and health <= 0 and state.bound then
        self:OnDied(state)
        return
    end
    local sec = math.floor(now)
    if sec <= state.lastSec then return end
    local hunger, damage = Vitals.Advance(state.hunger, sec - state.lastSec, c)
    state.lastSec = sec
    if hunger ~= state.hunger then
        state.hunger = hunger
        self:WriteHunger(state)
    end
    if damage > 0 then
        print('[MgrVitals] 饥饿掉血', state.player.UserId, damage, 'health=' .. tostring(health))
        self:ApplyDamage(state.player, damage, self:NewHit(nil, 'hunger'))
    end
end

function Mgr:Update()
    local now = self:Now()
    for _, state in pairs(self.States) do
        self:UpdateState(state, now)
    end
end

function Mgr:Start()
    self.World = game:GetService('World')
end

return Mgr

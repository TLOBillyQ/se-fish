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

local function controllerOf(state)
    local character = state.player.Character
    return character and character.Controller
end

local function healthOf(state)
    local controller = controllerOf(state)
    local ok, health = pcall(function() return controller and controller.Health end)
    return ok and tonumber(health) or nil
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
    write(state.player, 'MaxHealth', cfg().MaxHealth)
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
        controller.MaxHealth = cfg().MaxHealth
        if not state.bound then controller.Health = cfg().MaxHealth end
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
end

-- 复活的唯一入口（轮询 / OnReborn 两个来源，幂等）：两项回满，饥饿从这一秒重新计时
function Mgr:Revive(state, source)
    if not state.dead or self.States[state.player.UserId] ~= state then return end
    state.dead = false
    state.deadAt = nil
    state.hunger = cfg().MaxHunger
    state.lastSec = math.floor(self:Now())
    self:SetControllerHealth(state, cfg().MaxHealth)
    self:WriteHunger(state)
    print('[MgrVitals] 复活', state.player.UserId, source, 'health=' .. tostring(healthOf(state)),
        'hunger=' .. tostring(state.hunger))
end

-- 掉血单点；扣成功返回 true
function Mgr:ApplyDamage(player, amount)
    local state = self:GetState(player)
    if not state or state.dead or type(amount) ~= 'number' or amount <= 0 then return false end
    local controller = controllerOf(state)
    if not controller then return false end
    local ok = pcall(function() controller:TakeDamage(amount) end)
    self:WriteHealth(state)
    local health = healthOf(state)
    if health and health <= 0 then self:OnDied(state) end
    return ok
end

function Mgr:CanEat(player, itemId)
    local state = self:GetState(player)
    local definition = type(itemId) == 'string' and GameCfg.Items.Definitions[itemId]
    return state ~= nil and not state.dead and definition ~= nil and type(definition.EatPercent) == 'number'
end

-- 吃一件：血量与饥饿各恢复「食用恢复百分比 × 上限」，不超上限；库存由调用方先扣
function Mgr:Eat(player, itemId)
    if not self:CanEat(player, itemId) then return false end
    local state = self:GetState(player)
    local c = cfg()
    local percent = GameCfg.Items.Definitions[itemId].EatPercent
    state.hunger = Vitals.Restore(state.hunger, c.MaxHunger, percent)
    self:WriteHunger(state)
    local health = healthOf(state)
    if health then self:SetControllerHealth(state, Vitals.Restore(math.floor(health), c.MaxHealth, percent)) end
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
    if not state or state.dead or not isInt(value) or value < 0 or value > cfg().MaxHealth then return false end
    local health = healthOf(state)
    if not health then return false end
    if value < health then return self:ApplyDamage(player, health - value) end
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
        self:ApplyDamage(state.player, damage)
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

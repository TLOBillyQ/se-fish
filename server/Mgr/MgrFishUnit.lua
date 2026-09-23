-- 活鱼单位管理器（#37 起）：上岸结算交来的活鱼在这里登记，M2 在此之上接抓举 / 放下 / 逃脱 / 死亡。
-- 一条活鱼只记上钩时定下的鱼种与个体倍率；重量、售价随取随算（FishCatch.Weight / Price），不存快照。
-- 抓举（#41）：上岸即由服务端原生 Lift()（客户端发起无效，M0 台账 §1），只认服务端鱼本体的
-- OnLiftedBegin，回调里立刻建骨骼挂点并把鱼挂进去；举着期间不改 BodyType（引擎已切 Kinematic）。
local GameCfg = require('common.GameCfg')
local FishCatch = require('common.FishCatch')
local MgrFishCarrier = require('server.Mgr.MgrFishCarrier')

local Mgr = { Fish = {}, NextId = 0, Held = {}, Links = {} }

Mgr.State = { AwaitLift = 'awaitLift', Held = 'held' }

local function cfg()
    return GameCfg.FishUnit
end

function Mgr:Now()
    local world = self.World or game:GetService('World')
    return world:GetServerTime()
end

local function isBadNumber(v)
    return type(v) ~= 'number' or v ~= v or v == math.huge or v == -math.huge
end

local function readPosition(unit)
    local ok, pos = pcall(function() return unit.Position end)
    if ok and pos and not isBadNumber(pos.x) and not isBadNumber(pos.y) and not isBadNumber(pos.z) then
        return pos
    end
end

local function noCollide(unit, other)
    if unit and other and unit ~= other and unit.AddNoCollisionPairWithUnit then
        pcall(unit.AddNoCollisionPairWithUnit, unit, other)
    end
end

-- 碰撞隔离：鱼本体不和任何玩家、别的鱼本体与受击体互推（M18-2 漂移 / 顶飞 / NaN 的来源）
function Mgr:Isolate(fish)
    local body = fish.Carrier.Body
    for _, player in ipairs(self:Players()) do noCollide(body, player.Character) end
    for _, other in pairs(self.Fish) do
        if other ~= fish and other.Carrier then
            noCollide(body, other.Carrier.Body)
            noCollide(body, other.Carrier.Receiver)
            noCollide(other.Carrier.Body, fish.Carrier.Receiver)
        end
    end
end

function Mgr:IsolateCharacter(character)
    for _, fish in pairs(self.Fish) do
        if fish.Carrier then noCollide(fish.Carrier.Body, character) end
    end
end

function Mgr:Players()
    local service = game:GetService('Players')
    return service and service:GetPlayers() or {}
end

-- 在 position 生成一条归属 player 的待举起活鱼并立即发起抓举；载体建不出来返回 nil 与原因
function Mgr:SpawnLanded(player, catch, position)
    local species = catch and GameCfg.Fish[catch.fishId]
    if not player or not species or type(catch.mult) ~= 'number' then return nil, 'bad-catch' end
    local carrier, err = MgrFishCarrier:Spawn({
        Position = position,
        FishId = catch.fishId,
        MaxHealth = species.Health,
        ModelId = species.Model,
        Player = player,
        GravityEnabled = false,
        LinearDamping = cfg().LinearDamping,
        AngularDamping = cfg().AngularDamping,
    })
    if not carrier then return nil, err end
    self.NextId = self.NextId + 1
    local fish = { Id = self.NextId, Owner = player, FishId = catch.fishId, Mult = catch.mult,
        Carrier = carrier, State = Mgr.State.AwaitLift, Anchor = position, LiftAttempts = 0 }
    self.Fish[fish.Id] = fish
    -- 受击体是带 Controller 的 EggyUnit，不关掉会被 Lift() 当成身前目标抓走
    if carrier.Receiver and carrier.Receiver.Controller then
        pcall(function() carrier.Receiver.Controller.LiftedEnabled = false end)
    end
    self:Isolate(fish)
    local body = carrier.Body
    if body and body.OnLiftedBegin then
        fish.Conns = {
            body.OnLiftedBegin:Connect(function(liftunit) self:OnLifted(fish, liftunit) end),
        }
    end
    self:RequestLift(fish)
    return fish
end

-- 发起一次服务端抓举：主人手上有鱼、鱼已不是待抓、次数用完都不调（Lift 不幂等）
function Mgr:RequestLift(fish)
    local owner = fish.Owner
    if fish.State ~= Mgr.State.AwaitLift or self.Held[owner.UserId]
        or fish.LiftAttempts >= cfg().LiftAttempts then return false end
    local controller = owner.Character and owner.Character.Controller
    if not controller then return false end
    fish.LiftAttempts = fish.LiftAttempts + 1
    fish.LiftAt = self:Now()
    local ok, err = pcall(function() controller:Lift() end)
    if not ok then print('[MgrFishUnit] Lift 调用失败', owner.UserId, tostring(err)) end
    return ok
end

-- 抓举者：回调带了角色就按角色找玩家；没带就认正在等抓举确认的主人
function Mgr:ResolveLifter(fish, liftunit)
    if liftunit == nil then return fish.LiftAt and fish.Owner or nil end
    if fish.Owner.Character == liftunit then return fish.Owner end
    for _, player in ipairs(self:Players()) do
        if player.Character == liftunit then return player end
    end
end

function Mgr:OnLifted(fish, liftunit)
    if self.Fish[fish.Id] ~= fish or fish.State ~= Mgr.State.AwaitLift then return end
    local holder = self:ResolveLifter(fish, liftunit)
    local character = holder and holder.Character
    if not character or self.Held[holder.UserId] then
        print('[MgrFishUnit] 抓举回调找不到空手的抓举者', fish.Id)
        return
    end
    local offset = cfg().LiftSocketOffset
    local world = self.World or game:GetService('World')
    local ok, mount = pcall(world.CreateUnit, world, 'SkeletalSocketMount', {
        Name = 'FishMount_' .. tostring(fish.Id),
        Parent = character,
        SocketName = cfg().LiftSocket,
        SocketOffset = Vector3.New(offset.x, offset.y, offset.z),
    })
    if not ok or not mount then
        print('[MgrFishUnit] 顶鱼挂点创建失败', fish.Id, tostring(mount))
        return
    end
    fish.Mount = mount
    fish.State = Mgr.State.Held
    fish.Holder = holder
    self.Held[holder.UserId] = fish
    pcall(function() fish.Carrier.Body.Parent = mount end)
    print('[MgrFishUnit] 举起', holder.UserId, fish.FishId, fish.Mult, 'fish=' .. tostring(fish.Id))
    if self.Cast then self.Cast:PushState(holder) end
end

function Mgr:GetHeld(player)
    return player and self.Held[player.UserId] or nil
end

function Mgr:HeldInfo(player)
    local fish = self:GetHeld(player)
    return fish and { fishId = fish.FishId, mult = fish.Mult } or nil
end

-- 举着鱼时不能抛竿：2 号位此时是「放下」
function Mgr:CanCast(player)
    return self:GetHeld(player) == nil
end

function Mgr:GetFish(player)
    local list = {}
    for _, fish in pairs(self.Fish) do
        if fish.Owner == player then list[#list + 1] = fish end
    end
    table.sort(list, function(a, b) return a.Id < b.Id end)
    return list
end

function Mgr:Weight(fish)
    return FishCatch.Weight(GameCfg.Fish[fish.FishId], fish.Mult)
end

function Mgr:Price(fish)
    return FishCatch.Price(GameCfg.Fish[fish.FishId], fish.Mult)
end

function Mgr:Remove(fish)
    if not fish or self.Fish[fish.Id] ~= fish then return end
    self.Fish[fish.Id] = nil
    for _, conn in ipairs(fish.Conns or {}) do conn:Disconnect() end
    fish.Conns = nil
    if fish.Holder and self.Held[fish.Holder.UserId] == fish then self.Held[fish.Holder.UserId] = nil end
    MgrFishCarrier:Despawn(fish.Carrier)
    if fish.Mount then pcall(function() fish.Mount:Destroy() end) end
    fish.Mount = nil
end

-- 待抓的鱼钉在生成点：偏离超过容差或坐标变 NaN 就拉回并清速度
function Mgr:Stabilize(fish)
    local body = fish.Carrier.Body
    local anchor = fish.Anchor
    if not body or not anchor then return end
    local pos = readPosition(body)
    local tol = cfg().AwaitDriftTolerance
    if pos and math.abs(pos.x - anchor.x) <= tol and math.abs(pos.y - anchor.y) <= tol
        and math.abs(pos.z - anchor.z) <= tol then return end
    pcall(function()
        body.Position = anchor
        body.LinearVelocity = Vector3.New(0, 0, 0)
        body.AngularVelocity = Vector3.New(0, 0, 0)
    end)
end

function Mgr:Start()
    self.World = game:GetService('World')
end

function Mgr:Stop()
    for _, link in pairs(self.Links) do link:Disconnect() end
    self.Links = {}
end

function Mgr:OnPlayerAdded(player)
    if self.Links[player.UserId] then self.Links[player.UserId]:Disconnect() end
    self.Links[player.UserId] = player.CharacterAdded:Connect(function(character)
        self:IsolateCharacter(character)
    end)
    if player.Character then self:IsolateCharacter(player.Character) end
end

-- 主人离线：还没被举起的鱼与举在他头上的鱼一并清掉，避免场上留下无主的鱼和挂点
function Mgr:OnPlayerRemoving(player)
    if self.Links[player.UserId] then
        self.Links[player.UserId]:Disconnect()
        self.Links[player.UserId] = nil
    end
    local held = self:GetHeld(player)
    if held then self:Remove(held) end
    for _, fish in ipairs(self:GetFish(player)) do
        if fish.State == Mgr.State.AwaitLift then self:Remove(fish) end
    end
end

function Mgr:Update()
    local now = self:Now()
    for _, fish in pairs(self.Fish) do
        if fish.State == Mgr.State.AwaitLift then
            self:Stabilize(fish)
            if fish.LiftAt and now - fish.LiftAt >= cfg().LiftConfirmSec then
                if not self:RequestLift(fish) and fish.LiftAttempts >= cfg().LiftAttempts and not fish.LiftGaveUp then
                    fish.LiftGaveUp = true
                    print('[MgrFishUnit] 抓举未确认，放弃重试', fish.Owner.UserId, 'fish=' .. tostring(fish.Id))
                end
            end
        end
    end
end

return Mgr

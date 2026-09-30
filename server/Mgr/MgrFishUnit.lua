-- 活鱼单位管理器（#37 起）：上岸结算交来的活鱼在这里登记，M2 在此之上接抓举 / 放下 / 逃脱 / 死亡。
-- 一条活鱼只记上钩时定下的鱼种与个体倍率；重量、售价随取随算（FishCatch.Weight / Price），不存快照。
-- 抓举（#41）：上岸即由服务端原生 Lift(鱼本体)，只认服务端鱼本体的
-- OnLiftedBegin，回调里立刻建骨骼挂点并把鱼挂进去；举着期间不改 BodyType（引擎已切 Kinematic）。
-- 放下 / 逃脱（#42）：主动放下、OnLiftedEnd、持有者死亡走同一条幂等 Release——回世界、落在面前、
-- Kinematic 朝最近水区跑；只按 (x,z) 判入水，入水即销毁、无收益。不调 Throw。
local GameCfg = require('common.GameCfg')
local FishCatch = require('common.FishCatch')
local MathWaterJudge = require('common.MathWaterJudge')
local MgrFishCarrier = require('server.Mgr.MgrFishCarrier')
-- #132 T11 原型：飞行/俯冲、叼人、首领分阶段的纯逻辑。本文件只做引擎驱动（读坐标、写位置、结算伤害）。
local FlightPath = require('common.FlightPath')
local CarryMount = require('common.CarryMount')
local BossPhase = require('common.BossPhase')
local GarBiteNotice = require('common.GarBiteNotice')

-- AbilityAPI 懒加载：MgrFishUnit 被大量单测用假 game 加载，顶层 require 会连带跑技能包
-- （包内 api.lua 加载时要 RunService:IsServer()），把无关用例拖挂。
local function abilityApi()
    return require('server.AbilityAPI')
end

local Mgr = { Fish = {}, NextId = 0, Held = {}, Links = {} }

Mgr.State = { AwaitLift = 'awaitLift', Held = 'held', Escaping = 'escaping',
    Combat = 'combat', Attacking = 'attacking', Sleeping = 'sleeping', Wild = 'wild',
    Flying = 'flying' }

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

-- #136 蟹湖节拍初始化：Release 放下与帝王蟹眩晕醒来共用，两处必须一致
-- （漏一项就会出现醒来后双击 / 冲撞 / 旋转节拍错位）。JabAt / PinchAt 从 -1 起，
-- 让放下或醒来后的首次进距立刻起手，避免与引擎时间推进错位。
local function resetCrabRhythm(fish, now, params)
    if params.ActiveSec then fish.ActiveUntil = now + params.ActiveSec end
    fish.JabAt = -1
    fish.PinchAt = -1
    fish.SpecialAt = now + (params.SpinSec or 0)
    fish.ChargeAt = now + (params.ChargeSec or 0)
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
        Carrier = carrier, State = Mgr.State.AwaitLift, Anchor = position, LiftAttempts = 0, Threat = {} }
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
        if body.OnLiftedEnd then
            fish.Conns[#fish.Conns + 1] = body.OnLiftedEnd:Connect(function() self:Release(fish, 'liftEnd') end)
        end
    end
    self:RequestLift(fish)
    return fish
end

-- #129 爆炸保底鱼：与 SpawnLanded 同款载体，但不接抓举（Wild 状态），到期即消失；
-- 归属投掷者（Owner），被打死走统一 Loot / 任务流
function Mgr:SpawnBlastFish(fishId, mult, position, owner)
    local species = GameCfg.Fish[fishId]
    if not species or type(mult) ~= 'number' or not position then return nil, 'bad-fish' end
    local carrier, err = MgrFishCarrier:Spawn({
        Position = position,
        FishId = fishId,
        MaxHealth = species.Health,
        ModelId = species.Model,
        Player = owner,
        GravityEnabled = false,
        LinearDamping = cfg().LinearDamping,
        AngularDamping = cfg().AngularDamping,
    })
    if not carrier then return nil, err end
    self.NextId = self.NextId + 1
    local ttl = (GameCfg.Ability.Throw and GameCfg.Ability.Throw.FishTtlSec) or 60
    local fish = { Id = self.NextId, Owner = owner, FishId = fishId, Mult = mult,
        Carrier = carrier, State = Mgr.State.Wild, Anchor = position,
        WildUntil = self:Now() + ttl, Threat = {} }
    self.Fish[fish.Id] = fish
    -- 受击体是带 Controller 的 EggyUnit，不关掉会被 Lift() 当成身前目标抓走
    if carrier.Receiver and carrier.Receiver.Controller then
        pcall(function() carrier.Receiver.Controller.LiftedEnabled = false end)
    end
    self:Isolate(fish)
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
    -- 不依赖身前目标搜索：鱼的受击体与场景单位可能干扰搜索，明确抓取本次上岸的鱼。
    -- SE 实测 Lift 的指定目标支持 WorldUnit；仍由原生 OnLiftedBegin 确认成功。
    local ok, err = pcall(function() controller:Lift(fish.Carrier.Body) end)
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

-- 主动放下：只有持有者能放自己头上的鱼
function Mgr:Drop(player)
    local fish = self:GetHeld(player)
    return fish ~= nil and self:Release(fish, 'drop')
end

local function flatDirection(x, z)
    local length = math.sqrt(x * x + z * z)
    if length < 0.01 then return nil end
    return x / length, z / length
end

-- 离 (x,z) 最近的水区中心方向（单位向量）
local function towardWater(pos)
    local best, bx, bz
    for _, zone in ipairs(GameCfg.Water.Zones) do
        local dx, dz = zone.Center.x - pos.x, zone.Center.z - pos.z
        local d = dx * dx + dz * dz
        if not best or d < best then best, bx, bz = d, dx, dz end
    end
    if best then return flatDirection(bx, bz) end
end

-- 入水只看 (x,z)：岸上鱼的 y 高于水面（V4 实测 2.15 > SurfaceY），按 y 判会永远判不进
local function inWater(pos)
    for _, zone in ipairs(GameCfg.Water.Zones) do
        if MathWaterJudge.InZone(zone, { x = pos.x, y = zone.SurfaceY, z = pos.z }) then return zone end
    end
end

-- #139：鱼移速唯一读取点乘武器持续效果（霜冻 0.7 / 麻痹 0，MgrAbility:FishSpeedFactor）；效果口故障按 1。
function Mgr:Speed(fish)
    local species = GameCfg.Fish[fish.FishId]
    local speed = species and species.Speed or cfg().EscapeSpeed
    if self.Ability and self.Ability.FishSpeedFactor then
        local ok, factor = pcall(self.Ability.FishSpeedFactor, self.Ability, fish)
        if ok and type(factor) == 'number' and factor >= 0 and factor <= 1 then speed = speed * factor end
    end
    return speed
end

function Mgr:SetHeading(fish, x, z)
    if not x then return end
    local speed = self:Speed(fish)
    fish.Heading = { x = x, z = z }
    local ok, err = pcall(function() fish.Carrier.Body.LinearVelocity = Vector3.New(x * speed, 0, z * speed) end)
    if not ok then
        print("[MgrFishUnit] 逃跑速度写入失败", fish.Id, tostring(err))
        return false, tostring(err)
    end
    fish.AppliedSpeed = speed
    return true
end

-- 释放举着的鱼（放下 / 抓举结束 / 持有者死亡）：只处理一次，之后重复触发都是空操作
function Mgr:Release(fish, reason)
    if self.Fish[fish.Id] ~= fish or fish.State ~= Mgr.State.Held then return false end
    local holder = fish.Holder
    if holder and self.Held[holder.UserId] == fish then self.Held[holder.UserId] = nil end
    local body = fish.Carrier.Body
    local world = self.World or game:GetService('World')
    local character = holder and holder.Character
    local origin = character and readPosition(character) or readPosition(body)
    local fx, fz
    pcall(function()
        local forward = character.Rotation:GetForward()
        fx, fz = flatDirection(forward.x, forward.z)
    end)
    fx, fz = fx or 0, fz or 0
    pcall(function() body.Parent = world end)
    if fish.Mount then pcall(function() fish.Mount:Destroy() end) end
    fish.Mount = nil
    if origin then
        local c = cfg()
        pcall(function()
            body.Position = Vector3.New(origin.x + fx * c.DropOffset, origin.y + c.DropHeight, origin.z + fz * c.DropOffset)
        end)
    end
    pcall(function()
        body.BodyType = 2 -- Enums.BodyType.Kinematic：由脚本给速度驱动（V4）
        body.AngularVelocity = Vector3.New(0, 0, 0)
    end)
    local now = self:Now()
    fish.State = Mgr.State.Escaping
    fish.EscapeAt = now
    fish.EscapeBy = holder
    fish.TurnAt = now + cfg().TurnSec
    fish.RayAt = now
    local pos = readPosition(body) or origin
    local species = GameCfg.Fish[fish.FishId]
    if self:FlightProfile(fish.FishId) then
        -- #132 T11 原型：飞行鱼放下后起飞（俯冲由 UpdateFlying 驱动，空中仍可被 #128 的受击体打到）
        fish.FleeAt = now + (species.EscapeSec or 180)
        body.LinearVelocity = Vector3.New(0, 0, 0)
        if not self:StartFlight(fish, now) then
            print('[MgrFishUnit] 飞行档案或边界缺失，回落普通逃脱', fish.FishId, 'fish=' .. tostring(fish.Id))
            self:SetHeading(fish, towardWater(pos))
        end
    elseif self:BossPhaseEnabled(fish.FishId) then
        -- #132 T11 原型：分阶段首领放下后进战斗（阶段机由 UpdateCombat 分支驱动）
        fish.State = Mgr.State.Combat
        fish.FleeAt = now + (species.EscapeSec or 300)
        fish.CombatPosition = pos
        fish.CombatRotation = body.Rotation
        fish.Phase = BossPhase.New(GameCfg.Ability.BossPhase, now, pos)
        fish.PhaseAt = now
        fish.Yaw = 0
        body.LinearVelocity = Vector3.New(0, 0, 0)
    elseif species.Combat then
        fish.State = Mgr.State.Combat
        fish.FleeAt = now + species.EscapeSec
        fish.CombatPosition = pos
        fish.CombatRotation = body.Rotation
        body.LinearVelocity = Vector3.New(0, 0, 0)
        if GameCfg.FishCombat and GameCfg.FishCombat[species.Combat] then
            -- 首领近战（#88 / #134）：由 UpdateChase 在目标进入咬距时锁定朝向起咬，每口前都有完整预警
            fish.BiteAim = nil
            if species.Combat == 'shrimp' or species.Combat == 'dragon' then
                local params = GameCfg.FishCombat[species.Combat]
                fish.ActiveUntil = now + (params.ActiveSec or params.SpecialSec)
                fish.SpecialAt = now + (params.SpecialSec or 0)
                fish.Combo = 0
            elseif species.Combat == 'kingCrab' or species.Combat == 'crabBoss' then
                -- #136 蟹湖：帝王蟹活动计时；蟹老板冲撞 / 旋转 / 双击各自的节拍。
                -- 与眩晕醒来共用 resetCrabRhythm，字段清单只有一处。
                resetCrabRhythm(fish, now, GameCfg.FishCombat[species.Combat])
            elseif species.Combat == 'swordfish' or species.Combat == 'shark' then
                -- #141 树林岛精英 / 首领：准备跳跃节拍；RollSlot 供三头鲨翻滚接触去重。
                local params = GameCfg.FishCombat[species.Combat]
                fish.JumpAt = now + params.JumpIntervalSec
                fish.RollSlot = -1
            end
        elseif self.Ability then
            self.Ability:EquipFish(fish)
        end
        self:PublishCombat(fish)
    elseif pos then
        self:SetHeading(fish, towardWater(pos))
    end
    print('[MgrFishUnit] 放下', holder and holder.UserId, reason, fish.FishId, 'fish=' .. tostring(fish.Id))
    -- 新手任务「丢在岸上」事实（#52）：只认持有者主动放下且落点不在水区；抓举结束 / 死亡松手、水里放下都不算
    if reason == 'drop' and holder and self.Quest and not (pos and inWater(pos)) then
        self.NextFactId = (self.NextFactId or 0) + 1
        self.Quest:Notify('DropShore', holder, { itemId = fish.FishId,
            eventId = 'drop:' .. tostring(fish.Id) .. ':' .. tostring(self.NextFactId) })
    end
    self:EnforceEscapeCap(holder, fish)
    if self.Cast and holder then self.Cast:PushState(holder) end
    return true
end

function Mgr:Escaping()
    local list = {}
    for _, fish in pairs(self.Fish) do
        if fish.State == Mgr.State.Escaping then list[#list + 1] = fish end
    end
    table.sort(list, function(a, b)
        if a.EscapeAt ~= b.EscapeAt then return a.EscapeAt < b.EscapeAt end
        return a.Id < b.Id
    end)
    return list
end

local function trimOldest(self, list, extra, keep, why)
    for _, fish in ipairs(list) do
        if extra <= 0 then return end
        if fish ~= keep then
            print('[MgrFishUnit] 在逃超出' .. why .. '，清最旧', 'fish=' .. tostring(fish.Id))
            self:Remove(fish)
            extra = extra - 1
        end
    end
end

-- 在逃上限：先按触发者每人 ≤ PerPlayerEscapeCap，再按全局 ≤ 在线人数 × GlobalEscapePerPlayer；
-- 都从最旧的清，刚放下的那条（keep）不清。每人 1 条先清过，全局超限时触发者已没有别的旧鱼可清
function Mgr:EnforceEscapeCap(trigger, keep)
    local c = cfg()
    if trigger then
        local own = {}
        for _, fish in ipairs(self:Escaping()) do
            if fish.EscapeBy == trigger then own[#own + 1] = fish end
        end
        trimOldest(self, own, #own - c.PerPlayerEscapeCap, keep, '每人上限')
    end
    local list = self:Escaping()
    trimOldest(self, list, #list - #self:Players() * c.GlobalEscapePerPlayer, keep, '全局上限')
end

-- 探墙射线的排除表：所有玩家角色、所有鱼本体与受击体
function Mgr:RayExclusions()
    local list = {}
    for _, player in ipairs(self:Players()) do
        if player.Character then list[#list + 1] = player.Character end
    end
    for _, fish in pairs(self.Fish) do
        if fish.Carrier then
            list[#list + 1] = fish.Carrier.Body
            if fish.Carrier.Receiver then list[#list + 1] = fish.Carrier.Receiver end
        end
    end
    return list
end

-- 射线会命中 TGUnitShop 这类 TriggerUnit（V4 实测），它们和不碰撞的物体都不算墙
local function passThrough(unit)
    if not unit then return true end
    local ok, trigger = pcall(function() return unit.IsA ~= nil and unit:IsA('TriggerUnit') end)
    if ok and trigger then return true end
    local okCollide, collide = pcall(function() return unit.CanCollide end)
    return okCollide and collide == false
end

-- 前方 RayDistance 米内有实体墙返回 true；穿透物加进排除表重投，最多 RayRetries 次
function Mgr:WallAhead(fish, pos)
    local heading = fish.Heading
    if not heading or not RaycastParams then return false end
    local physics = game:GetService('PhysicsService')
    if not physics then return false end
    local distance = cfg().RayDistance
    local params = RaycastParams.New()
    local excluded = self:RayExclusions()
    for _ = 1, cfg().RayRetries do
        params.FilterDescendantsInstances = excluded
        local ok, hit = pcall(physics.Raycast, physics, Vector3.New(pos.x, pos.y, pos.z),
            Vector3.New(heading.x * distance, 0, heading.z * distance), params)
        if not ok or not hit then return false end
        if not passThrough(hit.Instance) then
            return hit.Distance == nil or hit.Distance <= distance
        end
        excluded[#excluded + 1] = hit.Instance
    end
    return false
end

-- 在逃：坐标异常就移除，(x,z) 进水即销毁；每 TurnSec 重新朝水，RayHz 探墙，撞墙左转 90°
function Mgr:UpdateEscaping(fish, now)
    local pos = readPosition(fish.Carrier.Body)
    if not pos then
        print('[MgrFishUnit] 在逃的鱼坐标异常，移除', 'fish=' .. tostring(fish.Id))
        self:Remove(fish)
        return
    end
    local zone = inWater(pos)
    if zone then
        print('[MgrFishUnit] 逃回水里', zone.Id, fish.FishId, 'fish=' .. tostring(fish.Id))
        self:Remove(fish)
        return
    end
    -- 精英逃跑时锁定直线；不走普通鱼的转向与避墙。
    -- 持续效果可在两次转向之间应用/到期，每帧按当前效果刷新直线速度。
    if fish.Heading and fish.AppliedSpeed ~= self:Speed(fish) then
        self:SetHeading(fish, fish.Heading.x, fish.Heading.z)
    end
    if fish.StraightEscape then return end
    if now >= fish.TurnAt then
        fish.TurnAt = now + cfg().TurnSec
        self:SetHeading(fish, towardWater(pos))
    end
    if now >= fish.RayAt then
        fish.RayAt = now + 1 / cfg().RayHz
        if self:WallAhead(fish, pos) then
            local h = fish.Heading
            self:SetHeading(fish, -h.z, h.x)
        end
    end
end

-- 首领追咬（#88 / #128）：目标优先取本场累计有效伤害最高的玩家，无记录时取最近目标；
-- 濒死 / 死亡 / 离线目标立即从仇恨与特殊覆盖里清掉。咬人经 MgrVitals 命中入口，不直接碰 Controller。
function Mgr:IsTargetValid(player, pos, params)
    if not player or not self.Vitals or not self.Vitals:CanTakeDamage(player) then return false end
    local character = player.Character
    local controller = character and character.Controller
    local cp = controller and controller.Health and controller.Health > 0 and readPosition(character)
    if not cp then return false end
    if params and type(params.AggroRange) == 'number' and pos then
        local dx, dz = cp.x - pos.x, cp.z - pos.z
        if dx * dx + dz * dz > params.AggroRange * params.AggroRange then return false end
    end
    return true, cp
end

function Mgr:NoteDamage(fish, player, amount)
    if not fish or self.Fish[fish.Id] ~= fish or not player
        or type(amount) ~= 'number' or amount <= 0 or amount ~= amount then return false end
    fish.Threat = fish.Threat or {}
    fish.Threat[player] = (fish.Threat[player] or 0) + amount
    return true
end

function Mgr:SetTargetOverride(fish, player)
    if not fish or self.Fish[fish.Id] ~= fish then return false end
    fish.TargetOverride = player
    return true
end

function Mgr:ChooseTarget(fish, pos, params)
    local override = fish.TargetOverride
    if override then
        local valid, cp = self:IsTargetValid(override, pos, params)
        if valid then return override, cp end
        fish.TargetOverride = nil
    end
    local target, tpos, bestThreat = nil, nil, -1
    if fish.Threat then
        for player, total in pairs(fish.Threat) do
            local valid, cp = self:IsTargetValid(player, pos, params)
            if valid then
                if total > bestThreat or (total == bestThreat and target and player.UserId < target.UserId) then
                    bestThreat, target, tpos = total, player, cp
                end
            else
                fish.Threat[player] = nil
            end
        end
    end
    if target then return target, tpos end
    local bestDistance
    for _, player in ipairs(self:Players()) do
        local valid, cp = self:IsTargetValid(player, pos, params)
        if valid then
            local d = (cp.x - pos.x) * (cp.x - pos.x) + (cp.z - pos.z) * (cp.z - pos.z)
            if not bestDistance or d < bestDistance then bestDistance, target, tpos = d, player, cp end
        end
    end
    return target, tpos
end

-- #134 头部攻击：头部区 = 以鱼身中点为圆心 BiteRange 内、与朝向夹角 < HeadHalfAngleDeg；
-- 其余（正侧面、后半圆）是后身，绕后即咬空。与中点重合时没有方向，按贴脸算进头部区。
function Mgr.InHeadZone(pos, facing, tpos, params)
    local dx, dz = tpos.x - pos.x, tpos.z - pos.z
    local d2 = dx * dx + dz * dz
    if d2 > params.BiteRange * params.BiteRange then return false end
    if d2 < 1e-4 or not facing then return true end
    local limit = math.cos(math.rad(params.HeadHalfAngleDeg or 180))
    return (dx * facing.x + dz * facing.z) / math.sqrt(d2) > limit + 1e-9
end

local function withinBite(pos, tpos, params)
    local dx, dz = tpos.x - pos.x, tpos.z - pos.z
    return dx * dx + dz * dz <= params.BiteRange * params.BiteRange
end

-- 点到线段的最短水平距离平方（#141 翻滚接触：判定玩家是否落在本帧「真实滚动段」上）。
local function segmentDistanceSq(px, pz, ax, az, bx, bz)
    local dx, dz = bx - ax, bz - az
    local lenSq = dx * dx + dz * dz
    if lenSq <= 1e-12 then
        local ex, ez = px - ax, pz - az
        return ex * ex + ez * ez
    end
    local t = ((px - ax) * dx + (pz - az) * dz) / lenSq
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local ex, ez = px - (ax + t * dx), pz - (az + t * dz)
    return ex * ex + ez * ez
end

-- 预警广播（common/GarBiteNotice）；推送失败只记日志，不打断追咬。测试可替换本方法取载荷。
function Mgr:PublishBite(payload)
    GarBiteNotice.Publish(payload)
end

local function publishBite(self, payload)
    local ok, err = pcall(self.PublishBite, self, payload)
    if not ok then print('[MgrFishUnit] 首领咬预警推送失败', payload.kind, 'fish=' .. tostring(payload.fishId), tostring(err)) end
end

-- 朝向：服务端以 fish.Facing（水平单位向量）为准，并写 body.Rotation 让头朝向在各端可见
function Mgr:Face(fish, fx, fz, params)
    if not fx then return end
    fish.Facing = { x = fx, z = fz }
    if not Quaternion then return end
    local yaw = math.atan(fx, fz) + ((params and params.ModelYawOffset) or 0)
    local ok, err = pcall(function() fish.Carrier.Body.Rotation = Quaternion.FromEulerAngles(0, yaw, 0) end)
    if not ok then print('[MgrFishUnit] 首领转向失败', 'fish=' .. tostring(fish.Id), tostring(err)) end
end

-- 收起当前预警（咬出 / 咬空 / 取消 / 鱼没了）；无预警时空操作
function Mgr:EndBite(fish, reason)
    if not fish.BiteAim then return end
    fish.BiteAim = nil
    publishBite(self, GarBiteNotice.Clear(fish.Id, reason))
end

-- 锁定朝向起咬：朝向对准目标后不再转，BiteCooldownSec 后结算
function Mgr:LockBite(fish, target, pos, tpos, now, params)
    local fx, fz = flatDirection(tpos.x - pos.x, tpos.z - pos.z)
    if fx then self:Face(fish, fx, fz, params) end
    fish.BiteAim = { Target = target, StrikeAt = now + params.BiteCooldownSec }
    local facing = fish.Facing or { x = 0, z = 1 }
    publishBite(self, GarBiteNotice.Lock(fish.Id, pos, facing.x, facing.z, params.BiteRange,
        params.HeadHalfAngleDeg, params.BiteCooldownSec))
    print('[MgrFishUnit] 首领起咬', fish.FishId, 'target=' .. tostring(target.UserId),
        string.format('facing=%.2f,%.2f', facing.x, facing.z), 'fish=' .. tostring(fish.Id))
end

function Mgr:UpdateChase(fish, now, pos, params)
    local species = GameCfg.Fish[fish.FishId]
    local body = fish.Carrier.Body
    local aim = fish.BiteAim
    if aim then
        local valid, apos = self:IsTargetValid(aim.Target, pos, params)
        if not valid or not withinBite(pos, apos, params) then
            -- 预警中目标濒死 / 离线 / 走出咬距：取消本口，下面重新选目标
            self:EndBite(fish, 'cancel')
        else
            pcall(function() body.LinearVelocity = Vector3.New(0, 0, 0) end)
            if now < aim.StrikeAt then return end
            if Mgr.InHeadZone(pos, fish.Facing, apos, params) then
                self:EndBite(fish, 'bite')
                local hit = self.Vitals:NewHit(fish, 'fishAttack')
                self.Vitals:ApplyHit(hit, aim.Target, species.Attack)
                print('[MgrFishUnit] 首领追咬', fish.FishId, species.Attack, 'fish=' .. tostring(fish.Id))
            else
                self:EndBite(fish, 'miss')
                print('[MgrFishUnit] 首领咬空（绕后）', fish.FishId, 'target=' .. tostring(aim.Target.UserId),
                    'fish=' .. tostring(fish.Id))
            end
        end
    end
    local target, tpos = self:ChooseTarget(fish, pos, params)
    if not target then
        pcall(function() body.LinearVelocity = Vector3.New(0, 0, 0) end)
        return
    end
    if not withinBite(pos, tpos, params) then
        local ux, uz = flatDirection(tpos.x - pos.x, tpos.z - pos.z)
        local speed = self:Speed(fish)
        self:Face(fish, ux, uz, params)
        pcall(function() body.LinearVelocity = Vector3.New((ux or 0) * speed, 0, (uz or 0) * speed) end)
        return
    end
    pcall(function() body.LinearVelocity = Vector3.New(0, 0, 0) end)
    self:LockBite(fish, target, pos, tpos, now, params)
end

-- #135 每招只持有一个权威 Move；清理先摘掉它，重复帧不能再次结算。
function Mgr:EndMove(fish, reason)
    if not fish.Move then return end
    fish.Move, fish.MoveName = nil, nil
    publishBite(self, GarBiteNotice.Clear(fish.Id, reason))
    self:PublishCombat(fish)
end

function Mgr:StartMove(fish, name, pos, target, tpos, now, duration, range)
    self:EndMove(fish, 'replace')
    local fx, fz
    if tpos then fx, fz = flatDirection(tpos.x - pos.x, tpos.z - pos.z) end
    self:Face(fish, fx, fz)
    fish.Move = { Name = name, Target = target, At = now, StrikeAt = now + duration,
        Center = { x = pos.x, y = pos.y, z = pos.z },
        Destination = tpos and { x = tpos.x, y = pos.y, z = tpos.z } }
    local facing = fish.Facing or { x = 0, z = 1 }
    local warningPos = (name == 'dive' or name == 'jump') and fish.Move.Destination or pos
    warningPos = warningPos or pos
    local payload = GarBiteNotice.Lock(fish.Id, warningPos, facing.x, facing.z, range, 90, duration)
    payload.move = name
    if name == 'jump' then payload.shape, payload.halfAngleDeg = 'circle', 180 end
    publishBite(self, payload)
    fish.MoveName = name
    self:PublishCombat(fish)
    print('[MgrFishUnit] 招式预警', fish.FishId, name, 'fish=' .. tostring(fish.Id))
end

function Mgr:StunFish(fish, now, params)
    self:EndMove(fish, 'stun')
    fish.State, fish.WakeAt, fish.MoveName = 'stunned', now + params.StunSec, nil
    fish.Carrier.Body.LinearVelocity = Vector3.New(0, 0, 0)
    self:PublishCombat(fish)
    print('[MgrFishUnit] 眩晕', fish.FishId, 'wakeAt=' .. tostring(fish.WakeAt))
end

function Mgr:UpdateShrimpCombat(fish, now, pos, params, combat)
    local body = fish.Carrier.Body
    local dt = math.max(0, now - (fish.CombatStepAt or now))
    fish.CombatStepAt = now
    if fish.State == 'stunned' or fish.State == Mgr.State.Sleeping then
        body.LinearVelocity = Vector3.New(0, 0, 0)
        if now < (fish.WakeAt or math.huge) then return end
        fish.State, fish.WakeAt = Mgr.State.Combat, nil
        fish.ActiveUntil, fish.Combo = now + (params.ActiveSec or params.SpecialSec), 0
        dt = 0
        self:PublishCombat(fish)
    end
    if combat == 'shrimp' and now >= fish.ActiveUntil then
        self:StunFish(fish, now, params)
        return
    end
    local move = fish.Move
    if combat == 'dragon' and now >= fish.SpecialAt and (not move or move.Name == 'peck') then
        -- 正常帧按首次放下的30秒节拍；大dt不补发多周期，当前周期仍完整执行两招。
        fish.SpecialAt = now + params.SpecialSec
        self:StartMove(fish, 'rain', pos, nil, nil, now, params.RainSec, params.RainRadius)
        fish.Move.LastTick = 0
        move = fish.Move
    end
    if move then
        dt = 0 -- 预警与施法耗时不能折算成追击位移。
        body.LinearVelocity = Vector3.New(0, 0, 0)
        if move.Name == 'rain' then
            -- 不补历史tick：掉帧时只按当前范围结算一次，持续期固定不延长。
            local tick = math.min(params.RainSec, math.floor(now - move.At))
            if tick > move.LastTick then
                move.LastTick = tick
                for _, player in ipairs(self:Players()) do
                    local valid, cp = self:IsTargetValid(player, move.Center)
                    if valid and (cp.x - move.Center.x)^2 + (cp.z - move.Center.z)^2 <= params.RainRadius^2 then
                        self:Hit(fish, player, params.RainDamage, 'rain')
                    end
                end
            end
            if now < move.StrikeAt then return end
            self:EndMove(fish, 'rain-end')
            local target, tp = self:ChooseTarget(fish, pos, params)
            self:StartMove(fish, 'dive', pos, target, tp, now, params.DiveSec, params.DiveRadius)
            return
        elseif move.Name == 'dive' then
            local progress = math.min(1, math.max(0, (now - move.At) / params.DiveSec))
            local dest = move.Destination or move.Center
            body.Position = Vector3.New(move.Center.x + (dest.x - move.Center.x) * progress,
                move.Center.y + math.sin(progress * math.pi) * params.DiveHeight,
                move.Center.z + (dest.z - move.Center.z) * progress)
            if now < move.StrikeAt then return end
            self:EndMove(fish, 'dive-end')
            for _, player in ipairs(self:Players()) do
                local valid, cp = self:IsTargetValid(player, dest)
                if valid and (cp.x - dest.x)^2 + (cp.z - dest.z)^2 <= params.DiveRadius^2 then
                    self:Hit(fish, player, params.DiveDamage, 'dive')
                end
            end
            self:StunFish(fish, now, params)
            return
        end
        local valid, cp = self:IsTargetValid(move.Target, pos, params)
        if not valid or not withinBite(pos, cp, params) then
            self:EndMove(fish, 'cancel')
        elseif now < move.StrikeAt then return
        else
            self:EndMove(fish, 'strike')
            if Mgr.InHeadZone(pos, fish.Facing, cp, params) then
                local damage = move.Name == 'tail' and params.TailDamage
                    or (move.Name == 'peck' and params.PeckDamage or params.ClawDamage)
                local applied = self:Hit(fish, move.Target, damage, move.Name)
                if applied and move.Name == 'tail' then
                    local f = fish.Facing or { x = 0, z = 1 }
                    local ok, err = pcall(function()
                        move.Target.Character.Position = Vector3.New(cp.x + f.x * params.KnockHorizontal,
                            cp.y + params.KnockUp, cp.z + f.z * params.KnockHorizontal)
                    end)
                    if not ok then print('[MgrFishUnit] 尾刺击飞失败', fish.Id, tostring(err)) end
                end
            end
            fish.Combo = ((fish.Combo or 0) + 1) % 3
        end
    end
    local target, tp = self:ChooseTarget(fish, pos, params)
    if not target then body.LinearVelocity = Vector3.New(0, 0, 0); return end
    if not withinBite(pos, tp, params) then
        local fx, fz = flatDirection(tp.x - pos.x, tp.z - pos.z)
        self:Face(fish, fx, fz, params)
        local distance = math.sqrt((tp.x - pos.x)^2 + (tp.z - pos.z)^2)
        local step = math.min(self:Speed(fish) * dt, math.max(0, distance - params.BiteRange))
        body.LinearVelocity = Vector3.New(0, 0, 0)
        local moved, err = pcall(function()
            body.Position = Vector3.New(pos.x + (fx or 0) * step, pos.y, pos.z + (fz or 0) * step)
        end)
        if not moved then print('[MgrFishUnit] 虾池追击位移失败', fish.Id, tostring(err)) end
        return
    end
    body.LinearVelocity = Vector3.New(0, 0, 0)
    local name = combat == 'dragon' and 'peck' or ((fish.Combo or 0) == 2 and 'tail' or 'claw')
    self:StartMove(fish, name, pos, target, tp, now, params.BiteCooldownSec, params.BiteRange)
end

-- #136 帝王蟹：放下即锁定最近目标起手乱刺；每轮左右钳各 JabsPerSide 下、每下间隔
-- JabStepSec、每下 JabDamage。同一刺段（0.2 秒槽）只结算一次；掉帧大 dt 只补当前槽不追溯。
-- 一轮结束招式清除、预警收起，下一轮 JabAt + JabIntervalSec 后重新起手；活动 ActiveSec 秒
-- 眩晕 StunSec 秒（眩晕由通用 stunned 分支处理，醒来重置节拍）。
function Mgr:UpdateKingCrabCombat(fish, now, pos, params)
    local body = fish.Carrier.Body
    body.LinearVelocity = Vector3.New(0, 0, 0)
    -- 追击步长与帧率解耦：dt 取上一战斗帧间隔（与虾池 UpdateShrimpCombat 同口径）；
    -- 招式期间每帧也刷新 CombatStepAt，收招后首帧 dt 只是一帧间隔，不累积折算成位移。
    local dt = math.max(0, now - (fish.CombatStepAt or now))
    fish.CombatStepAt = now
    local move = fish.Move
    if move then
        if move.Name ~= 'jab' then return end
        -- 起手帧（now <= At）是预警帧，不结算；槽 k 在 At + (k+1) × JabStepSec 起结算，
        -- 钳与钳之间完整隔一个 JabStepSec；StrikeAt = At + 钳数 × step，末槽（第 6 钳）
        -- 与收招同帧：先结算末钳再收招。掉帧只补当前槽不追溯。
        local elapsed = now - move.At
        local slot = elapsed <= 0 and -1 or math.min(params.JabsPerSide * 2 - 1,
            math.floor(elapsed / params.JabStepSec + 1e-9) - 1)
        if slot > (move.LastSlot or -1) then
            move.LastSlot = slot
            local target, tp = self:IsTargetValid(move.Target, pos, params)
            if target and withinBite(pos, tp, params)
                and Mgr.InHeadZone(pos, fish.Facing, tp, params) then
                self:Hit(fish, move.Target, params.JabDamage, 'jab')
            end
        end
        if now < move.StrikeAt - 1e-9 then return end
        self:EndMove(fish, 'jab-end')
        return
    end
    local target, tp = self:ChooseTarget(fish, pos, params)
    if not target then return end
    if now < (fish.JabAt or 0) then return end
    if not withinBite(pos, tp, params) then
        local fx, fz = flatDirection(tp.x - pos.x, tp.z - pos.z)
        self:Face(fish, fx, fz, params)
        local distance = math.sqrt((tp.x - pos.x)^2 + (tp.z - pos.z)^2)
        local step = math.min(self:Speed(fish) * dt, math.max(0, distance - params.BiteRange))
        local moved, err = pcall(function()
            body.Position = Vector3.New(pos.x + (fx or 0) * step, pos.y, pos.z + (fz or 0) * step)
        end)
        if not moved then print('[MgrFishUnit] 帝王蟹追击位移失败', fish.Id, tostring(err)) end
        return
    end
    -- 起手乱刺：预警时长 = 钳数 × JabStepSec（起手帧 + 每钳一个间隔），
    -- 收招帧（now == StrikeAt）先结算末钳再收招。
    fish.JabAt = now + params.JabIntervalSec
    self:StartMove(fish, 'jab', pos, target, tp, now,
        params.JabStepSec * params.JabsPerSide * 2, params.BiteRange)
end

-- #136 蟹老板：三招互斥——双击（pinch）、冲撞（charge）、旋转（spin）。
-- 节拍：SpecialAt（旋转，每 25 秒）、ChargeAt（冲撞，每 30 秒）、PinchAt（双击，冷却 4 秒）。
-- 旋转 / 冲撞优先级高于双击；旋转优先级高于冲撞（旋转持续期跨过冲撞节拍时冲撞被压住）。
function Mgr:UpdateCrabBossCombat(fish, now, pos, params)
    local body = fish.Carrier.Body
    body.LinearVelocity = Vector3.New(0, 0, 0)
    -- 追击步长与帧率解耦：dt 取上一战斗帧间隔（与帝王蟹 / 虾池同口径）。
    local dt = math.max(0, now - (fish.CombatStepAt or now))
    fish.CombatStepAt = now
    local move = fish.Move
    if move then
        if move.Name == 'pinch' then
            -- 双击第 k 击在起手后 k × PinchStepSec 秒起结算
            local elapsed = now - move.At
            local strike = elapsed <= 0 and 0 or math.min(params.PinchStrikes,
                math.floor(elapsed / params.PinchStepSec + 1e-9))
            if strike > (move.LastStrike or 0) and strike >= 1 then
                move.LastStrike = strike
                local target, tp = self:IsTargetValid(move.Target, pos, params)
                if target and withinBite(pos, tp, params)
                    and Mgr.InHeadZone(pos, fish.Facing, tp, params) then
                    self:Hit(fish, move.Target, params.PinchDamage, 'pinch')
                end
            end
            if now < move.StrikeAt - 1e-9 then return end
            self:EndMove(fish, 'pinch-end')
            return
        elseif move.Name == 'charge' then
            -- 冲撞窗口内命中一次（窗口内只结算一次，不按帧重复）
            if not move.HitDone then
                local target, tp = self:ChooseTarget(fish, pos, params)
                if target and tp and (tp.x - pos.x)^2 + (tp.z - pos.z)^2 <= params.ChargeRange^2 then
                    move.HitDone = true
                    self:Hit(fish, target, params.ChargeDamage, 'charge')
                end
            end
            if now < move.StrikeAt - 1e-9 then return end
            self:EndMove(fish, 'charge-end')
            return
        elseif move.Name == 'spin' then
            -- 每秒槽一次碰触：同一秒槽同一玩家只结算一次（秒槽记在 move 上）
            local tick = math.min(params.SpinDurationSec,
                math.max(0, math.floor(now - move.At)))
            if tick > (move.LastTick or 0) then
                move.LastTick = tick
                for _, player in ipairs(self:Players()) do
                    local valid, cp = self:IsTargetValid(player, move.Center)
                    if valid and (cp.x - pos.x)^2 + (cp.z - pos.z)^2 <= params.SpinRadius^2 then
                        self:Hit(fish, player, params.SpinDamage, 'spin')
                    end
                end
            end
            if now < move.StrikeAt - 1e-9 then return end
            self:EndMove(fish, 'spin-end')
            return
        end
        return
    end
    -- 无招式时按节拍起新招：旋转 > 冲撞 > 双击
    local target, tp = self:ChooseTarget(fish, pos, params)
    if not target then return end
    if now >= (fish.SpecialAt or math.huge) then
        fish.SpecialAt = now + params.SpinSec
        self:StartMove(fish, 'spin', pos, target, tp, now, params.SpinDurationSec, params.SpinRadius)
        return
    end
    if now >= (fish.ChargeAt or math.huge) then
        fish.ChargeAt = now + params.ChargeSec
        self:StartMove(fish, 'charge', pos, target, tp, now, params.ChargeWindowSec, params.ChargeRange)
        return
    end
    if now >= (fish.PinchAt or 0) and withinBite(pos, tp, params) then
        fish.PinchAt = now + params.PinchCooldownSec
        self:StartMove(fish, 'pinch', pos, target, tp, now,
            params.PinchStepSec * params.PinchStrikes, params.BiteRange)
        return
    end
    -- 追击
    if not withinBite(pos, tp, params) then
        local fx, fz = flatDirection(tp.x - pos.x, tp.z - pos.z)
        self:Face(fish, fx, fz, params)
        local distance = math.sqrt((tp.x - pos.x)^2 + (tp.z - pos.z)^2)
        local step = math.min(self:Speed(fish) * dt, math.max(0, distance - params.BiteRange))
        local moved, err = pcall(function()
            body.Position = Vector3.New(pos.x + (fx or 0) * step, pos.y, pos.z + (fz or 0) * step)
        end)
        if not moved then print('[MgrFishUnit] 蟹老板追击位移失败', fish.Id, tostring(err)) end
    end
end
-- #141 树林岛精英 / 首领：高跃共用弹道与落地范围伤害。
-- 落点方向由 math.random 决定（表现细化 [未查证]），落地伤害按参数表 JumpDamage / JumpRadius。
function Mgr:StartJump(fish, now, pos, params)
    fish.JumpAt = now + params.JumpIntervalSec
    local rng = math.random
    local angle = (rng and rng() or 0.5) * math.pi * 2
    local dest = { x = pos.x + math.cos(angle) * params.JumpDistance, y = pos.y,
        z = pos.z + math.sin(angle) * params.JumpDistance }
    self:StartMove(fish, 'jump', pos, nil, dest, now, params.JumpSec, params.JumpRadius)
end

-- 腾空弧线：水平线性插值到落点，高度按 sin(进度×π) 抬起；到点结算一次落地范围伤害。
function Mgr:AdvanceJump(fish, now, pos, params)
    local body = fish.Carrier.Body
    local move = fish.Move
    local dest = move.Destination or move.Center
    local progress = math.min(1, math.max(0, (now - move.At) / params.JumpSec))
    local ok, err = pcall(function()
        body.Position = Vector3.New(
            move.Center.x + (dest.x - move.Center.x) * progress,
            move.Center.y + math.sin(progress * math.pi) * params.JumpHeight,
            move.Center.z + (dest.z - move.Center.z) * progress)
    end)
    if not ok then
        print('[MgrFishUnit] 高跃位移失败', 'fish=' .. tostring(fish.Id), tostring(err))
        self:EndMove(fish, 'cancel')
        return
    end
    if now < move.StrikeAt - 1e-9 then return end
    self:EndMove(fish, 'jump-end')
    for _, player in ipairs(self:Players()) do
        local valid, cp = self:IsTargetValid(player, dest, params)
        if valid and (cp.x - dest.x)^2 + (cp.z - dest.z)^2 <= params.JumpRadius * params.JumpRadius then
            self:Hit(fish, player, params.JumpDamage, 'jump')
        end
    end
end

-- 剑鱼：翻滚追击 + 左右挥头（SwingDamage）+ 周期高跃。
-- 挥头起手即锁定朝向（StartMove），预警期间不转头，绕后落空；起手时长取 SwingCooldownSec（配置细化）。
function Mgr:UpdateSwordfishCombat(fish, now, pos, params)
    local body = fish.Carrier.Body
    body.LinearVelocity = Vector3.New(0, 0, 0)
    local dt = math.max(0, now - (fish.CombatStepAt or now))
    fish.CombatStepAt = now
    local move = fish.Move
    if move then
        if move.Name == 'jump' then
            self:AdvanceJump(fish, now, pos, params)
            return
        end
        local valid, tp = self:IsTargetValid(move.Target, pos, params)
        if not valid or not withinBite(pos, tp, params) then
            self:EndMove(fish, 'cancel')
        elseif now < move.StrikeAt - 1e-9 then
            return
        else
            self:EndMove(fish, 'swing')
            if Mgr.InHeadZone(pos, fish.Facing, tp, params) then
                self:Hit(fish, move.Target, params.SwingDamage, 'swing')
            end
            return
        end
    end
    if now >= (fish.JumpAt or math.huge) then
        self:StartJump(fish, now, pos, params)
        return
    end
    local target, tpos = self:ChooseTarget(fish, pos, params)
    if not target then return end
    if withinBite(pos, tpos, params) then
        self:StartMove(fish, 'swing', pos, target, tpos, now, params.SwingCooldownSec, params.BiteRange)
        return
    end
    local fx, fz = flatDirection(tpos.x - pos.x, tpos.z - pos.z)
    self:Face(fish, fx, fz, params)
    local distance = math.sqrt((tpos.x - pos.x)^2 + (tpos.z - pos.z)^2)
    local step = math.min(self:Speed(fish) * dt, math.max(0, distance - params.BiteRange))
    local moved, err = pcall(function()
        body.Position = Vector3.New(pos.x + (fx or 0) * step, pos.y, pos.z + (fz or 0) * step)
    end)
    if not moved then
        print('[MgrFishUnit] 剑鱼追击位移失败', 'fish=' .. tostring(fish.Id), tostring(err))
        return
    end
end

-- 三头鲨：翻滚追击（贴身接触伤害 RollDamage，独立段，同一秒槽每玩家只结算一次）+ 扫头（SweepDamage）+ 周期高跃。
function Mgr:UpdateSharkCombat(fish, now, pos, params)
    local body = fish.Carrier.Body
    body.LinearVelocity = Vector3.New(0, 0, 0)
    local dt = math.max(0, now - (fish.CombatStepAt or now))
    fish.CombatStepAt = now
    local move = fish.Move
    if move then
        if move.Name == 'jump' then
            self:AdvanceJump(fish, now, pos, params)
            return
        end
        local valid, tp = self:IsTargetValid(move.Target, pos, params)
        if not valid or not withinBite(pos, tp, params) then
            self:EndMove(fish, 'cancel')
        elseif now < move.StrikeAt - 1e-9 then
            return
        else
            self:EndMove(fish, 'sweep')
            if Mgr.InHeadZone(pos, fish.Facing, tp, params) then
                self:Hit(fish, move.Target, params.SweepDamage, 'sweep')
            end
            return
        end
    end
    if now >= (fish.JumpAt or math.huge) then
        self:StartJump(fish, now, pos, params)
        return
    end
    local target, tpos = self:ChooseTarget(fish, pos, params)
    if not target then return end
    if withinBite(pos, tpos, params) then
        self:StartMove(fish, 'sweep', pos, target, tpos, now, params.SweepCooldownSec, params.BiteRange)
        return
    end
    local fx, fz = flatDirection(tpos.x - pos.x, tpos.z - pos.z)
    self:Face(fish, fx, fz, params)
    local distance = math.sqrt((tpos.x - pos.x)^2 + (tpos.z - pos.z)^2)
    local step = math.min(self:Speed(fish) * dt, math.max(0, distance - params.BiteRange))
    if step <= 0 then return end
    local moved, err = pcall(function()
        body.Position = Vector3.New(pos.x + (fx or 0) * step, pos.y, pos.z + (fz or 0) * step)
    end)
    if not moved then
        print('[MgrFishUnit] 三头鲨追击位移失败', 'fish=' .. tostring(fish.Id), tostring(err))
        return
    end
    -- 成功移动后用实际滚动线段判接触；每玩家独立去重，不消耗本秒其它玩家的接触机会。
    local actual = readPosition(body)
    if not actual or (actual.x == pos.x and actual.z == pos.z) then return end
    local slot = math.floor(now)
    if fish.RollSlot ~= slot then fish.RollSlot, fish.RollHits = slot, {} end
    for _, player in ipairs(self:Players()) do
        local valid, cp = self:IsTargetValid(player, actual, params)
        if valid and not fish.RollHits[player]
            and segmentDistanceSq(cp.x, cp.z, pos.x, pos.z, actual.x, actual.z) <= params.BiteRange^2 then
            fish.RollHits[player] = true
            self:Hit(fish, player, params.RollDamage, 'roll')
        end
    end
end

-- 战斗只在首次放下后计时；逃跑时限优先于攻击和睡眠。
function Mgr:UpdateCombat(fish, now)
    local body = fish.Carrier.Body
    local pos = readPosition(body)
    if not pos then
        print('[MgrFishUnit] 战斗鱼坐标异常，移除', fish.Id)
        self:Remove(fish)
        return
    end
    local moveName = fish.Move and fish.Move.Name
    local diving = moveName == 'dive'
    local jumping = moveName == 'jump'
    -- 俯冲（dragon）与高跃（#141 swordfish / shark）腾空期间不算落水，避免空中误判逃脱。
    local airborne = (diving or jumping) and pos.y > fish.Move.Center.y + 0.1
    if now >= fish.FleeAt or (not airborne and inWater(pos)) then
        if diving or jumping then
            local ground = fish.Move.Center.y
            local ok, err = pcall(function() body.Position = Vector3.New(pos.x, ground, pos.z) end)
            if not ok then print('[MgrFishUnit] 腾空逃脱落地失败', fish.Id, tostring(err)) end
            pos = readPosition(body) or pos
        end
        if self.Ability then self.Ability:RemoveFish(fish) end
        self:EndBite(fish, 'gone')
        self:EndMove(fish, 'gone')
        fish.WakeAt, fish.MoveName = nil, nil
        fish.State = Mgr.State.Escaping
        fish.StraightEscape = true
        if fish.CombatRotation then body.Rotation = fish.CombatRotation end
        self:SetHeading(fish, towardWater(pos))
        print('[MgrFishUnit] 精英开始逃脱', fish.FishId, 'fish=' .. tostring(fish.Id))
        self:PublishCombat(fish)
        self:UpdateEscaping(fish, now)
        return
    end
    self:RefreshMovingCombat(fish, now)
    -- #139 麻痹（雷霆之力）：就地停住，本帧不追咬/不施法/不起招；逃跑时限仍在上面优先结算
    if self.Ability and self.Ability.FishParalyzed then
        local ok, paralyzed = pcall(self.Ability.FishParalyzed, self.Ability, fish)
        if ok and paralyzed then
            pcall(function() body.LinearVelocity = Vector3.New(0, 0, 0) end)
            return
        end
    end
    -- #136 蟹湖眩晕：shrimp/dragon 的 stunned 由 UpdateShrimpCombat 专属分支处理，
    -- 帝王蟹在这里醒转并重置节拍；蟹老板无眩晕机制，不会进入该分支。
    local combat = GameCfg.Fish[fish.FishId].Combat
    if fish.State == 'stunned' and combat == 'kingCrab' then
        body.LinearVelocity = Vector3.New(0, 0, 0)
        if now < (fish.WakeAt or math.huge) then return end
        fish.State, fish.WakeAt = Mgr.State.Combat, nil
        local params = GameCfg.FishCombat and GameCfg.FishCombat[combat]
        if params then resetCrabRhythm(fish, now, params) end
        self:PublishCombat(fish)
    end
    -- #132 T11 原型：分阶段首领走自己的状态机（阈值切换 → 招式集 → 咬中叼人）
    if self:BossPhaseEnabled(fish.FishId) then
        self:UpdateBossPhase(fish, now, pos)
        return
    end
    -- 首领近战（#88）不走技能装配与睡眠，追咬由 UpdateChase 驱动
    local chase = GameCfg.FishCombat and GameCfg.FishCombat[combat]
    if chase then
        if combat == 'shrimp' or combat == 'dragon' then
            self:UpdateShrimpCombat(fish, now, pos, chase, combat)
        elseif combat == 'kingCrab' then
            -- #136 帝王蟹：活动 30 秒眩晕 5 秒优先于起手
            if now >= (fish.ActiveUntil or math.huge) then
                self:StunFish(fish, now, chase)
            else
                self:UpdateKingCrabCombat(fish, now, pos, chase)
            end
        elseif combat == 'crabBoss' then
            -- #136 蟹老板：双击 / 冲撞 / 旋转三招互斥
            self:UpdateCrabBossCombat(fish, now, pos, chase)
        elseif combat == 'swordfish' then
            -- #141 剑鱼：翻滚追击 + 左右挥头 + 周期高跃（10 米外、5 米范围）
            self:UpdateSwordfishCombat(fish, now, pos, chase)
        elseif combat == 'shark' then
            -- #141 三头鲨：翻滚追击（接触伤害独立段）+ 扫头 + 周期高跃（15 米外、10 米范围）
            self:UpdateSharkCombat(fish, now, pos, chase)
        else
            self:UpdateChase(fish, now, pos, chase)
        end
        return
    end
    self:UpdateEel(fish, now, GameCfg.Ability.FishAbilities[combat])
end

-- #134 精英鱼（电鳗 180 秒 / 鳄雀鳝 300 秒共用）战斗状态广播：FishCombatState 只读快照，
-- 客户端据此画逃跑时限条，电鳗另显放电次数与睡眠倒计时；权威状态只在服务端。
-- 原地不动的技能型精英只在状态切换时发；会移动的追咬型首领按 MovingRefreshSec 限频补发坐标。
function Mgr:CombatPayload(fish, gone)
    if gone then return { id = fish.Id, state = 'gone' } end
    local entry = GameCfg.Ability.FishAbilities[GameCfg.Fish[fish.FishId].Combat]
    local pos = readPosition(fish.Carrier.Body) or fish.CombatPosition or fish.Anchor
    return { id = fish.Id, fishId = fish.FishId, state = fish.State,
        fleeAt = fish.FleeAt, escapeSec = GameCfg.Fish[fish.FishId].EscapeSec,
        wakeAt = fish.WakeAt, move = fish.MoveName, discharges = fish.Discharges or 0, dischargeCount = entry and entry.DischargeCount,
        position = pos and { x = pos.x, y = pos.y, z = pos.z } }
end

-- 会移动的精英（无技能表条目）限频补发坐标，头顶逃跑条跟着鱼走。
function Mgr:RefreshMovingCombat(fish, now)
    if GameCfg.Ability.FishAbilities[GameCfg.Fish[fish.FishId].Combat] then return end
    if now < (fish.CombatRefreshAt or 0) then return end
    fish.CombatRefreshAt = now + GameCfg.FishCombatLabel.MovingRefreshSec
    self:PublishCombat(fish)
end

function Mgr:PublishCombat(fish, gone)
    local species = GameCfg.Fish[fish.FishId]
    if not (species and species.Combat) then return end
    if gone and not fish.CombatPublished then return end
    fish.CombatPublished = not gone and fish.State ~= Mgr.State.Escaping
    local publish = self.CombatPublisher
    if not publish and self.CombatRE then
        publish = function(payload) self.CombatRE:FireAllClients(payload) end
    end
    if not publish then return end
    local ok, err = pcall(publish, self:CombatPayload(fish, gone))
    if not ok then print('[MgrFishUnit] 战斗状态广播失败', 'fish=' .. tostring(fish.Id), tostring(err)) end
end

-- 迟加入 / 重开界面的只读快照：逐条回发当前仍在战斗的技能型精英；按玩家限频。
function Mgr:StartCombatChannel()
    if self.CombatRequestConn or not game:GetService('RunService') then return end
    local REUtil = require('common.REUtil')
    self.CombatRE = REUtil:GetRE('FishCombatState')
    self.CombatRequestConn = REUtil:GetRE('RequestFishCombat').OnServerEvent:Connect(function(player)
        if not player or REUtil:CheckRECD(player, 'RequestFishCombat', 0.5) then return end
        for _, fish in pairs(self.Fish) do
            if fish.CombatPublished then
                local ok, err = pcall(function() self.CombatRE:FireClient(player, self:CombatPayload(fish)) end)
                if not ok then print('[MgrFishUnit] 战斗快照发送失败', player.UserId, tostring(err)) end
            end
        end
    end)
end

-- #134 电鳗：Combat →（首次施法成功）Attacking 每 DischargeIntervalSec 施法放电一次，共 DischargeCount 次
-- →（最后一次后再满一个间隔）Sleeping SleepSec → Combat 重新开始。
-- 每次 Update 最多放电一次、下一次按实际放电时刻 + 间隔排期：重复 Update 不连放，大 dt 不补发连击，
-- 次数只按施法成功计（施法被拒/打断不计数，下帧重试）。睡眠从实际入睡时刻起算，大 dt 不会吞掉睡眠窗口。
function Mgr:UpdateEel(fish, now, entry)
    local body = fish.Carrier.Body
    body.Position = fish.CombatPosition
    body.LinearVelocity = Vector3.New(0, 0, 0)
    if fish.State == Mgr.State.Sleeping then
        if now < fish.WakeAt then return end
        if fish.CombatRotation then body.Rotation = fish.CombatRotation end
        fish.State = Mgr.State.Combat
        fish.WakeAt = nil
        fish.Discharges = 0
        print('[MgrFishUnit] 电鳗醒来', 'fish=' .. tostring(fish.Id))
        self:PublishCombat(fish)
    end
    local attacking = fish.State == Mgr.State.Attacking
    local done = fish.Discharges or 0
    if attacking and done >= entry.DischargeCount then
        if now < fish.NextDischargeAt then
            self:FlailEel(fish, now, entry)
            return
        end
        if fish.CombatRotation and Quaternion then
            body.Rotation = fish.CombatRotation * Quaternion.FromEulerAngles(0, 0, entry.SleepRollRadians)
        end
        fish.State = Mgr.State.Sleeping
        fish.WakeAt = now + entry.SleepSec
        fish.NextDischargeAt = nil
        print('[MgrFishUnit] 电鳗睡眠', 'fish=' .. tostring(fish.Id), 'wakeAt=' .. tostring(fish.WakeAt))
        self:PublishCombat(fish)
        return
    end
    if attacking then self:FlailEel(fish, now, entry) end
    if attacking and now < fish.NextDischargeAt then return end
    local castOk, casted = true, false
    if self.Ability then castOk, casted = pcall(self.Ability.CastFish, self.Ability, fish) end
    if not castOk then
        print('[MgrFishUnit] 电鳗施法异常', 'fish=' .. tostring(fish.Id), tostring(casted))
    end
    if not castOk or not casted then
        if not fish.CastRejected then
            fish.CastRejected = true
            print('[MgrFishUnit] 电鳗施法未成功，下帧重试', 'fish=' .. tostring(fish.Id), 'done=' .. tostring(done))
        end
        return
    end
    fish.CastRejected = nil
    if not attacking then
        fish.State = Mgr.State.Attacking
        fish.AttackAt = now
        done = 0
    end
    fish.Discharges = done + 1
    fish.NextDischargeAt = now + entry.DischargeIntervalSec
    print('[MgrFishUnit] 电鳗放电', 'fish=' .. tostring(fish.Id), fish.Discharges .. '/' .. entry.DischargeCount)
    self:PublishCombat(fish)
end

function Mgr:FlailEel(fish, now, entry)
    if fish.CombatRotation and Quaternion then
        fish.Carrier.Body.Rotation = fish.CombatRotation * Quaternion.FromEulerAngles(0,
            math.sin((now - fish.AttackAt) * math.pi * 2 * entry.FlailHz) * entry.FlailRadians, 0)
    end
end

-- ============================================================================================
-- #132 T11 高风险能力原型：飞行 / 俯冲、叼人、首领分阶段。
-- 纯逻辑（边界钳制、挂点净空与跟随、阈值状态机）在 common/FlightPath.lua、common/CarryMount.lua、
-- common/BossPhase.lua；本段只做引擎驱动：读坐标、写位置、经 MgrVitals 结算伤害。
-- 本单未试玩：真机贴地/撞墙、玩家被叼走的手感、首领动画驱动都待编辑器窗口（见 issue #132 待办清单）。
-- ============================================================================================

local function zoneScene(zoneId)
    for _, zone in ipairs(GameCfg.Zones or {}) do
        if zone.Id == zoneId then return zone.Scene end
    end
end

---该鱼种是否走飞行（GameCfg.Ability.Flight.Species 按鱼种 Id 登记）
function Mgr:FlightProfile(fishId)
    local species = GameCfg.Ability.Flight.Species
    return species and species[fishId] or nil
end

---该鱼种是否走分阶段首领（GameCfg.Ability.BossPhase.Species 按鱼种 Id 登记）
function Mgr:BossPhaseEnabled(fishId)
    local species = GameCfg.Ability.BossPhase.Species
    return type(species) == 'table' and species[fishId] == true
end

---飞行边界：优先本区场景合同（#125 的 Scene.Boundary），缺失时用配置兜底围栏；
---两者都拿不到就不飞（返回 nil），绝不无边界乱飞。
function Mgr:FlightBounds(fishId)
    local species = GameCfg.Fish[fishId]
    local scene = species and zoneScene(species.ZoneId)
    local bounds = FlightPath.BoundsOf(scene, GameCfg.Ability.Flight)
    if bounds then return bounds end
    local fallback = GameCfg.Ability.Flight.FallbackBounds
    if not fallback then return nil end
    return FlightPath.BoundsOf({ Boundary = fallback, SafePoint = { x = 0, y = 0, z = 0 } }, GameCfg.Ability.Flight)
end

---起飞：建立飞行状态并切 State.Flying。没有档案或没有边界时返回 false（调用方回落普通逃脱）。
function Mgr:StartFlight(fish, now)
    local profile = self:FlightProfile(fish.FishId)
    local bounds = self:FlightBounds(fish.FishId)
    if not profile or not bounds then return false end
    local pos = readPosition(fish.Carrier.Body)
    fish.Flight = FlightPath.New(bounds, GameCfg.Ability.Flight, profile, pos, now)
    fish.FlightAt = now
    fish.State = Mgr.State.Flying
    fish.DiveActive = false
    -- 飞行期间由脚本给速度驱动：Kinematic 不受重力影响（与在逃鱼同口径，BodyType=2 见本文件 280 行注释）
    pcall(function() fish.Carrier.Body.BodyType = 2 end)
    print('[MgrFishUnit] 起飞', fish.FishId, 'fish=' .. tostring(fish.Id))
    return true
end

---结束飞行，回落到既有的在逃逻辑（入水即销毁）。
function Mgr:ExitFlight(fish, now, reason)
    fish.Flight = nil
    fish.DiveActive = false
    if self.Fish[fish.Id] ~= fish then return end
    fish.State = Mgr.State.Escaping
    fish.StraightEscape = true
    fish.EscapeAt = now
    fish.EscapeBy = nil
    fish.TurnAt = now + cfg().TurnSec
    fish.RayAt = now
    if fish.CombatRotation then pcall(function() fish.Carrier.Body.Rotation = fish.CombatRotation end) end
    self:SetHeading(fish, towardWater(readPosition(fish.Carrier.Body) or fish.Anchor))
    print('[MgrFishUnit] 结束飞行', reason or '', fish.FishId, 'fish=' .. tostring(fish.Id))
end

---飞行/俯冲每帧：轨迹与钳制由 FlightPath 保证，这里只把结果写回引擎并结算俯冲命中。
function Mgr:UpdateFlying(fish, now)
    local state = fish.Flight
    local body = fish.Carrier.Body
    if not state then
        self:Remove(fish)
        return
    end
    local pos = readPosition(body)
    if not pos then
        print('[MgrFishUnit] 飞行鱼坐标异常，移除', fish.Id)
        self:Remove(fish)
        return
    end
    if (fish.FleeAt and now >= fish.FleeAt) or inWater(pos) then
        self:ExitFlight(fish, now, (fish.FleeAt and now >= fish.FleeAt) and 'timeout' or 'water')
        return
    end
    local flight = GameCfg.Ability.Flight
    -- 空中受击由 #128 链路自己处理（受击体照常可打，伤害进 Threat），飞行只影响移动
    local target, tpos = self:ChooseTarget(fish, pos, { AggroRange = flight.AggroRange })
    FlightPath.SetTarget(state, tpos)
    local dt = math.max(0, now - (fish.FlightAt or now))
    fish.FlightAt = now
    local events = FlightPath.Step(state, now, dt)
    -- 位置写回是飞行能不能动的关键：写失败只打一次日志（每帧打会刷屏），速度是只读镜像，失败就算了
    local moved, moveErr = pcall(function()
        body.Position = Vector3.New(state.Pos.x, state.Pos.y, state.Pos.z)
    end)
    if not moved and not fish.MoveWarned then
        fish.MoveWarned = true
        print('[MgrFishUnit] 飞行位置写回失败', fish.FishId, tostring(moveErr))
    end
    pcall(function()
        body.LinearVelocity = Vector3.New(state.Vel.x, state.Vel.y, state.Vel.z)
    end)
    if events.dive then
        fish.DiveActive = true
    elseif fish.DiveActive and state.Phase == 'climb' then
        -- 俯冲触底那一刻：目标还在命中半径内才算砸到
        fish.DiveActive = false
        if target and tpos then
            local dx, dz = tpos.x - state.Pos.x, tpos.z - state.Pos.z
            if math.sqrt(dx * dx + dz * dz) <= flight.DiveRadius then
                self:Hit(fish, target, events.diveDamage or state.Profile.DiveDamage or flight.DiveDamage, 'dive')
            end
        end
    end
end

---统一的鱼攻击结算口（走 #128 的 MgrVitals，不直接碰 Controller）。
function Mgr:Hit(fish, target, damage, kind)
    if not target or not self.Vitals or type(damage) ~= 'number' or damage <= 0 then return false end
    local hit = self.Vitals:NewHit(fish, 'fishAttack')
    local applied = self.Vitals:ApplyHit(hit, target, damage)
    if applied then
        print('[MgrFishUnit] 命中', kind or 'attack', fish.FishId, damage, 'fish=' .. tostring(fish.Id))
    end
    return applied == true
end

---首领分阶段每帧：血量阈值 → 阶段，阶段招式集 → 落地伤害；咬中即叼人（沧龙式）。
function Mgr:UpdateBossPhase(fish, now, pos)
    local state = fish.Phase
    if not state then
        self:Remove(fish)
        return
    end
    if fish.Carry then
        self:UpdateCarry(fish, now)
        return
    end
    local params = GameCfg.FishCombat and GameCfg.FishCombat[fish.Fight] or nil
    params = params or GameCfg.Ability.BossPhase.Chase
    local target, tpos = self:ChooseTarget(fish, pos, params)
    local dt = math.max(0, now - (fish.PhaseAt or now))
    fish.PhaseAt = now
    pcall(function() fish.Carrier.Body.LinearVelocity = Vector3.New(0, 0, 0) end)
    local events = BossPhase.Update(state, now, dt, {
        Health = fish.Carrier.Health, MaxHealth = fish.Carrier.MaxHealth,
        Alive = not fish.Carrier.Dead, Target = tpos, Pos = pos,
    })
    if not events.Attack then return end
    local attack = events.Attack
    if attack.Name == 'bite' and target and tpos and CarryMount.InRange(
        CarryMount.New(GameCfg.Ability.Carry, pos, fish.Yaw or 0, now), tpos) then
        -- 咬中即叼走：伤害只在 GrabPlayer 里结算一次，避免「咬一下扣两次血」
        self:GrabPlayer(fish, target, now, attack.Damage)
        return
    end
    if target then self:Hit(fish, target, attack.Damage, attack.Name) end
end

---叼人：宿主挂点上建挂点单位，玩家位置每帧写回挂点（不 parent 玩家，见下方说明）。
---@param damage? number 咬中伤害（缺省用 GameCfg.Ability.Carry.GrabDamage）
function Mgr:GrabPlayer(fish, target, now, damage)
    if fish.Carry then return false end
    local carryCfg = GameCfg.Ability.Carry
    local pos = readPosition(fish.Carrier.Body)
    if not pos then return false end
    local state = CarryMount.New(carryCfg, pos, fish.Yaw or 0, now)
    state.GroundY = (fish.Anchor and fish.Anchor.y) or pos.y
    state.TargetPlayer = target
    state.LastStepAt = now
    local grabbed = CarryMount.Attach(state, target.Character and readPosition(target.Character) or pos, now)
    if not grabbed.Ok then
        print('[MgrFishUnit] 叼人失败', tostring(grabbed.Reason), 'fish=' .. tostring(fish.Id))
        return false
    end
    fish.Carry = state
    self:Hit(fish, target, damage or carryCfg.GrabDamage, 'bite')
    -- 咬中这一下就是本次伤害，过程接触从下一个间隔才起算，避免同帧扣两次
    fish.ContactAt = now
    -- 挂点只建不挂：把玩家角色 parent 到挂点下会不会打断控制器/相机本单未试玩（[未查证]），
    -- 所以位置由服务端每帧写回（CarryMount.Follow），挂点留着给真机试玩时验证 parent 模式。
    local ok, attached = pcall(abilityApi().AttachToSocket, self.World, nil, fish.Carrier.Body,
        carryCfg.Socket, state.Offset)
    if ok and attached and attached.Ok then
        fish.CarryMount = attached.Mount
    else
        print('[MgrFishUnit] 叼人挂点创建失败', 'fish=' .. tostring(fish.Id))
    end
    print('[MgrFishUnit] 叼起玩家', target.UserId, 'fish=' .. tostring(fish.Id))
    return true
end

---携带每帧：超时/目标消失即释放；过程接触按固定节奏补伤害。
function Mgr:UpdateCarry(fish, now)
    local state = fish.Carry
    local carryCfg = GameCfg.Ability.Carry
    local pos = readPosition(fish.Carrier.Body)
    if pos then state.Host = pos end
    local dt = math.max(0, now - (state.LastStepAt or now))
    state.LastStepAt = now
    local target = state.TargetPlayer
    local tpos = target and target.Character and readPosition(target.Character)
    if not tpos then
        self:ReleaseCarried(fish, nil, 'gone')
        return
    end
    local step = CarryMount.Step(state, now, dt)
    if step.Released then
        self:ReleaseCarried(fish, step.DropPoint, step.Reason)
        return
    end
    local followed = CarryMount.Follow(state, tpos, now, dt)
    if followed.Released then
        self:ReleaseCarried(fish, followed.Position, followed.Reason)
        return
    end
    if followed.Position and target.Character then
        pcall(function()
            target.Character.Position = Vector3.New(followed.Position.x, followed.Position.y, followed.Position.z)
        end)
    end
    -- 过程接触伤害（GameSpec §12「叼走过程接触 150」）：固定节奏，不按帧
    if carryCfg.ContactDamage and now - (fish.ContactAt or 0) >= (carryCfg.ContactIntervalSec or 1) then
        fish.ContactAt = now
        self:Hit(fish, target, carryCfg.ContactDamage, 'carry')
    end
end

---释放被叼走的玩家：把玩家放到前方落点，销毁挂点。重复调用是空操作。
function Mgr:ReleaseCarried(fish, dropPoint, reason)
    local state = fish.Carry
    if not state then return false end
    local now = self:Now()
    local target = state.TargetPlayer
    local drop = dropPoint or CarryMount.DropPoint(state.Host, state.Yaw, state.GroundY, GameCfg.Ability.Carry)
    CarryMount.Release(state, now, reason or 'release')
    fish.Carry = nil
    fish.ContactAt = nil
    if fish.CarryMount then
        pcall(abilityApi().DetachFromSocket, fish.CarryMount)
        fish.CarryMount = nil
    end
    if target and target.Character and drop then
        pcall(function() target.Character.Position = Vector3.New(drop.x, drop.y, drop.z) end)
        self:Hit(fish, target, GameCfg.Ability.Carry.FallDamage or 0, 'fall')
    end
    print('[MgrFishUnit] 放开玩家', target and target.UserId, reason or '', 'fish=' .. tostring(fish.Id))
    return true
end

function Mgr:FindByCarrier(carrier)
    for _, fish in pairs(self.Fish) do
        if fish.Carrier == carrier then return fish end
    end
end

-- 鱼被打死（#43）：举着的先解除抓举（挂点销毁、持有者空手），鱼获位置取持有者脚下；
-- 其余状态取鱼本体位置。随后移除活鱼，返回 {fishId, mult, position}，只会成功一次
function Mgr:TakeKilled(fish)
    if not fish or self.Fish[fish.Id] ~= fish then return nil end
    local holder = fish.State == Mgr.State.Held and fish.Holder or nil
    local pos = holder and holder.Character and readPosition(holder.Character)
        or readPosition(fish.Carrier.Body) or fish.Anchor
    self:Remove(fish)
    print('[MgrFishUnit] 被打死', fish.FishId, fish.Mult, holder and ('held by ' .. tostring(holder.UserId)) or fish.State,
        'fish=' .. tostring(fish.Id))
    if holder and self.Cast then self.Cast:PushState(holder) end
    -- 新手任务「打死」事实（#52）：引擎 Died / TakeDamage 不带攻击者，服务端能确认的归属是鱼的主人（上岸者），
    -- 只推进这一名玩家；TakeKilled 对一条鱼只成功一次，鱼 id 即唯一 eventId
    if fish.Owner and self.Quest then
        self.Quest:Notify('Kill', fish.Owner, { itemId = fish.FishId, eventId = 'kill:' .. tostring(fish.Id) })
    end
    return { fishId = fish.FishId, mult = fish.Mult, position = pos }
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
    -- #132 T11：鱼被打死/清场时先把叼着的玩家放下来（否则玩家会跟着一条死鱼卡在空中）
    if fish.Carry then self:ReleaseCarried(fish, nil, 'died') end
    self:EndBite(fish, 'gone') -- #134：死亡或清场时收起咬预警
    self:EndMove(fish, 'gone')
    fish.WakeAt, fish.MoveName = nil, nil
    self.Fish[fish.Id] = nil
    self:PublishCombat(fish, true)
    if self.Ability then self.Ability:RemoveFish(fish) end
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
    self:StartCombatChannel()
end

function Mgr:ClearLinks(player)
    local links = self.Links[player.UserId]
    if not links then return end
    if links.Added then links.Added:Disconnect() end
    if links.Died then links.Died:Disconnect() end
    self.Links[player.UserId] = nil
end

function Mgr:Stop()
    for _, links in pairs(self.Links) do
        if links.Added then links.Added:Disconnect() end
        if links.Died then links.Died:Disconnect() end
    end
    self.Links = {}
    if self.CombatRequestConn then self.CombatRequestConn:Disconnect() end
    self.CombatRequestConn = nil
end

-- 持有者死亡：放鱼进逃脱，并打断还在抛竿的会话（上钩后的断线由 MgrReelIn 处理）；道具栏不动
function Mgr:OnDied(player)
    local fish = self:GetHeld(player)
    if fish then self:Release(fish, 'died') end
    if self.Cast and self.Cast.Abort then self.Cast:Abort(player) end
end

function Mgr:WatchCharacter(player, character)
    local links = self.Links[player.UserId]
    if links.Died then links.Died:Disconnect() end
    links.Died = nil
    if not character then return end
    self:IsolateCharacter(character)
    local controller = character.Controller
    if controller and controller.Died then
        links.Died = controller.Died:Connect(function() self:OnDied(player) end)
    end
end

function Mgr:OnPlayerAdded(player)
    self:ClearLinks(player)
    local links = {}
    self.Links[player.UserId] = links
    links.Added = player.CharacterAdded:Connect(function(character)
        self:WatchCharacter(player, character)
    end)
    self:WatchCharacter(player, player.Character)
end

-- 主人离线：还没被举起的鱼与举在他头上的鱼一并清掉，避免场上留下无主的鱼和挂点；
-- 已在逃的鱼留在场上，在线人数变少后由 Update 里的全局上限收
function Mgr:OnPlayerRemoving(player)
    self:ClearLinks(player)
    local held = self:GetHeld(player)
    if held then self:Remove(held) end
    for _, fish in pairs(self.Fish) do
        if fish.Threat then fish.Threat[player] = nil end
        if fish.TargetOverride == player then fish.TargetOverride = nil end
    end
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
        elseif fish.State == Mgr.State.Wild then
            if fish.WildUntil and now >= fish.WildUntil then
                print('[MgrFishUnit] 爆炸保底鱼到期消失', fish.FishId, 'fish=' .. tostring(fish.Id))
                self:Remove(fish)
            end
        elseif fish.State == Mgr.State.Escaping then
            self:UpdateEscaping(fish, now)
        elseif fish.State == Mgr.State.Flying then
            self:UpdateFlying(fish, now)
        elseif fish.FleeAt then
            self:UpdateCombat(fish, now)
        end
    end
    self:EnforceEscapeCap(nil)
end

return Mgr

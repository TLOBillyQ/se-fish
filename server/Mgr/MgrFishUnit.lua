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

local Mgr = { Fish = {}, NextId = 0, Held = {}, Links = {} }

Mgr.State = { AwaitLift = 'awaitLift', Held = 'held', Escaping = 'escaping',
    Combat = 'combat', Attacking = 'attacking', Sleeping = 'sleeping', Wild = 'wild' }

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

function Mgr:Speed(fish)
    local species = GameCfg.Fish[fish.FishId]
    return species and species.Speed or cfg().EscapeSpeed
end

function Mgr:SetHeading(fish, x, z)
    if not x then return end
    local speed = self:Speed(fish)
    fish.Heading = { x = x, z = z }
    pcall(function() fish.Carrier.Body.LinearVelocity = Vector3.New(x * speed, 0, z * speed) end)
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
    if species.Combat then
        fish.State = Mgr.State.Combat
        fish.FleeAt = now + species.EscapeSec
        fish.CombatPosition = pos
        fish.CombatRotation = body.Rotation
        body.LinearVelocity = Vector3.New(0, 0, 0)
        if GameCfg.FishCombat and GameCfg.FishCombat[species.Combat] then
            -- 首领近战（#88）：首个冷却期是起手预警，不立刻咬
            fish.NextBiteAt = now + GameCfg.FishCombat[species.Combat].BiteCooldownSec
        elseif self.Ability then
            self.Ability:EquipFish(fish)
        end
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

function Mgr:UpdateChase(fish, now, pos, params)
    local species = GameCfg.Fish[fish.FishId]
    local body = fish.Carrier.Body
    local target, tpos = self:ChooseTarget(fish, pos, params)
    if not target then
        pcall(function() body.LinearVelocity = Vector3.New(0, 0, 0) end)
        return
    end
    local best = (tpos.x - pos.x) * (tpos.x - pos.x) + (tpos.z - pos.z) * (tpos.z - pos.z)
    if best > params.BiteRange * params.BiteRange then
        local ux, uz = flatDirection(tpos.x - pos.x, tpos.z - pos.z)
        local speed = self:Speed(fish)
        pcall(function() body.LinearVelocity = Vector3.New((ux or 0) * speed, 0, (uz or 0) * speed) end)
        return
    end
    pcall(function() body.LinearVelocity = Vector3.New(0, 0, 0) end)
    if now < (fish.NextBiteAt or 0) then return end
    fish.NextBiteAt = now + params.BiteCooldownSec
    local hit = self.Vitals:NewHit(fish, 'fishAttack')
    self.Vitals:ApplyHit(hit, target, species.Attack)
    print('[MgrFishUnit] 首领追咬', fish.FishId, species.Attack, 'fish=' .. tostring(fish.Id))
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
    if now >= fish.FleeAt or inWater(pos) then
        if self.Ability then self.Ability:RemoveFish(fish) end
        fish.State = Mgr.State.Escaping
        fish.StraightEscape = true
        if fish.CombatRotation then body.Rotation = fish.CombatRotation end
        self:SetHeading(fish, towardWater(pos))
        print('[MgrFishUnit] 精英开始逃脱', fish.FishId, 'fish=' .. tostring(fish.Id))
        self:UpdateEscaping(fish, now)
        return
    end
    -- 首领近战（#88）不走技能装配与睡眠，追咬由 UpdateChase 驱动
    local combat = GameCfg.Fish[fish.FishId].Combat
    local chase = GameCfg.FishCombat and GameCfg.FishCombat[combat]
    if chase then
        self:UpdateChase(fish, now, pos, chase)
        return
    end
    local entry = GameCfg.Ability.FishAbilities[combat]
    body.Position = fish.CombatPosition
    body.LinearVelocity = Vector3.New(0, 0, 0)
    if fish.State == Mgr.State.Attacking then
        if now < fish.AttackEndsAt then
            if fish.CombatRotation and Quaternion then
                body.Rotation = fish.CombatRotation * Quaternion.FromEulerAngles(0,
                    math.sin((now - fish.AttackAt) * math.pi * 2 * entry.FlailHz) * entry.FlailRadians, 0)
            end
            return
        end
        if fish.CombatRotation then
            body.Rotation = fish.CombatRotation * Quaternion.FromEulerAngles(0, 0, entry.SleepRollRadians)
        end
        fish.State = Mgr.State.Sleeping
        fish.WakeAt = now + entry.SleepSec
        print('[MgrFishUnit] 电鳗睡眠', 'fish=' .. tostring(fish.Id), 'wakeAt=' .. tostring(fish.WakeAt))
    end
    if fish.State == Mgr.State.Sleeping and now < fish.WakeAt then return end
    if fish.CombatRotation then body.Rotation = fish.CombatRotation end
    fish.State = Mgr.State.Combat
    if self.Ability and self.Ability:CastFish(fish) then
        fish.State = Mgr.State.Attacking
        fish.AttackAt = now
        fish.AttackEndsAt = now + entry.CastSec
        print('[MgrFishUnit] 电鳗放电', 'fish=' .. tostring(fish.Id))
    end
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
    self.Fish[fish.Id] = nil
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
        elseif fish.FleeAt then
            self:UpdateCombat(fish, now)
        end
    end
    self:EnforceEscapeCap(nil)
end

return Mgr

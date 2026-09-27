-- 鱼获与拾取管理器（#43）：鱼载体死亡单点（MgrFishCarrier:SubscribeDied）里向活鱼管理器取走被打死的鱼，
-- 在地面生成一份携带鱼种与个体倍率的鱼获；鱼获静止、不参与物理、不消失，被拾取即销毁。
-- 拾取走道具栏动作通道（ItemBarAction{action='Pickup', value=<lootId>}），服务端复验目标、距离、空格；
-- 先删记录再发放，重放与多人争抢都只发一份。鱼获列表经 LootState 广播给客户端画「拾取」文字泡。
-- 固定点位鱼饵（#45）共用这套记录、广播与拾取复验：Kind='bait'，拾取进 Bait 计数库存（不占格），
-- 成功后该点位 RespawnSec 秒刷新一份新的（新 id，旧 id 重放无效）；鱼获（Kind='fish'）不刷新、不消失。
-- 分区上限回收（#91，GameSpec §6.5）：鱼获按落点归入最近的钓鱼区，每区 FIFO 计数，超 PerZoneCap
-- 最旧的进入待回收：可见性来回闪烁 FlashBeforeRecycleSec 秒后销毁；待回收不计入区总量、仍可拾取，
-- 拾取即取消回收。点位鱼饵不占区上限。
local GameCfg = require('common.GameCfg')
local MathWaterJudge = require('common.MathWaterJudge')
local MgrFishCarrier = require('server.Mgr.MgrFishCarrier')

local Mgr = { Loots = {}, NextId = 0, Spots = {}, ZoneQueues = {}, Recycling = {} }

-- 待回收闪烁的可见性切换间隔（秒）
local FLASH_INTERVAL = 0.5

local function cfg()
    return GameCfg.Loot
end

function Mgr:Broadcast()
    _G.REUtil:GetRE('LootState'):FireAllClients(self:Snapshot())
end

function Mgr:Reply(player, payload)
    _G.REUtil:GetRE('LootResult'):FireClient(player, payload)
end

function Mgr:Snapshot()
    local list = {}
    for _, loot in pairs(self.Loots) do
        list[#list + 1] = { id = loot.Id, kind = loot.Kind, fishId = loot.FishId, itemId = loot.ItemId,
            x = loot.Position.x, y = loot.Position.y, z = loot.Position.z }
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

-- 从 pos 上方往下探地；探不到就用原高度
function Mgr:Ground(pos)
    local c = cfg()
    local physics = game:GetService('PhysicsService')
    if physics and RaycastParams then
        local params = RaycastParams.New()
        params.FilterDescendantsInstances = self.FishUnit and self.FishUnit:RayExclusions() or {}
        local ok, hit = pcall(physics.Raycast, physics, Vector3.New(pos.x, pos.y + c.GroundRayUp, pos.z),
            Vector3.New(0, -c.GroundRayDown, 0), params)
        if ok and hit and hit.Position then return hit.Position.y, hit end
    end
    return pos.y
end

function Mgr:OnCarrierDied(carrier)
    local fish = self.FishUnit and self.FishUnit:FindByCarrier(carrier)
    local killed = fish and self.FishUnit:TakeKilled(fish)
    if not killed or not killed.position then return end
    local species = GameCfg.Fish[killed.fishId]
    if species.Drops then
        local total = 0
        for _, drop in ipairs(species.Drops) do total = total + drop.Count end
        local index = 0
        for _, drop in ipairs(species.Drops) do
            for _ = 1, drop.Count do
                index = index + 1
                local p = killed.position
                local pos = Vector3.New(p.x + (index - (total + 1) / 2) * cfg().DropSpacing, p.y, p.z)
                self:Spawn(killed.fishId, killed.mult, pos, drop.ItemId)
            end
        end
    else
        self:Spawn(killed.fishId, killed.mult, killed.position)
    end
end

-- 落点归入水平距离最近的钓鱼区
function Mgr:ZoneAt(pos)
    local best, bestDist
    for _, zone in ipairs(GameCfg.Water.Zones) do
        local dx, dz = pos.x - zone.Center.x, pos.z - zone.Center.z
        local dist = dx * dx + dz * dz
        if not bestDist or dist < bestDist then best, bestDist = zone, dist end
    end
    return best and best.Id or nil
end

-- 鱼获计入所属区 FIFO 队列，并立刻执行上限检查
function Mgr:Track(loot)
    local zoneId = self:ZoneAt(loot.Position)
    if not zoneId then return end
    loot.ZoneId = zoneId
    local queue = self.ZoneQueues[zoneId]
    if not queue then
        queue = {}
        self.ZoneQueues[zoneId] = queue
    end
    queue[#queue + 1] = loot.Id
    self:EnforceCap(zoneId)
end

-- 从区队列与待回收里摘除（拾取成功时调用）
function Mgr:Untrack(loot)
    self.Recycling[loot.Id] = nil
    local queue = loot.ZoneId and self.ZoneQueues[loot.ZoneId]
    if not queue then return end
    for i, id in ipairs(queue) do
        if id == loot.Id then
            table.remove(queue, i)
            return
        end
    end
end

-- 超上限时把最旧的鱼获移入待回收（不计入区总量，闪烁后销毁）
function Mgr:EnforceCap(zoneId)
    local queue = self.ZoneQueues[zoneId]
    local cap = cfg().PerZoneCap
    while queue and cap and #queue > cap do
        local id = table.remove(queue, 1)
        local loot = self.Loots[id]
        if loot then
            local now = self:Now()
            self.Recycling[id] = { At = now + cfg().FlashBeforeRecycleSec, NextFlash = now, Visible = true }
            print('[MgrLoot] 待回收', loot.ItemId, 'loot=' .. tostring(id), 'zone=' .. zoneId)
        end
    end
end

function Mgr:Spawn(fishId, mult, pos, itemId)
    local species = GameCfg.Fish[fishId]
    if not species then return nil end
    local position = Vector3.New(pos.x, self:Ground(pos) + cfg().Height, pos.z)
    self.NextId = self.NextId + 1
    local id = self.NextId
    local world = game:GetService('World')
    local ok, unit = pcall(world.CreateUnit, world, 'WorldUnit', {
        Name = 'FishLoot_' .. tostring(id),
        Position = position,
        RenderMeshId = 'official://mesh/' .. tostring(species.Model),
        BodyType = 1, -- Enums.BodyType.Static
        PhysicsActive = false,
        GravityEnabled = false,
        CanCollide = false,
        Liftable = false,
    })
    if not ok or not unit then
        print('[MgrLoot] 鱼获实体创建失败', fishId, tostring(unit))
        return nil
    end
    local loot = { Id = id, Kind = 'fish', ItemId = itemId or fishId, FishId = fishId, Mult = mult, Position = position, Unit = unit }
    self.Loots[id] = loot
    self:Track(loot)
    print('[MgrLoot] 生成鱼获', loot.ItemId, mult, 'loot=' .. tostring(id))
    self:Broadcast()
    return loot
end

local function distance(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- 拾取：谁先到谁得；成功返回 true。满格回一句提示并保留地上的鱼获
function Mgr:Pickup(player, id)
    if type(id) ~= 'number' or id ~= math.floor(id) then return false end
    local loot = self.Loots[id]
    local data = loot and self.PlayerData and self.PlayerData:GetDataInst(player)
    local character = player and player.Character
    local pos = character and character.Position
    if not data or not pos then return false end
    if distance(pos, loot.Position) > cfg().PickupRadius + cfg().PickupSlack then return false end
    self.Loots[id] = nil
    if loot.Kind == 'bait' then return self:GiveBait(player, data, loot) end
    if not data:AddItem(loot.ItemId, loot.Mult) then
        self.Loots[id] = loot
        self:Reply(player, { ok = false, reason = 'full', id = id })
        print('[MgrLoot] 背包已满，拒绝拾取', player.UserId, 'loot=' .. tostring(id))
        return false
    end
    self:Untrack(loot)
    pcall(function() loot.Unit:Destroy() end)
    print('[MgrLoot] 拾取', player.UserId, loot.ItemId, loot.Mult, 'loot=' .. tostring(id))
    self.PlayerData:SendItemBar(player)
    self:Reply(player, { ok = true, id = id })
    self:Broadcast()
    return true
end

function Mgr:GiveBait(player, data, loot)
    if not data:AddBait(loot.ItemId, loot.Count) then
        self.Loots[loot.Id] = loot
        return false
    end
    self:Untrack(loot)
    pcall(function() loot.Unit:Destroy() end)
    local spot = self.Spots[loot.SpotId]
    if spot then
        spot.LootId = nil
        spot.RespawnAt = self:Now() + GameCfg.BaitSpots.RespawnSec
    end
    print('[MgrLoot] 拾饵', player.UserId, loot.ItemId, loot.Count, 'spot=' .. tostring(loot.SpotId), 'loot=' .. tostring(loot.Id))
    -- 新手任务事实（#51）：鱼饵 id 全局唯一、每份只能被拾一次，用作 eventId
    if self.Quest then
        self.Quest:Notify('PickBait', player, { itemId = loot.ItemId, count = loot.Count, eventId = 'loot:' .. tostring(loot.Id) })
    end
    self.PlayerData:SendItemBar(player)
    self:Reply(player, { ok = true, id = loot.Id })
    self:Broadcast()
    return true
end

function Mgr:Now()
    return game:GetService('World'):GetServerTime()
end

-- 在点位生成一份鱼饵；该点位已有一份就不生成
function Mgr:SpawnBait(spotCfg)
    local spot = self.Spots[spotCfg.Id]
    if not spot or spot.LootId then return nil end
    local c = GameCfg.BaitSpots
    local p = spotCfg.Position
    for _, zone in ipairs(GameCfg.Water.Zones) do
        if MathWaterJudge.InZone(zone, { x = p.x, y = zone.SurfaceY, z = p.z }) then
            print('[MgrLoot] 鱼饵点位在水区，跳过刷新', spotCfg.Id, zone.Id)
            return nil
        end
    end
    local groundY, hit = self:Ground(p)
    if not hit or hit.Normal and hit.Normal.y < 0.5 then
        print('[MgrLoot] 鱼饵点位未命中陆地，跳过刷新', spotCfg.Id)
        spot.RespawnAt = self:Now() + c.RespawnSec
        return nil
    end
    local position = Vector3.New(p.x, groundY + cfg().Height, p.z)
    self.NextId = self.NextId + 1
    local id = self.NextId
    local world = game:GetService('World')
    local ok, unit = pcall(world.CreateUnit, world, 'WorldUnit', {
        Name = 'BaitSpot_' .. tostring(spotCfg.Id) .. '_' .. tostring(id),
        Position = position,
        RenderMeshId = c.Mesh,
        Scale = Vector3.New(c.Scale, c.Scale, c.Scale),
        BodyType = 1, -- Enums.BodyType.Static
        PhysicsActive = false,
        GravityEnabled = false,
        CanCollide = false,
        Liftable = false,
    })
    if not ok or not unit then
        print('[MgrLoot] 点位鱼饵创建失败', spotCfg.Id, tostring(unit))
        spot.RespawnAt = self:Now() + c.RespawnSec
        return nil
    end
    local loot = { Id = id, Kind = 'bait', ItemId = spotCfg.ItemId, Count = spotCfg.Count or 1,
        SpotId = spotCfg.Id, Position = position, Unit = unit }
    self.Loots[id] = loot
    spot.LootId = id
    spot.RespawnAt = nil
    print('[MgrLoot] 点位刷新鱼饵', spotCfg.Id, spotCfg.ItemId, 'loot=' .. tostring(id))
    self:Broadcast()
    return loot
end

function Mgr:StartSpots()
    for _, spotCfg in ipairs(GameCfg.BaitSpots.Spots) do
        self.Spots[spotCfg.Id] = { Cfg = spotCfg }
        self:SpawnBait(spotCfg)
    end
end

function Mgr:Start()
    MgrFishCarrier:SubscribeDied(function(carrier) self:OnCarrierDied(carrier) end)
    self:Listen()
    self:StartSpots()
end

function Mgr:Listen()
    _G.REUtil:GetRE('RequestLoot').OnServerEvent:Connect(function(player)
        _G.REUtil:GetRE('LootState'):FireClient(player, self:Snapshot())
    end)
end

function Mgr:Update()
    local now
    for _, spot in pairs(self.Spots) do
        if spot.RespawnAt then
            now = now or self:Now()
            if now >= spot.RespawnAt then self:SpawnBait(spot.Cfg) end
        end
    end
    local expired
    for id, entry in pairs(self.Recycling) do
        now = now or self:Now()
        if now >= entry.At then
            expired = expired or {}
            expired[#expired + 1] = id
        elseif now >= entry.NextFlash then
            -- 服务端驱动闪烁：可见性按固定间隔来回切换（WorldUnit 的可见性是 ModelVisible）
            local loot = self.Loots[id]
            if loot then
                entry.Visible = not entry.Visible
                local visible = entry.Visible
                local ok, err = pcall(function() loot.Unit.ModelVisible = visible end)
                if not ok and not entry.FlashFailed then
                    entry.FlashFailed = true
                    print('[MgrLoot] 闪烁失败', id, tostring(err))
                end
            end
            entry.NextFlash = now + FLASH_INTERVAL
        end
    end
    for _, id in ipairs(expired or {}) do
        local loot = self.Loots[id]
        if loot then
            local ok, err = pcall(function() loot.Unit:Destroy() end)
            if not ok then
                -- 销毁失败：记录与单位都保留，5 秒后重试，不报成功
                print('[MgrLoot] 回收销毁失败', id, tostring(err))
                self.Recycling[id].At = now + 5
            else
                self.Loots[id] = nil
                self.Recycling[id] = nil
                print('[MgrLoot] 回收', loot.ItemId, 'loot=' .. tostring(id), 'zone=' .. tostring(loot.ZoneId))
            end
        else
            self.Recycling[id] = nil
        end
    end
    if expired then self:Broadcast() end
end

return Mgr

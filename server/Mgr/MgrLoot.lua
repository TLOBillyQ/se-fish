-- 鱼获与拾取管理器（#43）：鱼载体死亡单点（MgrFishCarrier:SubscribeDied）里向活鱼管理器取走被打死的鱼，
-- 在地面生成一份携带鱼种与个体倍率的鱼获；鱼获静止、不参与物理、不消失，被拾取即销毁。
-- 拾取走道具栏动作通道（ItemBarAction{action='Pickup', value=<lootId>}），服务端复验目标、距离、空格；
-- 先删记录再发放，重放与多人争抢都只发一份。鱼获列表经 LootState 广播给客户端画「拾取」文字泡。
-- 固定点位鱼饵（#45）共用这套记录、广播与拾取复验：Kind='bait'，拾取进 Bait 计数库存（不占格），
-- 成功后该点位 RespawnSec 秒刷新一份新的（新 id，旧 id 重放无效）；鱼获（Kind='fish'）不刷新、不消失。
local GameCfg = require('common.GameCfg')
local MgrFishCarrier = require('server.Mgr.MgrFishCarrier')

local Mgr = { Loots = {}, NextId = 0, Spots = {} }

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
        if ok and hit and hit.Position then return hit.Position.y end
    end
    return pos.y
end

function Mgr:OnCarrierDied(carrier)
    local fish = self.FishUnit and self.FishUnit:FindByCarrier(carrier)
    local killed = fish and self.FishUnit:TakeKilled(fish)
    if not killed or not killed.position then return end
    self:Spawn(killed.fishId, killed.mult, killed.position)
end

function Mgr:Spawn(fishId, mult, pos)
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
    local loot = { Id = id, Kind = 'fish', ItemId = fishId, FishId = fishId, Mult = mult, Position = position, Unit = unit }
    self.Loots[id] = loot
    print('[MgrLoot] 生成鱼获', fishId, mult, 'loot=' .. tostring(id))
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
    if not data:AddItem(loot.FishId, loot.Mult) then
        self.Loots[id] = loot
        self:Reply(player, { ok = false, reason = 'full', id = id })
        print('[MgrLoot] 道具栏已满，拒绝拾取', player.UserId, 'loot=' .. tostring(id))
        return false
    end
    pcall(function() loot.Unit:Destroy() end)
    print('[MgrLoot] 拾取', player.UserId, loot.FishId, loot.Mult, 'loot=' .. tostring(id))
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
    pcall(function() loot.Unit:Destroy() end)
    local spot = self.Spots[loot.SpotId]
    if spot then
        spot.LootId = nil
        spot.RespawnAt = self:Now() + GameCfg.BaitSpots.RespawnSec
    end
    print('[MgrLoot] 拾饵', player.UserId, loot.ItemId, loot.Count, 'spot=' .. tostring(loot.SpotId), 'loot=' .. tostring(loot.Id))
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
    local position = Vector3.New(p.x, self:Ground(p) + cfg().Height, p.z)
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
end

return Mgr

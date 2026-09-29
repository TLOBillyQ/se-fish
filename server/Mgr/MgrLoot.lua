-- 鱼获与共享地面实例管理器（#43、#126 T05）：
-- 鱼载体死亡单点（MgrFishCarrier:SubscribeDied）里向活鱼管理器取走被打死的鱼，在地面生成一份携带鱼种与
-- 个体倍率的鱼获；鱼获静止、不参与物理、不消失，被拾取即销毁。拾取走道具栏动作通道
-- （ItemBarAction{action='Pickup', value=<lootId>}），服务端复验目标、距离、空格；先删记录再发放，
-- 重放与多人争抢都只发一份。鱼获列表经 LootState 广播给客户端画「拾取」文字泡。
-- 固定点位鱼饵（#45）共用这套记录、广播与拾取复验：Kind='bait'，拾取进 Bait 计数库存（不占格），
-- 成功后该点位 RespawnSec 秒刷新一份新的（新 id，旧 id 重放无效）；鱼获（Kind='fish'）不刷新、不消失。
-- 分区上限回收（#91/#126，GameSpec §6.5）：掉落物按落点归入最近的**钓鱼区**（Water.Zones[*].ZoneId），
-- 同区的多块水域（鱼塘两个水圈与池壁拼接条）共用一份 PerZoneCap 预算；超上限最旧的进入待回收：
-- 可见性来回闪烁 FlashBeforeRecycleSec 秒后销毁；待回收不计入区总量（但另有 PendingCap 封顶，见
-- EnforcePending）、仍可拾取，拾取即取消回收。点位鱼饵不占区上限。
-- 主动丢弃（#124 契约、#126 落地）：Kind='item' 承载信物/首领饵/船票/鱼饵/武器/烤鱼等一切可丢弃品，
-- 实例属性（个体倍率 Mult、烤制状态 Cooked）随地面实例走，拾回按物品表的容器原样还原（鱼饵回计数、
-- 武器回武器库存、其余回道具栏/背包）。三段式：PrepareDrop 预留（校验身份/库存/位置，并**先生成隐藏实例**）
-- → 调用方扣件 → CommitDrop 上屏并入区队列；CancelDrop 释放预留。生成在扣件之前，实例建不出来就整体
-- 不成立（#124 遗留边界）；CommitDrop 若发现实例已失（件已扣），把物品按原属性退回库存（补偿只做一次）。
-- 盲盒满格溢出一类「不经先扣后落」的来源复用 SpawnItem 直接落地。
local GameCfg = require('common.GameCfg')
local MathWaterJudge = require('common.MathWaterJudge')
local MgrFishCarrier = require('server.Mgr.MgrFishCarrier')

local Mgr = { Loots = {}, NextId = 0, Spots = {}, ZoneQueues = {}, PendingQueues = {}, Recycling = {},
    ZoneStats = {}, Reserved = {} }

local function cfg()
    return GameCfg.Loot
end

local function isWeapon(definition)
    return definition ~= nil and (definition.Type == '近战武器' or definition.Type == '远程武器')
end

function Mgr:Broadcast()
    _G.REUtil:GetRE('LootState'):FireAllClients(self:Snapshot())
end

function Mgr:Reply(player, payload)
    _G.REUtil:GetRE('LootResult'):FireClient(player, payload)
end

-- warn = 该件在 30 秒预警期内（待回收），客户端据此闪文字泡
function Mgr:Snapshot()
    local list = {}
    for _, loot in pairs(self.Loots) do
        local row = { id = loot.Id, kind = loot.Kind, fishId = loot.FishId, itemId = loot.ItemId,
            x = loot.Position.x, y = loot.Position.y, z = loot.Position.z }
        if self.Recycling[loot.Id] then row.warn = true end
        list[#list + 1] = row
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

-- 销毁世界单位：失败只记日志，不改变业务结果（回收另有重试路径）
local function destroyUnit(unit, why, id)
    local ok, err = pcall(function() unit:Destroy() end)
    if not ok then print('[MgrLoot] 实例销毁失败', why, tostring(id), tostring(err)) end
    return ok
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

-- 落点归入水平距离最近的钓鱼区（Water.Zones[*].ZoneId）：同区多块水域共用一份预算
function Mgr:RegionAt(pos)
    local best, bestDist
    for _, zone in ipairs(GameCfg.Water.Zones) do
        local dx, dz = pos.x - zone.Center.x, pos.z - zone.Center.z
        local dist = dx * dx + dz * dz
        if not bestDist or dist < bestDist then best, bestDist = zone, dist end
    end
    return best and (best.ZoneId or best.Id) or nil
end

-- 分区计数与峰值台账（#126 验收③：连续大量生成时用日志证明活跃/待回收有界）
function Mgr:Stats(zoneId)
    local stat = self.ZoneStats[zoneId]
    if not stat then
        stat = { Active = 0, Pending = 0, PeakActive = 0, PeakPending = 0, Recycled = 0, RecycledEarly = 0 }
        self.ZoneStats[zoneId] = stat
    end
    return stat
end

function Mgr:NotePeak(zoneId)
    local stat = self:Stats(zoneId)
    local active, pending = #(self.ZoneQueues[zoneId] or {}), #(self.PendingQueues[zoneId] or {})
    stat.Active, stat.Pending = active, pending
    if active > stat.PeakActive or pending > stat.PeakPending then
        stat.PeakActive, stat.PeakPending = math.max(stat.PeakActive, active), math.max(stat.PeakPending, pending)
        print('[MgrLoot] 区峰值 zone=' .. tostring(zoneId), 'active=' .. active, 'pending=' .. pending,
            'cap=' .. tostring(cfg().PerZoneCap), 'pendingCap=' .. tostring(cfg().PendingCap))
    end
end

-- 掉落物计入所属区 FIFO 队列，并立刻执行上限检查
function Mgr:Track(loot)
    local zoneId = self:RegionAt(loot.Position)
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

-- 从区队列与待回收里摘除（拾取成功时调用）；按显式下标遍历，避免某一边为空时 ipairs 提前中止
function Mgr:Untrack(loot)
    local zoneId = loot.ZoneId
    self.Recycling[loot.Id] = nil
    local lists = { zoneId and self.PendingQueues[zoneId], zoneId and self.ZoneQueues[zoneId] }
    for index = 1, 2 do
        local list = lists[index]
        if list then
            for i, id in ipairs(list) do
                if id == loot.Id then table.remove(list, i) break end
            end
        end
    end
    if zoneId then self:NotePeak(zoneId) end
end

-- 超上限时把最旧的掉落物移入待回收（不计入区总量，闪烁后销毁）
function Mgr:EnforceCap(zoneId)
    local queue = self.ZoneQueues[zoneId]
    local cap = cfg().PerZoneCap
    while queue and cap and #queue > cap do
        local id = table.remove(queue, 1)
        local loot = self.Loots[id]
        if loot then self:MarkRecycling(loot) end
        self:EnforcePending(zoneId)
    end
    self:NotePeak(zoneId)
end

function Mgr:MarkRecycling(loot)
    local now = self:Now()
    self.Recycling[loot.Id] = { At = now + cfg().FlashBeforeRecycleSec, NextFlash = now, Visible = true }
    local pending = self.PendingQueues[loot.ZoneId]
    if not pending then
        pending = {}
        self.PendingQueues[loot.ZoneId] = pending
    end
    pending[#pending + 1] = loot.Id
    print('[MgrLoot] 待回收', loot.ItemId, 'loot=' .. tostring(loot.Id), 'zone=' .. tostring(loot.ZoneId),
        'after=' .. tostring(cfg().FlashBeforeRecycleSec) .. 's')
end

-- 预警期也有上限：待回收件不算 PerZoneCap，不封顶则「活跃 200 + 预警无限」仍会涨；
-- 超过 PendingCap 时立刻回收最旧的预警件（跳过剩余预警），单区总量恒 ≤ PerZoneCap + PendingCap
function Mgr:EnforcePending(zoneId)
    local pending = self.PendingQueues[zoneId]
    local cap = cfg().PendingCap
    while pending and cap and #pending > cap do
        local id = table.remove(pending, 1)
        if self.Recycling[id] then
            local stat = self:Stats(zoneId)
            stat.RecycledEarly = stat.RecycledEarly + 1
            self:Recycle(id, '预警超限即回收')
        end
    end
end

-- 回收一件：销毁世界单位、摘记录与计时；销毁失败保留记录、按 RecycleRetrySec 后重试，不报成功
function Mgr:Recycle(id, why)
    local loot = self.Loots[id]
    if not loot then
        self.Recycling[id] = nil
        return false
    end
    local ok, err = pcall(function() loot.Unit:Destroy() end)
    if not ok then
        print('[MgrLoot] 回收销毁失败', id, tostring(err))
        local entry = self.Recycling[id]
        if entry then entry.At = self:Now() + cfg().RecycleRetrySec end
        return false
    end
    self.Loots[id] = nil
    self.Recycling[id] = nil
    local pending = self.PendingQueues[loot.ZoneId]
    if pending then
        for i, value in ipairs(pending) do
            if value == id then table.remove(pending, i) break end
        end
    end
    local stat = self:Stats(loot.ZoneId or 'unknown')
    stat.Recycled = stat.Recycled + 1
    self:NotePeak(loot.ZoneId or 'unknown')
    print('[MgrLoot] 回收', loot.ItemId, 'loot=' .. tostring(id), 'zone=' .. tostring(loot.ZoneId), why or '',
        'active=' .. #(self.ZoneQueues[loot.ZoneId] or {}), 'pending=' .. #(self.PendingQueues[loot.ZoneId] or {}),
        'recycled=' .. stat.Recycled)
    return true
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

-- 掉落物外观：鱼获用鱼种模型，其余（信物/鱼饵/武器/船票/烤鱼）用通用落物外观
function Mgr:MeshOf(itemId)
    local species = GameCfg.Fish[itemId]
    if species and species.Model then return 'official://mesh/' .. tostring(species.Model) end
    local scale = cfg().ItemScale
    return cfg().ItemMesh, Vector3.New(scale, scale, scale)
end

-- 建一份掉落物实例（含世界单位）但不登记：预留期不进 Loots / 区队列 / 快照，外部也拾不到
local function createLoot(self, itemId, mult, cooked, position)
    self.NextId = self.NextId + 1
    local id = self.NextId
    local mesh, scale = self:MeshOf(itemId)
    local world = game:GetService('World')
    local values = {
        Name = 'ItemDrop_' .. tostring(id),
        Position = position,
        RenderMeshId = mesh,
        BodyType = 1, -- Enums.BodyType.Static
        PhysicsActive = false,
        GravityEnabled = false,
        CanCollide = false,
        Liftable = false,
        ModelVisible = false, -- 预留期隐藏；上屏（Live）才显示
    }
    if scale then values.Scale = scale end
    local ok, unit = pcall(world.CreateUnit, world, 'WorldUnit', values)
    if not ok or not unit then
        print('[MgrLoot] 掉落实例创建失败', itemId, tostring(unit))
        return nil, 'spawn-failed'
    end
    return { Id = id, Kind = 'item', ItemId = itemId, Mult = mult, Cooked = cooked, Position = position, Unit = unit }
end

-- 上屏：登记、进区队列（含 FIFO 回收）、显示模型、广播
function Mgr:Live(loot)
    self.Loots[loot.Id] = loot
    local ok, err = pcall(function() loot.Unit.ModelVisible = true end)
    if not ok then print('[MgrLoot] 掉落实例显示失败', loot.Id, tostring(err)) end
    self:Track(loot)
    print('[MgrLoot] 生成掉落', loot.ItemId, loot.Mult, 'loot=' .. tostring(loot.Id), 'zone=' .. tostring(loot.ZoneId))
    self:Broadcast()
    return loot
end

-- 满格落地入口（#126）：不经「先扣后落」的来源（盲盒等）直接在一处生成地面实例，保留倍率与烤制状态
function Mgr:SpawnItem(itemId, mult, cooked, pos)
    if type(itemId) ~= 'string' or not GameCfg.Items.Definitions[itemId] then return nil, 'bad-item' end
    if type(pos) ~= 'table' or type(pos.x) ~= 'number' or type(pos.z) ~= 'number' then return nil, 'bad-position' end
    local position = Vector3.New(pos.x, self:Ground(pos) + cfg().Height, pos.z)
    local loot, reason = createLoot(self, itemId, mult, cooked, position)
    if not loot then return nil, reason end
    return self:Live(loot)
end

-- 「丢弃落物」payload 校验：物品表里有定义、倍率与烤制值在存档允许范围
local function validated(drop)
    if type(drop) ~= 'table' then return nil, 'bad-item' end
    local itemId = drop.itemId
    if type(itemId) ~= 'string' or not GameCfg.Items.Definitions[itemId] then return nil, 'bad-item' end
    local mult = drop.mult
    if mult ~= nil and (type(mult) ~= 'number' or mult < 1 or mult > 2) then return nil, 'bad-item' end
    local cooked = drop.cooked
    if cooked ~= nil and (type(cooked) ~= 'number' or cooked < 1 or cooked ~= cooked or cooked >= math.huge) then
        return nil, 'bad-item'
    end
    return { itemId = itemId, mult = mult, cooked = cooked }
end

-- 库存校验：丢弃的必须是玩家真实持有的一件（给了格号就核格号，否则核道具栏/背包、武器、鱼饵计数）
local function owns(data, drop)
    if type(drop.slot) == 'number' and drop.slot == math.floor(drop.slot) then
        local snapshot = data:GetItemBarSnapshot()
        local entry = snapshot and snapshot.slots[drop.slot]
        return entry ~= nil and entry.count > 0 and entry.itemId == drop.itemId
    end
    return data:ItemCount(drop.itemId) >= 1 or data:WeaponCount(drop.itemId) >= 1 or data:HasBait(drop.itemId)
end

local function forwardOf(character)
    local fx, fz
    pcall(function()
        local forward = character.Rotation:GetForward()
        local length = math.sqrt(forward.x * forward.x + forward.z * forward.z)
        if length >= 0.01 then fx, fz = forward.x / length, forward.z / length end
    end)
    return fx or 0, fz or 0
end

-- 丢弃预留（#124 契约：PrepareDrop(player, drop) -> reservation|nil, reason）。
-- 校验失败一律不生成、调用方也就不会扣件；生成失败同样在此返回 spawn-failed（先建后扣，没有半成品）。
function Mgr:PrepareDrop(player, drop)
    local data = self.PlayerData and self.PlayerData:GetDataInst(player)
    if not data then return nil, 'not-ready' end
    local item, reason = validated(drop)
    if not item then return nil, reason end
    if not owns(data, drop) then return nil, 'not-owned' end
    local character = player.Character
    local origin = character and character.Position
    if not origin then return nil, 'no-character' end
    -- 同一玩家只保留一个未结算预留：旧预留（上一次请求没走完）先释放，避免叠加隐藏实例
    local previous = self.Reserved[player.UserId]
    if previous then
        print('[MgrLoot] 丢弃预留被顶替，释放旧的', player.UserId, previous.Loot.ItemId)
        self:CancelDrop(player, previous)
    end
    local fx, fz = forwardOf(character)
    local pos = Vector3.New(origin.x + fx * cfg().DropOffset, origin.y, origin.z + fz * cfg().DropOffset)
    local position = Vector3.New(pos.x, self:Ground(pos) + cfg().Height, pos.z)
    local loot, failure = createLoot(self, item.itemId, item.mult, item.cooked, position)
    if not loot then return nil, failure end
    local reservation = { Player = player, Loot = loot, Done = false,
        Id = loot.Id, ItemId = loot.ItemId, Position = loot.Position, Unit = loot.Unit }
    self.Reserved[player.UserId] = reservation
    return reservation
end

-- 发放：按物品表容器把一件落物放进玩家库存（共享地面实例 → 库存的唯一路径）
function Mgr:Give(data, itemId, mult, cooked, count)
    local definition = GameCfg.Items.Definitions[itemId]
    if not definition then return false end
    count = count or 1
    if definition.Container == GameCfg.Items.ContainerId.Bait then return data:AddBait(itemId, count) end
    if isWeapon(definition) then return data:GrantWeapon(itemId, count) end
    if count > 1 then return false end
    return data:AddItem(itemId, mult, cooked)
end

-- 补偿（#124 遗留边界）：实例已失而件已扣，把物品按原实例属性退回库存；一次预留只补偿一次
function Mgr:Refund(player, reservation)
    local loot = reservation.Loot
    local data = self.PlayerData and self.PlayerData:GetDataInst(player)
    if not data or not self:Give(data, loot.ItemId, loot.Mult, loot.Cooked) then
        print('[MgrLoot] 丢弃补偿失败，物品未退回', player.UserId, loot.ItemId, 'loot=' .. tostring(loot.Id))
        return false, 'spawn-failed'
    end
    destroyUnit(loot.Unit, '丢弃补偿', loot.Id)
    self.PlayerData:SendItemBar(player)
    print('[MgrLoot] 丢弃落物生成失败，已退回物品', player.UserId, loot.ItemId, 'loot=' .. tostring(loot.Id))
    return false, 'spawn-failed'
end

-- 丢弃提交（#124 契约：CommitDrop(player, reservation, drop) -> ok, reason）。
-- 只在调用方已经扣件之后调用：成功即上屏并入区队列；重复调用不生成第二份；实例已失则退回库存。
function Mgr:CommitDrop(player, reservation, drop)
    if type(reservation) ~= 'table' or reservation.Player ~= player or type(reservation.Loot) ~= 'table' then
        return false, 'bad-reservation'
    end
    if self.Reserved[player.UserId] == reservation then self.Reserved[player.UserId] = nil end
    if reservation.Done then return false, reservation.Outcome == 'refunded' and 'refunded' or 'committed' end
    reservation.Done, reservation.Outcome = true, 'committed'
    local unit = reservation.Loot.Unit
    local alive = unit ~= nil and not unit.Destroyed
    if alive then
        local ok, err = pcall(function() unit.ModelVisible = true end)
        if not ok then
            alive = false
            print('[MgrLoot] 掉落实例显示失败', reservation.Loot.Id, tostring(err))
        end
    end
    if not alive then
        reservation.Outcome = 'refunded'
        return self:Refund(player, reservation)
    end
    self:Live(reservation.Loot)
    return true
end

-- 释放预留（持久写失败 / 请求被拒 / 玩家离开）：销毁隐藏实例，幂等
function Mgr:CancelDrop(player, reservation, drop)
    if type(reservation) ~= 'table' or reservation.Player ~= player or type(reservation.Loot) ~= 'table' then
        return false
    end
    if self.Reserved[player.UserId] == reservation then self.Reserved[player.UserId] = nil end
    if reservation.Done then return false end
    reservation.Done, reservation.Outcome = true, 'cancelled'
    destroyUnit(reservation.Loot.Unit, '取消预留', reservation.Loot.Id)
    print('[MgrLoot] 丢弃预留取消', player.UserId, reservation.Loot.ItemId, 'loot=' .. tostring(reservation.Loot.Id))
    return true
end

function Mgr:OnPlayerRemoving(player)
    local reservation = player and self.Reserved[player.UserId]
    if reservation then self:CancelDrop(player, reservation) end
end

-- 拾取：谁先到谁得；成功返回 true。满格回一句提示并保留地上的掉落物
function Mgr:Pickup(player, id)
    if type(id) ~= 'number' or id ~= math.floor(id) then return false end
    local loot = self.Loots[id]
    local data = loot and self.PlayerData and self.PlayerData:GetDataInst(player)
    local character = player and player.Character
    local pos = character and character.Position
    if not data or not pos then return false end
    if distance(pos, loot.Position) > cfg().PickupRadius + cfg().PickupSlack then return false end
    -- 唯一领取者：先摘记录再发放，重放 / 抢拾都拿不到第二份；发放失败放回，留给下一位
    self.Loots[id] = nil
    if loot.Kind == 'bait' then return self:GiveBait(player, data, loot) end
    if not self:Give(data, loot.ItemId, loot.Mult, loot.Cooked, loot.Count) then
        self.Loots[id] = loot
        self:Reply(player, { ok = false, reason = 'full', id = id })
        print('[MgrLoot] 背包已满，拒绝拾取', player.UserId, 'loot=' .. tostring(id))
        return false
    end
    self:Untrack(loot)
    destroyUnit(loot.Unit, '拾取', id)
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
    destroyUnit(loot.Unit, '拾饵', loot.Id)
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
            entry.NextFlash = now + (cfg().FlashIntervalSec or 0.5)
        end
    end
    if not expired then return end
    for _, id in ipairs(expired) do self:Recycle(id, '预警到期') end
    self:Broadcast()
end

return Mgr

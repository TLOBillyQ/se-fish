-- 活鱼单位管理器（#37 起）：上岸结算交来的活鱼在这里登记，M2 在此之上接抓举 / 放下 / 逃脱 / 死亡。
-- 一条活鱼只记上钩时定下的鱼种与个体倍率；重量、售价随取随算（FishCatch.Weight / Price），不存快照。
local GameCfg = require('common.GameCfg')
local FishCatch = require('common.FishCatch')
local MgrFishCarrier = require('server.Mgr.MgrFishCarrier')

local Mgr = { Fish = {}, NextId = 0 }

Mgr.State = { AwaitLift = 'awaitLift' }

-- 在 position 生成一条归属 player 的待举起活鱼；载体建不出来返回 nil 与原因
function Mgr:SpawnLanded(player, catch, position)
    local species = catch and GameCfg.Fish[catch.fishId]
    if not player or not species or type(catch.mult) ~= 'number' then return nil, 'bad-catch' end
    local carrier, err = MgrFishCarrier:Spawn({
        Position = position,
        FishId = catch.fishId,
        MaxHealth = species.Health,
        ModelId = species.Model,
        Player = player,
    })
    if not carrier then return nil, err end
    self.NextId = self.NextId + 1
    local fish = { Id = self.NextId, Owner = player, FishId = catch.fishId, Mult = catch.mult,
        Carrier = carrier, State = Mgr.State.AwaitLift }
    self.Fish[fish.Id] = fish
    return fish
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
    MgrFishCarrier:Despawn(fish.Carrier)
end

-- 主人离线：还没被举起的鱼一并清掉，避免场上留下无主的鱼
function Mgr:OnPlayerRemoving(player)
    for _, fish in ipairs(self:GetFish(player)) do
        if fish.State == Mgr.State.AwaitLift then self:Remove(fish) end
    end
end

return Mgr

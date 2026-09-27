-- #88 探针②（server 端）：远离水面放首领进战斗，验证追咬与击杀掉落
local MgrFishUnit = require('server.Mgr.MgrFishUnit')
local MgrLoot = require('server.Mgr.MgrLoot')
local Task = game:GetService('Task')

local player = game:GetService('Players'):GetPlayers()[1]

-- 水面 (x -17.75..-5.75, z 21.75..33.75)，传送到远处陆地再生成
player.Character.Position = Vector3.New(-11.75, 2.2, 8)
local origin = player.Character.Position
local fish = MgrFishUnit:SpawnLanded(player, { fishId = 'alligatorGar', mult = 1 },
    Vector3.New(origin.x + 2, origin.y + 0.5, origin.z))
print('PROBE88B spawned fish=' .. tostring(fish and fish.Id))

Task:Delay(4, function()
    print('PROBE88B beforeDrop state=' .. tostring(fish.State))
    MgrFishUnit:Drop(player)
    print('PROBE88B dropped state=' .. tostring(fish.State))
    local healthBefore = player.Character.Controller.Health
    Task:Delay(6, function()
        local healthAfter = player.Character.Controller.Health
        print('PROBE88B bite health ' .. tostring(healthBefore) .. '->' .. tostring(healthAfter)
            .. ' state=' .. tostring(fish.State))
        local receiver = fish.Carrier and fish.Carrier.Receiver
        if receiver and receiver.Controller then
            receiver.Controller:TakeDamage(9999)
        end
        Task:Delay(1.5, function()
            local meat, head = 0, 0
            for _, loot in pairs(MgrLoot.Loots) do
                if loot.ItemId == 'garMeat' then meat = meat + 1 end
                if loot.ItemId == 'garHead' then head = head + 1 end
            end
            print('PROBE88B loot garMeat=' .. meat .. ' garHead=' .. head)
            print('PROBE88B DONE')
        end)
    end)
end)

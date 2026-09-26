-- #88 探针③（server 端）：在玩家当前所在的安全地面生成首领，验证追咬与击杀掉落增量
local MgrFishUnit = require('server.Mgr.MgrFishUnit')
local MgrLoot = require('server.Mgr.MgrLoot')
local Task = game:GetService('Task')

local player = game:GetService('Players'):GetPlayers()[1]

local function countLoot()
    local meat, head = 0, 0
    for _, loot in pairs(MgrLoot.Loots) do
        if loot.ItemId == 'garMeat' then meat = meat + 1 end
        if loot.ItemId == 'garHead' then head = head + 1 end
    end
    return meat, head
end

Task:Delay(1, function()
    local controller = player.Character and player.Character.Controller
    local origin = player.Character.Position
    print('PROBE88C player health=' .. tostring(controller and controller.Health)
        .. ' pos=' .. tostring(origin))
    local fish = MgrFishUnit:SpawnLanded(player, { fishId = 'alligatorGar', mult = 1 },
        Vector3.New(origin.x + 3, origin.y + 0.5, origin.z))
    print('PROBE88C spawned fish=' .. tostring(fish and fish.Id))
    local meat0, head0 = countLoot()

    Task:Delay(4, function()
        print('PROBE88C beforeDrop state=' .. tostring(fish.State))
        MgrFishUnit:Drop(player)
        print('PROBE88C dropped state=' .. tostring(fish.State))
        local healthBefore = controller.Health
        Task:Delay(6, function()
            local healthAfter = controller.Health
            print('PROBE88C bite health ' .. tostring(healthBefore) .. '->' .. tostring(healthAfter)
                .. ' state=' .. tostring(fish.State))
            local receiver = fish.Carrier and fish.Carrier.Receiver
            if receiver and receiver.Controller then
                receiver.Controller:TakeDamage(9999)
            end
            Task:Delay(1.5, function()
                local meat1, head1 = countLoot()
                print('PROBE88C loot delta garMeat=' .. (meat1 - meat0) .. ' garHead=' .. (head1 - head0))
                print('PROBE88C DONE')
            end)
        end)
    end)
end)

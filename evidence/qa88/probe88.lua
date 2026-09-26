-- #88 试玩验收探针（server 端）：挂鸭子必出鳄雀鳝 / 首领战追咬与掉落 / 饵消耗不返还
local GameCfg = require('common.GameCfg')
local MgrCast = require('server.Mgr.MgrCast')
local MgrFishUnit = require('server.Mgr.MgrFishUnit')
local MgrLoot = require('server.Mgr.MgrLoot')
local MgrPlayerData = _G.MgrPlayerData
local Task = game:GetService('Task')

local player = game:GetService('Players'):GetPlayers()[1]
local data = MgrPlayerData:GetDataInst(player)
local world = game:GetService('World')

local function slotOf(itemId)
    local bar = data.Data.Containers.itemBar
    for i = 1, data:ItemBarCapacity() do
        if bar[i] and bar[i].itemId == itemId then return i end
    end
end

-- ① 挂鸭子在水边抛竿
data:GrantItem('starterRod', 1)
data:GrantItem('duck', 1)
local rodSlot = slotOf('starterRod')
data:SelectSlot(rodSlot)
data:SelectBait('duck')
-- 传到水边（WaterCircle2 中心 (-11.75,27.75)，站 z=22 朝 +z，落点 5m 进水）
player.Character.Position = Vector3.New(-11.75, 2.2, 22)
player.Character.Rotation = Quaternion.FromEulerAngles(0, 0, 0)
MgrCast:Cast(player, { slot = rodSlot, itemId = 'starterRod' })
print('PROBE88 cast duck=' .. data:ItemCount('duck')
    .. ' session=' .. tostring(MgrCast.Sessions[player.UserId] ~= nil))

Task:Delay(4, function()
    local current = MgrCast.Sessions[player.UserId]
    local s = current and current.session
    print('PROBE88 hook phase=' .. tostring(s and s.phase)
        .. ' fishId=' .. tostring(s and s.fishId)
        .. ' duck=' .. data:ItemCount('duck'))
    -- 收线断会话（脱钩等价路径之一）：鸭子不应返还
    if s and s.phase == 'hooked' then
        MgrCast:FinishReel(player, s.reelSession, 'escaped')
    end
    print('PROBE88 afterEscape duck=' .. data:ItemCount('duck'))

    -- ② 首领战与掉落：上岸一条鳄雀鳝，举起放下进战斗
    local origin = player.Character.Position
    local fish = MgrFishUnit:SpawnLanded(player, { fishId = 'alligatorGar', mult = 1 },
        Vector3.New(origin.x, origin.y + 0.5, origin.z + 2))
    print('PROBE88 spawned fish=' .. tostring(fish and fish.Id))
    Task:Delay(4, function()
        print('PROBE88 beforeDrop state=' .. tostring(fish.State))
        MgrFishUnit:Drop(player)
        print('PROBE88 dropped state=' .. tostring(fish.State)
            .. ' fleeAt=' .. tostring(fish.FleeAt))
        local healthBefore = player.Character.Controller.Health
        Task:Delay(5, function()
            local healthAfter = player.Character.Controller.Health
            print('PROBE88 bite health ' .. tostring(healthBefore) .. '->' .. tostring(healthAfter)
                .. ' state=' .. tostring(fish.State))
            -- 击杀：对受击体造成致命伤害，走载体死亡订阅掉落实物
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
                print('PROBE88 loot garMeat=' .. meat .. ' garHead=' .. head)
                print('PROBE88 DONE')
            end)
        end)
    end)
end)

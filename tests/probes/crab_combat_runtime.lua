-- #136 独立战斗夹具：从真实SpawnLanded/Drop入口生成帝王蟹/蟹老板，用于招式表现取证。
-- 明确不作为自然抽鱼/从零经济证明；不修改血量、时间、玩家库存或奖励裁决。
local units = require('server.Mgr.MgrFishUnit')
local player = game:GetService('Players'):GetPlayers()[1]
if not player or not player.Character then return end
local id = _G.Crab136Species or 'fish23Elite'
_G.Crab136CombatToken = (_G.Crab136CombatToken or 0) + 1
local runId = _G.Crab136CombatToken
local p = player.Character.Position
local fish, err = units:SpawnLanded(player, { fishId = id, mult = 1 }, Vector3.New(p.x, p.y, p.z + 2))
print('CRAB136_FIXTURE', id, fish and fish.Id, err)
if fish then
    game:GetService('Task'):Delay(2, function()
        if _G.Crab136CombatToken == runId and units.Fish[fish.Id] == fish then
            units:Drop(player)
            print('CRAB136_RELEASE', fish.Id, fish.State, fish.Carrier.Health, fish.Carrier.Body.Position)
            if _G.Crab136Observe then
                local task = game:GetService('Task')
                task:Spawn(function()
                    local world = game:GetService('World')
                    local started, last = world:GetServerTime(), nil
                    while _G.Crab136CombatToken == runId and units.Fish[fish.Id] == fish and world:GetServerTime() - started < 70 do
                        local move = fish.Move
                        local name = move and move.Name or fish.State
                        if name ~= last then
                            print('CRAB136_BEHAVIOR', fish.Id, name, player.Character.Controller.Health,
                                fish.WakeAt, world:GetServerTime() - started)
                            last = name
                        end
                        if require('server.Mgr.MgrVitals'):CanAct(player) then
                            local fp = fish.Carrier.Body.Position
                            if fish.State ~= 'stunned' and name ~= 'spin' then
                                local forward = fish.Carrier.Body.Rotation:GetForward()
                                player.Character.Position = Vector3.New(fp.x - forward.x * 1.5, fp.y, fp.z - forward.z * 1.5)
                            elseif name == 'spin' then
                                -- 旋转波及周身 3 米：退出半径观察碰触
                                player.Character.Position = Vector3.New(fp.x + 6, fp.y, fp.z)
                            end
                        end
                        task:Wait(0.1)
                    end
                    print('CRAB136_BEHAVIOR_END', fish.Id, player.Character.Controller.Health)
                end)
            end
            if _G.Crab136Attack then
                local weapons = require('server.Mgr.MgrWeapon')
                local data = require('server.Mgr.MgrPlayerData'):GetDataInst(player)
                local world, task = game:GetService('World'), game:GetService('Task')
                local started = world:GetServerTime()
                print('CRAB136_INPUT', '主动定位并面向目标；真实攻击，不改血量/时间', data:WeaponDamageScale('melee'))
                task:Spawn(function()
                    while _G.Crab136CombatToken == runId and units.Fish[fish.Id] == fish and world:GetServerTime() - started < 100 do
                        local fp = fish.Carrier.Body.Position
                        local forward = fish.Carrier.Body.Rotation:GetForward()
                        local character = player.Character
                        if character and character.Controller and require('server.Mgr.MgrVitals'):CanAct(player) then
                            character.Position = Vector3.New(fp.x - forward.x * 1.5, fp.y, fp.z - forward.z * 1.5)
                            character.Rotation = fish.Carrier.Body.Rotation
                        end
                        local before = fish.Carrier.Health
                        local result = weapons:Attack(player)
                        print('CRAB136_ATTACK', fish.Id, before, result and result.ok, character and character.Controller and character.Controller.Health,
                            world:GetServerTime() - started)
                        task:Wait(0.5)
                    end
                    print('CRAB136_END', fish.Id, fish.State, fish.Carrier.Health, world:GetServerTime() - started)
                end)
            end
        end
    end)
end

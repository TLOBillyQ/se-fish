-- #37 真实服务端运行时观察探针，在已启动本图的服务端执行本文件全文。
-- 前置：玩家站在礁石岸边；正常路线先购买 item141 狙击枪和弹药。
-- _G.Reef37Species='fish47Elite'（白头鹰）或 'fish48Boss'（翼龙）；默认翼龙。
-- 首次执行生成战斗夹具，2 秒后经真实 Drop 放下；不改时间、血量、库存或攻击裁决。
-- 再次执行前 _G.Reef37Action='cleanup' 可停止观察并移除本次夹具。
-- 观察 35 秒可覆盖每 4 秒投掷与 20 秒俯冲；手动 input 射击/换弹/走出落点取证。
-- 轨迹目标/受击体同步误差与预警起落打印 REEF37_FRAME；本体读值可能有引擎延迟，单独记录。
-- 夹具不能证明自然抽鱼、从零经济、正常金币枪单杀；这些另走真实购买/钓鱼/input 路线。
local units=require('server.Mgr.MgrFishUnit')
local task=game:GetService('Task')
local world=game:GetService('World')
local player=game:GetService('Players'):GetPlayers()[1]
_G.Reef37Token=(_G.Reef37Token or 0)+1
local runNumber=_G.Reef37Token
if _G.Reef37Action=='cleanup' then
    local prior=_G.Reef37Fish
    if prior and units.Fish[prior.Id]==prior then units:Remove(prior) end
    _G.Reef37Fish=nil
    print('REEF37_CLEANUP',runNumber)
    return
end
if not player or not player.Character then print('REEF37_BLOCKED','没有玩家'); return end
local pos=player.Character.Position
local id=_G.Reef37Species or 'fish48Boss'
local fish,err=units:SpawnLanded(player,{fishId=id,mult=1},Vector3.New(pos.x,pos.y,pos.z+2))
print('REEF37_FIXTURE',id,fish and fish.Id,err)
if not fish then return end
_G.Reef37Fish=fish
task:Delay(2,function()
    if runNumber~=_G.Reef37Token or units.Fish[fish.Id]~=fish then return end
    print('REEF37_DROP',units:Drop(player),fish.State,fish.Carrier.Health)
    task:Spawn(function()
        local started=world:GetServerTime()
        local last
        local maxTargetError=0
        while runNumber == _G.Reef37Token and units.Fish[fish.Id]==fish and world:GetServerTime()-started<35 do
            local body,receiver=fish.Carrier.Body,fish.Carrier.Receiver
            local bp,rp=body.Position,receiver and receiver.Position
            local bodyError=rp and math.sqrt((bp.x-rp.x)^2+(bp.y-rp.y)^2+(bp.z-rp.z)^2)
            local flight=fish.Flight and fish.Flight.Pos
            local offset=fish.Carrier.ReceiverOffset
            local target=flight and {x=flight.x+offset.x,y=flight.y+offset.y,z=flight.z+offset.z}
            local error=rp and target and math.sqrt((target.x-rp.x)^2+(target.y-rp.y)^2+(target.z-rp.z)^2)
            if error then maxTargetError=math.max(maxTargetError,error) end
            local dive=fish.AirAttacks and fish.AirAttacks.airDive
            local throw=fish.AirAttacks and fish.AirAttacks.airThrow
            local phase=fish.State..':'..tostring(dive and dive.Id)..':'..tostring(throw and throw.Id)
            if phase~=last or (error and error>0.05) then
                print('REEF37_FRAME',fish.Id,phase,fish.Carrier.Health,player.Character.Controller.Health,
                    bp,'targetError',error,'bodyReadError',bodyError,world:GetServerTime()-started)
                last=phase
            end
            task:Wait(0.1)
        end
        print('REEF37_END',fish.Id,fish.State,fish.Carrier.Health,world:GetServerTime()-started,
            'maxTargetError',maxTargetError)
    end)
end)

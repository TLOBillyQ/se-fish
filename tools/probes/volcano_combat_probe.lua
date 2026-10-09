-- #38 可重跑服务端触发探针：由编辑器 exec 加载后显式调用，不自动加载。
-- 仅在独立验收存档中使用；不改配置、不伪造平台成功、不触碰其他玩家的鱼。
-- 步骤：
-- 1. Spawn(player,'fish55Elite',true)，等待真实 Lift 回调，再 Drop(player,id)。
-- 2. 每秒 Snapshot(player,id)；15秒后观察预警、落地、叼人、入水与甩头。
-- 3. 哥斯拉换 fish56Boss；Damage(id,11000) 触发56%入水，再 Damage(id,10000) 触发16%狂暴。
-- 4. 单帧跨阈值另起一条 Damage(id,21000)；观察唯一最终阶段。
-- 5. 吐息等30秒起手后侧移4米，另轮站在线内；死亡/离线由真实玩法触发。
-- 6. Snapshot 只回读本地成就与送达标记；平台ID缺失时只能记为缺证。
-- Cleanup(id) 仅清本探针创建的鱼；测试过程中原有主循环持续运行。
local Probe={Owned={}}
local Fish=require('server.Mgr.MgrFishUnit')
local Data=require('server.Mgr.MgrPlayerData')
local Cfg=require('common.GameCfg')
local function point(unit)
    if not unit then return nil end
    local p=unit.Position
    return p and {x=p.x,y=p.y,z=p.z}
end
local function log(action,id)
    print('[volcano_probe]',action,'fish='..tostring(id),'at='..tostring(Fish:Now()))
end

function Probe.Spawn(player,species,isolated)
    assert(isolated==true,'必须明确使用独立验收会话')
    assert(species=='fish55Elite' or species=='fish56Boss','只允许火山岛战斗目标')
    assert(player and player.Character and not Fish:GetHeld(player),'需要在线空手玩家')
    local safe=Cfg.Zones[7].Scene.SafePoint
    player.Character.Position=Vector3.New(safe.x,safe.y,safe.z)
    local fish,err=Fish:SpawnLanded(player,{fishId=species,mult=1},player.Character.Position)
    assert(fish,err)
    Probe.Owned[fish.Id]=fish
    log('spawn 等待原生抓举确认',fish.Id)
    return fish.Id
end

function Probe.Drop(player,id)
    local fish=assert(Probe.Owned[id],'不是探针创建的鱼')
    assert(Fish:GetHeld(player)==fish,'原生抓举尚未确认')
    assert(Fish:Drop(player),'放下失败')
    log('drop',id)
end

function Probe.Damage(id,amount)
    local fish=assert(Probe.Owned[id],'不是探针创建的鱼')
    assert(Fish.Fish[id]==fish and amount>0 and amount==math.floor(amount),'目标或伤害无效')
    fish.Carrier.Receiver.Controller:TakeDamage(amount)
    log('阶段触发伤害 '..tostring(amount),id)
end

function Probe.Snapshot(player,id)
    local fish=Probe.Owned[id]
    local data=Data:GetDataInst(player)
    local result={at=Fish:Now(),exists=fish~=nil and Fish.Fish[id]==fish,
        player=point(player.Character),playerHealth=player.Character and player.Character.Controller.Health,
        localCompleted=data and data.Extra.achievements and data.Extra.achievements.final,
        platformDelivered=data and data.Extra.achievementDelivered and data.Extra.achievementDelivered.final,
        platformConfigured=type(Cfg.Achievements.final.PlatformId)=='number'}
    if result.exists then
        result.body,result.receiver=point(fish.Carrier.Body),point(fish.Carrier.Receiver)
        result.health,result.maxHealth=fish.Carrier.Health,fish.Carrier.MaxHealth
        result.state,result.phase=fish.State,fish.Phase and fish.Phase.Phase
        result.transitions=fish.Phase and fish.Phase.Stats.Transitions
        result.carry=fish.Carry and fish.Carry.TargetPlayer.UserId
        result.warning=fish.BossWarn~=nil
    end
    log('snapshot',id)
    return result
end

function Probe.Cleanup(id)
    local fish=Probe.Owned[id]
    if fish and Fish.Fish[id]==fish then Fish:Remove(fish) end
    Probe.Owned[id]=nil
    log('cleanup',id)
end
return Probe

--local RunService = game:GetService("RunService")
--if RunService.EnableDeveloperMode() then
--    debug.start_debugger()
--end

local Task = game:GetService("Task")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
MgrUtil = require("server.MgrUtil")
MgrUtil:Start()

local MgrMap = {
    MgrPlayer = require("server.Mgr.MgrPlayer"),
    MgrPlayerData = require("server.Mgr.MgrPlayerData"),
    MgrCast = require("server.Mgr.MgrCast"),
    MgrAbility = require("server.Mgr.MgrAbility"),
    MgrReelIn = require("server.Mgr.MgrReelIn"),
    MgrFishCarrier = require("server.Mgr.MgrFishCarrier"),
    MgrFishUnit = require("server.Mgr.MgrFishUnit"),
    MgrLoot = require("server.Mgr.MgrLoot"),
    MgrInteract = require("server.Mgr.MgrInteract"),
    MgrGM = require("server.Mgr.MgrGM"),
    MgrShop = require("server.Mgr.MgrShop"),
    MgrQuest = require("server.Mgr.MgrQuest"),
    MgrVitals = require("server.Mgr.MgrVitals"),
    MgrStory = require("server.Mgr.MgrStory"),
    MgrFerry = require("server.Mgr.MgrFerry"),
    MgrSave = require("server.Mgr.MgrSave"),
    MgrSurvival = require("server.Mgr.MgrSurvival"),
    MgrWeapon = require("server.Mgr.MgrWeapon"),
}

MgrMap.MgrCast.ReelIn = MgrMap.MgrReelIn
MgrMap.MgrReelIn.Cast = MgrMap.MgrCast
MgrMap.MgrCast.FishUnit = MgrMap.MgrFishUnit
MgrMap.MgrFishUnit.Cast = MgrMap.MgrCast
MgrMap.MgrFishUnit.Ability = MgrMap.MgrAbility
MgrMap.MgrLoot.FishUnit = MgrMap.MgrFishUnit
MgrMap.MgrLoot.PlayerData = MgrMap.MgrPlayerData
MgrMap.MgrPlayerData.Loot = MgrMap.MgrLoot
MgrMap.MgrInteract.PlayerData = MgrMap.MgrPlayerData
MgrMap.MgrGM.PlayerData = MgrMap.MgrPlayerData
MgrMap.MgrGM.Cast = MgrMap.MgrCast
MgrMap.MgrShop.PlayerData = MgrMap.MgrPlayerData
MgrMap.MgrShop.Interact = MgrMap.MgrInteract
MgrMap.MgrLoot.Quest = MgrMap.MgrQuest
MgrMap.MgrInteract.Quest = MgrMap.MgrQuest
MgrMap.MgrShop.Quest = MgrMap.MgrQuest
MgrMap.MgrPlayerData.Quest = MgrMap.MgrQuest
MgrMap.MgrCast.Quest = MgrMap.MgrQuest
MgrMap.MgrFishUnit.Quest = MgrMap.MgrQuest
MgrMap.MgrPlayerData.Vitals = MgrMap.MgrVitals
MgrMap.MgrGM.Vitals = MgrMap.MgrVitals
MgrMap.MgrGM.Save = MgrMap.MgrSave
MgrMap.MgrFerry.PlayerData = MgrMap.MgrPlayerData
MgrMap.MgrFerry.Interact = MgrMap.MgrInteract
MgrMap.MgrPlayerData.Save = MgrMap.MgrSave
MgrMap.MgrInteract.Save = MgrMap.MgrSave
MgrMap.MgrFerry.Save = MgrMap.MgrSave
MgrMap.MgrShop.Save = MgrMap.MgrSave
MgrMap.MgrFerry.Save = MgrMap.MgrSave
MgrMap.MgrSave.PlayerData = MgrMap.MgrPlayerData

-- #128 战斗接线：统一伤害入口的依赖单向注入在这里完成。
-- Vitals 需要鱼受击体解析（ApplyHit 的鱼分支）；Ability / FishUnit / Cast 需要玩家生命状态
-- （施法守卫、追咬结算、动作互斥）；鱼受击体的有效伤害经 DamageListener 回报仇恨。
-- 契约：DamageListener(carrier, actual, hit) 中 hit.sourcePlayer 是服务端登记的玩家来源身份，
-- 只有玩家武器伤害才累计仇恨；鱼攻击（fishAttack）来源不是玩家，自然不记。
MgrMap.MgrAbility.Vitals = MgrMap.MgrVitals
MgrMap.MgrFishUnit.Vitals = MgrMap.MgrVitals
-- #132 T11 三倍体型：吃药水成功后由 MgrPlayerData 就地重算体型（唯一消费口，幂等）。
MgrMap.MgrPlayerData.Ability = MgrMap.MgrAbility
MgrMap.MgrVitals.FishCarrier = MgrMap.MgrFishCarrier
MgrMap.MgrCast.Vitals = MgrMap.MgrVitals
-- #131 生存恢复：经 #128 预留的 LifeHooks 接管濒死/死亡，依赖单向注入在这里完成。
MgrMap.MgrSurvival.Vitals = MgrMap.MgrVitals
MgrMap.MgrSurvival.FishUnit = MgrMap.MgrFishUnit
MgrMap.MgrSurvival.ReelIn = MgrMap.MgrReelIn
MgrMap.MgrSurvival.PlayerData = MgrMap.MgrPlayerData
MgrMap.MgrSurvival.Save = MgrMap.MgrSave
MgrMap.MgrVitals:SetLifeHooks(MgrMap.MgrSurvival:Hooks())
MgrMap.MgrFishCarrier.DamageListener = function(carrier, actual, hit)
    local fish = carrier and MgrMap.MgrFishUnit:FindByCarrier(carrier)
    local attacker = hit and hit.sourcePlayer
    if fish and attacker and type(actual) == 'number' and actual > 0 then
        MgrMap.MgrFishUnit:NoteDamage(fish, attacker, actual)
    end
end

-- #129 武器系统接线：近战/枪械/投掷结算经统一伤害入口（Vitals）与鱼受击体解析（FishCarrier）；
-- 武器库存/装备读 PlayerData，投掷消耗走 Save 持久协议，爆炸保底鱼生成进 FishUnit。
-- Update（投掷飞行物推进）由 HandleTimeUpdate 心跳统一驱动，Start 注册 WeaponAction 通道与挥砍施法守卫。
MgrMap.MgrWeapon.Vitals = MgrMap.MgrVitals
MgrMap.MgrWeapon.PlayerData = MgrMap.MgrPlayerData
MgrMap.MgrWeapon.FishUnit = MgrMap.MgrFishUnit
MgrMap.MgrWeapon.FishCarrier = MgrMap.MgrFishCarrier
MgrMap.MgrWeapon.Save = MgrMap.MgrSave

-- 存档就绪前不创建 Vitals/Ability 等玩家状态；退出先撤销就绪标记，再清理管理器。
local ActivePlayers = {}
local Started = false
local ReadyQueue = {}
local function invoke(name, mgr, method, ...)
    if not mgr[method] then return end
    local ok, err = pcall(mgr[method], mgr, ...)
    if not ok then print('[server.main]', name, method, tostring(err)) end
end
MgrMap.MgrSave.OnReady = function(player, data)
    if MgrMap.MgrPlayerData:GetDataInst(player) ~= data or ActivePlayers[player.UserId] == player then return end
    if not Started then ReadyQueue[player.UserId] = { player, data } return end
    ActivePlayers[player.UserId] = player
    -- 这些管理器直接操作角色与生命状态，先于依赖它们的其他管理器初始化。
    -- MgrSurvival 紧随 MgrVitals：离线恢复要读 Vitals 状态并把控制器血量锁回 1。
    for _, name in ipairs({ 'MgrPlayer', 'MgrVitals', 'MgrSurvival', 'MgrAbility', 'MgrFishUnit' }) do
        invoke(name, MgrMap[name], 'OnPlayerAdded', player)
    end
    for name, mgr in pairs(MgrMap) do
        if name ~= 'MgrPlayerData' and name ~= 'MgrPlayer' and name ~= 'MgrVitals'
            and name ~= 'MgrSurvival' and name ~= 'MgrAbility' and name ~= 'MgrFishUnit' then
            invoke(name, mgr, 'OnPlayerAdded', player)
        end
    end
end
local function HandlePlayerAdded(player)
    invoke('MgrPlayerData', MgrMap.MgrPlayerData, 'OnPlayerAdded', player)
end

local function HandlePlayerRemoving(player)
    local queued = ReadyQueue[player.UserId]
    if queued and queued[1] == player then ReadyQueue[player.UserId] = nil end
    local active = ActivePlayers[player.UserId] == player
    if active then ActivePlayers[player.UserId] = nil end
    -- 终镜像必须先于 MgrPlayerData 的 SaveLeaving 序列化，离线标记才是最新的
    if active then invoke('MgrSurvival', MgrMap.MgrSurvival, 'BeforeLeave', player) end
    invoke('MgrPlayerData', MgrMap.MgrPlayerData, 'OnPlayerRemoving', player)
    if active then
        for name, mgr in pairs(MgrMap) do
            if name ~= 'MgrPlayerData' then invoke(name, mgr, 'OnPlayerRemoving', player) end
        end
    end
end

local function HandleTimeUpdate(deltaTime)
    for k, mgr in pairs(MgrMap) do
        if mgr.Update then
            pcall(function() mgr:Update(deltaTime) end)
        end
    end
end 

local function GameStart()
    for name, mgr in pairs(MgrMap) do invoke(name, mgr, 'Start') end
    Started = true
    for userId, entry in pairs(ReadyQueue) do
        ReadyQueue[userId] = nil
        MgrMap.MgrSave.OnReady(entry[1], entry[2])
    end
end



Players.PlayerAdded:Connect(HandlePlayerAdded)
Players.PlayerRemoving:Connect(HandlePlayerRemoving)
--处理玩家在事件注册之前就加入的情况
local plst = Players:GetPlayers()
for _, player in pairs(plst)  do
    HandlePlayerAdded(player)
end

GameStart()
RunService.Heartbeat:Connect(HandleTimeUpdate)





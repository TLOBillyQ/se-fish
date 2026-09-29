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
MgrMap.MgrSave.PlayerData = MgrMap.MgrPlayerData

-- 存档就绪前不创建 Vitals/Ability 等玩家状态；退出先撤销就绪标记，再清理管理器。
local ActivePlayers = {}
local function invoke(name, mgr, method, ...)
    if not mgr[method] then return end
    local ok, err = pcall(mgr[method], mgr, ...)
    if not ok then print('[server.main]', name, method, tostring(err)) end
end
MgrMap.MgrSave.OnReady = function(player, data)
    if MgrMap.MgrPlayerData:GetDataInst(player) ~= data or ActivePlayers[player.UserId] == player then return end
    ActivePlayers[player.UserId] = player
    for name, mgr in pairs(MgrMap) do
        if name ~= 'MgrPlayerData' then invoke(name, mgr, 'OnPlayerAdded', player) end
    end
end
local function HandlePlayerAdded(player)
    invoke('MgrPlayerData', MgrMap.MgrPlayerData, 'OnPlayerAdded', player)
end

local function HandlePlayerRemoving(player)
    local active = ActivePlayers[player.UserId] == player
    if active then ActivePlayers[player.UserId] = nil end
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
    for k, mgr in pairs(MgrMap) do
        if mgr.Start then
            pcall(function() mgr:Start() end)
        end
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





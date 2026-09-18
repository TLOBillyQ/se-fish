local Mgr = {}
local DataMap = {}
local World = game:GetService("World")
local Task = game:GetService("Task")

local TRY_COUNT_SAVE = 1
local TRY_COUNT_INT = 10
local TRY_COUNT_TIME_UPDATE = 1

local PlayerData = require("server.Data.PlayerData")

function Mgr:GetDataInst(player)
    local pData = DataMap[player.UserId]
    if not pData then
        print("[MgrPlayerData] non player data", player)
        return
    end

    if not pData.Inited then
        if not pData.Locked then
            Task:Spawn(function() 
                pData:Init(TRY_COUNT_INT) --继续尝试获取
            end)
        end
        print("[MgrPlayerData] not inited", player)
        return 
    end

    return pData
end

function Mgr:OnPlayerAdded(player)
    print("[MgrPlayerData] OnPlayerAdded", player)
    local pData = PlayerData.New(player)
    DataMap[player.UserId] = pData
    Task:Spawn(function() 
        pData:Init(TRY_COUNT_INT)
    end)
    print("[MgrPlayerData] check all ", DataMap)
end

function Mgr:OnPlayerRemoving(player)
    local pData = DataMap[player.UserId]
    if pData then
        Task:Spawn(function() 
            pData:Save(TRY_COUNT_SAVE)
            pData:Destroy()
        end)
    end
    DataMap[player.UserId] = nil
end

function Mgr:Update(deltaTime)
    local nowTime = World:GetServerTime()
    for uid, pData in pairs(DataMap) do
        --if pData.Locked then continue end
        if not pData.Locked then
            if pData.Inited then
                if pData.Changed and pData.NextSaveTime < nowTime then
                     Task:Spawn(function() 
                        pData:Save(TRY_COUNT_SAVE)
                    end)
                end    
            else
                Task:Spawn(function() 
                    pData:Init(TRY_COUNT_SAVE)
                end)
            end
        end
    end
end

local function ResetGM(player)
    --if player:HasTag("Removing") then return end
    local pData = DataMap[player.UserId]
    if not pData then
        return
    end
    pData:Reset()
end

function Mgr:Start()
    _G.REUtil:GetRE("ResetGM").OnServerEvent:Connect(ResetGM)
end

_G.MgrPlayerData = Mgr
return Mgr
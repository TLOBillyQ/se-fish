local PlayerData = {}
PlayerData.__index = PlayerData

local DataStoreService = game:GetService("DataStoreService")
local Task = game:GetService("Task")
local World = game:GetService("World")

local AUTO_SAVE_TIME_INTERVAL = 30
local KEY_PLAYER_DATA = "PlayerData"
local KEY_GLOBAL = "global"

 local InitData = {
    FishCoin = 0,
    FishCount = 0,
    FishLevel = 1,
    RodLevel = 1,
}

function PlayerData.New(player)
    print("[PlayerData] new")
    local t = {}
    setmetatable(t, PlayerData)
    t.Player = player
    print("[PlayerData] new setmetatable success")
    return t
end

function PlayerData:Reset()
    if not self.Player then return end
    if self.Locked then
        return
    end
    self.Locked = true
    local myDataStore = DataStoreService:GetDataStore(KEY_PLAYER_DATA, KEY_GLOBAL)
    local success, data = pcall(function() 
        return myDataStore:RemoveAsync(self.Player.UserId)
    end)
    if success then
        print("[PlayerData] reset:", self.Player.UserId)
        self.Data = {}
        self.Locked = false
        self.Inited = false
        self.NextSaveTime = World:GetServerTime() + AUTO_SAVE_TIME_INTERVAL
        self.Player:Kick()
    end 
end

function PlayerData:Destroy()
    self.Player = nil
end

function PlayerData:Init(tryCount)
    if not self.Player then return end
    if self.Locked then
        return
    end

    if not tryCount then
        tryCount = 1
    end

    self.Locked = true
    local myDataStore = DataStoreService:GetDataStore(KEY_PLAYER_DATA, KEY_GLOBAL)
    while tryCount > 0 do
        local success, data = pcall(function() 
            return myDataStore:GetAsync(self.Player.UserId)
        end)
       
        if success then
            if not data then
                print("[PlayerData] use InitData")
                data = {}
                --测试clone 功能
                for k,v in pairs(InitData) do
                    if type(v) == "table" then
                        --TODO:复杂表结构的复制
                    else
                        data[k] = v
                    end
                end
            end
            self.Data = data
            print("[PlayerData] Init success", self.Data)
            self.Locked = false
            self.Inited = true
            self.NextSaveTime = World:GetServerTime() + AUTO_SAVE_TIME_INTERVAL
            self:Sync()
            return
        end

        tryCount = tryCount - 1
        print("[PlayerData]  Init fail, try next", tryCount)
        Task:Wait(1)
    end

    self.Locked = false
    self.Inited = false
end

function PlayerData:Save(tryCount)
    if not self.Player then return end

    if self.Locked or not self.Inited then
        return
    end
    local myDataStore = DataStoreService:GetDataStore(KEY_PLAYER_DATA, KEY_GLOBAL)
    if not tryCount then
        tryCount = 1
    end
  
    self.Locked = true
    while tryCount > 0 do
        local success, data = pcall(function() 
            return myDataStore:SetAsync(self.Player.UserId, self.Data)
        end)
       
        if success then
            self.Locked = false
            self.Changed = false
            self.NextSaveTime = World:GetServerTime() + AUTO_SAVE_TIME_INTERVAL
            print("[PlayerData] Save success", self.Data)
            return
        end

        tryCount = tryCount - 1
        print("[PlayerData]  Save fail, try next", tryCount)
        Task:Wait(1)
    end
    self.Locked = false
end

function PlayerData:UpdateData(updateCallBack, doSync)
    if not self.Inited then
        return
    end

    if updateCallBack then
        updateCallBack(self.Data) 
        self.Changed = true
        if doSync then
            self.NextSaveTime = 0
            self:Sync()
        end
    end
end   

function PlayerData:Sync()
    print("[PlayerData] sync() start")
    for k, v in pairs(InitData) do
        local curValue = self.Data[k]
        self.Player:SetAttribute(k, curValue)
        print("[PlayerData] sync() ", k, curValue)
    end
    print("[PlayerData] sync() end")
end

return PlayerData
local ScreenHandler = {}
ScreenHandler.UINodes = {
    "BtnShopClose",
    "LabelFishLv",
    "LabelRodLv",
    "ListRodLv",
    "ListFishLv",
    "BtnRodLvUp",
    "BtnFishLvUp",
    "LabelRodLvUpCost",
    "LabelFishLvUpCost",
    "LabelRodLvMax",
    "LabelFishLvMax",
    "LabelCurCoin",
    "BtnResetGM",
}

local MaxNum = 6
ScreenHandler.UINodeMap = {}

local World = game:GetService("World")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local Task = game:GetService("Task")
local GameCfg = require("common.GameCfg")
local PassBy = nil
--{
--}
local function UpdateFishLv(curLv, curCoin)
    print("[ScreenShop] UpdateFishLv() ", curLv, curCoin)
    if not curLv then
        curLv = LocalPlayer:GetAttribute("FishLevel") or 0
    end
    if not curCoin then
        curCoin = LocalPlayer:GetAttribute("FishCoin") or 0
    end

    ScreenHandler.UINodeMap.LabelFishLv.Text = "Lv." .. curLv

    for i = 1, GameCfg.MaxFishLv do
        local rectImage = ScreenHandler.UINodeMap.ListFishLv:FindFirstChild(tostring(i))
        rectImage:SetColor(i > curLv and tonumber("000000", 16) or tonumber("00ff00", 16))
    end

    local lvMax = curLv == GameCfg.MaxFishLv
    local lvCfg = GameCfg.FishLevelMap[curLv]
    
    ScreenHandler.UINodeMap.LabelFishLvMax.Visible = lvMax
    ScreenHandler.UINodeMap.BtnFishLvUp.Visible = not lvMax
    if not lvMax then
        ScreenHandler.UINodeMap.LabelFishLvUpCost.Text = tostring(lvCfg.Cost)
        ScreenHandler.UINodeMap.LabelFishLvUpCost:SetTextColor(curCoin < lvCfg.Cost and tonumber("ff0000", 16) or tonumber("ffffff", 16))
    end
    ScreenHandler.UINodeMap.LabelCurCoin.Text = tostring(curCoin)
end

local function UpdateRodLv(curLv, curCoin)
     if not curLv then
        curLv = LocalPlayer:GetAttribute("RodLevel") or 0
    end
    if not curCoin then
        curCoin = LocalPlayer:GetAttribute("FishCoin") or 0
    end
  
    ScreenHandler.UINodeMap.LabelRodLv.Text = "Lv." .. curLv

    for i = 1, GameCfg.MaxRodLv do
        local rectImage = ScreenHandler.UINodeMap.ListRodLv:FindFirstChild(tostring(i))
        rectImage:SetColor(i > curLv and tonumber("000000", 16) or tonumber("00ff00", 16))
    end

    local lvMax = curLv == GameCfg.MaxRodLv
    local lvCfg = GameCfg.RodLevelMap[curLv]
    
    ScreenHandler.UINodeMap.LabelRodLvMax.Visible = lvMax
    ScreenHandler.UINodeMap.BtnRodLvUp.Visible = not lvMax
    if not lvMax then
        ScreenHandler.UINodeMap.LabelRodLvUpCost.Text = tostring(lvCfg.Cost)
        ScreenHandler.UINodeMap.LabelRodLvUpCost:SetTextColor(curCoin < lvCfg.Cost and tonumber("ff0000", 16) or tonumber("ffffff", 16))
    end
    ScreenHandler.UINodeMap.LabelCurCoin.Text = tostring(curCoin)
end

function ScreenHandler:Init()
    self.Inited = true
    self.Links = {}

    self.UINodeMap.BtnShopClose.OnClicked:Connect(function(player) 
        _G.MgrGameUI:CloseScreen("ScreenShop")
    end)

    self.UINodeMap.BtnRodLvUp.OnClicked:Connect(function(player) 
        --check coin
        if _G.REUtil:CheckRECD(LocalPlayer, "RodLevelUp", 1) then return end
        _G.REUtil:GetRE("RodLevelUp"):FireServer()
    end)

    self.UINodeMap.BtnFishLvUp.OnClicked:Connect(function(player) 
        --check coin
        if _G.REUtil:CheckRECD(LocalPlayer, "FishLevelUp", 1) then return end
        _G.REUtil:GetRE("FishLevelUp"):FireServer()
    end)

     self.UINodeMap.BtnResetGM.OnClicked:Connect(function(player) 
        _G.REUtil:GetRE("ResetGM"):FireServer()
    end)

end

function ScreenHandler:OpenScreen(passBy)
    UpdateFishLv()
    UpdateRodLv()
    --简单通过监听金币变化来刷新等级状态
    self.Links["FishCoin"] = LocalPlayer:GetAttributeChangedSignal("FishCoin"):Connect(function()
        Task:Defer(function() -- wait for attribute update
            UpdateFishLv()
            UpdateRodLv()
        end)
    end)
end

function ScreenHandler:CloseScreen()
    PassBy = nil
    if self.Links then
        for k, v in pairs(self.Links) do
            v:Disconnect()
        end

        self.Links = {}
    end
end

function ScreenHandler:Destroy()
    self.RootNode = nil
    self.Inited = false
    self:CloseScreen()
end

return ScreenHandler
local ScreenHandler = {}
ScreenHandler.UINodes = {
    "BtnClose",
    "Btn1",
    "Btn2",
    "Btn3",
    "Btn4",
    "Btn5",
    "Btn6",
    "ProgressRoot",
    "FrameNumsArea",
    "Bg",
    "UIFXTestYes",
    "UIFXTestNo",
    --Reward Pop dialog
    "BtnRewardConfirm",
    "RewardRootBG",
    "LabelRewardMsg",
    "ImageReward",
}

local MaxNum = 6
ScreenHandler.UINodeMap = {}

local TimerService = game:GetService("TimerService")
local World = game:GetService("World")
local Players = game:GetService("Players")
local Task = game:GetService("Task")
local GameCfg = require("common.GameCfg")

local PassBy = nil
--{
--  ReqStep:int
--  TotalTime:int
--}

local curStep = 0
local endTime = 0
local totalTime = 1
local runTimer = nil

local function ResetStep()
    curStep = 0
    local FrameNumsArea = ScreenHandler.UINodeMap.FrameNumsArea
    local startPos = FrameNumsArea.Position
    local size = FrameNumsArea.Size

    print("[ScreenFishing] ResetStep FrameNumsArea", startPos, size)

    
    local cellSize = ScreenHandler.UINodeMap.Btn1.Size

    local cellX = cellSize.x
    local cellY = cellSize.y

    local countX = math.floor(size.x/cellX) - 2 --保留边缘
    local countY = math.floor(size.y/cellY) - 2 

    
    local fishCfg = GameCfg.FishMap[PassBy.FishId]
    PassBy.ReqStep = fishCfg.ReqStep

    local reqStep = PassBy.ReqStep
    local indexMap = {}
    local function GetXY()
        local x = (math.random(countX) - countX*0.5)
        local y = (math.random(countY) - countY*0.5)
        local indexStr = string.format("%f_%f", x, y)
        return x,y,indexStr  
    end

    for i = 1, MaxNum do 
        local btnN = ScreenHandler.UINodeMap["Btn" .. i]

        if i >  reqStep then
            btnN.Visible = false
        else
            btnN.Visible = true

            local x,y,indexStr = GetXY()
            while(indexMap[indexStr]) do
                x,y,indexStr = GetXY()
            end
            
            indexMap[indexStr] = true
            local offsetV2 = Vector2(cellX * x, cellY * y)
            btnN.Position = startPos + offsetV2

            --local effect = ScreenHandler.UINodeMap["BtnEffect" .. i]
            --effect.Position = btnN.Position
            --print("[ScreenFishing] ResetStep ", btnN, btnN.Position)
        end
    end
end

local function HandleNumClick(num)

    local isRight = curStep + 1 == num
    local btnN = ScreenHandler.UINodeMap["Btn" .. num]
    
    local tempEffect = ScreenHandler.UINodeMap["BtnEffect" .. num]
    tempEffect.Position = btnN.Position
    --print("Play Click Effect", btnN.Position, tempEffect.Position)
    local effectId = isRight and 8 or 9
    tempEffect:SetEffect(effectId)
    tempEffect.Visible = true
    tempEffect:PlayAnimation()
    Task:Delay(1, function() 
        tempEffect:StopAnimation()
        tempEffect.Visible = false
    end)

    if isRight then   
        btnN.Visible = false
        curStep = curStep + 1
        if curStep == PassBy.ReqStep then
            --Task:Wait(0.3) -- for effect play
            _G.REUtil:GetRE("DoneFish"):FireServer(true)
        end
    else
        ResetStep()
    end
end

local function UpdateTime()
    local ProgressRoot = ScreenHandler.UINodeMap.ProgressRoot
    local leftTime = endTime - World:GetServerTime()
    if leftTime < 0 then
        _G.REUtil:GetRE("DoneFish"):FireServer(false)
        runTimer:Cancel()
        runTimer = nil
        ProgressRoot:SetPercent(1)
        return
    end


    local timeRate = 100 - 100*leftTime/totalTime
    ProgressRoot:SetPercent(math.ceil(timeRate))
end

function ScreenHandler:Init()
    self.Inited = true
    self.Links = {}

    self.UINodeMap.BtnClose.OnClicked:Connect(function(player) 
        _G.REUtil:GetRE("CancelFish"):FireServer()
    end)

    self.UINodeMap.BtnRewardConfirm.OnClicked:Connect(function(player) 
        _G.MgrGameUI:CloseScreen("ScreenFishing")
        --_G.UpdatePlayerCoin()
    end)

    --[[ 获取特效ID，clone方案失败，采用CreateEffect方式进行
    local UIEffect = self.UINodeMap.UIFXTestNo
    if UIEffect then
        print("UIEffect", UIEffect.EffectID) --9
        UIEffect:StopAnimation()
        UIEffect.Visible = false
    end
    --]]

    local euiMgr = _G.GameUI:GetEuiManager()
    for i = 1, MaxNum do
        local btnN = self.UINodeMap["Btn" .. i]
        print("[ScreenFishing] record button ", btnN, btnN.Position)
        local effect = euiMgr:CreateEffect(self.RootNode, {
            EffectID = 9,
            LoopPlay = false,
        })
        effect.Name = "BtnEffect"..i
        self.UINodeMap[effect.Name] = effect
        effect.Visible = false
        --effect:PlayAnimation()

        btnN.OnClicked:Connect(function(player) 
            HandleNumClick(i)
        end)
    end
end

function ScreenHandler:DoReward()
     if runTimer then
        runTimer:Cancel()
        runTimer = nil
    end
    
    local fishCfg = GameCfg.FishMap[PassBy.FishId]
    self.UINodeMap.RewardRootBG.Visible = true
    self.UINodeMap.LabelRewardMsg.Text = string.format("恭喜钓到%s，回收价：%d金币", fishCfg.Name, fishCfg.Coin) 
    self.UINodeMap.ImageReward.Visible = true

    print("[DoReward] before", self.UINodeMap.ImageReward:GetAllProps())
    self.UINodeMap.ImageReward.Image = fishCfg.Icon
    --self.UINodeMap.ImageReward:SetImage("official://image/37137")
    --print("[DoReward] after", self.UINodeMap.ImageReward:GetAllProps())
end

function ScreenHandler:TimeOverPop()
     if runTimer then
        runTimer:Cancel()
        runTimer = nil
    end
    
    self.UINodeMap.RewardRootBG.Visible = true
    self.UINodeMap.LabelRewardMsg.Text = "鱼跑掉咯，再接再厉！"
    self.UINodeMap.ImageReward.Visible = false
end

local function TestCloneFX()
    local UIEffect = ScreenHandler.UINodeMap.UIFXTestYes
    if UIEffect then
        
        local testFX = UIEffect:Clone()
        local newPos = UIEffect.Position + Vector2(math.random(100) - 50, math.random(100) - 50)
        testFX.Position = newPos
        testFX.Visible = true
        testFX.LoopPlay = true
        testFX:PlayAnimation()
        testFX.Name = "TestFX" .. World:GetServerTime()
        testFX.Parent = UIEffect.Parent
        print("[TestCloneFX] new pos:", newPos, testFX.Position, testFX:GetAllProps())
    end
end

function ScreenHandler:OpenScreen(passBy)
    PassBy = passBy
    if PassBy.TimeOver then
        self:TimeOverPop()
        return
    end
    if PassBy.DoReward then
        self:DoReward()
        return
    end

    self.UINodeMap.RewardRootBG.Visible = false
    ResetStep()
    totalTime = PassBy.TotalTime
    endTime = World:GetServerTime() + totalTime
    if runTimer then
        runTimer:Cancel()
        runTimer = nil
    end
    runTimer = TimerService:CreateTimer(-1, 0.033, true, UpdateTime)
    --TestCloneFX()
end

function ScreenHandler:CloseScreen()
    PassBy = nil
    if runTimer then
        runTimer:Cancel()
        runTimer = nil
    end

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
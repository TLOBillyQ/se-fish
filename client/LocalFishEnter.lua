local LocalFishEnter = {}
local Players = game:GetService("Players")
local Task = game:GetService("Task")
local World = game:GetService("World")
local LocalPlayer = Players.LocalPlayer
local LabelCoin = nil
local LastCoin = 0

function LocalFishEnter:ReqFish()
    if _G.REUtil:CheckRECD(LocalPlayer, "ReqFish", 1) then return end
    _G.REUtil:GetRE("ReqFish"):FireServer()
end

local function DoCoinAnim(from, to)
    print("[LocalFishEnter] DoCoinAnim", from, to)
    local stepCount = 15
    local stepValue = (to - from)/stepCount

    local curValue = from
    local startPlay = false
    local limitWaitCount = 300 --至多等待约10秒
    while stepCount > 0 and limitWaitCount > 0 do
        --其他界面遮挡情况下，暂停更新金币
        if startPlay or #_G.MgrGameUI:IsAnyScreenOpen({"ScreenMain","ScreenMsg"})==0 then 
            stepCount = stepCount - 1
            curValue = curValue + stepValue
            LabelCoin.Text = tostring(math.floor(curValue))
            startPlay = true
        end
        Task:Wait(0.033)
        limitWaitCount = limitWaitCount - 1
    end
    LabelCoin.Text = tostring(to)
    --print("[LocalFishEnter] DoCoinAnim end")
end

local lastTaskThread = nil
local function UpdatePlayerCoin()
    print("[LocalFishEnter] UpdatePlayerCoin")
    local curCoin = LocalPlayer:GetAttribute("FishCoin") or 0
    print("[LocalFishEnter] get coin:", curCoin, LastCoin)
    if LastCoin ~= curCoin then
        if LastCoin then
            if lastTaskThread then
                Task:Cancel(lastTaskThread)
                lastTaskThread = nil
                print("取消未播放的金币动画")
            end
            lastTaskThread = Task:Spawn(function() DoCoinAnim(LastCoin, curCoin) end)
        else
            LabelCoin.Text = tostring(curCoin)    
        end
        LastCoin = curCoin
    else
        LabelCoin.Text = tostring(curCoin)
    end
end

function LocalFishEnter:Start()
    local UIRoot = _G.GameUI:GetUIRoot()
    local ScreenMain = UIRoot:FindFirstChild("ScreenMain")
    local ScreenFishing = UIRoot:FindFirstChild("ScreenFishing")

    LabelCoin = ScreenMain:FindFirstChild("LabelCoin", true)
    local BtnFishEnter = ScreenMain:FindFirstChild("BtnFishEnter", true)
   
    ScreenMain.Visible = true
    --ScreenMain:SetLocalZOrder(0)
    print("[ScreenMain] check parent", ScreenMain.Parent, ScreenMain.Parent:GetChildren())
    
    --ScreenFishing:SetLocalZOrder(10)

    self.BtnFishEnter = BtnFishEnter
    BtnFishEnter.OnClicked:Connect(function() 
        self:ReqFish()
    end)

    local TGUnitFish = _G.Util:WaitForChild(World, "TGUnitFish")
    TGUnitFish.OnTriggerEnter:Connect(function(otherUnit) 
        if otherUnit == Players.LocalPlayer.Character then
            BtnFishEnter.Visible = true
        end
    end)

    TGUnitFish.OnTriggerExit:Connect(function(otherUnit) 
        if otherUnit == Players.LocalPlayer.Character then
            BtnFishEnter.Visible = false
        end
    end)


    --shop
    --map://preset/uf5ad80a4c6a40d59b7f6e0eb99a58c0
    --fish
    --map://preset/u621115343554ccea235520655847b05
    local sceneNode = _G.GameUI:CreateSceneNode("map://preset/u621115343554ccea235520655847b05", TGUnitFish)
    if sceneNode then
        sceneNode.Visible = true
    end
    
    local TGUnitShop = _G.Util:WaitForChild(World, "TGUnitShop")
    TGUnitShop.OnTriggerEnter:Connect(function(otherUnit) 
        if otherUnit == Players.LocalPlayer.Character then
            if _G.MgrGameUI:IsScreenOpen("ScreenFishing") then return end
            _G.MgrGameUI:OpenScreen("ScreenShop", {})
        end
    end)
    TGUnitShop.OnTriggerExit:Connect(function(otherUnit) 
        if otherUnit == Players.LocalPlayer.Character then
            if not _G.MgrGameUI:IsScreenOpen("ScreenShop") then return end
            _G.MgrGameUI:CloseScreen("ScreenShop")
        end
    end)
    _G.GameUI:CreateSceneNode("map://preset/uf5ad80a4c6a40d59b7f6e0eb99a58c0", TGUnitShop, Vector3(0, 7, 0))
    Task:Delay(1, function() 
        --基于LocalPlayer GetAttributeChangedSignal的初始化不稳定性，需要延迟注册
        LocalPlayer:GetAttributeChangedSignal("FishCoin"):Connect(UpdatePlayerCoin)
        UpdatePlayerCoin()
    end)
    _G.UpdatePlayerCoin = UpdatePlayerCoin
end

return LocalFishEnter
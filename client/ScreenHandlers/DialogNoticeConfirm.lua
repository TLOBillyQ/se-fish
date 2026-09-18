local ScreenHandler = {}
ScreenHandler.UINodes = {
    "BtnYes",
    "BtnNo",
    "LabelText",
    "UIList",
}

ScreenHandler.UINodeMap = {}
local World = game:GetService("World")
local Players = game:GetService("Players")
local PassBy = nil
--{
--  Msg:string
--  CallBack:function(yesNo)
--}

function ScreenHandler:Init()
    self.Inited = true
    self.Links = {}
end

local function SimpleConfirm(yesNo)
    pcall(function() 
        PassBy.CallBack(yesNo)
    end)
    _G.MgrGameUI:CloseScreen("DialogNoticeConfirm")
end

function ScreenHandler:OpenScreen(passBy)
    PassBy = passBy
    if self.Links then
        for k, v in pairs(self.Links) do
            v:Disconnect()
        end
    end
    self.Links = {}
    self.UINodeMap.LabelText.Text = passBy.Msg

    self.Links["Yes"] = self.UINodeMap.BtnYes.OnClicked:Connect(function(player)
        SimpleConfirm(true)
    end)
    self.Links["No"] = self.UINodeMap.BtnNo.OnClicked:Connect(function(player)
        SimpleConfirm(false)
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
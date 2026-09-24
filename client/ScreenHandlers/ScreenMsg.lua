local ScreenHandler = {}
ScreenHandler.UINodes = {
    "ItemMsg",
}

ScreenHandler.UINodeMap = {}
local Task = game:GetService("Task")

local function PopMsgNotice(msg, duration, textColor)
    local showItemUI = ScreenHandler.UINodeMap.ItemMsg:Clone()
    
    local labelMsg = showItemUI:FindFirstChild("LabelMsg")
    labelMsg.Text = msg
    if textColor then
        labelMsg.TextColor = textColor
    end
    if not duration then duration = 2 end

    Task:Spawn(function() 
        showItemUI.Parent = ScreenHandler.RootNode
        showItemUI.Opacity = 0
        showItemUI.Visible = true

        local endPosition = showItemUI.Position + Vector2(0, 50)
        local easingDirection = Enums.EasingDirection.Out
        local easingStyle = Enums.EasingStyle.Quad
        local animTime = 0.5

        showItemUI:TweenPosition(endPosition, easingDirection, easingStyle, animTime, true)
        showItemUI:TweenOpacity(1, easingDirection, easingStyle, animTime, true, function()
            showItemUI.Opacity = 1
        end)
        Task:Wait(duration)
        showItemUI:TweenOpacity(0, easingDirection, easingStyle, animTime, true, function()
            showItemUI:Destroy()
        end)
    end)
end

function ScreenHandler:Init()
    self.Inited = true
    self.Links = {}
    _G.LocalMsgNotice = PopMsgNotice
end

function ScreenHandler:OpenScreen(passBy)
     if self.Links then
        for k, v in pairs(self.Links) do
            v:Disconnect()
        end
    end
    self.Links = {}
end

function ScreenHandler:CloseScreen()
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

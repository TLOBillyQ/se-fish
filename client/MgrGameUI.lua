local MgrGameUI = {}
local Task = game:GetService("Task")
local StarterGui = game:GetService("StarterGui")
local Util = require("common.Util")
local GameUI = require("client.GameUI")
--local UINodes = require("data.UINodes")
local REUtil = require("common.REUtil")
local OpenScreenRE = REUtil:GetRE("OpenScreenRE")
local CloseScreenRE = REUtil:GetRE("CloseScreenRE")
local curShowMap = {}

function MgrGameUI:GetScreen(screenName)
    local UIRoot = GameUI:GetUIRoot()
    if not UIRoot then
        print("[MgrGameUI] GetScreen() no UIRoot now!")
        return 
    end
    
    local screenNode = UIRoot:FindFirstChild(screenName)
     if not screenNode then
        print("[ShaoTest] MgrGameUI:GetScreen() can not find Screen Node", screenName)
        return
    end
    --EUILayout
    local handlerName = string.format("client.ScreenHandlers.%s", screenName)
    local screenHandler = require(handlerName)

    screenHandler.ScreenName = screenName
    screenHandler.RootNode = screenNode
    if (not screenHandler.Inited or screenHandler.BoundRootNode and screenHandler.BoundRootNode ~= screenNode)
        and screenHandler.UINodes and screenHandler.UINodeMap then
        for k, v in pairs(screenHandler.UINodes) do
            local uiNode = screenNode:FindFirstChild(v, true)
            if uiNode then
                screenHandler.UINodeMap[v] = uiNode
                --print("[ShaoTest]MgrGameUI:OpenScreen() find uiNode", v, uiNode)
            else
                print("[ShaoTest]MgrGameUI:OpenScreen() Can not find", v)
            end
        end
        screenHandler:Init()
    end

    return screenHandler
end 

function MgrGameUI:OpenScreen(screenName, passBy, useAnim)
    local screenHandler = MgrGameUI:GetScreen(screenName)
    if not screenHandler then return end

    if not screenHandler.RootNode.Visible then
      
        if useAnim then
            screenHandler.RootNode.Opacity = 0
            screenHandler.RootNode.Visible = true
            local duration = 0.5
            screenHandler.AnimOpen = true
            screenHandler.RootNode:TweenOpacity(1, Enums.EasingDirection.Out, Enums.EasingStyle.Quad, duration, true, function()
                --screenHandler.RootNode:StopOpacityAnim()
                screenHandler.AnimOpen = nil
                screenHandler.RootNode.Opacity = 1
            end)

        else
            screenHandler.RootNode.Opacity = 1
            screenHandler.RootNode.Visible = true
        end
    end

    curShowMap[screenName] = true
    if screenHandler.OpenScreen then
        screenHandler:OpenScreen(passBy)
    end
end

function MgrGameUI:CloseScreen(screenName, useAnim)
    local screenHandler = MgrGameUI:GetScreen(screenName)
    if not screenHandler then return end

    if screenHandler.RootNode.Visible then
        if useAnim then
            print("[ShaoTest] start Opacity close anim")
            screenHandler.RootNode.Opacity = 1
            local duration = 0.5
            screenHandler.AnimClosing = true
            screenHandler.RootNode:TweenOpacity(0, Enums.EasingDirection.Out, Enums.EasingStyle.Quad, true, function()
                screenHandler.RootNode.Visible = false 
                screenHandler.AnimClosing = false
            end)
        end
        screenHandler.RootNode.Visible = false
    end

    curShowMap[screenName] = nil
    if screenHandler.CloseScreen then
        screenHandler:CloseScreen()
    end
end

OpenScreenRE.OnClientEvent:Connect(function(screenName, passBy, useAnim) 
    print("[ShaoTest] OpenScreenRE", screenName, passBy, useAnim)
    MgrGameUI:OpenScreen(screenName, passBy, useAnim)
end)

CloseScreenRE.OnClientEvent:Connect(function(screenName, useAnim)
    print("[ShaoTest] CloseScreenRE", screenName, useAnim) 
    MgrGameUI:CloseScreen(screenName, useAnim)
end)

function MgrGameUI:IsScreenOpen(screenName)
    local screenHandler = MgrGameUI:GetScreen(screenName)
    if not screenHandler then return end
   return screenHandler.RootNode.Visible
end

function MgrGameUI:IsAnyScreenOpen(exceptLst)
    local exceptMap = {}
    for _, screenName in pairs(exceptLst) do
        exceptMap[screenName] = true
    end
    local showLst = {}
    for screenName,show in pairs(curShowMap) do
        if not exceptMap[screenName] and show then
            table.insert(showLst, screenName)
        end
    end
    --print("MgrGameUI:IsAnyScreenOpen()", showLst)
    return showLst
end

local AllCustomUINodeMap = {}
function MgrGameUI:SetCustomControlUI(uiNode, value)
    AllCustomUINodeMap[uiNode] = value
end

function MgrGameUI:HideLiftButton()
    pcall(function() StarterGui:SetCoreGuiEnabled(Enums.CoreGuiType.LiftButton, false) end)
end

function MgrGameUI:SetControlUI(visible)
    StarterGui:SetCoreGuiEnabled(Enums.CoreGuiType.All, visible)
    self:HideLiftButton()
    for k, v in pairs(AllCustomUINodeMap) do
        k.Visible = visible
        print("[SetControlUI]", k, visible)
    end
end

_G.MgrGameUI = MgrGameUI
return MgrGameUI
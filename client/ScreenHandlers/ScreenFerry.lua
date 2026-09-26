-- 摆渡交互与开船倒计时（#89）：去程锚点（船）旁文字泡「乘船」，虾池返程锚点旁「返程」；
-- 只发 FerryAction{action, seq}（seq 递增防重放），结果以服务端 FerryResult 为准。
-- 倒计时是服务端广播的 FerryState：乘船者之外的搭便船玩家也能看到顶部倒计时条。
-- 放在 ScreenHandlers 下（#89 端别约定），但不是 MgrGameUI 屏幕：随 client/main.lua 直接 Start，
-- 与 ScreenGM 的用法同款。
local GameCfg = require('common.GameCfg')
local REUtil = require('common.REUtil')
local Util = require('common.Util')

local Bubble = require('client.InteractionBubble')

local World = game:GetService('World')
local Players = game:GetService('Players')

local ScreenFerry = { Seq = 0, Legs = {} }

local function notice(msg)
    if _G.LocalMsgNotice then _G.LocalMsgNotice(msg) end
end

function ScreenFerry:Send(action)
    self.Seq = self.Seq + 1
    REUtil:GetRE('FerryAction'):FireServer({ action = action, seq = self.Seq })
end

-- 一条腿一个文字泡：legCfg 带 AnchorName / Radius / BubbleHeight，buttonText 如「乘船」
function ScreenFerry:CreateLeg(key, legCfg, action, buttonText)
    local anchor = Util:WaitForChild(World, legCfg.AnchorName)
    local player = Players.LocalPlayer
    local eui = player and player.PlayerGui and player.PlayerGui.EuiManager
    if not anchor or not eui then
        print('[ScreenFerry] 摆渡锚点或 EUI 未就绪', legCfg.AnchorName)
        return
    end
    local center = anchor.Position
    local ok, node = pcall(eui.CreateSceneNodeAtPosition, eui,
        Vector3.New(center.x, center.y + legCfg.BubbleHeight, center.z))
    if not ok or not node then
        print('[ScreenFerry] 文字泡创建失败', legCfg.AnchorName, tostring(node))
        return
    end
    Bubble.CreateButton(node, 'BtnFerry' .. action, buttonText, 0, function() self:Send(action) end)
    node.Visible = false
    self.Legs[key] = { Node = node, Center = center, Radius = legCfg.Radius, Visible = false }
end

function ScreenFerry:UpdateLegs()
    local character = Players.LocalPlayer and Players.LocalPlayer.Character
    local pos = character and character.Position
    for _, leg in pairs(self.Legs) do
        local visible = false
        if pos then
            local dx, dz = pos.x - leg.Center.x, pos.z - leg.Center.z
            visible = dx * dx + dz * dz <= leg.Radius * leg.Radius
        end
        if leg.Visible ~= visible then
            leg.Visible = visible
            pcall(function() leg.Node.Visible = visible end)
        end
    end
end

function ScreenFerry:UpdateCountdown(dt)
    if not self.CountdownLeft then return end
    self.CountdownLeft = self.CountdownLeft - (type(dt) == 'number' and dt or 0)
    if self.CountdownLeft <= 0 then
        self.CountdownLeft = nil
        if self.CountdownLabel then pcall(function() self.CountdownLabel.Visible = false end) end
        return
    end
    if self.CountdownLabel then
        pcall(function()
            self.CountdownLabel.Visible = true
            self.CountdownLabel.Text = string.format('开船倒计时 %d 秒', math.ceil(self.CountdownLeft))
        end)
    end
end

function ScreenFerry:OnState(state)
    if type(state) ~= 'table' then return end
    if state.phase == 'countdown' then
        self.CountdownLeft = tonumber(state.seconds) or GameCfg.Ferry.Outbound.CountdownSec
    elseif state.phase == 'departed' then
        self.CountdownLeft = nil
        if self.CountdownLabel then pcall(function() self.CountdownLabel.Visible = false end) end
        notice('船到虾池了')
    elseif state.phase == 'cancelled' then
        self.CountdownLeft = nil
        if self.CountdownLabel then pcall(function() self.CountdownLabel.Visible = false end) end
        notice('航班取消，船票已退')
    end
end

function ScreenFerry:OnResult(result)
    if type(result) ~= 'table' then return end
    if result.ok then
        if result.action == 'Board' then
            notice('船票已交，' .. tostring(result.seconds) .. ' 秒后开船')
        elseif result.action == 'Return' then
            notice('回到第一钓鱼区，金币 -' .. tostring(result.price))
        end
        return
    end
    local reasons = {
        ticket = '需要虾池船票（鳄雀鳝鱼头喂钓鱼佬可换）',
        coin = '金币不够，船家不开船',
        range = '离船太远了',
        sailing = '船已经在倒计时了，等下一班',
        teleport = '传送失败，金币已退',
    }
    notice(reasons[result.reason] or '摆渡暂时不可用')
end

function ScreenFerry:Start()
    local ferry = GameCfg.Ferry
    self:CreateLeg('outbound', ferry.Outbound, 'Board', '乘船')
    self:CreateLeg('return', ferry.Return, 'Return', '返程')
    -- 顶部倒计时条：代码建 EUITextLabel，与 ScreenMain 的运行时建节点同款
    local eui = Players.LocalPlayer and Players.LocalPlayer.PlayerGui
        and Players.LocalPlayer.PlayerGui.EuiManager
    local root = eui and eui:GetRootNode()
    if root then
        local resolution = eui:GetDeviceResolution()
        local ok, label = pcall(World.CreateUnit, World, 'EUITextLabel', {
            Parent = root, Name = 'FerryCountdown',
            Position = Vector2.New(resolution.x / 2, resolution.y - 120),
            Size = Vector2.New(360, 60), Text = '', FontSize = 36,
            TextColor = Color.New(255, 255, 255, 255),
        })
        if ok and label then
            label.Visible = false
            label.TouchEnabled = false
            label.SwallowTouchEnabled = false
            self.CountdownLabel = label
        else
            print('[ScreenFerry] 倒计时条创建失败', tostring(label))
        end
    end
    REUtil:GetRE('FerryResult').OnClientEvent:Connect(function(result) self:OnResult(result) end)
    REUtil:GetRE('FerryState').OnClientEvent:Connect(function(state) self:OnState(state) end)
    game:GetService('RunService').Heartbeat:Connect(function(dt)
        self:UpdateLegs()
        self:UpdateCountdown(dt)
    end)
end

return ScreenFerry

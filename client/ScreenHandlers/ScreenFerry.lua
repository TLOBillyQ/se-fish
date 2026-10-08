-- 摆渡交互与开船倒计时（#89 起；#127 扩到七区六航线）：每条航线两条腿——去程「乘船」与返程「返程」，
-- 各自在航线锚点旁一个文字泡。请求只发 FerryAction{action, routeId, seq}（seq 递增防重放），
-- 航线 id 由服务端校验；结果以服务端 FerryResult 为准。
-- 倒计时是服务端广播的 FerryState{phase, routeId, seconds}：**按航线分开记账**，
-- 不同航线的倒计时互不串台；顶部倒计时条只显示最近的一班并写明目的地。
-- 放在 ScreenHandlers 下（#89 端别约定），但不是 MgrGameUI 屏幕：随 client/main.lua 直接 Start，
-- 与 ScreenGM 的用法同款。
local GameCfg = require('common.GameCfg')
local BodyScale = require('common.BodyScale')
local REUtil = require('common.REUtil')
local Util = require('common.Util')

local Bubble = require('client.InteractionBubble')

local World = game:GetService('World')
local Players = game:GetService('Players')

local ScreenFerry = { Seq = 0, Legs = {}, Countdowns = {} }

local function notice(msg)
    if _G.LocalMsgNotice then _G.LocalMsgNotice(msg) end
end

-- 航线 id → 目的区中文名（给倒计时条与提示用）；返程的目的地是出发区。
-- 查不到就退回区 id / 占位词，不阻断表现。
function ScreenFerry:ZoneName(routeId, action)
    local route = GameCfg.Ferry.Route(routeId)
    if not route then return '目的地' end
    local zoneId = action == 'Return' and route.FromZoneId or route.ToZoneId
    for _, zone in ipairs(GameCfg.Zones) do
        if zone.Id == zoneId then return zone.Name end
    end
    return zoneId
end

function ScreenFerry:Send(action, routeId)
    self.Seq = self.Seq + 1
    REUtil:GetRE('FerryAction'):FireServer({ action = action, routeId = routeId, seq = self.Seq })
end

-- 一条腿一个文字泡：legCfg 带 AnchorName / Radius / BubbleHeight，buttonText 如「乘船」
function ScreenFerry:CreateLeg(key, routeId, legCfg, action, buttonText)
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
    -- 按钮名带锚点名：七区十二条腿名字互不重复
    Bubble.CreateButton(node, 'BtnFerry' .. legCfg.AnchorName, buttonText, 0,
        function() self:Send(action, routeId) end)
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
            local radius = BodyScale.InteractionRadius(character, leg.Radius)
            visible = dx * dx + dz * dz <= radius * radius
        end
        if leg.Visible ~= visible then
            leg.Visible = visible
            pcall(function() leg.Node.Visible = visible end)
        end
    end
end

-- 逐航线扣时；倒计时条显示剩余最少的一班（同一时刻可能有多条航线在倒计时）
function ScreenFerry:UpdateCountdown(dt)
    local step = type(dt) == 'number' and dt or 0
    local soonest, soonestLeft
    for routeId, left in pairs(self.Countdowns) do
        local remaining = left - step
        if remaining <= 0 then
            self.Countdowns[routeId] = nil
        else
            self.Countdowns[routeId] = remaining
            if not soonestLeft or remaining < soonestLeft then soonest, soonestLeft = routeId, remaining end
        end
    end
    if not self.CountdownLabel then return end
    if not soonest then
        pcall(function() self.CountdownLabel.Visible = false end)
        return
    end
    pcall(function()
        self.CountdownLabel.Visible = true
        self.CountdownLabel.Text = string.format('前往%s %d 秒', self:ZoneName(soonest), math.ceil(soonestLeft))
    end)
end

function ScreenFerry:OnState(state)
    if type(state) ~= 'table' then return end
    local routeId = state.routeId
    if type(routeId) ~= 'string' then
        print('[ScreenFerry] 摆渡状态缺少航线 id，忽略', tostring(state.phase))
        return
    end
    if state.phase == 'countdown' then
        self.Countdowns[routeId] = tonumber(state.seconds) or 5
    elseif state.phase == 'departed' then
        self.Countdowns[routeId] = nil
        notice('已经到' .. self:ZoneName(routeId) .. '了')
    elseif state.phase == 'cancelled' then
        self.Countdowns[routeId] = nil
        notice('前往' .. self:ZoneName(routeId) .. '的航班取消，船票已退')
    end
end

function ScreenFerry:OnResult(result)
    if type(result) ~= 'table' then return end
    if result.ok then
        if result.action == 'Board' then
            notice('船票已交，' .. tostring(result.seconds) .. ' 秒后开船')
        elseif result.action == 'Return' then
            notice('已经回到' .. self:ZoneName(result.routeId, 'Return') .. '，金币 -' .. tostring(result.price))
        end
        return
    end
    local reasons = {
        route = '找不到这条航线，请重进本图',
        ticket = '需要本区船票（本区首领信物喂钓鱼佬可换）',
        coin = '金币不够，船家不开船',
        range = '离船太远了',
        sailing = '这条航线已经在倒计时了，等下一班',
        pending = '上一趟摆渡还没结清，稍后再试',
        teleport = '传送失败，金币已退',
    }
    notice(reasons[result.reason] or '摆渡暂时不可用')
end

function ScreenFerry:Start()
    -- 六条航线 × 去程/返程 = 十二条腿；未建区的锚点取不到时只记日志，不影响既有区的腿
    for index, route in ipairs(GameCfg.Ferry.Routes) do
        self:CreateLeg(index .. ':out', route.Id, route.Outbound, 'Board', '乘船')
        self:CreateLeg(index .. ':return', route.Id, route.Return, 'Return', '返程')
    end
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

-- 烧烤客户端（#137 T16，策划案烧烤段）：三区起每个烧烤锚点（GameCfg.Grill.Points，#125 场景合同）
-- 上方一个「烧烤」文字泡，2 米内可见。点击开烤；烤的是信物时服务端先回 token-warn，
-- 这里提示「失去兑换与抽奖资格」并在确认窗口期内再点才带 confirm=true 上行。
-- 烤炉弹窗是运行时自绘面板（不走 EUI 预制，与 ScreenSurvival 同理）：显示物品、已烤时间与
-- 当前倍率（两位小数，曲线见 common/GrillCurve.lua），倍率只是本地预告——结算以服务端
-- World:GetServerTime() 为准，快慢帧不改变收益。「取出」上行 Takeout；烤糊由服务端推
-- GrillState{state='burnt'} 撤板并提示「你的鱼烤糊了！」。
-- 不经 MgrGameUI 加载（没有同名 EUI 节点），由 client/main.lua Task:Spawn 直接启动（同 ScreenFerry）。
local GameCfg = require('common.GameCfg')
local GrillCurve = require('common.GrillCurve')
local REUtil = require('common.REUtil')
local Util = require('common.Util')
local Bubble = require('client.InteractionBubble')

local World = game:GetService('World')
local Players = game:GetService('Players')

local Panel = { Seq = 0, Bubbles = {}, Session = nil, ArmedUntil = 0 }

local ColorBlockImage = 'official://image/11017' -- 官方正方形纯色块（ScreenSurvival 同款约定）

local function cfg()
    return GameCfg.Grill
end

local function notice(msg)
    if _G.LocalMsgNotice then _G.LocalMsgNotice(msg) end
end

local function create(kind, parent, name, x, y, width, height, props)
    props = props or {}
    props.Parent = parent
    props.Name = name
    props.Position = Vector2.New(x, y)
    props.Size = Vector2.New(width, height)
    local node = game:GetService('World'):CreateUnit(kind, props)
    if not node then error('烧烤界面节点创建失败：' .. name) end
    node.TouchEnabled = false
    node.SwallowTouchEnabled = false
    return node
end

function Panel:Now()
    local ok, now = pcall(function() return World:GetServerTime() end)
    return ok and tonumber(now) or 0
end

function Panel:Send(action, confirm)
    self.Seq = self.Seq + 1
    local payload = { action = action, seq = self.Seq }
    if confirm then payload.confirm = true end
    REUtil:GetRE('GrillAction'):FireServer(payload)
end

local function itemName(itemId)
    local definition = itemId and GameCfg.Items.Definitions[itemId]
    return definition and definition.Name or tostring(itemId or '')
end

-- 弹窗显隐与静态内容；进度数字由 Tick 每帧刷
function Panel:ShowPanel()
    if self.Root then pcall(function() self.Root.Visible = true end) end
    local session = self.Session
    if session and self.Title then
        pcall(function() self.Title.Text = itemName(session.itemId) end)
    end
    self:Tick()
end

function Panel:HidePanel()
    if self.Root then pcall(function() self.Root.Visible = false end) end
end

-- 帧刷新：已烤秒数与当前倍率（两位小数）；ready 会话用服务端冻结倍率
function Panel:Tick()
    local session = self.Session
    if not session or not self.Root or not self.Root.Visible then return end
    local elapsed = math.max(0, self:Now() - (session.startedAt or self:Now()))
    local rate = session.rate or GrillCurve.Rate(elapsed, cfg()) or 0
    if self.TimeLabel then
        pcall(function() self.TimeLabel.Text = '已烤 ' .. GrillCurve.Format(elapsed) .. ' 秒' end)
    end
    if self.RateLabel then
        pcall(function() self.RateLabel.Text = '倍率 ' .. GrillCurve.Format(rate) end)
    end
end

-- 点击「烧烤」气泡：有会话就弹窗同步进度；没会话发开烤（信物确认期内带 confirm）
function Panel:ClickGrill()
    if self.Session and (self.Session.state == 'cooking' or self.Session.state == 'ready') then
        self:Send('Query')
        self:ShowPanel()
        return
    end
    local confirm = self:Now() <= (self.ArmedUntil or 0)
    self.ArmedUntil = 0
    self:Send('Start', confirm)
end

function Panel:OnResult(result)
    if type(result) ~= 'table' then return end
    if result.ok then
        if result.action == 'Start' then
            self.Session = { state = 'cooking', itemId = result.itemId, mult = result.mult,
                startedAt = result.startedAt }
            self:ShowPanel()
        elseif result.action == 'Takeout' then
            notice(cfg().CookedPrefix .. itemName(result.itemId)
                .. '（倍率 ' .. GrillCurve.Format(result.rate or 1) .. '）')
            self.Session = nil
            self:HidePanel()
        end
        return
    end
    local reason = result.reason
    if reason == 'token-warn' then
        notice(cfg().TokenWarnText)
        self.ArmedUntil = self:Now() + 5 -- 确认窗口：5 秒内再点才真烤信物
    elseif reason == 'no-fish' then
        notice(cfg().NoFishText)
    elseif reason == 'full' then
        notice(cfg().FullText)
    elseif reason == 'burnt' then
        notice(cfg().BurntText)
        self.Session = nil
        self:HidePanel()
    elseif reason == 'busy' then
        self:Send('Query') -- 已有自己的一炉：弹窗看进度
        self:ShowPanel()
    elseif reason == 'no-session' or reason == 'not-alive' then
        self.Session = nil
        self:HidePanel()
    end
end

function Panel:OnState(state)
    if type(state) ~= 'table' then return end
    if state.state == 'cooking' or state.state == 'ready' then
        self.Session = { state = state.state, itemId = state.itemId, mult = state.mult,
            startedAt = state.startedAt, rate = state.rate }
        self:Tick()
    elseif state.state == 'burnt' then
        notice(cfg().BurntText)
        self.Session = nil
        self:HidePanel()
    else
        self.Session = nil
        self:HidePanel()
    end
end

-- 每个烧烤锚点一个「烧烤」文字泡，本地角色 2 米内才显示
function Panel:CreateBubble(anchor, suffix)
    local player = Players.LocalPlayer
    local eui = player and player.PlayerGui and player.PlayerGui.EuiManager
    local center = anchor.Position
    if not eui or not center then return end
    local ok, node = pcall(eui.CreateSceneNodeAtPosition, eui,
        Vector3.New(center.x, center.y + cfg().BubbleHeight, center.z))
    if not ok or not node then
        print('[ScreenGrill] 烧烤文字泡创建失败', tostring(node))
        return
    end
    Bubble.CreateButton(node, 'BtnGrill' .. suffix, cfg().BubbleText, 0,
        function() self:ClickGrill() end)
    node.Visible = false
    self.Bubbles[#self.Bubbles + 1] = { Node = node, Center = center, Visible = false }
end

function Panel:UpdateBubbles()
    local character = Players.LocalPlayer and Players.LocalPlayer.Character
    local pos = character and character.Position
    local radius = cfg().Radius
    for _, bubble in ipairs(self.Bubbles) do
        local visible = false
        if pos then
            local dx, dz = pos.x - bubble.Center.x, pos.z - bubble.Center.z
            visible = dx * dx + dz * dz <= radius * radius
        end
        if bubble.Visible ~= visible then
            bubble.Visible = visible
            local ok, err = pcall(function() bubble.Node.Visible = visible end)
            if not ok then print('[ScreenGrill] 气泡显隐失败', tostring(err)) end
        end
    end
end

function Panel:BuildPanel()
    local okRoot, root, resolution = pcall(function()
        local eui = Players.LocalPlayer.PlayerGui.EuiManager
        return eui and eui:GetRootNode(), eui and eui:GetDeviceResolution()
    end)
    if not okRoot or not root then
        print('[ScreenGrill] EUI 未就绪，跳过建面板')
        return
    end
    local size = resolution or { x = 1920, y = 1080 }
    local cx, cy = size.x / 2, size.y / 2
    local ok, err = pcall(function()
        local banner = create('EUIImage', root, 'GrillPanel', cx - 280, cy - 200, 560, 400, {
            Color = Color.New(0, 0, 0, 180), Image = ColorBlockImage, Visible = false })
        self.Root = banner
        self.Title = create('EUITextLabel', banner, 'GrillTitle', 0, 20, 560, 60, {
            Text = '', FontSize = 36, TextColor = Color.New(255, 220, 150, 255) })
        self.TimeLabel = create('EUITextLabel', banner, 'GrillTime', 0, 100, 560, 50, {
            Text = '', FontSize = 30, TextColor = Color.New(255, 255, 255, 255) })
        self.RateLabel = create('EUITextLabel', banner, 'GrillRate', 0, 160, 560, 50, {
            Text = '', FontSize = 30, TextColor = Color.New(255, 255, 255, 255) })
        local takeout = create('EUIButton', banner, 'GrillTakeout', 70, 250, 180, 80, {
            ButtonText = '', NormalImage = ColorBlockImage, PressImage = ColorBlockImage,
            Color = Color.New(230, 120, 40, 255) })
        takeout.TouchEnabled = true
        create('EUITextLabel', takeout, 'GrillTakeoutText', 0, 0, 180, 80, {
            Text = cfg().TakeoutText, FontSize = 32, TextColor = Color.New(255, 255, 255, 255),
            LocalZOrder = 1 })
        takeout.OnClicked:Connect(function() self:Send('Takeout') end)
        local close = create('EUIButton', banner, 'GrillClose', 310, 250, 180, 80, {
            ButtonText = '', NormalImage = ColorBlockImage, PressImage = ColorBlockImage,
            Color = Color.New(120, 120, 120, 255) })
        close.TouchEnabled = true
        create('EUITextLabel', close, 'GrillCloseText', 0, 0, 180, 80, {
            Text = '关闭', FontSize = 32, TextColor = Color.New(255, 255, 255, 255), LocalZOrder = 1 })
        close.OnClicked:Connect(function() self:HidePanel() end)
    end)
    if not ok then
        print('[ScreenGrill] 面板创建失败', tostring(err))
        self.Root = nil
    end
end

function Panel:Start()
    self:BuildPanel()
    for index, point in ipairs(cfg().Points) do
        local anchor = Util:WaitForChild(World, point.AnchorName)
        if anchor then
            self:CreateBubble(anchor, tostring(index))
        else
            print('[ScreenGrill] 找不到烧烤锚点', point.ZoneId, point.AnchorName)
        end
    end
    REUtil:GetRE('GrillResult').OnClientEvent:Connect(function(result) self:OnResult(result) end)
    REUtil:GetRE('GrillState').OnClientEvent:Connect(function(state) self:OnState(state) end)
    game:GetService('RunService').Heartbeat:Connect(function()
        self:UpdateBubbles()
        self:Tick()
    end)
end

return Panel

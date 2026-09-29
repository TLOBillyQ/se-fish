-- 生存状态客户端蒙版（#131 T10）：服端按状态变化广播 SurvivalState
-- （phase + 服务端时刻的 endsAt / weakUntil），这里只做展示与上行交互：
-- 濒死 / 死亡居中大字 + 倒计时条，虚弱底部提示，肾上腺素按钮在濒死时可用。
-- 正常状态整个面板隐藏；任何节点创建失败都只记日志，不阻塞主流程。
local GameCfg = require('common.GameCfg')
local REUtil = require('common.REUtil')

local Panel = { Seq = 0, Phase = 'alive', EndsAt = nil, WeakUntil = nil }

local ColorBlockImage = 'official://image/11017' -- 官方正方形纯色块（ScreenGM 同款约定）

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
    if not node then error('生存界面节点创建失败：' .. name) end
    node.TouchEnabled = false
    node.SwallowTouchEnabled = false
    return node
end

function Panel:Send(action)
    self.Seq = self.Seq + 1
    REUtil:GetRE('SurvivalAction'):FireServer({ action = action, seq = self.Seq })
end

local RESULT_TEXT = {}

-- 倒计时 / 提示刷新（RunService 驱动）；时间为负按 0 处理，等服端广播撤板
function Panel:Tick()
    if self.Phase == 'downed' or self.Phase == 'dead' then
        local left = math.max(0, math.ceil((self.EndsAt or 0) - self:Now()))
        local key = self.Phase == 'downed' and 'DownedTitle' or 'DeadTitle'
        local base = GameCfg.Survival[key]
        if self.Title then pcall(function() self.Title.Text = base .. '（' .. left .. ' 秒）' end) end
    end
    if self.WeakUntil then
        local left = math.max(0, math.ceil(self.WeakUntil - self:Now()))
        if self.WeakLabel then
            pcall(function()
                self.WeakLabel.Visible = left > 0
                self.WeakLabel.Text = GameCfg.Survival.WeakText .. '（' .. left .. ' 秒）'
            end)
        end
        if left <= 0 then self.WeakUntil = nil end
    end
end

function Panel:Now()
    local ok, now = pcall(function() return game:GetService('World'):GetServerTime() end)
    return ok and tonumber(now) or 0
end

function Panel:SetPhase(state)
    local phase = state and state.phase or 'alive'
    self.Phase = phase
    self.EndsAt = tonumber(state and state.endsAt) or nil
    self.WeakUntil = tonumber(state and state.weakUntil) or nil
    local downed = phase == 'downed' or phase == 'dead'
    if self.Banner then pcall(function() self.Banner.Visible = downed end) end
    if self.Title then
        pcall(function()
            self.Title.Visible = downed
            self.Title.Text = GameCfg.Survival[phase == 'dead' and 'DeadTitle' or 'DownedTitle']
        end)
    end
    if self.AdrenalineBtn then pcall(function() self.AdrenalineBtn.Visible = phase == 'downed' end) end
    if phase == 'dead' then notice(GameCfg.Survival.CallHelpText) end
    self:Tick() -- 立即渲染一次，不空一个心跳帧
end

function Panel:OnResult(result)
    if type(result) ~= 'table' then return end
    if result.ok then
        if result.reason then notice(result.reason) end
        return
    end
    notice(RESULT_TEXT[result.reason] or GameCfg.Survival.AdrenalineText)
end

function Panel:Start()
    RESULT_TEXT = {
        ['busy'] = GameCfg.Survival.AdrenalineText,
        ['no-adrenaline'] = GameCfg.Survival.NoAdrenalineText,
        ['not-downed'] = '',
        ['replay'] = '',
    }
    local okRoot, root = pcall(function()
        local eui = game:GetService('Players').LocalPlayer.PlayerGui.EuiManager
        return eui and eui:GetRootNode(), eui and eui:GetDeviceResolution()
    end)
    if not okRoot or not root then
        print('[ScreenSurvival] EUI 未就绪，跳过建面板')
        return
    end
    local resolution = root[2] or { x = 1920, y = 1080 }
    local cx, cy = resolution.x / 2, resolution.y / 2
    local banner = create('EUIImage', root[1], 'SurvivalBanner', cx - 320, cy - 90, 640, 180, {
        Color = Color.New(0, 0, 0, 160), Image = ColorBlockImage, Visible = false })
    self.Banner = banner
    self.Title = create('EUITextLabel', banner, 'SurvivalTitle', 0, -80, 640, 80, {
        Text = '', FontSize = 48, TextColor = Color.New(255, 80, 80, 255), LocalZOrder = 1 })
    local btn = create('EUIButton', banner, 'SurvivalAdrenaline', 140, 20, 360, 80, {
        ButtonText = '', NormalImage = ColorBlockImage, PressImage = ColorBlockImage,
        Color = Color.New(230, 120, 40, 255), Visible = false })
    btn.TouchEnabled = true
    self.AdrenalineBtn = btn
    create('EUITextLabel', btn, 'SurvivalAdrenalineText', 0, 0, 360, 80, {
        Text = GameCfg.Survival.AdrenalineText, FontSize = 32,
        TextColor = Color.New(255, 255, 255, 255), LocalZOrder = 1 })
    if btn.OnClicked then
        btn.OnClicked:Connect(function() self:Send('UseAdrenaline') end)
    end
    self.WeakLabel = create('EUITextLabel', root[1], 'SurvivalWeak', cx - 320, resolution.y - 200, 640, 60, {
        Text = '', FontSize = 30, TextColor = Color.New(200, 200, 255, 255), Visible = false })
    REUtil:GetRE('SurvivalState').OnClientEvent:Connect(function(state) self:SetPhase(state) end)
    REUtil:GetRE('SurvivalResult').OnClientEvent:Connect(function(result) self:OnResult(result) end)
    game:GetService('RunService').Heartbeat:Connect(function() self:Tick() end)
end

return Panel

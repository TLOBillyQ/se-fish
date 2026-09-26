-- 仅调试地图显示的 GM 面板；按钮只发送固定参数，余额与结果以服务端同步为准。
local GameCfg = require('common.GameCfg')
local GameUI = require('client.GameUI')
local REUtil = require('common.REUtil')

local Panel = { Connections = {}, Nodes = {} }

local Groups = {
    { title = '金币', actions = {
        { label = '+100 金币', payload = { action = 'Coin', amount = 100 } },
        { label = '+6300 金币', payload = { action = 'Coin', amount = 6300 } },
    } },
}

local function listen(self, signal, callback)
    self.Connections[#self.Connections + 1] = signal:Connect(callback)
end

local function create(self, kind, parent, name, x, y, width, height, props)
    props = props or {}
    props.Parent = parent
    props.Name = name
    props.Position = Vector2.New(x, y)
    props.Size = Vector2.New(width, height)
    local node = game:GetService('World'):CreateUnit(kind, props)
    if not node then error('GM 界面节点创建失败：' .. name) end
    self.Nodes[#self.Nodes + 1] = node
    return node
end

local function label(self, parent, name, text, x, y, width, height, fontSize)
    local node = create(self, 'EUITextLabel', parent, name, x, y, width, height, {
        Text = text, FontSize = fontSize, TextColor = Color.New(255, 255, 255, 255),
    })
    node.TouchEnabled = false
    node.SwallowTouchEnabled = false
    return node
end

local function button(self, parent, name, text, x, y, width, height, callback)
    local node = create(self, 'EUIButton', parent, name, x, y, width, height, {
        ButtonText = text, ButtonTextFontSize = 23,
        ButtonNormalColor = Color.New(42, 89, 126, 255),
        ButtonTextColor = Color.New(255, 255, 255, 255),
    })
    node.TouchEnabled = true
    listen(self, node.OnClicked, callback)
    return node
end

function Panel:ShowCoin()
    if not self.CoinLabel then return end
    local player = game:GetService('Players').LocalPlayer
    local coin = player and player:GetAttribute('FishCoin')
    self.CoinLabel.Text = '当前金币：' .. (type(coin) == 'number' and tostring(math.floor(coin)) or '等待同步')
end

function Panel:Toggle()
    self.IsOpen = not self.IsOpen
    self.Background.Visible = self.IsOpen
    self.Entry.ButtonText = self.IsOpen and '收起 GM' or 'GM'
    if self.IsOpen then self:ShowCoin() end
    print('[GMPanel]', self.IsOpen and '展开' or '收起')
end

function Panel:Start()
    if not (GameCfg.Debug and GameCfg.Debug.Enabled) then return end
    local manager = GameUI:GetEuiManager()
    if not manager then return end
    local root = manager:GetRootNode()
    local resolution = manager:GetDeviceResolution()
    local player = game:GetService('Players').LocalPlayer
    if not root or not resolution or not player then return end
    if self.Started then
        if self.Root == root then return end
        self:Destroy()
    end
    local ok, err = pcall(self.Build, self, root, resolution, player)
    if not ok then
        print('[GMPanel] 初始化失败', err)
        self:Destroy()
        return
    end
    self.Root = root
    self.Started = true
end

function Panel:Build(root, resolution, player)
    local width = 420
    local right = math.max(width / 2 + 16, resolution.x - 560)
    local top = resolution.y - 105
    local height = 194
    for _, group in ipairs(Groups) do
        height = height + 53 + math.ceil(#group.actions / 2) * 78
    end
    self.Entry = button(self, root, 'GM入口', 'GM', right, top, 170, 64,
        function() self:Toggle() end)
    self.Background = create(self, 'EUIImage', root, 'GM面板', right, top - height / 2 - 75, width, height, {
        Color = Color.New(20, 34, 49, 235),
    })
    local panel = self.Background
    local center = 0
    local topRow = height / 2 - 44
    label(self, panel, 'GM标题', '调试操作', center, topRow, width - 24, 45, 29)
    self.CoinLabel = label(self, panel, 'GM金币状态', '当前金币：等待同步', center, topRow - 49,
        width - 24, 40, 24)
    local y = topRow - 94
    for _, group in ipairs(Groups) do
        label(self, panel, 'GM分组_' .. group.title, group.title, center, y, width - 24, 34, 24)
        y = y - 53
        for index, action in ipairs(group.actions) do
            local item = action
            local column = (index - 1) % 2
            local x = center + (column - 0.5) * 196
            local rowY = y - math.floor((index - 1) / 2) * 78
            button(self, panel, 'GM操作_' .. group.title .. index, item.label, x, rowY, 182, 55, function()
                REUtil:GetRE('GMAction'):FireServer({ action = item.payload.action, amount = item.payload.amount })
                self.Feedback.Text = '等待服务端确认…'
                print('[GMPanel] 请求', item.payload.action, item.payload.amount)
            end)
        end
        y = y - math.ceil(#group.actions / 2) * 78
    end
    self.Feedback = label(self, panel, 'GM反馈', '等待操作', center, y, width - 24, 50, 22)
    panel.Image = 'official://image/10000'
    panel.Color = Color.New(20, 34, 49, 235)
    self.Background.TouchEnabled = false
    self.Background.SwallowTouchEnabled = false
    self.Background.Visible = false
    self:ShowCoin()
    listen(self, player:GetAttributeChangedSignal('FishCoin'), function() self:ShowCoin() end)
    listen(self, REUtil:GetRE('GMResult').OnClientEvent, function(result)
        if type(result) ~= 'table' or result.action ~= 'Coin' then return end
        self.Feedback.Text = result.ok and '服务端确认：金币发放成功'
            or ('服务端拒绝：' .. tostring(result.reason or '请求未通过'))
        self:ShowCoin()
        print('[GMPanel] 结果', result.ok and '成功' or '拒绝', tostring(result.reason or ''))
    end)
end

function Panel:Destroy()
    for _, connection in ipairs(self.Connections) do connection:Disconnect() end
    for index = #self.Nodes, 1, -1 do self.Nodes[index]:Destroy() end
    self.Connections = {}
    self.Nodes = {}
    self.Started = false
    self.Root = nil
    self.IsOpen = false
    self.Entry = nil
    self.Background = nil
    self.CoinLabel = nil
    self.Feedback = nil
end

return Panel

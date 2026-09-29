-- 钓场商店界面（#48/#90 多摊位；#130 四页分页）：复用场景里既有的 ScreenShop 节点，
-- 编辑器侧只有两行商品节点（ShopItemIcon/Name<i>、BtnShopBuy<i> 内的 LabelShopPrice<i>），
-- 外加 LabelCurCoin 与 BtnShopClose；其余页签、翻页与补位行全部运行时创建。
-- 页签取 GameCfg.Shop.Pages（钓具/武器/升级/金币）；行内容用 GameCfg.Shop.ListForPage 同口径排序
-- （含锁定行灰显）；升级行无 itemKey，购买一律发货架行编号 number；结果以服务端 ShopResult 为准。
-- 金币页是平台商店入口：平台不可用时提示并可返回其他分页，不伪成功（汇率/商品 ID 由后台交付）。
local GameCfg = require('common.GameCfg')
local LocalShop = require('client.LocalShop')

local SquareButtonImage = 'official://image/11017'
local RowCount = 2            -- 编辑器侧商品行节点数
local PageSize = 8            -- 每页行数（编辑器 2 行 + 运行时补 6 行）
local TabNames = GameCfg.Shop.Pages

local ScreenHandler = { UINodes = { 'BtnShopClose', 'LabelCurCoin' }, UINodeMap = {}, Seq = 0,
    Page = TabNames[1], PageIndex = 1, Purchases = {}, UpgradeLevels = {} }

for index = 1, RowCount do
    for _, prefix in ipairs({ 'ShopItemIcon', 'ShopItemName', 'BtnShopBuy', 'LabelShopPrice' }) do
        ScreenHandler.UINodes[#ScreenHandler.UINodes + 1] = prefix .. index
    end
end

local function styleButton(button)
    if not button then return end
    button.ButtonText = ''
    button.NormalImage = SquareButtonImage
    button.PressImage = SquareButtonImage
    button.DisableImage = SquareButtonImage
end

local function createButtonLabel(parent, button, name, text, fontSize)
    local label = game:GetService('World'):CreateUnit('EUITextLabel', {
        Parent = parent, Name = name, Position = button.Position, Size = button.Size,
        Text = text, FontSize = fontSize, TextColor = Color.New(255, 255, 255, 255),
    })
    if label then
        label.TouchEnabled = false
        label.SwallowTouchEnabled = false
        label.LocalZOrder = 1
    end
    return label
end

-- 行状态：locked（摊位等级不够或强化越级，灰显）/ owned（限购已满或强化级别已购）/ buy（可购买）
function ScreenHandler:RowState(goods, level)
    if goods.MinShopLevel > level then return 'locked' end
    if goods.Upgrade then
        local current = self:CurrentUpgradeLevel(goods.Upgrade.kind)
        if goods.Upgrade.level <= current then return 'owned' end
        if goods.Upgrade.level > current + 1 then return 'locked' end
    end
    if (goods.PurchaseLimit or 0) > 0 and (self.Purchases[goods.Number] or 0) >= goods.PurchaseLimit then
        return 'owned'
    end
    return 'buy'
end

function ScreenHandler:CurrentUpgradeLevel(kind)
    if kind == 'backpack' then return self.UpgradeLevel or 0 end
    return self.UpgradeLevels[kind] or 0
end

function ScreenHandler:SetPage(page)
    self.Page = page
    self.PageIndex = 1
    self:ShowGoods()
end

function ScreenHandler:TurnPage(delta)
    self.PageIndex = math.max(1, self.PageIndex + delta)
    self:ShowGoods()
end

function ScreenHandler:Buy(index)
    local row = self.VisibleRows and self.VisibleRows[index]
    if not row or not self.IsOpen then return end
    if self:RowState(row.goods, self.Level or 1) ~= 'buy' then return end
    self.Seq = self.Seq + 1
    _G.REUtil:GetRE('ShopAction'):FireServer({ action = 'Buy', number = row.goods.Number, seq = self.Seq })
end

function ScreenHandler:ShowCoin()
    local label = self.UINodeMap.LabelCurCoin
    local player = game:GetService('Players').LocalPlayer
    if label and player then label.Text = tostring(math.floor(tonumber(player:GetAttribute('FishCoin')) or 0)) end
end

-- 金币页：平台商店入口（降级口径）。平台不可用时只提示、停留本屏（页签可返回），不伪成功。
function ScreenHandler:ShowCoinPage()
    for index = 1, PageSize do self:SetRowVisible(index, nil) end
    self.VisibleRows = {}
    self.PrevButton.Visible = false
    self.NextButton.Visible = false
    self.CoinHint.Visible = true
    self.CoinButton.Visible = true
end

function ScreenHandler:OpenPlatformShop()
    local platform = rawget(_G, 'PlatformShop')
    if type(platform) ~= 'table' or type(platform.Open) ~= 'function' then
        self.CoinHint.Text = '平台商店暂不可用，请稍后再试；可返回其他分页继续购买金币商品'
        return
    end
    local ok, err = pcall(function() platform:Open() end)
    self.CoinHint.Text = ok and '已请求打开平台商店，请在平台侧完成购买'
        or ('平台商店打开失败：' .. tostring(err) .. '；可返回其他分页')
end

-- 单行渲染：编辑器行（1..RowCount）写既有节点；运行时行写补位按钮与标签
function ScreenHandler:SetRowVisible(index, goods)
    local state = goods and self:RowState(goods, self.Level or 1) or nil
    if index <= RowCount then
        local nodes = self.UINodeMap
        local definition = goods and goods.ItemId and GameCfg.Items.Definitions[goods.ItemId] or nil
        for _, prefix in ipairs({ 'ShopItemIcon', 'ShopItemName', 'BtnShopBuy' }) do
            local node = nodes[prefix .. index]
            if node then node.Visible = goods ~= nil end
        end
        if nodes['LabelShopPrice' .. index] then nodes['LabelShopPrice' .. index].Visible = goods ~= nil end
        if goods then
            if nodes['ShopItemIcon' .. index] and definition then
                nodes['ShopItemIcon' .. index].Image = definition.Icon
            end
            if nodes['ShopItemName' .. index] then
                nodes['ShopItemName' .. index].Text = goods.Name
                    .. (state == 'owned' and '（已购）' or state == 'locked' and '（需 ' .. goods.MinShopLevel .. ' 级摊位）' or '')
            end
            if nodes['LabelShopPrice' .. index] then
                nodes['LabelShopPrice' .. index].Text = tostring(goods.Price)
            end
            local btn = nodes['BtnShopBuy' .. index]
            if btn then
                btn.TouchEnabled = state == 'buy'
                btn.Disabled = state ~= 'buy'
            end
        end
        return
    end
    local btn = self.ExtraButtons and self.ExtraButtons[index]
    if not btn then return end
    btn.Visible = goods ~= nil
    if goods and self.ExtraLabels[index] then
        self.ExtraLabels[index].Text = goods.Name .. '  ' .. tostring(goods.Price) .. ' 金币'
            .. (state == 'owned' and '（已购）' or state == 'locked' and '（需 ' .. goods.MinShopLevel .. ' 级摊位）' or '')
    end
    btn.TouchEnabled = state == 'buy'
    btn.Disabled = state ~= 'buy'
end

function ScreenHandler:ShowGoods()
    local shop = GameCfg.Shop
    -- 站在哪个摊位旁开的商店就用哪个摊位的等级；兜底取第一个摊位（等级最低）
    local level = (LocalShop.Stand and LocalShop.Stand.Level) or shop.Stands[1].Level
    self.Level = level
    for name, tab in pairs(self.PageTabs or {}) do
        tab.ButtonNormalColor = name == self.Page and Color.New(36, 130, 94, 255)
            or Color.New(54, 100, 140, 255)
    end
    self.CoinHint.Visible = false
    self.CoinButton.Visible = false
    if self.Page == '金币' then self:ShowCoinPage() return end
    local rows = shop.ListForPage(level, self.Page, true)
    local maxPage = math.max(1, math.ceil(#rows / PageSize))
    if self.PageIndex > maxPage then self.PageIndex = maxPage end
    self.PrevButton.Visible = self.PageIndex > 1
    self.NextButton.Visible = self.PageIndex < maxPage
    local start = (self.PageIndex - 1) * PageSize
    self.VisibleRows = {}
    for index = 1, PageSize do
        local goods = rows[start + index]
        self.VisibleRows[index] = goods and { goods = goods } or nil
        self:SetRowVisible(index, goods)
    end
end

-- 购买结果回包：会话内累计购买次数与强化等级（服务端仍是唯一权威，失败不回包计数）
function ScreenHandler:NoteResult(result)
    if type(result) ~= 'table' then return end
    if result.ok then
        if result.number then self.Purchases[result.number] = (self.Purchases[result.number] or 0) + 1 end
        if result.kind and result.level then
            self.UpgradeLevels[result.kind] = math.max(self.UpgradeLevels[result.kind] or 0, result.level)
        end
        if result.action == 'UpgradeStorage' and result.level then self.UpgradeLevel = result.level end
    end
    if self.IsOpen then self:ShowGoods() self:ShowCoin() end
end

function ScreenHandler:Init()
    if self.Inited and self.BoundRootNode == self.RootNode then return end
    for _, connection in ipairs(self.Connections or {}) do connection:Disconnect() end
    for _, btn in pairs(self.ExtraButtons or {}) do btn:Destroy() end
    for _, label in pairs(self.ExtraLabels or {}) do label:Destroy() end
    for _, btn in pairs(self.PageTabs or {}) do btn:Destroy() end
    for _, btn in pairs(self.PageButtons or {}) do btn:Destroy() end
    if self.CoinHint then self.CoinHint:Destroy() end
    if self.CoinButton then self.CoinButton:Destroy() end
    if self.CoinButtonLabel then self.CoinButtonLabel:Destroy() end
    self.ExtraButtons, self.ExtraLabels = {}, {}
    self.PageTabs, self.PageButtons = {}, {}
    self.CoinHint, self.CoinButton, self.CoinButtonLabel = nil, nil, nil
    self.VisibleRows = {}
    self.Connections = {}
    local function listen(signal, callback)
        if signal then self.Connections[#self.Connections + 1] = signal:Connect(callback) end
    end
    for index = 1, RowCount do
        local btn = self.UINodeMap['BtnShopBuy' .. index]
        if btn then
            styleButton(btn)
            btn.ButtonNormalColor = Color.New(54, 100, 140, 255)
            btn.ButtonPressColor = Color.New(36, 130, 94, 255)
            btn.ButtonDisableColor = Color.New(120, 120, 120, 255)
            btn.TouchEnabled = true
            listen(btn.OnClicked, function() self:Buy(index) end)
        end
    end
    local close = self.UINodeMap.BtnShopClose
    if close then
        styleButton(close)
        close.ButtonNormalColor = Color.New(54, 100, 140, 255)
        close.ButtonPressColor = Color.New(36, 130, 94, 255)
        close.ButtonDisableColor = Color.New(120, 120, 120, 255)
        self.CloseLabel = createButtonLabel(close.Parent, close, 'LabelShopCloseTheme', '关闭', 26)
        listen(close.OnClicked, function() _G.MgrGameUI:CloseScreen('ScreenShop') end)
    end
    local root = self.RootNode
    local world = game:GetService('World')
    local resolution = _G.GameUI:GetEuiManager():GetDeviceResolution()
    local x, y = resolution.x / 2, resolution.y / 2 - 110
    -- 页签（四页分页，#130）
    for index, name in ipairs(TabNames) do
        local tab = world:CreateUnit('EUIButton', {
            Parent = root, Name = 'BtnShopPage' .. name,
            Position = Vector2.New(x - 330 + (index - 1) * 220, y + 320), Size = Vector2.New(200, 70),
        })
        styleButton(tab)
        tab.ButtonNormalColor = Color.New(54, 100, 140, 255)
        tab.ButtonPressColor = Color.New(36, 130, 94, 255)
        tab.ButtonDisableColor = Color.New(120, 120, 120, 255)
        tab.TouchEnabled = true
        self.PageTabs[name] = tab
        createButtonLabel(root, tab, 'LabelShopPage' .. name, name, 26)
        listen(tab.OnClicked, function() self:SetPage(name) end)
    end
    -- 页内翻页（升级页 24 行，#130）
    self.PrevButton = world:CreateUnit('EUIButton', {
        Parent = root, Name = 'BtnShopPrev', Position = Vector2.New(x - 160, y + 210), Size = Vector2.New(300, 70),
    })
    self.NextButton = world:CreateUnit('EUIButton', {
        Parent = root, Name = 'BtnShopNext', Position = Vector2.New(x + 160, y + 210), Size = Vector2.New(300, 70),
    })
    for _, pair in ipairs({ { self.PrevButton, '上一页' }, { self.NextButton, '下一页' } }) do
        styleButton(pair[1])
        pair[1].ButtonNormalColor = Color.New(54, 100, 140, 255)
        pair[1].ButtonPressColor = Color.New(36, 130, 94, 255)
        pair[1].ButtonDisableColor = Color.New(120, 120, 120, 255)
        pair[1].TouchEnabled = true
        createButtonLabel(root, pair[1], pair[1].Name .. 'Label', pair[2], 26)
    end
    listen(self.PrevButton.OnClicked, function() self:TurnPage(-1) end)
    listen(self.NextButton.OnClicked, function() self:TurnPage(1) end)
    -- 金币页：提示 + 平台入口按钮（平台由后台交付，这里只做降级入口）
    self.CoinHint = world:CreateUnit('EUITextLabel', {
        Parent = root, Name = 'LabelCoinPageHint', Position = Vector2.New(x, y), Size = Vector2.New(700, 90),
        Text = '', FontSize = 26, TextColor = Color.New(255, 255, 255, 255),
    })
    if self.CoinHint then
        self.CoinHint.TouchEnabled = false
        self.CoinHint.SwallowTouchEnabled = false
    end
    self.CoinButton = world:CreateUnit('EUIButton', {
        Parent = root, Name = 'BtnOpenPlatformShop', Position = Vector2.New(x, y - 110), Size = Vector2.New(500, 85),
    })
    if self.CoinButton then
        styleButton(self.CoinButton)
        self.CoinButton.ButtonNormalColor = Color.New(54, 100, 140, 255)
        self.CoinButton.ButtonPressColor = Color.New(36, 130, 94, 255)
        self.CoinButton.TouchEnabled = true
        self.CoinButtonLabel = createButtonLabel(root, self.CoinButton, 'LabelOpenPlatformShop', '打开平台商店', 26)
        listen(self.CoinButton.OnClicked, function() self:OpenPlatformShop() end)
    end
    -- 运行时商品补位行（编辑器侧只有两行商品节点；第 3..PageSize 行运行时建文本按钮）
    for index = RowCount + 1, PageSize do
        local btn = world:CreateUnit('EUIButton', {
            Parent = root, Name = 'BtnShopBuyExtra' .. index,
            Position = Vector2.New(x, y - 100 * (index - RowCount)), Size = Vector2.New(590, 85),
        })
        styleButton(btn)
        btn.ButtonNormalColor = Color.New(54, 100, 140, 255)
        btn.ButtonPressColor = Color.New(36, 130, 94, 255)
        btn.ButtonDisableColor = Color.New(120, 120, 120, 255)
        btn.TouchEnabled = true
        btn.Visible = false
        self.ExtraButtons[index] = btn
        self.ExtraLabels[index] = createButtonLabel(root, btn, 'LabelShopBuyExtra' .. index, '', 26)
        listen(btn.OnClicked, function() self:Buy(index) end)
    end
    listen(_G.REUtil:GetRE('ItemBarState').OnClientEvent, function(state)
        if state and state.upgradeLevel then self.UpgradeLevel = state.upgradeLevel end
        if self.IsOpen then self:ShowGoods() self:ShowCoin() end
    end)
    listen(_G.REUtil:GetRE('ShopResult').OnClientEvent, function(result) self:NoteResult(result) end)
    self:ShowGoods()
    self:ShowCoin()
    self.BoundRootNode = self.RootNode
    self.Inited = true
end

function ScreenHandler:OpenScreen()
    self.IsOpen = true
    self:ShowGoods()
    self:ShowCoin()
end

function ScreenHandler:CloseScreen()
    self.IsOpen = false
end

return ScreenHandler

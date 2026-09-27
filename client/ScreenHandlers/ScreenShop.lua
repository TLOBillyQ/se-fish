-- 钓场商店界面（#48；#90 多摊位）：复用场景里既有的 ScreenShop 节点，旧等级节点已在编辑器侧改造成两行商品
-- （ShopItemIcon/Name<i>、BtnShopBuy<i> 内的 LabelShopPrice<i>），外加 LabelCurCoin 与 BtnShopClose。
-- 商品按当前摊位等级（LocalShop.Stand.Level）从 GameCfg.Shop.Goods 过滤上架；编辑器侧只有两行商品节点，
-- 虾池摊（2 级）上架 4 件，超出两行的用代码建的文本按钮补位（叠在扩容按钮上方，占位样式）。
-- 商品行按 Goods 顺序填名称、图标、价格；点购买只发 ShopAction{action='Buy', itemId, seq}，
-- 结果以服务端 ShopResult 为准（提示由 client/LocalShop.lua 统一处理）。
local GameCfg = require('common.GameCfg')
local LocalShop = require('client.LocalShop')

local SquareButtonImage = 'official://image/11017'
local RowCount = 2

local ScreenHandler = { UINodes = { 'BtnShopClose', 'LabelCurCoin' }, UINodeMap = {}, Seq = 0 }

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

function ScreenHandler:Upgrade()
    if not self.IsOpen then return end
    self.Seq = self.Seq + 1
    _G.REUtil:GetRE('ShopAction'):FireServer({ action = 'UpgradeStorage', seq = self.Seq })
end

function ScreenHandler:ShowUpgrade(state)
    if not self.UpgradeButton then return end
    local level = state and state.upgradeLevel or self.UpgradeLevel or 0
    self.UpgradeLevel = level
    local price = GameCfg.Items.UpgradePrices[level + 1]
    local gain = level + 1 == #GameCfg.Items.UpgradePrices
        and GameCfg.Items.MaxBackpackSlots - GameCfg.Items.InitialBackpackSlots
            - level * GameCfg.Items.BackpackSlotsPerUpgrade
        or GameCfg.Items.BackpackSlotsPerUpgrade
    self.UpgradeLabel.Text = price and ('扩容 ' .. tostring(price) .. ' 金币（道具栏 +1 / 背包 +' .. tostring(gain) .. '）') or '已升至上限'
    self.UpgradeButton.TouchEnabled = price ~= nil
    self.UpgradeButton.Disabled = price == nil
end
for index = 1, RowCount do
    for _, prefix in ipairs({ 'ShopItemIcon', 'ShopItemName', 'BtnShopBuy', 'LabelShopPrice' }) do
        ScreenHandler.UINodes[#ScreenHandler.UINodes + 1] = prefix .. index
    end
end

function ScreenHandler:Buy(index)
    local goods = self.Goods and self.Goods[index]
    if not goods or not self.IsOpen then return end
    self.Seq = self.Seq + 1
    _G.REUtil:GetRE('ShopAction'):FireServer({ action = 'Buy', itemId = goods.ItemId, seq = self.Seq })
end

function ScreenHandler:ShowCoin()
    local label = self.UINodeMap.LabelCurCoin
    local player = game:GetService('Players').LocalPlayer
    if label and player then label.Text = tostring(math.floor(tonumber(player:GetAttribute('FishCoin')) or 0)) end
end

function ScreenHandler:ShowGoods()
    local shop = GameCfg.Shop
    -- 站在哪个摊位旁开的商店就用哪个摊位的等级；兜底取第一个摊位（等级最低）
    local level = (LocalShop.Stand and LocalShop.Stand.Level) or shop.Stands[1].Level
    self.Goods = {}
    for _, goods in ipairs(shop.Goods) do
        if goods.MinShopLevel <= level then self.Goods[#self.Goods + 1] = goods end
    end
    for index = 1, RowCount do
        local goods = self.Goods[index]
        local definition = goods and GameCfg.Items.Definitions[goods.ItemId]
        local nodes = self.UINodeMap
        for _, prefix in ipairs({ 'ShopItemIcon', 'ShopItemName', 'BtnShopBuy' }) do
            local node = nodes[prefix .. index]
            if node then node.Visible = definition ~= nil end
        end
        if definition then
            if nodes['ShopItemIcon' .. index] then nodes['ShopItemIcon' .. index].Image = definition.Icon end
            if nodes['ShopItemName' .. index] then nodes['ShopItemName' .. index].Text = definition.Name end
            if nodes['LabelShopPrice' .. index] then nodes['LabelShopPrice' .. index].Text = tostring(goods.Price) end
        end
    end
    -- 超出编辑器两行的商品走运行时补位行（Init 里按 Goods 表长度建满，这里只按上架结果显隐）
    for index, btn in pairs(self.ExtraButtons or {}) do
        local goods = self.Goods[index]
        local definition = goods and GameCfg.Items.Definitions[goods.ItemId]
        btn.Visible = definition ~= nil
        if definition and self.ExtraLabels[index] then
            self.ExtraLabels[index].Text = definition.Name .. '  ' .. tostring(goods.Price) .. ' 金币'
        end
    end
end

function ScreenHandler:Init()
    if self.Inited and self.BoundRootNode == self.RootNode then return end
    for _, connection in ipairs(self.Connections or {}) do connection:Disconnect() end
    if self.UpgradeButton then self.UpgradeButton:Destroy() end
    if self.UpgradeLabel then self.UpgradeLabel:Destroy() end
    if self.CloseLabel then self.CloseLabel:Destroy() end
    self.CloseLabel = nil
    for _, btn in pairs(self.ExtraButtons or {}) do btn:Destroy() end
    for _, label in pairs(self.ExtraLabels or {}) do label:Destroy() end
    self.ExtraButtons = {}
    self.ExtraLabels = {}
    self.UpgradeButton = nil
    self.UpgradeLabel = nil
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
    self.UpgradeButton = world:CreateUnit('EUIButton', {
        Parent = root, Name = 'BtnStorageUpgrade',
        Position = Vector2.New(x, y), Size = Vector2.New(590, 85),
    })
    styleButton(self.UpgradeButton)
    self.UpgradeButton.ButtonNormalColor = Color.New(54, 100, 140, 255)
    self.UpgradeButton.ButtonPressColor = Color.New(36, 130, 94, 255)
    self.UpgradeButton.ButtonDisableColor = Color.New(120, 120, 120, 255)
    self.UpgradeButton.TouchEnabled = true
    listen(self.UpgradeButton.OnClicked, function() self:Upgrade() end)
    self.UpgradeLabel = world:CreateUnit('EUITextLabel', {
        Parent = root, Name = 'LabelStorageUpgrade',
        Position = Vector2.New(x, y), Size = Vector2.New(590, 85),
        Text = '', FontSize = 26, TextColor = Color.New(255, 255, 255, 255),
    })
    self.UpgradeLabel.TouchEnabled = false
    self.UpgradeLabel.SwallowTouchEnabled = false
    self.UpgradeLabel.LocalZOrder = 1
    -- 运行时商品补位行（#90）：编辑器侧只有两行商品节点，Goods 表更长时按行建文本按钮，
    -- 叠在扩容按钮上方；显隐与文案由 ShowGoods 按当前摊位上架结果刷
    for index = RowCount + 1, #GameCfg.Shop.Goods do
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
    self:ShowUpgrade()
    listen(_G.REUtil:GetRE('ItemBarState').OnClientEvent, function(state)
        self:ShowUpgrade(state)
        if self.IsOpen then self:ShowCoin() end
    end)
    self:ShowGoods()
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

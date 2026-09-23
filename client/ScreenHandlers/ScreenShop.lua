-- 钓场商店界面（#48）：复用场景里既有的 ScreenShop 节点，旧等级节点已在编辑器侧改造成两行商品
-- （ShopItemIcon/Name<i>、BtnShopBuy<i> 内的 LabelShopPrice<i>），外加 LabelCurCoin 与 BtnShopClose。
-- 商品行按 GameCfg.Shop.Goods 的顺序填名称、图标、价格；点购买只发 ShopAction{action='Buy', itemId, seq}，
-- 结果以服务端 ShopResult 为准（提示由 client/LocalShop.lua 统一处理）。
local GameCfg = require('common.GameCfg')

local RowCount = 2

local ScreenHandler = { UINodes = { 'BtnShopClose', 'LabelCurCoin' }, UINodeMap = {}, Seq = 0 }
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
    self.Goods = {}
    for _, goods in ipairs(shop.Goods) do
        if goods.MinShopLevel <= shop.Level then self.Goods[#self.Goods + 1] = goods end
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
end

function ScreenHandler:Init()
    if self.Inited and self.BoundRootNode == self.RootNode then return end
    for _, connection in ipairs(self.Connections or {}) do connection:Disconnect() end
    self.Connections = {}
    local function listen(signal, callback)
        if signal then self.Connections[#self.Connections + 1] = signal:Connect(callback) end
    end
    for index = 1, RowCount do
        local btn = self.UINodeMap['BtnShopBuy' .. index]
        if btn then
            btn.TouchEnabled = true
            listen(btn.OnClicked, function() self:Buy(index) end)
        end
    end
    local close = self.UINodeMap.BtnShopClose
    if close then listen(close.OnClicked, function() _G.MgrGameUI:CloseScreen('ScreenShop') end) end
    listen(_G.REUtil:GetRE('ItemBarState').OnClientEvent, function() if self.IsOpen then self:ShowCoin() end end)
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

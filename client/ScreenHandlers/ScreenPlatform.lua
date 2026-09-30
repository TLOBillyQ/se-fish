-- 平台购买客户端面板（#147 T26）：只消费服务端 PlatformResult 回包并上行 PlatformAction，不做本地结算。
--   * AdrenalineShop：濒死无药时服务端拉起的肾上腺素两份报价（1 金豆 ×1 / 4 金豆 ×5），点选后上行
--     Purchase；不可用（商品 ID 未交付且生产构建）明确提示，不伪成功；
--   * Grant：购买发货落账提示（满格溢出的件数落在面前地上）；Purchase/CoinShop 失败给可读原因；
--   * TestFlow：调试构建的测试 flow 开/关——显示「成功 / 取消 / 失败」驱动按钮，上行 PlatformTestAction；
--     生产构建服务端既不建测试 flow 也拒绝驱动器，这组按钮不会出现；
--   * _G.PlatformShop.Open：地图商店金币页入口（ScreenShop:OpenPlatformShop），上行 OpenCoinShop。
-- 节点全部运行时创建（data/ 只读）；创建失败只记日志，不阻塞主流程。
local GameCfg = require('common.GameCfg')
local REUtil = require('common.REUtil')
local GameUI = require('client.GameUI')

local ColorBlockImage = 'official://image/11017'

local Panel = { Nodes = {} }

local function cfg()
    return GameCfg.Platform
end

local function notice(msg)
    if _G.LocalMsgNotice then _G.LocalMsgNotice(msg) end
end

local function reasonText(reason)
    return cfg().ReasonText[reason] or cfg().UnavailableText
end

function Panel:Create(kind, parent, name, x, y, w, h, props)
    props = props or {}
    props.Parent = parent
    props.Name = name
    props.Position = Vector2.New(x, y)
    props.Size = Vector2.New(w, h)
    local world = game:GetService('World')
    local ok, node = pcall(world.CreateUnit, world, kind, props)
    if not ok or not node then
        print('[ScreenPlatform] 节点创建失败', name, tostring(node))
        return nil
    end
    if kind == 'EUITextLabel' then
        node.TouchEnabled = false
        node.SwallowTouchEnabled = false
    end
    self.Nodes[name] = node
    return node
end

function Panel:Button(parent, name, x, y, w, h, text, onClick)
    local button = self:Create('EUIButton', parent, name, x, y, w, h, {
        ButtonText = '', NormalImage = ColorBlockImage, PressImage = ColorBlockImage,
        Color = Color.New(54, 100, 140, 255) })
    if not button then return nil end
    button.TouchEnabled = true
    self:Create('EUITextLabel', button, name .. 'Text', 0, 0, w, h, {
        Text = text, FontSize = 26, TextColor = Color.New(255, 255, 255, 255), LocalZOrder = 1 })
    if button.OnClicked then button.OnClicked:Connect(onClick) end
    return button
end

function Panel:SetVisible(name, visible)
    local node = self.Nodes[name]
    if node then pcall(function() node.Visible = visible end) end
end

function Panel:BuildNodes()
    local root = GameUI:GetUIRoot()
    if not root then return false end
    local resolution = GameUI:GetEuiManager():GetDeviceResolution() or { x = 1920, y = 1080 }
    local cx, cy = resolution.x / 2, resolution.y / 2
    local offers = self:Create('EUIImage', root, 'PlatformOffers', cx - 300, cy + 120, 600, 220, {
        Image = ColorBlockImage, Color = Color.New(0, 0, 0, 180), Visible = false })
    if offers then
        self:Create('EUITextLabel', offers, 'PlatformOffersTitle', 0, -80, 600, 50, {
            Text = cfg().OfferTitle, FontSize = 30, TextColor = Color.New(255, 255, 255, 255) })
        for index = 1, 2 do
            self:Button(offers, 'BtnPlatformOffer' .. index, -150 + (index - 1) * 300, 0, 260, 80, '',
                function() self:Buy(index) end)
        end
        self:Button(offers, 'BtnPlatformOffersClose', 0, 80, 200, 50, '关闭',
            function() self:SetVisible('PlatformOffers', false) end)
    end
    local driver = self:Create('EUIImage', root, 'PlatformTestDriver', resolution.x - 360, 260, 340, 200, {
        Image = ColorBlockImage, Color = Color.New(80, 0, 0, 180), Visible = false })
    if driver then
        self:Create('EUITextLabel', driver, 'PlatformTestDriverTitle', 0, -70, 340, 50, {
            Text = cfg().TestDriverTitle, FontSize = 22, TextColor = Color.New(255, 220, 220, 255) })
        local outcomes = { { 'success', '成功' }, { 'cancel', '取消' }, { 'fail', '失败' } }
        for index, entry in ipairs(outcomes) do
            self:Button(driver, 'BtnPlatformTest_' .. entry[1], -110 + (index - 1) * 110, 10, 100, 60, entry[2],
                function() self:Drive(entry[1]) end)
        end
    end
    return true
end

-- 两份报价：按服务端回包渲染（价目以服务端 GameCfg.Platform.Goods 为准）
function Panel:ShowOffers(offers)
    self.Offers = type(offers) == 'table' and offers or {}
    for index = 1, 2 do
        local offer = self.Offers[index]
        self:SetVisible('BtnPlatformOffer' .. index, offer ~= nil)
        local label = self.Nodes['BtnPlatformOffer' .. index .. 'Text']
        if offer and label then
            pcall(function()
                label.Text = string.format('%s（%d%s）', offer.name or offer.key, offer.beans or 0,
                    cfg().BeanCurrency)
            end)
        end
    end
    self:SetVisible('PlatformOffers', true)
end

function Panel:Buy(index)
    local offer = self.Offers and self.Offers[index]
    if not offer then return false end
    self:SetVisible('PlatformOffers', false)
    REUtil:GetRE('PlatformAction'):FireServer({ action = 'Purchase', goods = offer.key })
    return true
end

function Panel:Drive(outcome)
    REUtil:GetRE('PlatformTestAction'):FireServer({ action = 'ResolveFlow', outcome = outcome })
end

-- 地图商店金币页入口（ScreenShop:OpenPlatformShop 经 rawget(_G, 'PlatformShop') 调用）
function Panel:Open()
    REUtil:GetRE('PlatformAction'):FireServer({ action = 'OpenCoinShop' })
end

function Panel:NoteResult(result)
    if type(result) ~= 'table' then return end
    local action = result.action
    if action == 'TestFlow' then
        self:SetVisible('PlatformTestDriver', result.open == true)
        local title = self.Nodes.PlatformTestDriverTitle
        if title then
            pcall(function()
                title.Text = cfg().TestDriverTitle .. (result.open and ('：' .. tostring(result.key)) or '')
            end)
        end
    elseif action == 'AdrenalineShop' then
        if result.ok then self:ShowOffers(result.offers) else notice(cfg().UnavailableText) end
    elseif action == 'Grant' and result.ok then
        local row = cfg().Goods[result.goods]
        local text = string.format('获得 %s', row and row.name or tostring(result.goods))
        if (result.overflow or 0) > 0 then
            text = text .. string.format('，背包已满：%d 件落在面前地上', result.overflow)
        end
        notice(text)
    elseif not result.ok then
        notice(reasonText(result.reason))
    end
end

function Panel:Start()
    _G.PlatformShop = self
    REUtil:GetRE('PlatformResult').OnClientEvent:Connect(function(result) self:NoteResult(result) end)
    local task = game:GetService('Task')
    task:Spawn(function()
        for _ = 1, 50 do
            if self:BuildNodes() then return end
            task:Wait(0.2)
        end
        print('[ScreenPlatform] UIRoot 未就绪，平台购买面板不可用')
    end)
end

return Panel

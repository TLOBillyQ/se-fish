-- 钓场商店入口（#48；#90 多摊位）：每个摊位（GameCfg.Shop.Stands）一个文字泡「看看有什么可买的」，
-- 本地角色在该摊位 Radius 米内（只看 x/z）才显示，点击打开 ScreenShop；商店界面的商品按当前摊位
-- 的等级（Stands.Level）上架。走出所有摊位范围自动关商店。购买结果 ShopResult 在这里统一转成消息条提示。
local GameCfg = require('common.GameCfg')
local REUtil = require('common.REUtil')
local Util = require('common.Util')
local SquareButtonImage = 'official://image/11017'

local LocalShop = { Bubbles = {} }

local World = game:GetService('World')
local Players = game:GetService('Players')

local FailText = {
    coin = '金币不足',
    full = '背包已满',
    max = '道具栏和背包已升至上限',
    range = '离钓场老板太远了',
    item = '这件商品暂不出售',
}

local function notice(msg)
    if _G.LocalMsgNotice then _G.LocalMsgNotice(msg) end
end

function LocalShop:CreateBubble(anchor)
    local cfg = GameCfg.Shop
    local offset = Vector3.New(0, cfg.BubbleHeight, 0)
    local ok, node = pcall(_G.GameUI.CreateSceneNode, _G.GameUI, cfg.BubblePreset, anchor, offset)
    if not ok or not node then
        print('[LocalShop] 文字泡预设创建失败，改用场景 UI', tostring(node))
        local eui = _G.GameUI:GetEuiManager()
        local center = anchor.Position
        ok, node = pcall(eui.CreateSceneNodeAtPosition, eui,
            Vector3.New(center.x, center.y + cfg.BubbleHeight, center.z))
        if not ok or not node then
            print('[LocalShop] 场景 UI 创建失败', tostring(node))
            return
        end
    end
    pcall(function()
        local title = node:FindFirstChild('LabelShopTitle', true)
        if title then title.Text = cfg.HintText end
    end)
    local okBtn, btn = pcall(World.CreateUnit, World, 'EUIButton', {
        Parent = node, Name = 'BtnShopEnter', Position = Vector2.New(0, 0), Size = Vector2.New(360, 72),
    })
    if okBtn and btn then
        btn.ButtonText = ''
        btn.NormalImage = SquareButtonImage
        btn.PressImage = SquareButtonImage
        btn.DisableImage = SquareButtonImage
        btn.ButtonNormalColor = Color.New(54, 100, 140, 255)
        btn.ButtonPressColor = Color.New(36, 130, 94, 255)
        btn.ButtonDisableColor = Color.New(120, 120, 120, 255)
        btn.TouchEnabled = true
        local label = World:CreateUnit('EUITextLabel', {
            Parent = node, Name = 'LabelShopEnterTheme', Position = btn.Position, Size = btn.Size,
            Text = cfg.HintText, FontSize = 26, TextColor = Color.New(255, 255, 255, 255),
        })
        if label then
            label.TouchEnabled = false
            label.SwallowTouchEnabled = false
            label.LocalZOrder = 1
        end
        btn.OnClicked:Connect(function() self:Open() end)
    else
        print('[LocalShop] 入口按钮创建失败', tostring(btn))
    end
    node.Visible = false
    return node
end

function LocalShop:Open()
    if not self.Stand then return end
    print('[LocalShop] 打开商店', self.Stand.AnchorName, 'level=' .. tostring(self.Stand.Level))
    _G.MgrGameUI:OpenScreen('ScreenShop')
end

function LocalShop:Update()
    local character = Players.LocalPlayer and Players.LocalPlayer.Character
    local pos = character and character.Position
    local shop = GameCfg.Shop
    local nearStand
    for _, bubble in ipairs(self.Bubbles) do
        local near = false
        if pos then
            local dx, dz = pos.x - bubble.Center.x, pos.z - bubble.Center.z
            near = dx * dx + dz * dz <= shop.Radius * shop.Radius
        end
        if near then nearStand = bubble.Stand end
        if bubble.Near ~= near then
            bubble.Near = near
            local ok, err = pcall(function() bubble.Node.Visible = near end)
            if not ok then print('[LocalShop] 气泡显隐失败', tostring(err)) end
        end
    end
    if self.Stand ~= nearStand then
        self.Stand = nearStand
        if not nearStand and _G.MgrGameUI:IsScreenOpen('ScreenShop') then
            print('[LocalShop] 离开钓场老板，关闭商店')
            _G.MgrGameUI:CloseScreen('ScreenShop')
        end
    end
end

function LocalShop:Start()
    REUtil:GetRE('ShopResult').OnClientEvent:Connect(function(result)
        if type(result) ~= 'table' then return end
        local definition = GameCfg.Items.Definitions[result.itemId]
        if result.ok and result.action == 'UpgradeStorage' then
            notice('扩容成功：道具栏 ' .. tostring(GameCfg.Items.InitialItemBarSlots + result.level)
                .. ' 格，背包 ' .. tostring((result.level == #GameCfg.Items.UpgradePrices and GameCfg.Items.MaxBackpackSlots
                    or GameCfg.Items.InitialBackpackSlots + result.level * GameCfg.Items.BackpackSlotsPerUpgrade)) .. ' 格')
        elseif result.ok then
            notice('购买成功：' .. (definition and definition.Name or tostring(result.itemId))
                .. '，花费 ' .. tostring(result.price) .. ' 金币')
        else
            notice(FailText[result.reason] or '购买失败')
        end
    end)
    for _, stand in ipairs(GameCfg.Shop.Stands) do
        local anchor = Util:WaitForChild(World, stand.AnchorName)
        if anchor then
            local node = self:CreateBubble(anchor)
            if node then
                self.Bubbles[#self.Bubbles + 1] = { Node = node, Center = anchor.Position, Stand = stand, Near = false }
            end
        else
            print('[LocalShop] 找不到钓场老板单位', stand.AnchorName)
        end
    end
    game:GetService('RunService').Heartbeat:Connect(function() self:Update() end)
end

return LocalShop

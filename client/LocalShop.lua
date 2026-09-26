-- 钓场商店入口（#48）：在钓场老板触发器 TGUnitShop 上挂旧入口用过的文字泡预设，放一个「看看有什么可买的」按钮；
-- 本地角色在 Radius 米内（只看 x/z）才显示，点击打开 ScreenShop，走出范围自动关闭。
-- 购买结果 ShopResult 在这里统一转成消息条提示。
local GameCfg = require('common.GameCfg')
local REUtil = require('common.REUtil')
local Util = require('common.Util')

local LocalShop = {}

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
        btn.ButtonText = cfg.HintText
        btn.TouchEnabled = true
        btn.OnClicked:Connect(function() self:Open() end)
    else
        print('[LocalShop] 入口按钮创建失败', tostring(btn))
    end
    node.Visible = false
    self.Node = node
end

function LocalShop:Open()
    if not self.Near then return end
    print('[LocalShop] 打开商店')
    _G.MgrGameUI:OpenScreen('ScreenShop')
end

function LocalShop:Update()
    local character = Players.LocalPlayer and Players.LocalPlayer.Character
    local pos = character and character.Position
    local near = false
    if pos and self.Center then
        local dx, dz = pos.x - self.Center.x, pos.z - self.Center.z
        near = dx * dx + dz * dz <= GameCfg.Shop.Radius * GameCfg.Shop.Radius
    end
    if self.Near == near then return end
    self.Near = near
    if self.Node then pcall(function() self.Node.Visible = near end) end
    if not near and _G.MgrGameUI:IsScreenOpen('ScreenShop') then
        print('[LocalShop] 离开钓场老板，关闭商店')
        _G.MgrGameUI:CloseScreen('ScreenShop')
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
    local anchor = Util:WaitForChild(World, GameCfg.Shop.AnchorName)
    if not anchor then
        print('[LocalShop] 找不到钓场老板单位', GameCfg.Shop.AnchorName)
        return
    end
    self.Center = anchor.Position
    self:CreateBubble(anchor)
    game:GetService('RunService').Heartbeat:Connect(function() self:Update() end)
end

return LocalShop

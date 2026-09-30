-- 抽奖机入口（#138 T17，GameSpec §14）：每区一台抽奖机（GameCfg.Lottery.MachineAnchors 的
-- Z*_Lottery 场景实体）一个文字泡「极品食物换大奖」，本地角色在 Radius 米内（只看 x/z）才显示，
-- 点击打开 ScreenLottery；走出所有抽奖机范围自动关窗。锚点未摆放（编辑器侧还没建实体）只记日志，
-- 不影响其余入口。结算与发奖全部在服务端（MgrLottery），这里只负责入口与开关窗。
local GameCfg = require('common.GameCfg')
local Util = require('common.Util')
local SquareButtonImage = 'official://image/11017'

local LocalLottery = { Bubbles = {} }

local World = game:GetService('World')
local Players = game:GetService('Players')

function LocalLottery:CreateBubble(anchor)
    local cfg = GameCfg.Lottery
    local offset = Vector3.New(0, cfg.BubbleHeight, 0)
    local ok, node = pcall(_G.GameUI.CreateSceneNode, _G.GameUI, cfg.BubblePreset, anchor, offset)
    if not ok or not node then
        print('[LocalLottery] 文字泡预设创建失败', tostring(node))
        return nil
    end
    local okBtn, btn = pcall(World.CreateUnit, World, 'EUIButton', {
        Parent = node, Name = 'BtnLotteryEnter', Position = Vector2.New(0, 0), Size = Vector2.New(360, 72),
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
        local okLabel, label = pcall(World.CreateUnit, World, 'EUITextLabel', {
            Parent = node, Name = 'LabelLotteryEnterTheme', Position = btn.Position, Size = btn.Size,
            Text = cfg.HintText, FontSize = 26, TextColor = Color.New(255, 255, 255, 255),
        })
        if okLabel and label then
            label.TouchEnabled = false
            label.SwallowTouchEnabled = false
            label.LocalZOrder = 1
        end
        btn.OnClicked:Connect(function() self:Open() end)
    else
        print('[LocalLottery] 入口按钮创建失败', tostring(btn))
    end
    node.Visible = false
    return node
end

function LocalLottery:Open()
    if not self.Machine then return end
    _G.MgrGameUI:OpenScreen('ScreenLottery')
end

function LocalLottery:Update()
    local character = Players.LocalPlayer and Players.LocalPlayer.Character
    local pos = character and character.Position
    local radius = GameCfg.Lottery.Radius
    local nearMachine
    for _, bubble in ipairs(self.Bubbles) do
        local near = false
        if pos then
            local dx, dz = pos.x - bubble.Center.x, pos.z - bubble.Center.z
            near = dx * dx + dz * dz <= radius * radius
        end
        if near then nearMachine = bubble end
        if bubble.Near ~= near then
            bubble.Near = near
            local ok, err = pcall(function() bubble.Node.Visible = near end)
            if not ok then print('[LocalLottery] 气泡显隐失败', tostring(err)) end
        end
    end
    if self.Machine ~= nearMachine then
        self.Machine = nearMachine
        if not nearMachine and _G.MgrGameUI:IsScreenOpen('ScreenLottery') then
            print('[LocalLottery] 离开抽奖机，关闭界面')
            _G.MgrGameUI:CloseScreen('ScreenLottery')
        end
    end
end

function LocalLottery:Start()
    for _, name in ipairs(GameCfg.Lottery.MachineAnchors()) do
        local anchor = Util:WaitForChild(World, name)
        if anchor then
            local node = self:CreateBubble(anchor)
            if node then
                self.Bubbles[#self.Bubbles + 1] = { Node = node, Center = anchor.Position,
                    AnchorName = name, Near = false }
            end
        else
            print('[LocalLottery] 找不到抽奖机单位', name)
        end
    end
    game:GetService('RunService').Heartbeat:Connect(function() self:Update() end)
end

return LocalLottery

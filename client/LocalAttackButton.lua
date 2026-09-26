-- 右手武器的 1 号操作位，由 ScreenMain 持有，独立于道具操作位。
local Players = game:GetService("Players")
local World = game:GetService("World")
local GameCfg = require("common.GameCfg")
local AbilityAPI = require("client.AbilityAPI")
local LocalAttackButton = {}

local function findMeleeSlot()
    for _, entry in ipairs(GameCfg.Ability.InitialAbilities or {}) do
        if entry.AnchorBehavior == "melee_hit" then return entry.Index end
    end
end

function LocalAttackButton:Start(parent, resolution)
    if self.Root == parent and self.Container then return end
    self:Destroy()
    self.Slot = findMeleeSlot()
    if not self.Slot then
        print("[LocalAttackButton] 配置里没有挥砍技能，不建按钮")
        return
    end
    self.Root = parent
    -- 左下原点：位于原生大按钮上方，并避开上方的道具操作位。
    local container = World:CreateUnit("EUILayout", {
        Parent = parent, Name = "AttackControl",
        Position = Vector2.New(resolution.x - 245, 555), Size = Vector2.New(200, 200),
    })
    container.TouchEnabled = false
    container.SwallowTouchEnabled = false
    self.Container = container
    local btn = World:CreateUnit("EUIButton", {
        Parent = container, Name = "BtnAttack",
        Position = Vector2.New(100, 100), Size = Vector2.New(200, 200),
    })
    btn.ButtonText = ""
    btn.NormalImage = "official://image/10055"
    btn.PressImage = "official://image/10056"
    btn.DisableImage = "official://image/10055"
    btn.ButtonNormalColor = Color.New(245, 250, 242, 185)
    btn.ButtonPressColor = Color.New(210, 235, 185, 240)
    btn.ButtonDisableColor = Color.New(190, 195, 185, 100)
    self.BtnAttack = btn
    local label = World:CreateUnit("EUITextLabel", {
        Parent = container, Name = "AttackLabel",
        Position = Vector2.New(100, 100), Size = Vector2.New(160, 70),
    })
    label.Text = "攻击"
    label.FontSize = 36
    label.TextColor = Color.New(48, 65, 44, 255)
    label.TextHorizontalAlignment = 1
    label.TextVerticalAlignment = 1
    label.LocalZOrder = 1
    label.TouchEnabled = false
    label.SwallowTouchEnabled = false
    self.ClickConn = btn.OnClicked:Connect(function() self:RequestMelee() end)
    _G.MgrGameUI:SetCustomControlUI(container, true)
    self:SetOpen(false)
end

function LocalAttackButton:SetOpen(open)
    self.IsOpen = open == true
    if self.Container then self.Container.Visible = self.IsOpen end
    if self.BtnAttack then self.BtnAttack.TouchEnabled = self.IsOpen end
end

-- 隐藏主界面或操作区时，探针与按钮点击均不得发起攻击。
function LocalAttackButton:RequestMelee()
    if not self.Slot or not self.IsOpen or not self.Container or not self.Container.Visible
        or not self.Root or not self.Root.Visible then return end
    local character = Players.LocalPlayer and Players.LocalPlayer.Character
    local manager = character and AbilityAPI.GetManagerForUnit(character)
    if not manager then
        print("[LocalAttackButton] 技能管理器未就绪，忽略本次点击")
        return
    end
    print("[LocalAttackButton] 请求挥砍 slot=" .. tostring(self.Slot))
    return AbilityAPI.RequestCast(manager, self.Slot)
end

function LocalAttackButton:Destroy()
    self.IsOpen = false
    if self.ClickConn then self.ClickConn:Disconnect() end
    if self.Container then
        _G.MgrGameUI:SetCustomControlUI(self.Container, nil)
        self.Container:Destroy()
    end
    self.ClickConn = nil
    self.Container = nil
    self.BtnAttack = nil
    self.Root = nil
    self.Slot = nil
end

return LocalAttackButton

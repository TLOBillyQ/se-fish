-- 右手武器的 1 号操作位，由 ScreenMain 持有，独立于道具操作位。
-- #129：点按 / 连发 / 换弹全部经服务端 MgrWeapon 权威结算（WeaponAction 通道）。
-- 客户端不再直接 RequestCast：伤害由服务端按 GameCfg 表登记挥砍，伪造客户端包不产生伤害。
local Players = game:GetService("Players")
local World = game:GetService("World")
local GameCfg = require("common.GameCfg")
local Gesture = require("client.PressGesture")
local WeaponAim = require('client.WeaponAim')
local LocalAttackButton = {}

-- ScreenMain 每次快照刷新时同步装备状态：决定点按语义（攻击/连发）与长按语义（换弹）
function LocalAttackButton:SetEquipped(state)
    self.EquippedId = nil
    self.EquippedGun = nil
    self.AutoFireGun = nil
    local weapons = state and state.weapons or {}
    local held = state and state.held
    if held and held.kind == "weapon" and (weapons[held.id] or 0) > 0 then
        self.EquippedId = held.id
    elseif state and state.selectedWeapon and (weapons[state.selectedWeapon] or 0) > 0 then
        self.EquippedId = state.selectedWeapon
    end
    local gcfg = self.EquippedId and GameCfg.Ability.Guns[self.EquippedId] or nil
    if gcfg then
        self.EquippedGun = gcfg
        if gcfg.Auto then self.AutoFireGun = gcfg end
    end
    if self.Label then
        self.Label.Text = self.EquippedGun and "射击" or "攻击"
    end
end

function LocalAttackButton:Start(parent, resolution)
    if self.Root == parent and self.Container then return end
    self:Destroy()
    self.Root = parent
    self.Gesture = Gesture.New({ LongPressSec = GameCfg.Ability.Throw.LongPressSec })
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
    self.Label = label
    self.PressConns = {}
    if btn.OnTouchBegan and btn.OnTouchEnded then
        self.PressConns[#self.PressConns + 1] = btn.OnTouchBegan:Connect(function() self:OnPressBegin() end)
        self.PressConns[#self.PressConns + 1] = btn.OnTouchEnded:Connect(function() self:OnPressEnd() end)
    else
        -- 触摸信号缺失时退回点按（连发/长按换弹不可用）
        self.ClickConn = btn.OnClicked:Connect(function() self:RequestAttack() end)
    end
    local runService = game:GetService("RunService")
    if runService and runService.Heartbeat then
        self.HeartConn = runService.Heartbeat:Connect(function() self:Tick() end)
    end
    _G.MgrGameUI:SetCustomControlUI(container, true)
    self:SetOpen(false)
end

function LocalAttackButton:SetOpen(open)
    self.IsOpen = open == true
    if self.Container then self.Container.Visible = self.IsOpen end
    if self.BtnAttack then self.BtnAttack.TouchEnabled = self.IsOpen end
    if not self.IsOpen then self.Pressing = false end
end

function LocalAttackButton:Visible()
    return self.IsOpen and self.Container and self.Container.Visible
        and self.Root and self.Root.Visible
end

-- 隐藏主界面或操作区时，不得发起攻击/换弹
function LocalAttackButton:CanOperate()
    return self:Visible() and Players.LocalPlayer and Players.LocalPlayer.Character
end

function LocalAttackButton:OnPressBegin()
    self.Pressing = true
    self.AutoFired = false
    self.NextAutoFire = 0
    if self.Gesture then self.Gesture:Begin(World:GetServerTime()) end
end

function LocalAttackButton:OnPressEnd()
    self.Pressing = false
    if not self.Gesture then return end
    local result = self.Gesture:End(World:GetServerTime())
    if result == "tap" then
        -- 连发枪按住期间已由 Tick 开火，点按不再补一枪
        if not self.AutoFired then self:RequestAttack() end
    elseif result == "long" and self.EquippedGun and not self.AutoFireGun then
        -- 长按=手动换弹（连发枪靠空匣自动换弹，长按不抢）
        self:RequestReload()
    end
end

-- 按住连发：Auto 枪按票面射速持续请求，射速/弹量以服务端为准
function LocalAttackButton:Tick()
    if not self.Pressing or not self:CanOperate() then return end
    local now = World:GetServerTime()
    if self.Gesture then self.Gesture:Update(now) end
    if self.AutoFireGun and now >= (self.NextAutoFire or 0) then
        self.NextAutoFire = now + (self.AutoFireGun.IntervalSec or 0.2)
        self.AutoFired = true
        self:RequestAttack()
    end
end

function LocalAttackButton:RequestAttack()
    if not self:CanOperate() then return end
    print("[LocalAttackButton] 请求攻击 equipped=" .. tostring(self.EquippedId))
    _G.REUtil:GetRE("WeaponAction"):FireServer(WeaponAim:AttackPayload())
end

function LocalAttackButton:RequestReload()
    if not self:CanOperate() then return end
    print("[LocalAttackButton] 请求换弹 equipped=" .. tostring(self.EquippedId))
    _G.REUtil:GetRE("WeaponAction"):FireServer({ action = "reload" })
end

function LocalAttackButton:Destroy()
    self.IsOpen = false
    self.Pressing = false
    if self.ClickConn then self.ClickConn:Disconnect() end
    if self.HeartConn then self.HeartConn:Disconnect() end
    for _, conn in ipairs(self.PressConns or {}) do conn:Disconnect() end
    if self.Container then
        _G.MgrGameUI:SetCustomControlUI(self.Container, nil)
        self.Container:Destroy()
    end
    self.ClickConn = nil
    self.HeartConn = nil
    self.PressConns = nil
    self.Container = nil
    self.BtnAttack = nil
    self.Label = nil
    self.Root = nil
    self.EquippedId = nil
    self.EquippedGun = nil
    self.AutoFireGun = nil
end

return LocalAttackButton

local World = game:GetService('World')
local GameCfg = require('common.GameCfg')

local ScreenHandler = { UINodes = {}, UINodeMap = {} }

function ScreenHandler:Action(action, value)
    _G.REUtil:GetRE('ItemBarAction'):FireServer({ action = action, value = value })
end

function ScreenHandler:Show(state)
    if type(state) ~= 'table' or type(state.slots) ~= 'table' then return end
    self.Snapshot = state
    for index, slot in ipairs(self.Slots or {}) do
        local entry = state.slots[index]
        local definition = entry and GameCfg.Items.Definitions[entry.itemId]
        slot.Icon.Visible = definition ~= nil
        if definition then slot.Icon.Image = definition.Icon end
        slot.Label.Text = definition and definition.Name or ''
        slot.Count.Text = definition and tostring(entry.count) or ''
        slot.Background.ButtonNormalColor = index == state.selectedSlot
            and Color.New(36, 130, 94, 255) or Color.New(54, 100, 140, 255)
    end
    local baitId = GameCfg.Items.Id.Worm
    local count = state.bait and state.bait[baitId] or 0
    self.BtnBait.ButtonText = '蚯蚓 ×' .. tostring(count)
    self.BtnBait.ButtonNormalColor = state.selectedBait == baitId
        and Color.New(36, 130, 94, 255) or Color.New(54, 100, 140, 255)
    self.BtnBait.TouchEnabled = count > 0
    self.BtnEat.TouchEnabled = count > 0
    self.BtnEat.ButtonText = count > 0 and '吃蚯蚓' or '蚯蚓用尽'
    self.BtnNone.ButtonText = '不挂鱼饵'
    local selected = state.selectedSlot and state.slots[state.selectedSlot]
    self.BtnItemAction.Visible = selected ~= nil
    self.BtnItemAction.ButtonText = selected and selected.itemId == GameCfg.Items.Id.StarterRod
        and '抛竿' or '使用'
    self.BtnDiscard.Visible = selected ~= nil
end

local function button(parent, name, x, y, width, text)
    local btn = World:CreateUnit('EUIButton', {
        Parent = parent, Name = name,
        Position = Vector2.New(x, y), Size = Vector2.New(width, 90),
    })
    btn.TouchEnabled = true
    btn.ButtonText = text
    btn.NormalImage = 'official://image/11017'
    btn.PressImage = 'official://image/11017'
    btn.DisableImage = 'official://image/11017'
    btn.ButtonNormalColor = Color.New(54, 100, 140, 255)
    btn.ButtonTextColor = Color.New(255, 255, 255, 255)
    btn.ButtonTextFontSize = 30
    return btn
end

function ScreenHandler:Listen(source, callback)
    self.Connections[#self.Connections + 1] = source:Connect(callback)
end

function ScreenHandler:Cleanup()
    for _, connection in ipairs(self.Connections or {}) do connection:Disconnect() end
    for _, slot in ipairs(self.Slots or {}) do slot.Background:Destroy() end
    for _, node in ipairs(self.Buttons or {}) do node:Destroy() end
    self.Connections = nil
    self.Slots = nil
    self.Buttons = nil
    self.BtnBait = nil
    self.BtnNone = nil
    self.BtnEat = nil
    self.BtnDiscard = nil
    self.BtnItemAction = nil
    self.Snapshot = nil
    self.BoundRootNode = nil
    self.Inited = false
end

function ScreenHandler:Init()
    if self.Inited then
        if self.BoundRootNode == self.RootNode then return end
        self:Cleanup()
    end
    local euiMgr = _G.GameUI:GetEuiManager()
    if not euiMgr then return end
    local resolution = euiMgr:GetDeviceResolution()
    local root = self.RootNode
    local oldEntry = root:FindFirstChild('BtnFishEnter', true)
    if oldEntry then oldEntry.Visible = false end
    self.Slots = {}
    self.Connections = {}
    local count = GameCfg.Items.ItemBarSlots
    local step = 120
    local firstX = (resolution.x - (count - 1) * step) / 2
    for index = 1, count do
        local background = button(root, 'ItemBarSlot' .. index,
            firstX + (index - 1) * step, 400, 110, '')
        background.Size = Vector2.New(110, 110)
        local icon = World:CreateUnit('EUIImage', {
            Parent = background, Name = 'ItemBarIcon' .. index,
            Position = Vector2.New(55, 70), Size = Vector2.New(78, 78),
        })
        icon.Visible = false
        local label = World:CreateUnit('EUITextLabel', {
            Parent = background, Name = 'ItemBarLabel' .. index,
            Position = Vector2.New(55, 20), Size = Vector2.New(110, 28),
            FontSize = 24, TextColor = Color.New(255, 255, 255, 255),
        })
        local amount = World:CreateUnit('EUITextLabel', {
            Parent = background, Name = 'ItemBarAmount' .. index,
            Position = Vector2.New(92, 92), Size = Vector2.New(30, 30),
            FontSize = 24, TextColor = Color.New(255, 220, 40, 255),
        })
        self.Slots[index] = { Background = background, Icon = icon, Label = label, Count = amount }
        self:Listen(background.OnClicked, function() self:Action('SelectSlot', index) end)
    end
    self.BtnBait = button(root, 'BaitWorm', firstX + 80, 540, 170, '蚯蚓')
    self.BtnNone = button(root, 'BaitNone', firstX + 270, 540, 170, '不挂鱼饵')
    self.BtnEat = button(root, 'BaitEat', firstX + 460, 540, 170, '吃蚯蚓')
    self.BtnDiscard = button(root, 'ItemDiscard', firstX + 650, 540, 170, '丢弃选中物')
    self.BtnItemAction = button(root, 'ItemAction2', resolution.x - 220, 690, 180, '抛竿')
    self.Buttons = { self.BtnBait, self.BtnNone, self.BtnEat, self.BtnDiscard, self.BtnItemAction }
    self.BtnItemAction.TouchEnabled = false
    self.BtnItemAction.Visible = false
    self.BtnDiscard.Visible = false
    self:Listen(self.BtnBait.OnClicked, function() self:Action('SelectBait', GameCfg.Items.Id.Worm) end)
    self:Listen(self.BtnNone.OnClicked, function() self:Action('SelectBait') end)
    self:Listen(self.BtnEat.OnClicked, function() self:Action('EatBait', GameCfg.Items.Id.Worm) end)
    self:Listen(self.BtnDiscard.OnClicked, function()
        if self.Snapshot and self.Snapshot.selectedSlot then
            self:Action('DiscardSlot', self.Snapshot.selectedSlot)
        end
    end)
    self:Listen(_G.REUtil:GetRE('ItemBarState').OnClientEvent, function(state) self:Show(state) end)
    self.BoundRootNode = root
    self.Inited = true
    _G.REUtil:GetRE('RequestItemBar'):FireServer()
end

function ScreenHandler:Destroy()
    self:Cleanup()
    self.RootNode = nil
end

return ScreenHandler

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
        slot.Label.Visible = definition ~= nil
        slot.Count.Text = definition and tostring(entry.count) or ''
        slot.Count.Visible = definition ~= nil
        slot.Background.ButtonNormalColor = index == state.selectedSlot
            and Color.New(36, 130, 94, 255) or Color.New(54, 100, 140, 255)
    end
    local baitId = GameCfg.Items.Id.Worm
    local count = state.bait and state.bait[baitId] or 0
    self.BtnBaitLabel.Text = '蚯蚓 ×' .. tostring(count)
    self.BtnBait.ButtonNormalColor = state.selectedBait == baitId
        and Color.New(36, 130, 94, 255) or Color.New(54, 100, 140, 255)
    self.BtnBait.TouchEnabled = count > 0
    self.BtnEat.TouchEnabled = count > 0
    self.BtnEatLabel.Text = count > 0 and '吃蚯蚓' or '蚯蚓用尽'
    self.BtnNoneLabel.Text = '不挂鱼饵'
    local selected = state.selectedSlot and state.slots[state.selectedSlot]
    self.BtnItemAction.Visible = selected ~= nil
    self.BtnItemActionLabel.Visible = selected ~= nil
    self.BtnItemActionLabel.Text = selected and selected.itemId == GameCfg.Items.Id.StarterRod
        and '抛竿' or '使用'
    self.BtnDiscard.Visible = selected ~= nil
    self.BtnDiscardLabel.Visible = selected ~= nil
end

local function button(parent, name, x, y, width)
    local btn = World:CreateUnit('EUIButton', {
        Parent = parent, Name = name,
        Position = Vector2.New(x, y), Size = Vector2.New(width, 90),
    })
    btn.TouchEnabled = true
    btn.ButtonText = ''
    btn.NormalImage = 'official://image/11017'
    btn.PressImage = 'official://image/11017'
    btn.DisableImage = 'official://image/11017'
    btn.ButtonNormalColor = Color.New(54, 100, 140, 255)
    return btn
end

local function overlay(parent, name, x, y, width, height, text, size, color)
    local label = World:CreateUnit('EUITextLabel', {
        Parent = parent, Name = name,
        Position = Vector2.New(x, y), Size = Vector2.New(width, height),
        Text = text, FontSize = size, TextColor = color,
    })
    label.TouchEnabled = false
    label.SwallowTouchEnabled = false
    label.LocalZOrder = 1
    return label
end

function ScreenHandler:Listen(source, callback)
    self.Connections[#self.Connections + 1] = source:Connect(callback)
end

function ScreenHandler:Cleanup()
    for _, connection in ipairs(self.Connections or {}) do connection:Disconnect() end
    for _, node in ipairs(self.Overlays or {}) do node:Destroy() end
    for _, slot in ipairs(self.Slots or {}) do slot.Background:Destroy() end
    for _, node in ipairs(self.Buttons or {}) do node:Destroy() end
    self.Connections = nil
    self.Overlays = nil
    self.Slots = nil
    self.Buttons = nil
    self.BtnBait = nil
    self.BtnNone = nil
    self.BtnEat = nil
    self.BtnDiscard = nil
    self.BtnItemAction = nil
    self.BtnBaitLabel = nil
    self.BtnNoneLabel = nil
    self.BtnEatLabel = nil
    self.BtnDiscardLabel = nil
    self.BtnItemActionLabel = nil
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
    self.Overlays = {}
    local count = GameCfg.Items.ItemBarSlots
    local step = 120
    local firstX = (resolution.x - (count - 1) * step) / 2
    for index = 1, count do
        local x, y = firstX + (index - 1) * step, 400
        local background = button(root, 'ItemBarSlot' .. index, x, y, 110)
        background.Size = Vector2.New(110, 110)
        local icon = World:CreateUnit('EUIImage', {
            Parent = root, Name = 'ItemBarIcon' .. index,
            Position = Vector2.New(x, y + 15), Size = Vector2.New(78, 78),
        })
        icon.TouchEnabled = false
        icon.SwallowTouchEnabled = false
        icon.LocalZOrder = 1
        icon.Visible = false
        local label = overlay(root, 'ItemBarLabel' .. index, x, y - 35, 110, 28,
            '', 24, Color.New(255, 255, 255, 255))
        local amount = overlay(root, 'ItemBarAmount' .. index, x + 37, y + 37, 30, 30,
            '', 24, Color.New(255, 220, 40, 255))
        label.Visible = false
        amount.Visible = false
        self.Overlays[#self.Overlays + 1] = icon
        self.Overlays[#self.Overlays + 1] = label
        self.Overlays[#self.Overlays + 1] = amount
        self.Slots[index] = { Background = background, Icon = icon, Label = label, Count = amount }
        self:Listen(background.OnClicked, function() self:Action('SelectSlot', index) end)
    end
    self.BtnBait = button(root, 'BaitWorm', firstX + 80, 540, 170)
    self.BtnNone = button(root, 'BaitNone', firstX + 270, 540, 170)
    self.BtnEat = button(root, 'BaitEat', firstX + 460, 540, 170)
    self.BtnDiscard = button(root, 'ItemDiscard', firstX + 650, 540, 170)
    self.BtnItemAction = button(root, 'ItemAction2', resolution.x - 220, 690, 180)
    self.Buttons = { self.BtnBait, self.BtnNone, self.BtnEat, self.BtnDiscard, self.BtnItemAction }
    local labels = {
        { 'BtnBaitLabel', self.BtnBait, '蚯蚓' },
        { 'BtnNoneLabel', self.BtnNone, '不挂鱼饵' },
        { 'BtnEatLabel', self.BtnEat, '吃蚯蚓' },
        { 'BtnDiscardLabel', self.BtnDiscard, '丢弃选中物' },
        { 'BtnItemActionLabel', self.BtnItemAction, '抛竿' },
    }
    for _, entry in ipairs(labels) do
        local btn = entry[2]
        local label = overlay(root, entry[1], btn.Position.x, btn.Position.y,
            btn.Size.x, btn.Size.y, entry[3], 30, Color.New(255, 255, 255, 255))
        self[entry[1]] = label
        self.Overlays[#self.Overlays + 1] = label
    end
    self.BtnItemAction.TouchEnabled = false
    self.BtnItemAction.Visible = false
    self.BtnItemActionLabel.Visible = false
    self.BtnDiscard.Visible = false
    self.BtnDiscardLabel.Visible = false
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

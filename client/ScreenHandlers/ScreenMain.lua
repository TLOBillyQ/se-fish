local World = game:GetService('World')
local GameCfg = require('common.GameCfg')

local ScreenHandler = { UINodes = {}, UINodeMap = {} }

function ScreenHandler:Show(snapshot)
    if type(snapshot) ~= 'table' then return end
    self.Snapshot = snapshot
    for index, slot in ipairs(self.Slots or {}) do
        local entry = snapshot[index]
        local definition = entry and GameCfg.Items.Definitions[entry.itemId]
        slot.Icon.Visible = definition ~= nil
        if definition then
            slot.Icon.Image = definition.Icon
            slot.Label.Text = definition.Name
            slot.Count.Text = tostring(entry.count)
        else
            slot.Label.Text = ''
            slot.Count.Text = ''
        end
    end
end

function ScreenHandler:Init()
    if self.Inited then return end
    local euiMgr = _G.GameUI:GetEuiManager()
    if not euiMgr then return end
    local resolution = euiMgr:GetDeviceResolution()
    local root = self.RootNode
    self.Slots = {}
    local count = GameCfg.Items.ItemBarSlots
    local step = 120
    local firstX = (resolution.x - (count - 1) * step) / 2
    for index = 1, count do
        local background = World:CreateUnit('EUIImage', {
            Parent = root,
            Name = 'ItemBarSlot' .. index,
            Image = 'official://image/11017',
            Color = Color.New(35, 53, 68, 220),
            Position = Vector2.New(firstX + (index - 1) * step, 400),
            Size = Vector2.New(110, 110),
        })
        local icon = World:CreateUnit('EUIImage', {
            Parent = background,
            Name = 'ItemBarIcon' .. index,
            Position = Vector2.New(55, 70),
            Size = Vector2.New(78, 78),
        })
        icon.Visible = false
        local label = World:CreateUnit('EUITextLabel', {
            Parent = background,
            Name = 'ItemBarCount' .. index,
            Position = Vector2.New(55, 20),
            Size = Vector2.New(110, 28),
            FontSize = 22,
            TextColor = Color.New(255, 255, 255, 255),
        })
        local amount = World:CreateUnit('EUITextLabel', {
            Parent = background,
            Name = 'ItemBarAmount' .. index,
            Position = Vector2.New(92, 92),
            Size = Vector2.New(30, 30),
            FontSize = 24,
            TextColor = Color.New(255, 220, 40, 255),
        })
        self.Slots[index] = { Background = background, Icon = icon, Label = label, Count = amount }
    end
    _G.REUtil:GetRE('ItemBarState').OnClientEvent:Connect(function(snapshot)
        self:Show(snapshot)
    end)
    self.Inited = true
    _G.REUtil:GetRE('RequestItemBar'):FireServer()
end

return ScreenHandler

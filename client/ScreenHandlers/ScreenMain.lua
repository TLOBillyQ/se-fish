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
            slot.Label.Text = definition.Name .. ' ×' .. tostring(entry.count)
        else
            slot.Label.Text = ''
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
            Position = Vector2.New(firstX + (index - 1) * step, 310),
            Size = Vector2.New(110, 110),
        })
        local icon = World:CreateUnit('EUIImage', {
            Parent = background,
            Name = 'ItemBarIcon' .. index,
            Position = Vector2.New(0, 10),
            Size = Vector2.New(62, 62),
        })
        icon.Visible = false
        local label = World:CreateUnit('EUITextLabel', {
            Parent = background,
            Name = 'ItemBarCount' .. index,
            Position = Vector2.New(0, -40),
            Size = Vector2.New(110, 28),
            FontSize = 18,
            TextColor = Color.New(255, 255, 255, 255),
        })
        self.Slots[index] = { Background = background, Icon = icon, Label = label }
    end
    _G.REUtil:GetRE('ItemBarState').OnClientEvent:Connect(function(snapshot)
        self:Show(snapshot)
    end)
    self.Inited = true
    _G.REUtil:GetRE('RequestItemBar'):FireServer()
end

return ScreenHandler

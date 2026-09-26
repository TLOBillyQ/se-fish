-- 场景气泡共用按钮与文字层；节点均由调用方的场景根持有，随根隐藏和销毁。
local Style = require('common.GameCfg').InteractionBubble
local World = game:GetService('World')
local Bubble = {}

function Bubble.CreateButton(parent, name, text, x, onClick)
    local button, label
    local ok, err = pcall(function()
        local color = Style.BackgroundColor
        button = World:CreateUnit('EUIButton', {
            Parent = parent, Name = name, Position = Vector2.New(x, 0),
            Size = Vector2.New(Style.Width, Style.Height), ButtonText = '',
            NormalImage = Style.Image, PressImage = Style.Image, DisableImage = Style.Image,
            ButtonNormalColor = Color.New(color[1], color[2], color[3], color[4]),
        })
        assert(button, '按钮创建失败')
        label = World:CreateUnit('EUITextLabel', {
            Parent = parent, Name = name .. 'Text', Position = Vector2.New(x, 0),
            Size = Vector2.New(Style.Width, Style.Height),
            Text = text, FontSize = Style.FontSize, TextColor = Color.New(255, 255, 255, 255),
        })
        assert(label, '文字创建失败')
        label.TouchEnabled = false
        label.SwallowTouchEnabled = false
        label.LocalZOrder = 1
        button.TouchEnabled = true
        button.OnClicked:Connect(onClick)
    end)
    if not ok then
        if label then label:Destroy() end
        if button then button:Destroy() end
        print('[InteractionBubble] 创建失败', name, tostring(err))
        return nil
    end
    return button
end

return Bubble

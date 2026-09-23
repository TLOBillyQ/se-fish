-- 钓鱼佬「对话」「喂食」文字泡（#44）：在交互点锚点单位上方建一个场景 UI，放两个按钮，
-- 本地角色在 Radius 米内（只看 x/z）才显示。「对话」本地弹固定台词；「喂食」只发请求
-- （InteractAction{target, action, seq}，seq 递增防重放），结果以服务端回包为准。
local GameCfg = require('common.GameCfg')
local REUtil = require('common.REUtil')
local Util = require('common.Util')

local LocalInteract = { Seq = 0 }

local World = game:GetService('World')
local Players = game:GetService('Players')

local function notice(msg)
    if _G.LocalMsgNotice then _G.LocalMsgNotice(msg) end
end

function LocalInteract:Button(node, name, text, x, onClick)
    local ok, btn = pcall(World.CreateUnit, World, 'EUIButton', {
        Parent = node,
        Name = name,
        Position = Vector2.New(x, 0),
        Size = Vector2.New(160, 64),
    })
    if not ok or not btn then
        print('[LocalInteract] 按钮创建失败', name, tostring(btn))
        return nil
    end
    btn.ButtonText = text
    btn.TouchEnabled = true
    btn.OnClicked:Connect(onClick)
    return btn
end

function LocalInteract:Feed()
    self.Seq = self.Seq + 1
    REUtil:GetRE('InteractAction'):FireServer({ target = 'fisherman', action = 'Feed', seq = self.Seq })
end

function LocalInteract:Create(anchor)
    local cfg = GameCfg.Interact.Fisherman
    local player = Players.LocalPlayer
    local eui = player and player.PlayerGui and player.PlayerGui.EuiManager
    local center = anchor.Position
    if not eui or not center then return end
    local ok, node = pcall(eui.CreateSceneNodeAtPosition, eui,
        Vector3.New(center.x, center.y + cfg.BubbleHeight, center.z))
    if not ok or not node then
        print('[LocalInteract] 钓鱼佬文字泡创建失败', tostring(node))
        return
    end
    self:Button(node, 'BtnFishermanTalk', '对话', -90, function() notice(cfg.DialogText) end)
    self:Button(node, 'BtnFishermanFeed', '喂食', 90, function() self:Feed() end)
    node.Visible = false
    self.Node = node
    self.Center = center
end

function LocalInteract:Update()
    if not self.Node then return end
    local character = Players.LocalPlayer and Players.LocalPlayer.Character
    local pos = character and character.Position
    local visible = false
    if pos then
        local dx, dz = pos.x - self.Center.x, pos.z - self.Center.z
        local radius = GameCfg.Interact.Fisherman.Radius
        visible = dx * dx + dz * dz <= radius * radius
    end
    if self.Visible ~= visible then
        self.Visible = visible
        pcall(function() self.Node.Visible = visible end)
    end
end

function LocalInteract:Start()
    REUtil:GetRE('InteractResult').OnClientEvent:Connect(function(result)
        if type(result) ~= 'table' then return end
        if result.ok then
            notice('钓鱼佬吃得很香，金币 +' .. tostring(result.coins))
        elseif result.reason == 'nothing' then
            notice('先选中要喂的鱼获或鱼饵')
        end
    end)
    local anchor = Util:WaitForChild(World, GameCfg.Interact.Fisherman.AnchorName)
    if not anchor then
        print('[LocalInteract] 找不到钓鱼佬单位', GameCfg.Interact.Fisherman.AnchorName)
        return
    end
    self:Create(anchor)
    game:GetService('RunService').Heartbeat:Connect(function() self:Update() end)
end

return LocalInteract

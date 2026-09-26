-- 钓鱼佬「对话」「喂食」文字泡（#44）：在交互点锚点单位上方建一个场景 UI，放两个按钮，
-- 本地角色在 Radius 米内（只看 x/z）才显示。「对话」本地弹固定台词；「喂食」只发请求
-- （InteractAction{target, action, seq}，seq 递增防重放），结果以服务端回包为准。
-- 喂食成功的吃动作是客户端缩放脉冲：对 ModelName 模型按 Heartbeat 帧数播 1→放大→还原，
-- 仅喂食者本机可见；模型缺失或写 Scale 失败只记日志，不影响文字泡与结算。
local GameCfg = require('common.GameCfg')
local REUtil = require('common.REUtil')
local Util = require('common.Util')

local LocalInteract = { Seq = 0 }

-- 缩放脉冲参数：PulseFrames 帧内按 sin 曲线放大到 1+PulseAmp 再还原（帧率相关，表现层可接受）
local PulseFrames = 20
local PulseAmp = 0.2

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

function LocalInteract:UpdatePulse()
    if not self.PulseLeft then return end
    local model = self.Model
    if not model then
        self.PulseLeft = nil
        return
    end
    -- 末帧（PulseLeft==1）factor 取 1，把缩放显式还原到基准，免得脉冲结束残留放大
    local factor = 1
    if self.PulseLeft > 1 then
        local progress = 1 - self.PulseLeft / PulseFrames
        factor = 1 + PulseAmp * math.sin(math.pi * progress)
    end
    local base = self.ModelBaseScale
    local ok, err = pcall(function()
        model.Scale = Vector3.New(base.x * factor, base.y * factor, base.z * factor)
    end)
    if not ok then
        print('[LocalInteract] 钓鱼佬缩放脉冲失败，放弃表现', tostring(err))
        self.PulseLeft = nil
        self.Model = nil
        return
    end
    self.PulseLeft = self.PulseLeft - 1
    if self.PulseLeft <= 0 then self.PulseLeft = nil end
end

function LocalInteract:Update()
    self:UpdatePulse()
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
            if self.Model then self.PulseLeft = PulseFrames end
        elseif result.reason == 'nothing' then
            notice('先选中要喂的鱼获或鱼饵')
        end
    end)
    local cfg = GameCfg.Interact.Fisherman
    local anchor = Util:WaitForChild(World, cfg.AnchorName)
    if not anchor then
        print('[LocalInteract] 找不到钓鱼佬单位', cfg.AnchorName)
        return
    end
    self:Create(anchor)
    local model = cfg.ModelName and Util:WaitForChild(World, cfg.ModelName)
    if model then
        local ok, scale = pcall(function() return model.Scale end)
        if ok and scale then
            self.Model = model
            self.ModelBaseScale = scale
        else
            print('[LocalInteract] 钓鱼佬模型读 Scale 失败，跳过吃动作', tostring(scale))
        end
    else
        print('[LocalInteract] 找不到钓鱼佬模型，跳过吃动作', tostring(cfg.ModelName))
    end
    game:GetService('RunService').Heartbeat:Connect(function() self:Update() end)
end

return LocalInteract

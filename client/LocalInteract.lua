-- 钓鱼佬「对话」「喂食」文字泡（#44；#90 多锚点；#127 按区分派）：七区各一个钓鱼佬锚点
-- （Interact.Fishermen[i].AnchorNames，锚点取 #125 场景合同）上方建一个场景 UI，放两个按钮，
-- 本地角色在该锚点 Radius 米内（只看 x/z）才显示。「对话」本地弹固定台词；「喂食」只发请求
-- （InteractAction{target, action, seq}，seq 递增防重放），结果以服务端回包为准。
-- 喂食成功的吃动作是客户端缩放脉冲：对 ModelName 模型按 Heartbeat 帧数播 1→放大→还原，
-- 仅喂食者本机可见；模型缺失或写 Scale 失败只记日志，不影响文字泡与结算。
local GameCfg = require('common.GameCfg')
local BodyScale = require('common.BodyScale')
local REUtil = require('common.REUtil')
local Util = require('common.Util')

local Bubble = require('client.InteractionBubble')
local LocalInteract = { Seq = 0, Bubbles = {} }

-- 缩放脉冲参数：PulseFrames 帧内按 sin 曲线放大到 1+PulseAmp 再还原（帧率相关，表现层可接受）
local PulseFrames = 20
local PulseAmp = 0.2

local World = game:GetService('World')
local Players = game:GetService('Players')

local function notice(msg)
    if _G.LocalMsgNotice then _G.LocalMsgNotice(msg) end
end

function LocalInteract:Button(node, name, text, x, onClick)
    return Bubble.CreateButton(node, name, text, x, onClick)
end

function LocalInteract:Feed()
    self.Seq = self.Seq + 1
    REUtil:GetRE('InteractAction'):FireServer({ target = 'fisherman', action = 'Feed', seq = self.Seq })
end

function LocalInteract:Create(anchor, suffix)
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
    local offset = (GameCfg.InteractionBubble.Width + GameCfg.InteractionBubble.Gap) / 2
    -- 按钮名带区后缀：七区钓鱼佬各有自己的文字泡，名字不能撞
    self:Button(node, 'BtnFishermanTalk' .. suffix, '对话', -offset,
        function() notice(cfg.DialogText) end)
    self:Button(node, 'BtnFishermanFeed' .. suffix, '喂食', offset, function() self:Feed() end)
    node.Visible = false
    self.Bubbles[#self.Bubbles + 1] = { Node = node, Center = center, Visible = false }
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
    local character = Players.LocalPlayer and Players.LocalPlayer.Character
    local pos = character and character.Position
    local radius = BodyScale.InteractionRadius(character, GameCfg.Interact.Fisherman.Radius)
    for _, bubble in ipairs(self.Bubbles) do
        local visible = false
        if pos then
            local dx, dz = pos.x - bubble.Center.x, pos.z - bubble.Center.z
            visible = dx * dx + dz * dz <= radius * radius
        end
        if bubble.Visible ~= visible then
            bubble.Visible = visible
            local ok, err = pcall(function() bubble.Node.Visible = visible end)
            if not ok then print('[LocalInteract] 气泡显隐失败', tostring(err)) end
        end
    end
end

function LocalInteract:Start()
    REUtil:GetRE('InteractResult').OnClientEvent:Connect(function(result)
        if type(result) ~= 'table' then return end
        if result.ok then
            if result.achievement then
                -- 第七区最终成就（#127）：产物不占格，回包只给成就 id，名字查 GameCfg.Achievements
                local achievement = GameCfg.Achievements[result.achievement]
                notice('达成' .. (achievement and achievement.Name or tostring(result.achievement)))
            elseif type(result.exchange) == 'table' then
                -- 信物兑换（#87）：回包带兑换双方 id，按物品表名字拼提示；吃动作脉冲与金币喂食相同
                local defs = GameCfg.Items.Definitions
                local from = defs[result.exchange.from]
                local to = defs[result.exchange.to]
                notice('用' .. (from and from.Name or tostring(result.exchange.from))
                    .. '换得' .. (to and to.Name or tostring(result.exchange.to)) .. ' x1')
            else
                notice('钓鱼佬吃得很香，金币 +' .. tostring(result.coins))
            end
            if self.Model then self.PulseLeft = PulseFrames end
        elseif result.reason == 'nothing' then
            notice('先选中要喂的鱼获或鱼饵')
        elseif result.reason == 'full' then
            notice('格子满了，钓鱼佬不肯换')
        end
    end)
    local shared = GameCfg.Interact.Fisherman
    -- 按区分派（#127）：七区各一个钓鱼佬；未建区的锚点取不到时只记日志
    for index, npc in ipairs(GameCfg.Interact.Fishermen) do
        for _, name in ipairs(npc.AnchorNames) do
            local anchor = Util:WaitForChild(World, name)
            if anchor then
                self:Create(anchor, index .. '_' .. name)
            else
                print('[LocalInteract] 找不到钓鱼佬单位', npc.ZoneId, name)
            end
        end
    end
    local model = shared.ModelName and Util:WaitForChild(World, shared.ModelName)
    if model then
        local ok, scale = pcall(function() return model.Scale end)
        if ok and scale then
            self.Model = model
            self.ModelBaseScale = scale
        else
            print('[LocalInteract] 钓鱼佬模型读 Scale 失败，跳过吃动作', tostring(scale))
        end
    else
        print('[LocalInteract] 找不到钓鱼佬模型，跳过吃动作', tostring(shared.ModelName))
    end
    game:GetService('RunService').Heartbeat:Connect(function() self:Update() end)
end

return LocalInteract

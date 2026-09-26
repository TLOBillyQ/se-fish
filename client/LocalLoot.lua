-- 鱼获「拾取」文字泡（#43）：按服务端广播的鱼获列表在每份鱼获上方建场景 UI 按钮，
-- 本地角色在 PickupRadius 米内才显示；点击只发请求（ItemBarAction{action='Pickup'}），结果以服务端回包为准。
local GameCfg = require('common.GameCfg')
local REUtil = require('common.REUtil')

local LocalLoot = { Nodes = {} }

local Bubble = require('client.InteractionBubble')
local Players = game:GetService('Players')

function LocalLoot:EuiManager()
    local player = Players.LocalPlayer
    return player and player.PlayerGui and player.PlayerGui.EuiManager
end

function LocalLoot:Clear(id)
    local entry = self.Nodes[id]
    self.Nodes[id] = nil
    if entry then pcall(function() entry.Node:Destroy() end) end
end

function LocalLoot:Create(loot)
    local eui = self:EuiManager()
    if not eui then return end
    local ok, node = pcall(eui.CreateSceneNodeAtPosition, eui,
        Vector3.New(loot.x, loot.y + GameCfg.Loot.BubbleHeight, loot.z))
    if not ok or not node then
        print('[LocalLoot] 拾取文字泡创建失败', loot.id, tostring(node))
        return
    end
    local btn = Bubble.CreateButton(node, 'BtnPickup_' .. tostring(loot.id), '拾取', 0, function()
        REUtil:GetRE('ItemBarAction'):FireServer({ action = 'Pickup', value = loot.id })
    end)
    if not btn then
        pcall(function() node:Destroy() end)
        return
    end
    node.Visible = false
    self.Nodes[loot.id] = { Node = node, Position = loot }
end

function LocalLoot:Show(list)
    local alive = {}
    for _, loot in ipairs(list or {}) do
        alive[loot.id] = true
        if not self.Nodes[loot.id] then self:Create(loot) end
    end
    for id in pairs(self.Nodes) do
        if not alive[id] then self:Clear(id) end
    end
end

function LocalLoot:Update()
    local character = Players.LocalPlayer and Players.LocalPlayer.Character
    local pos = character and character.Position
    local radius = GameCfg.Loot.PickupRadius
    for _, entry in pairs(self.Nodes) do
        local visible = false
        if pos then
            local p = entry.Position
            local dx, dy, dz = pos.x - p.x, pos.y - p.y, pos.z - p.z
            visible = dx * dx + dy * dy + dz * dz <= radius * radius
        end
        if entry.Visible ~= visible then
            entry.Visible = visible
            pcall(function() entry.Node.Visible = visible end)
        end
    end
end

function LocalLoot:Start()
    REUtil:GetRE('LootState').OnClientEvent:Connect(function(list) self:Show(list) end)
    REUtil:GetRE('LootResult').OnClientEvent:Connect(function(result)
        if type(result) == 'table' and result.reason == 'full' and _G.LocalMsgNotice then
            _G.LocalMsgNotice('背包已满')
        end
    end)
    game:GetService('RunService').Heartbeat:Connect(function() self:Update() end)
    REUtil:GetRE('RequestLoot'):FireServer()
end

return LocalLoot

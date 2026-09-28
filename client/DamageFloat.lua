-- 鱼受伤跳字：只消费服务端确认的扣血通知；节点由 ScreenMain 持有并随界面清理。
local GameCfg = require('common.GameCfg')
local DamageFloat = { Active = {}, Pool = {}, Sequence = {}, PendingCleanup = {} }
local cfg = GameCfg.DamageFloat

function DamageFloat.DisplayAmount(amount)
    return math.max(1, math.floor(amount + 0.5))
end

function DamageFloat:Clear()
    local pending = {}
    local function destroy(node)
        local ok, err = pcall(function() node:Destroy() end)
        if not ok then
            print('[DamageFloat] 清理节点失败', tostring(err))
            pending[#pending + 1] = node
        end
    end
    for _, node in ipairs(self.PendingCleanup) do destroy(node) end
    self.PendingCleanup = pending
    for _, entry in ipairs(self.Active) do destroy(entry.Node) end
    for _, node in ipairs(self.Pool) do destroy(node) end
    self.Active, self.Pool, self.Sequence = {}, {}, {}
    self.Root, self.Resolution = nil, nil
end

function DamageFloat:Bind(root, resolution)
    if self.Root == root then return end
    self:Clear()
    self.Root, self.Resolution = root, resolution
end

local function valid(payload)
    local p = type(payload) == 'table' and payload.position
    return type(payload) == 'table' and type(payload.targetType) == 'string'
        and type(payload.targetId) == 'number' and type(payload.amount) == 'number'
        and payload.amount > 0 and payload.amount < math.huge and type(p) == 'table'
        and type(p.x) == 'number' and p.x == p.x and math.abs(p.x) < math.huge
        and type(p.y) == 'number' and p.y == p.y and math.abs(p.y) < math.huge
        and type(p.z) == 'number' and p.z == p.z and math.abs(p.z) < math.huge
end

function DamageFloat:Project(position, height)
    local camera = game:GetService('CameraService')
    if not camera or not camera.MainCamera or not self.Resolution then return nil end
    local screen, visible = camera:WorldToViewportPoint(Vector3.New(
        position.x, position.y + (height or cfg.HeadHeight), position.z))
    if not screen or not visible or screen.z <= 0 then return nil end
    return screen.x, self.Resolution.y - screen.y
end

function DamageFloat:Show(payload)
    if not self.Root or not valid(payload) then return end
    local x, y = self:Project(payload.position, payload.height)
    if not x then return end
    local node = table.remove(self.Pool)
    if not node then
        node = game:GetService('World'):CreateUnit('EUITextLabel', {
            Parent = self.Root, Name = 'DamageFloat',
            Position = Vector2.New(0, 0), Size = Vector2.New(cfg.Width, cfg.Height),
        })
    end
    if not node then return end
    local key = payload.targetType .. ':' .. tostring(payload.targetId)
    local sequence = (self.Sequence[key] or 0) + 1
    self.Sequence[key] = sequence
    local spread = ((sequence - 1) % 3 - 1) * cfg.SpreadPixels
    local critical = payload.critical == true
    local color = critical and cfg.CriticalColor or cfg.NormalColor
    node.Text = tostring(self.DisplayAmount(payload.amount))
    node.TextColor = Color.New(color[1], color[2], color[3], color[4])
    node.FontSize = critical and cfg.CriticalFontSize or cfg.NormalFontSize
    node.TouchEnabled = false
    node.SwallowTouchEnabled = false
    node.Position = Vector2.New(x + spread, y)
    node.Opacity = 1
    node.Visible = true
    node.LocalZOrder = 10
    local entry = { Node = node, Start = game:GetService('World'):GetServerTime(),
        Position = payload.position, Height = payload.height, Spread = spread }
    self.Active[#self.Active + 1] = entry
end

function DamageFloat:Update()
    if not self.Root then return end
    if #self.PendingCleanup > 0 then
        local pending = self.PendingCleanup
        self.PendingCleanup = {}
        for _, node in ipairs(pending) do
            local ok, err = pcall(function() node:Destroy() end)
            if not ok then
                print('[DamageFloat] 重试清理失败', tostring(err))
                self.PendingCleanup[#self.PendingCleanup + 1] = node
            end
        end
    end
    local now = game:GetService('World'):GetServerTime()
    for i = #self.Active, 1, -1 do
        local entry = self.Active[i]
        local progress = math.max(0, (now - entry.Start) / cfg.DurationSec)
        if progress >= 1 then
            entry.Node.Visible = false
            entry.Node.Opacity = 1
            table.remove(self.Active, i)
            if #self.Pool < cfg.PoolSize then
                self.Pool[#self.Pool + 1] = entry.Node
            else
                entry.Node:Destroy()
            end
        else
            local x, y = self:Project(entry.Position, entry.Height)
            entry.Node.Visible = x ~= nil
            if x then
                entry.Node.Position = Vector2.New(x + entry.Spread, y + cfg.RisePixels * progress)
                entry.Node.Opacity = 1 - progress
            end
        end
    end
end

return DamageFloat

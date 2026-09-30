-- #134 精英鱼头顶状态字：只消费服务端 FishCombatState 广播，显示逃跑时限条（电鳗 180 / 鳄雀鳝 300），
-- 电鳗另显放电次数与睡眠倒计时。
-- 节点挂在 ScreenMain 根节点下，随界面 Bind / Clear；倒计时按服务端时间与结束时刻计算，不在本地推进状态。
local GameCfg = require('common.GameCfg')
local FishCombatLabel = { Labels = {} }
local cfg = GameCfg.FishCombatLabel

local function finite(v)
    return type(v) == 'number' and v == v and math.abs(v) < math.huge
end

function FishCombatLabel.Valid(payload)
    if type(payload) ~= 'table' or type(payload.id) ~= 'number' or type(payload.state) ~= 'string' then return false end
    if payload.state == 'gone' or payload.state == 'escaping' then return true end
    local p = payload.position
    return type(payload.fishId) == 'string' and finite(payload.fleeAt) and finite(payload.escapeSec)
        and payload.escapeSec > 0 and type(p) == 'table' and finite(p.x) and finite(p.y) and finite(p.z)
end

-- 纯函数：由快照与服务端时间得出文字；到逃跑时限返回 nil（服务端随后广播 escaping）。
function FishCombatLabel.Text(payload, now)
    local left = payload.fleeAt - now
    if left <= 0 then return nil end
    local species = GameCfg.Fish[payload.fishId]
    local name = species and species.Name or payload.fishId
    local cells = cfg.BarCells
    local filled = math.max(0, math.min(cells, math.ceil(left / payload.escapeSec * cells)))
    local bar = '[' .. string.rep('=', filled) .. string.rep('-', cells - filled) .. ']'
    local flee = string.format('逃跑时限 %s %d 秒', bar, math.ceil(left))
    if payload.fishId == 'eel' and payload.state == 'attacking' then
        return string.format('%s 放电 %d/%d | %s', name, payload.discharges or 0, payload.dischargeCount or 0, flee), 'attack'
    elseif payload.state == 'stunned' and finite(payload.wakeAt) then
        return string.format('%s 眩晕 %d 秒 | %s', name, math.max(0, math.ceil(payload.wakeAt - now)), flee), 'sleep'
    elseif payload.move then
        local dragon = GameCfg.FishCombat.dragon
        local moves = { claw = '虾钳攻击', tail = '尾刺击飞', peck = '啄击',
            rain = string.format('雨云：%g米内每秒%g伤害', dragon.RainRadius, dragon.RainDamage), dive = '飞起俯冲',
            jab = '蟹钳乱刺', pinch = '蟹钳双击', charge = '冲撞', spin = '旋转' }
        return string.format('%s %s | %s', name, moves[payload.move] or '攻击', flee), 'attack'
    elseif payload.state == 'sleeping' and finite(payload.wakeAt) then
        return string.format('%s 睡眠 %d 秒 | %s', name, math.max(0, math.ceil(payload.wakeAt - now)), flee), 'sleep'
    end
    return string.format('%s | %s', name, flee), 'idle'
end

function FishCombatLabel:Clear()
    for _, label in pairs(self.Labels) do
        local ok, err = pcall(function() label.Node:Destroy() end)
        if not ok then print('[FishCombatLabel] 清理节点失败', tostring(err)) end
    end
    self.Labels = {}
    self.Root, self.Resolution = nil, nil
end

function FishCombatLabel:Bind(root, resolution)
    if self.Root == root then return end
    self:Clear()
    self.Root, self.Resolution = root, resolution
end

function FishCombatLabel:Drop(id)
    local label = self.Labels[id]
    if not label then return end
    self.Labels[id] = nil
    local ok, err = pcall(function() label.Node:Destroy() end)
    if not ok then print('[FishCombatLabel] 移除节点失败', id, tostring(err)) end
end

function FishCombatLabel:Apply(payload)
    if not self.Root or not self.Valid(payload) then return end
    if payload.state == 'gone' or payload.state == 'escaping' then
        self:Drop(payload.id)
        return
    end
    local label = self.Labels[payload.id]
    if not label then
        local node = game:GetService('World'):CreateUnit('EUITextLabel', {
            Parent = self.Root, Name = 'FishCombatLabel', Position = Vector2.New(0, 0),
            Size = Vector2.New(cfg.Width, cfg.Height),
        })
        if not node then
            print('[FishCombatLabel] 节点创建失败', payload.id)
            return
        end
        node.FontSize = cfg.FontSize
        node.TouchEnabled = false
        node.SwallowTouchEnabled = false
        node.LocalZOrder = 9
        label = { Node = node }
        self.Labels[payload.id] = label
    end
    label.Payload = payload
    self:Refresh(label, game:GetService('World'):GetServerTime())
end

function FishCombatLabel:Project(position)
    local camera = game:GetService('CameraService')
    if not camera or not camera.MainCamera or not self.Resolution then return nil end
    local screen, visible = camera:WorldToViewportPoint(Vector3.New(position.x, position.y + cfg.HeadHeight, position.z))
    if not screen or not visible or screen.z <= 0 then return nil end
    return screen.x, self.Resolution.y - screen.y
end

local COLORS = { attack = 'AttackColor', sleep = 'SleepColor', idle = 'IdleColor' }

function FishCombatLabel:Refresh(label, now)
    local text, kind = self.Text(label.Payload, now)
    local x, y
    if text then x, y = self:Project(label.Payload.position) end
    label.Node.Visible = x ~= nil
    if not x then return end
    local color = cfg[COLORS[kind]]
    label.Node.Text = text
    label.Node.TextColor = Color.New(color[1], color[2], color[3], color[4])
    label.Node.Position = Vector2.New(x, y)
end

function FishCombatLabel:Update()
    if not self.Root then return end
    local now = game:GetService('World'):GetServerTime()
    for _, label in pairs(self.Labels) do self:Refresh(label, now) end
end

return FishCombatLabel

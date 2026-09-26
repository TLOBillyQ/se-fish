local World = game:GetService('World')
local GameCfg = require('common.GameCfg')
local LocalAttackButton = require('client.LocalAttackButton')

local ScreenHandler = { UINodes = {}, UINodeMap = {} }

function ScreenHandler:Action(action, value)
    _G.REUtil:GetRE('ItemBarAction'):FireServer({ action = action, value = value })
end

function ScreenHandler:Show(state)
    if type(state) ~= 'table' or type(state.slots) ~= 'table' then return end
    self.Snapshot = state
    local capacity = state.slotCount or GameCfg.Items.ItemBarSlots
    for index, slot in ipairs(self.Slots or {}) do
        local entry = state.slots[index]
        local definition = entry and GameCfg.Items.Definitions[entry.itemId]
        slot.Background.Visible = index <= capacity
        slot.Background.TouchEnabled = index <= capacity
        slot.Icon.Visible = index <= capacity and definition ~= nil
        if definition then slot.Icon.Image = definition.Icon end
        slot.Label.Text = definition and definition.Name or ''
        slot.Label.Visible = index <= capacity and definition ~= nil
        slot.Count.Text = definition and tostring(entry.count) or ''
        slot.Count.Visible = index <= capacity and definition ~= nil
        slot.Background.ButtonNormalColor = index == state.selectedSlot
            and Color.New(36, 130, 94, 255) or Color.New(54, 100, 140, 255)
    end
    local baitId = GameCfg.Items.Id.Worm
    local count = state.bait and state.bait[baitId] or 0
    self.BtnBaitLabel.Text = '蚯蚓 ×' .. tostring(count)
    self.BtnBait.ButtonNormalColor = state.selectedBait == baitId
        and Color.New(36, 130, 94, 255) or Color.New(54, 100, 140, 255)
    self.BtnBait.TouchEnabled = count > 0
    -- 吃（#53）：选中格是能吃的鱼获时吃它，否则吃蚯蚓
    local food = self:SelectedFood()
    self.BtnEat.TouchEnabled = food ~= nil or count > 0
    self.BtnEatLabel.Text = food and '吃' .. GameCfg.Items.Definitions[food.itemId].Name
        or count > 0 and '吃蚯蚓' or '蚯蚓用尽'
    self.BtnNoneLabel.Text = '不挂鱼饵'
    self:ShowCoin(state.coin)
    self:ShowCast()
    local selected = state.selectedSlot and state.slots[state.selectedSlot]
    self.BtnDiscard.Visible = selected ~= nil
    self.BtnDiscardLabel.Visible = selected ~= nil
    self:ShowBackpack()
end

-- 上钩提示（#54）：同一收线会话只触发一次；提示音缺失或播放失败时只保留文字与高亮
function ScreenHandler:StartHookAlert(session)
    if session == nil or session == self.AlertedSession then return end
    self.AlertedSession = session
    local alert = GameCfg.HookAlert
    self.HookAlertUntil = World:GetServerTime() + alert.DurationSec
    local ok, err = false, '未配置提示音'
    if alert.Sound then
        ok, err = pcall(function()
            game:GetService('SoundService'):PlayLocalSound(alert.Sound, alert.Volume, 1)
        end)
    end
    print('[ScreenMain] 上钩提示', tostring(session), ok and ('音效 ' .. alert.Sound)
        or ('音效缺失，只保留文字与高亮 ' .. tostring(err)))
end

-- 选中格里能吃的物品（配了 EatPercent 的鱼获），没有返回 nil
function ScreenHandler:SelectedFood()
    local state = self.Snapshot
    local slot = state and state.selectedSlot
    local entry = slot and state.slots[slot]
    local definition = entry and GameCfg.Items.Definitions[entry.itemId]
    if definition and type(definition.EatPercent) == 'number' then return entry, slot end
end

local function readVital(player, key, default)
    local value = tonumber(player:GetAttribute(key))
    return value and math.floor(value) or default
end

local function vitalPercent(value, maximum)
    return maximum > 0 and math.max(0, math.min(100, value * 100 / maximum)) or 0
end

local function updateStarving(self, health, hunger)
    local starving = hunger <= 0 and health > 0
    if starving and not self.Starving then self.NextWarnAt = nil end
    self.Starving = starving
    self:UpdateStarveFx()
end

-- 血球 / 饥饿球（#53）：数值只读服务端写的玩家属性 Health / MaxHealth / Hunger / MaxHunger
function ScreenHandler:ShowVitals()
    if not self.HealthRing then return end
    local player = game:GetService('Players').LocalPlayer
    if not player then return end
    local c = GameCfg.Vitals
    local health = readVital(player, 'Health', c.MaxHealth)
    local maxHealth = readVital(player, 'MaxHealth', c.MaxHealth)
    local hunger = readVital(player, 'Hunger', c.MaxHunger)
    local maxHunger = readVital(player, 'MaxHunger', c.MaxHunger)
    self.HealthRing.Percent = vitalPercent(health, maxHealth)
    self.HungerRing.Percent = vitalPercent(hunger, maxHunger)
    self.HealthText.Text = '血 ' .. tostring(health)
    self.HungerText.Text = '饥饿 ' .. tostring(hunger)
    updateStarving(self, health, hunger)
end

local function warnStarving(self, now, config)
    if self.NextWarnAt and now < self.NextWarnAt then return end
    self.NextWarnAt = now + config.WarnIntervalSec
    if _G.LocalMsgNotice then _G.LocalMsgNotice(config.WarnText) end
    print('[ScreenMain] 饥饿提示', config.WarnText)
end

local function flashVisible(self, now, config)
    return self.Starving == true and math.floor(now / config.FlashPeriodSec) % 2 == 0
end

-- 饥饿归零期间：四边红框按 FlashPeriodSec 亮灭，WarnText 每 WarnIntervalSec 秒提示一次（不刷屏）
function ScreenHandler:UpdateStarveFx()
    if not self.FlashEdges then return end
    local c = GameCfg.Vitals
    local now = World:GetServerTime()
    local on = flashVisible(self, now, c)
    for _, edge in ipairs(self.FlashEdges) do edge.Visible = on end
    if self.Starving then warnStarving(self, now, c) end
end

-- 金币 HUD（#47）：接回场景既有的 ImageCoin / LabelCoin，以服务端同步的 FishCoin 属性为准
function ScreenHandler:ShowCoin(value)
    if not self.LabelCoin then return end
    if type(value) ~= 'number' then
        local players = game:GetService('Players')
        local player = players and players.LocalPlayer
        value = player and player:GetAttribute('FishCoin')
    end
    self.LabelCoin.Text = tostring(math.floor(tonumber(value) or 0))
end

-- 新手任务条（#51）：左上角一行「新手任务 步号/总数：文案（计数）」，以服务端 QuestState 为准；
-- 推进那一次带 notice，走既有消息条提示下一步
function ScreenHandler:ShowQuest(state)
    if not self.QuestLabel or type(state) ~= 'table' or type(state.text) ~= 'string' then return end
    self.QuestLabel.Text = state.text
    self.QuestLabel.Visible = true
    if type(state.notice) == 'string' and _G.LocalMsgNotice then _G.LocalMsgNotice(state.notice) end
end

local function castActionEnabled(self, phase, rod, drop, active)
    return self.IsOpen == true
        and ((rod and phase == 'idle') or drop or phase == 'cast' or active == true) or false
end

local function castActionColor(phase, now, alert)
    -- 上岸停留期间按钮灰化（#37），其余时候用常规底色
    if not now then
        return phase == 'landed' and Color.New(120, 120, 120, 255)
            or Color.New(54, 100, 140, 255)
    end
    local k = (math.sin(now * 2 * math.pi / alert.BreathPeriodSec) + 1) / 2
    local h = alert.HighlightColor
    return Color.New(math.floor(54 + (h[1] - 54) * k),
        math.floor(100 + (h[2] - 100) * k), math.floor(140 + (h[3] - 140) * k), h[4])
end

local function showCastAction(self, phase, rod, drop, active, alertNow)
    local visible = rod == true or phase ~= 'idle' or drop
    self.BtnItemAction.Visible = visible
    self.BtnItemActionLabel.Visible = visible
    self.BtnItemAction.TouchEnabled = castActionEnabled(self, phase, rod, drop, active)
    self.BtnItemAction.ButtonNormalColor = castActionColor(phase, alertNow, GameCfg.HookAlert)
    self.BtnItemActionLabel.Text = phase == 'hooked' and '点击收线'
        or phase == 'landed' and '已上岸' or phase == 'cast' and '收竿' or drop and '放下'
        or rod and '抛竿' or '使用'
end

local function castProgress(self, reel, active)
    local result = reel and reel.LastResult
    -- 收线中显示本地反馈并平滑追平权威进度（#38）；其余时候显示最后一次权威值
    return active and reel.DisplayProgress and reel:DisplayProgress()
        or result and self.CastState and result.session == self.CastState.reelSession and result.progress or 50
end

local function showCastFeedback(self, phase, active, alerting, progress)
    if self.ReelBar then
        self.ReelBar.Visible = active == true
        self.ReelBarBg.Visible = active == true
        self.ReelBar.Percent = progress
    end
    if self.HookHint then
        self.HookHint.Visible = active == true or phase == 'landed'
        self.HookHint.Text = phase == 'landed' and '鱼已上岸' or alerting and GameCfg.HookAlert.Text
            or active and '收线 ' .. tostring(math.floor(progress + 0.5)) .. '%' or ''
    end
    if self.BtnReelClose then
        self.BtnReelClose.Visible = active == true
        self.BtnReelCloseLabel.Visible = active == true
    end
end

function ScreenHandler:ShowCast()
    if not self.BtnItemAction then return end
    local state = self.Snapshot
    local selected = state and state.selectedSlot and state.slots[state.selectedSlot]
    local rod = selected and selected.itemId == GameCfg.Items.Id.StarterRod
    local phase = self.CastState and self.CastState.phase or 'idle'
    local reel = _G.LocalReelIn
    local active = self.IsOpen and phase == 'hooked' and reel
        and reel.SessionId == self.CastState.reelSession
    -- 头上顶着鱼（#41，以服务端 holding 为准）：空闲时 2 号位是「放下」
    local drop = phase == 'idle' and self.CastState ~= nil and self.CastState.holding ~= nil
    -- 上钩提示（#54）：本收线会话的前 DurationSec 秒按钮呼吸式高亮、文字改为提示语
    local now = active == true and self.HookAlertUntil ~= nil and World:GetServerTime()
    local alerting = now and now < self.HookAlertUntil
    showCastAction(self, phase, rod, drop, active, alerting and now)
    local progress = castProgress(self, reel, active)
    if type(progress) ~= 'number' or progress ~= progress then progress = 50 end
    progress = math.max(0, math.min(100, progress))
    showCastFeedback(self, phase, active, alerting, progress)
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

local function color(rgba)
    return Color.New(rgba[1], rgba[2], rgba[3], rgba[4])
end

local function passive(node)
    node.TouchEnabled = false
    node.SwallowTouchEnabled = false
    return node
end

-- 左上角血球 / 饥饿球与四边红框（#53）；图片用途见 GameCfg.Vitals
-- [未查证：位置是否与场景既有的 LabelCoin 重叠，待 #55 截图迭代；原点左下、Y 向上]
function ScreenHandler:BuildVitals(root, resolution)
    local c = GameCfg.Vitals
    local y = resolution.y - 130
    local rings = {
        { 'Health', 130, c.HealthRing, c.HealthColor },
        { 'Hunger', 290, c.HungerRing, c.HungerColor },
    }
    for _, spec in ipairs(rings) do
        local name, x = spec[1], spec[2]
        local bg = passive(World:CreateUnit('EUIImage', {
            Parent = root, Name = name .. 'RingBg',
            Position = Vector2.New(x, y), Size = Vector2.New(128, 128), Image = c.RingBg,
        }))
        local ring = passive(World:CreateUnit('EUIProgressTimer', {
            Parent = root, Name = name .. 'Ring',
            Position = Vector2.New(x, y), Size = Vector2.New(128, 128), Image = spec[3], Percent = 100,
        }))
        ring.Color = color(spec[4])
        ring.LocalZOrder = 1
        local text = overlay(root, name .. 'Text', x, y, 140, 40, '', 26, Color.New(255, 255, 255, 255))
        text.LocalZOrder = 2
        self[name .. 'Ring'] = ring
        self[name .. 'Text'] = text
        self.Overlays[#self.Overlays + 1] = bg
        self.Overlays[#self.Overlays + 1] = ring
        self.Overlays[#self.Overlays + 1] = text
    end
    local t, w, h = c.FlashThickness, resolution.x, resolution.y
    local edges = {
        { 'FlashTop', w / 2, h - t / 2, w, t }, { 'FlashBottom', w / 2, t / 2, w, t },
        { 'FlashLeft', t / 2, h / 2, t, h }, { 'FlashRight', w - t / 2, h / 2, t, h },
    }
    self.FlashEdges = {}
    for _, spec in ipairs(edges) do
        local edge = passive(World:CreateUnit('EUIImage', {
            Parent = root, Name = spec[1],
            Position = Vector2.New(spec[2], spec[3]), Size = Vector2.New(spec[4], spec[5]), Image = c.FlashImage,
        }))
        edge.Color = color(c.FlashColor)
        edge.LocalZOrder = 3
        edge.Visible = false
        self.FlashEdges[#self.FlashEdges + 1] = edge
        self.Overlays[#self.Overlays + 1] = edge
    end
end

function ScreenHandler:ShowBackpack()
    if not self.BackpackButton or not self.Snapshot then return end
    local state = self.Snapshot
    if type(state.backpackCount) ~= 'number' then return end
    self.BackpackLabel.Text = '背包 ' .. tostring(state.backpackCount) .. ' 格'
    self.BackpackPanel.Visible = self.BackpackOpen == true
    self.BackpackTitle.Visible = self.BackpackOpen == true
    for index, slot in ipairs(self.Slots or {}) do
        slot.Background.Visible = not self.BackpackOpen and index <= state.slotCount
        slot.Background.TouchEnabled = slot.Background.Visible
        slot.Icon.Visible = slot.Icon.Visible and not self.BackpackOpen
        slot.Label.Visible = slot.Label.Visible and not self.BackpackOpen
        slot.Count.Visible = slot.Count.Visible and not self.BackpackOpen
    end
    for index, slot in ipairs(self.BackpackSlots) do
        local visible = self.BackpackOpen == true and index <= state.backpackCount
        local entry = state.backpack and state.backpack[index]
        local definition = entry and GameCfg.Items.Definitions[entry.itemId]
        slot.Button.Visible = visible
        slot.Button.TouchEnabled = visible and definition ~= nil
        slot.Label.Visible = visible
        slot.Label.Text = definition and definition.Name or '空'
        slot.Button.ButtonNormalColor = index == self.SelectedBackpackSlot
            and Color.New(36, 130, 94, 255) or Color.New(54, 100, 140, 255)
    end
    local entry = state.backpack and state.backpack[self.SelectedBackpackSlot]
    self.MoveButton.Visible = self.BackpackOpen == true and entry ~= nil
    self.MoveLabel.Visible = self.MoveButton.Visible
    self.MoveButton.TouchEnabled = self.MoveButton.Visible
    local free = false
    for index = 1, state.slotCount do
        if not state.slots[index] then free = true break end
    end
    if self.BackpackOpen and entry and not free then
        self.MoveLabel.Text = '道具栏已满'
        self.MoveButton.TouchEnabled = false
    else
        self.MoveLabel.Text = '转入道具栏'
    end
end

function ScreenHandler:BuildBackpack(root, resolution)
    local center = resolution.x / 2
    local top = resolution.y - 100
    self.BackpackOpen = false
    self.BackpackSlots = {}
    self.BackpackButton = button(root, 'BtnBackpack', center, top, 220)
    self.BackpackLabel = overlay(root, 'LabelBackpack', center, top, 220, 70,
        '背包', 26, Color.New(255, 255, 255, 255))
    self.BackpackPanel = button(root, 'BackpackPanel', center, top - 360, 850)
    self.BackpackPanel.Size = Vector2.New(850, 690)
    self.BackpackPanel.TouchEnabled = false
    self.BackpackTitle = overlay(root, 'BackpackTitle', center, top - 70, 700, 48,
        '选择背包物品，再转入道具栏', 28, Color.New(255, 255, 255, 255))
    for index = 1, GameCfg.Items.MaxBackpackSlots do
        local col, row = (index - 1) % 8, math.floor((index - 1) / 8)
        local x, y = center - 350 + col * 100, top - 160 - row * 100
        local btn = button(root, 'BackpackSlot' .. index, x, y, 95)
        btn.Size = Vector2.New(95, 90)
        local label = overlay(root, 'BackpackLabel' .. index, x, y, 95, 80,
            '', 19, Color.New(255, 255, 255, 255))
        self.BackpackSlots[index] = { Button = btn, Label = label }
        self.Buttons[#self.Buttons + 1] = btn
        self.Overlays[#self.Overlays + 1] = label
        self:Listen(btn.OnClicked, function()
            self.SelectedBackpackSlot = index
            self:ShowBackpack()
        end)
    end
    self.MoveButton = button(root, 'BtnMoveToItemBar', center, top - 670, 330)
    self.MoveLabel = overlay(root, 'LabelMoveToItemBar', center, top - 670, 330, 70,
        '转入道具栏', 26, Color.New(255, 255, 255, 255))
    self.Buttons[#self.Buttons + 1] = self.BackpackButton
    self.Buttons[#self.Buttons + 1] = self.BackpackPanel
    self.Buttons[#self.Buttons + 1] = self.MoveButton
    self.Overlays[#self.Overlays + 1] = self.BackpackLabel
    self.Overlays[#self.Overlays + 1] = self.BackpackTitle
    self.Overlays[#self.Overlays + 1] = self.MoveLabel
    self:Listen(self.BackpackButton.OnClicked, function()
        self.BackpackOpen = not self.BackpackOpen
        self.SelectedBackpackSlot = nil
        if self.Snapshot then self:Show(self.Snapshot) end
    end)
    self:Listen(self.MoveButton.OnClicked, function()
        if self.SelectedBackpackSlot then self:Action('MoveToItemBar', self.SelectedBackpackSlot) end
    end)
    self.BackpackPanel.Visible = false
    self.BackpackTitle.Visible = false
    self.MoveButton.Visible = false
    self.MoveLabel.Visible = false
    for _, slot in ipairs(self.BackpackSlots) do
        slot.Button.Visible = false
        slot.Label.Visible = false
    end
end

function ScreenHandler:Listen(source, callback)
    self.Connections[#self.Connections + 1] = source:Connect(callback)
end

function ScreenHandler:Cleanup()
    self:CloseScreen()
    LocalAttackButton:Destroy()
    for _, connection in ipairs(self.Connections or {}) do connection:Disconnect() end
    for _, node in ipairs(self.Overlays or {}) do node:Destroy() end
    for _, slot in ipairs(self.Slots or {}) do slot.Background:Destroy() end
    for _, node in ipairs(self.Buttons or {}) do node:Destroy() end
    self.Connections = nil
    self.Overlays = nil
    self.Slots = nil
    self.BackpackSlots = nil
    self.BackpackButton = nil
    self.BackpackPanel = nil
    self.BackpackLabel = nil
    self.BackpackTitle = nil
    self.MoveButton = nil
    self.MoveLabel = nil
    self.SelectedBackpackSlot = nil
    self.Buttons = nil
    self.BtnBait = nil
    self.BtnNone = nil
    self.BtnEat = nil
    self.BtnDiscard = nil
    self.BtnItemAction = nil
    self.BtnReelClose = nil
    self.BtnReelCloseLabel = nil
    self.BtnBaitLabel = nil
    self.BtnNoneLabel = nil
    self.BtnEatLabel = nil
    self.BtnDiscardLabel = nil
    self.BtnItemActionLabel = nil
    self.HookHint = nil
    self.QuestLabel = nil
    self.HealthRing = nil
    self.HungerRing = nil
    self.HealthText = nil
    self.HungerText = nil
    self.FlashEdges = nil
    self.Starving = nil
    self.NextWarnAt = nil
    self.ReelBar = nil
    self.ReelBarBg = nil
    self.LabelCoin = nil
    self.Snapshot = nil
    self.CastState = nil
    self.BoundRootNode = nil
    self.Inited = false
end

local function listenPlayerAttributes(self, player)
    self:Listen(player:GetAttributeChangedSignal('FishCoin'), function() self:ShowCoin() end)
    self:ShowCoin()
    for _, key in ipairs({ 'Health', 'MaxHealth', 'Hunger', 'MaxHunger' }) do
        self:Listen(player:GetAttributeChangedSignal(key), function() self:ShowVitals() end)
    end
    self:ShowVitals()
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
    self.LabelCoin = root:FindFirstChild('LabelCoin', true)
    local imageCoin = root:FindFirstChild('ImageCoin', true)
    if self.LabelCoin then self.LabelCoin.Visible = true else print('[ScreenMain] 找不到 LabelCoin 节点') end
    if imageCoin then imageCoin.Visible = true end
    self.Slots = {}
    self.Buttons = {}
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
    self:BuildBackpack(root, resolution)
    self.BtnBait = button(root, 'BaitWorm', firstX + 80, 540, 170)
    self.BtnNone = button(root, 'BaitNone', firstX + 270, 540, 170)
    self.BtnEat = button(root, 'BaitEat', firstX + 460, 540, 170)
    self.BtnDiscard = button(root, 'ItemDiscard', firstX + 650, 540, 170)
    self.BtnItemAction = button(root, 'ItemAction2', resolution.x - 220, 690, 180)
    self.BtnReelClose = button(root, 'ReelClose', resolution.x - 220, 570, 180)
    for _, node in ipairs({ self.BtnBait, self.BtnNone, self.BtnEat, self.BtnDiscard, self.BtnItemAction, self.BtnReelClose }) do
        self.Buttons[#self.Buttons + 1] = node
    end
    local labels = {
        { 'BtnReelCloseLabel', self.BtnReelClose, '结束收线' },
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
    self.HookHint = overlay(root, 'HookHint', resolution.x - 320, 800, 400, 80,
        '', 32, Color.New(255, 220, 40, 255))
    self.HookHint.Visible = false
    self.Overlays[#self.Overlays + 1] = self.HookHint
    -- [未查证：任务条位置与 LabelCoin / 血球饥饿球（#53）是否重叠，待 #55 截图迭代]
    self.QuestLabel = overlay(root, 'QuestLabel', 500, resolution.y - 330, 900, 56,
        '', 30, Color.New(255, 255, 255, 255))
    self.QuestLabel.Visible = false
    self.Overlays[#self.Overlays + 1] = self.QuestLabel
    self:BuildVitals(root, resolution)
    self.ReelBarBg = World:CreateUnit('EUIImage', {
        Parent = root, Name = 'ReelProgressBg',
        Position = Vector2.New(resolution.x - 600, 860), Size = Vector2.New(400, 36),
        Image = 'official://image/30008',
    })
    self.ReelBar = World:CreateUnit('EUILoadingBar', {
        Parent = root, Name = 'ReelProgress',
        Position = Vector2.New(resolution.x - 600, 860), Size = Vector2.New(400, 36),
        Image = 'official://image/30007', Direction = 0, Percent = 50,
        Color = Color.New(36, 200, 94, 255),
    })
    for _, node in ipairs({ self.ReelBarBg, self.ReelBar }) do
        node.TouchEnabled = false
        node.SwallowTouchEnabled = false
        node.Visible = false
        self.Overlays[#self.Overlays + 1] = node
    end
    self.BtnItemAction.TouchEnabled = false
    self.BtnItemAction.Visible = false
    self.BtnItemActionLabel.Visible = false
    self.BtnReelClose.Visible = false
    self.BtnReelCloseLabel.Visible = false
    self:Listen(self.BtnReelClose.OnClicked, function()
        _G.LocalReelIn:Close()
        self:ShowCast()
    end)
    self.BtnDiscard.Visible = false
    self.BtnDiscardLabel.Visible = false
    self:Listen(self.BtnItemAction.OnClicked, function()
        if not self.IsOpen then return end
        local phase = self.CastState and self.CastState.phase or 'idle'
        if phase == 'hooked' and self.IsOpen
            and _G.LocalReelIn.SessionId == self.CastState.reelSession then
            _G.LocalReelIn:Click()
            self:ShowCast()
        elseif phase == 'cast' then
            _G.REUtil:GetRE('CastAction'):FireServer({ action = 'Reel' })
        elseif phase == 'idle' and self.CastState and self.CastState.holding then
            _G.REUtil:GetRE('CastAction'):FireServer({ action = 'Drop' })
        elseif phase == 'idle' and self.Snapshot then
            local slot = self.Snapshot.selectedSlot
            local entry = slot and self.Snapshot.slots[slot]
            if entry and entry.itemId == GameCfg.Items.Id.StarterRod then
                _G.REUtil:GetRE('CastAction'):FireServer({
                    action = 'Cast', slot = slot, itemId = entry.itemId,
                })
            end
        end
    end)
    self:Listen(self.BtnBait.OnClicked, function() self:Action('SelectBait', GameCfg.Items.Id.Worm) end)
    self:Listen(self.BtnNone.OnClicked, function() self:Action('SelectBait') end)
    self:Listen(self.BtnEat.OnClicked, function()
        local _, slot = self:SelectedFood()
        if slot then self:Action('EatSlot', slot) else self:Action('EatBait', GameCfg.Items.Id.Worm) end
    end)
    self:Listen(self.BtnDiscard.OnClicked, function()
        if self.Snapshot and self.Snapshot.selectedSlot then
            self:Action('DiscardSlot', self.Snapshot.selectedSlot)
        end
    end)
    self:Listen(_G.REUtil:GetRE('ItemBarState').OnClientEvent, function(state) self:Show(state) end)
    self:Listen(_G.REUtil:GetRE('CastState').OnClientEvent, function(state)
        if type(state) ~= 'table'
            or (state.phase ~= 'idle' and state.phase ~= 'cast'
                and state.phase ~= 'hooked' and state.phase ~= 'landed') then return end
        if not self.IsOpen then
            if state.phase == 'hooked' then _G.LocalReelIn:Close(state.reelSession) end
            return
        end
        if state.phase == 'hooked' then
            _G.LocalReelIn:SetSession(state.reelSession)
            self:StartHookAlert(state.reelSession)
        else
            _G.LocalReelIn:Clear(self.CastState and self.CastState.reelSession)
        end
        self.CastState = state
        self:ShowCast()
    end)
    self:Listen(_G.REUtil:GetRE('QuestState').OnClientEvent, function(state) self:ShowQuest(state) end)
    -- 开场对话降级的单行公告（#54，server/Mgr/MgrStory.lua）
    self:Listen(_G.REUtil:GetRE('StoryNotice').OnClientEvent, function(payload)
        if type(payload) == 'table' and type(payload.text) == 'string' and _G.LocalMsgNotice then
            _G.LocalMsgNotice(payload.text)
        end
    end)
    self:Listen(_G.REUtil:GetRE('ReelInRE').OnClientEvent, function()
        self:ShowCast()
    end)
    -- 追平要 150–200ms 内连续变化，服务端 100ms 一报不够平滑，收线中逐帧刷新进度条
    local runService = game:GetService('RunService')
    if runService and runService.Heartbeat then
        self:Listen(runService.Heartbeat, function()
            if self.ReelBar and self.ReelBar.Visible then self:ShowCast() end
            if self.Starving then self:UpdateStarveFx() end
        end)
    end
    -- 进图早期注册 FishCoin 属性监听不稳定，延迟后再挂
    local task = game:GetService('Task')
    if task and task.Delay then
        task:Delay(1, function()
            if not self.Inited or self.BoundRootNode ~= root then return end
            local player = game:GetService('Players').LocalPlayer
            if not player then return end
            listenPlayerAttributes(self, player)
        end)
    end
    LocalAttackButton:Start(root, resolution)
    self.BoundRootNode = root
    self.Inited = true
    self.IsOpen = false
    if _G.LocalReelIn then _G.LocalReelIn:Suspend() end
end

function ScreenHandler:OpenScreen()
    self.IsOpen = true
    LocalAttackButton:SetOpen(true)
    _G.LocalReelIn:Resume()
    self:ShowCast()
    self:ShowCoin()
    self:ShowVitals()
    _G.REUtil:GetRE('RequestItemBar'):FireServer()
    _G.REUtil:GetRE('RequestCastState'):FireServer()
    _G.REUtil:GetRE('RequestQuest'):FireServer()
    -- 开场对话（#54）：服务端每名玩家本局只播一次，重开界面不重播
    _G.REUtil:GetRE('RequestStory'):FireServer()
end

function ScreenHandler:CloseScreen()
    self.IsOpen = false
    LocalAttackButton:SetOpen(false)
    if _G.LocalReelIn then
        _G.LocalReelIn:Suspend(self.CastState and self.CastState.reelSession)
    end
    self.CastState = nil
    self:ShowCast()
end

function ScreenHandler:Destroy()
    self:Cleanup()
    self.RootNode = nil
end

return ScreenHandler

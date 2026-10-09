local World = game:GetService('World')
local GameCfg = require('common.GameCfg')
local LocalAttackButton = require('client.LocalAttackButton')
local WeaponAim = require('client.WeaponAim')
local PressGesture = require('client.PressGesture')
local DamageFloat = require('client.DamageFloat')
local FishCombatLabel = require('client.FishCombatLabel')

local ScreenHandler = { UINodes = {}, UINodeMap = {} }

function ScreenHandler:Action(action, value)
    _G.REUtil:GetRE('ItemBarAction'):FireServer({ action = action, value = value })
end

-- #124 两步操作（吃/丢弃/攻击）：每次请求带单调 seq，服务端回包带 operation 身份，
-- 断线重试可凭 seq 或原 identity 续发，重复结算由服务端操作日志挡掉。
function ScreenHandler:Operate(payload)
    self.OpSeq = (self.OpSeq or 0) + 1
    payload.seq = self.OpSeq
    payload.action = 'Operate'
    _G.REUtil:GetRE('ItemBarAction'):FireServer(payload)
end

-- #124 双向拖拽：触摸起点记源格，抬起位置命中其他格发 MoveSlot；
-- 原地（点击）与拖出格区都不发请求，容器与槽位由服务端复验。
function ScreenHandler:bindDrag(btn, container, index)
    if not btn.OnTouchBegan or not btn.OnTouchEnded then return end
    self:Listen(btn.OnTouchBegan, function(touch)
        self.DragSource = { container = container, index = index,
            began = touch and touch.BeganPosition }
    end)
    self:Listen(btn.OnTouchEnded, function(touch)
        local source = self.DragSource
        self.DragSource = nil
        if not source or source.container ~= container or source.index ~= index then return end
        local ended = touch and touch.EndedPosition
        if not ended or not source.began then return end
        if math.abs(ended.x - source.began.x) < 10 and math.abs(ended.y - source.began.y) < 10 then return end
        local target = self:SlotAtPosition(ended)
        if not target or target.container == source.container and target.index == source.index then return end
        self:Action('MoveSlot', { from = source.container, index = source.index,
            target = target.container, slot = target.index })
    end)
end

function ScreenHandler:SlotAtPosition(pos)
    if type(pos) ~= 'table' or type(pos.x) ~= 'number' or type(pos.y) ~= 'number' then return nil end
    for index, p in ipairs(self.ItemBarSlotPos or {}) do
        local slot = self.Slots and self.Slots[index]
        if slot and slot.Background.Visible
            and math.abs(pos.x - p.x) <= 55 and math.abs(pos.y - p.y) <= 55 then
            return { container = GameCfg.Items.ContainerId.ItemBar, index = index }
        end
    end
    for index, p in ipairs(self.BackpackSlotPos or {}) do
        local entry = self.BackpackSlots and self.BackpackSlots[index]
        if entry and entry.Button.Visible
            and math.abs(pos.x - p.x) <= 47 and math.abs(pos.y - p.y) <= 45 then
            return { container = GameCfg.Items.ContainerId.Backpack, index = index }
        end
    end
    return nil
end

-- ===== #129 投掷（爆炸物槽位手势：点按=直接投 20 米，长按=瞄准选点） =====
-- 手势与冷却统一使用服务器时刻；SE 沙盒不提供 os
local function nowSec()
    return World.GetServerTime and World:GetServerTime() or 0
end

function ScreenHandler:SlotDefinition(index)
    local entry = self.Snapshot and self.Snapshot.slots[index]
    return entry and GameCfg.Items.Definitions[entry.itemId] or nil
end

function ScreenHandler:IsExplosiveSlot(index)
    local definition = self:SlotDefinition(index)
    return definition ~= nil and definition.Type == '爆炸物'
end

-- 槽位按压手势：OnClicked 与手势都会响应一次点按，用标志位保证只消费一次
function ScreenHandler:BindSlotGesture(btn, index)
    if not btn.OnTouchBegan or not btn.OnTouchEnded then return end
    self:Listen(btn.OnTouchBegan, function(touch)
        self.SlotPress = { index = index, gesture = PressGesture.New({
            LongPressSec = GameCfg.Ability.Throw.LongPressSec }) }
        self.SlotPress.gesture:Begin(nowSec(),
            touch and touch.BeganPosition or nil)
    end)
    self:Listen(btn.OnTouchEnded, function(touch)
        local press = self.SlotPress
        if not press or press.index ~= index then return end
        self.SlotPress = nil
        if not self:IsExplosiveSlot(index) then return end
        local result = press.gesture:End(nowSec(),
            touch and touch.EndedPosition or nil)
        if result == 'tap' then
            self.ThrowHandled = { index = index, valid = true }
            self:ThrowExplosive(index, nil) -- 直接投：朝向前方票面 20 米
        elseif result == 'long' then
            self.ThrowHandled = { index = index, valid = true }
            self:BeginAim(index)
        end
    end)
end

function ScreenHandler:ConsumeThrowClick(index)
    local handled = self.ThrowHandled
    if handled and handled.index == index and handled.valid then
        handled.valid = false
        return true
    end
    return false
end

-- 投掷消耗持久物，走 #124 同款单调 seq：服务端按 #123 协议幂等去重
function ScreenHandler:ThrowExplosive(slot, target)
    self.WeaponSeq = (self.WeaponSeq or 0) + 1
    local payload = { action = 'throw', slot = slot, seq = self.WeaponSeq }
    if type(target) == 'table' then payload.target = target end
    print('[ScreenMain] 投掷 slot=' .. tostring(slot) .. ' seq=' .. tostring(self.WeaponSeq))
    _G.REUtil:GetRE('WeaponAction'):FireServer(payload)
end

-- 长按进入瞄准：全屏拾取层，点哪里投哪里（落点服务端再钳到 20 米内）
function ScreenHandler:BeginAim(slot)
    self:EndAim()
    if not self.UIRoot or not self.EuiResolution then return end
    self.AimSlot = slot
    local resolution = self.EuiResolution
    local overlay = World:CreateUnit('EUIButton', {
        Parent = self.UIRoot, Name = 'ThrowAimOverlay',
        Position = Vector2.New(resolution.x / 2, resolution.y / 2),
        Size = Vector2.New(resolution.x, resolution.y),
    })
    if not overlay then self.AimSlot = nil return end
    overlay.ButtonText = ''
    pcall(function() overlay.ButtonNormalColor = Color.New(30, 40, 30, 40) end)
    pcall(function() overlay.ButtonPressColor = Color.New(30, 40, 30, 60) end)
    self.AimOverlay = overlay
    if _G.LocalMsgNotice then _G.LocalMsgNotice('点击屏幕选择投掷落点') end
    self:Listen(overlay.OnTouchEnded, function(touch) self:PickAim(touch) end)
end

function ScreenHandler:PickAim(touch)
    local pos = touch and touch.EndedPosition
    local slot = self.AimSlot
    self:EndAim()
    if not slot or not pos then return end
    -- [未查证：ScreenPointToRay 的 depth 语义按射线长度处理]，无命中时回退直接投掷
    local target
    local ok, ray = pcall(function()
        local camera = game:GetService('CameraService')
        return camera and camera:ScreenPointToRay(pos.x, pos.y,
            GameCfg.Ability.Throw.Range * 2)
    end)
    if ok and ray and ray.Origin and ray.Direction then
        local physics = game:GetService('PhysicsService')
        local hit = physics and physics.Raycast
            and physics:Raycast(ray.Origin, ray.Direction, nil)
        local p = hit and hit.Position
        if p then target = { x = p.x, y = p.y, z = p.z } end
    end
    self:ThrowExplosive(slot, target)
end

function ScreenHandler:EndAim()
    if self.AimOverlay then
        pcall(function() self.AimOverlay:Destroy() end)
    end
    self.AimOverlay = nil
    self.AimSlot = nil
end

function ScreenHandler:Show(state)
    if type(state) ~= 'table' or type(state.slots) ~= 'table' then return end
    self.Snapshot = state
    LocalAttackButton:SetEquipped(state) -- #129：攻击按钮语义随装备走（攻击/射击/连发/换弹）
    local capacity = state.slotCount or GameCfg.Items.ItemBarSlots
    for index, slot in ipairs(self.Slots or {}) do
        local entry = state.slots[index]
        local definition = entry and GameCfg.Items.Definitions[entry.itemId]
        slot.Background.Visible = index <= capacity
        slot.Background.TouchEnabled = index <= capacity
        slot.Icon.Visible = index <= capacity and definition ~= nil
        if definition then slot.Icon.Image = definition.Icon end
        -- #137：烤过的物品名字加前缀；CookRate 统一口径（含旧布尔档 saved.cooked==true）
        slot.Label.Text = definition
            and ((GameCfg.Items.CookRate(entry) ~= nil and GameCfg.Grill.CookedPrefix or '') .. definition.Name) or ''
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
    -- 首领饵「鸭子」（#88）：件数由服务端快照 bait 表给出，挂上后抛竿必出鳄雀鳝
    local duckId = GameCfg.Items.Id.Duck
    local duckCount = state.bait and state.bait[duckId] or 0
    self.BtnDuckLabel.Text = '鸭子 ×' .. tostring(duckCount)
    self.BtnDuck.ButtonNormalColor = state.selectedBait == duckId
        and Color.New(36, 130, 94, 255) or Color.New(54, 100, 140, 255)
    self.BtnDuck.TouchEnabled = duckCount > 0
    -- 香肠（#90）：虾池鱼饵，与蚯蚓同走 Bait 计数库存
    local sausageId = GameCfg.Items.Id.Sausage
    local sausageCount = state.bait and state.bait[sausageId] or 0
    self.BtnSausageLabel.Text = '香肠 ×' .. tostring(sausageCount)
    self.BtnSausage.ButtonNormalColor = state.selectedBait == sausageId
        and Color.New(36, 130, 94, 255) or Color.New(54, 100, 140, 255)
    self.BtnSausage.TouchEnabled = sausageCount > 0
    -- 吃（#53/#124）：选中格有食物时走 Operate 两步——首次只切手持，再点真吃；
    -- 手持确认态由服务端快照驱动，重复点击、关闭界面后状态仍合法
    local food, foodSlot = self:SelectedFood()
    local heldSlot = state.held and state.held.kind == 'slot' and state.held.slot or nil
    self.BtnEat.TouchEnabled = food ~= nil or count > 0
    if food then
        local name = GameCfg.Items.Definitions[food.itemId].Name
        self.BtnEatLabel.Text = heldSlot == foodSlot and ('吃' .. name) or ('手持' .. name)
    else
        self.BtnEatLabel.Text = count > 0 and '吃蚯蚓' or '蚯蚓用尽'
    end
    self.BtnNoneLabel.Text = '不挂鱼饵'
    self:ShowCoin(state.coin)
    self:ShowCast()
    local selected = state.selectedSlot and state.slots[state.selectedSlot]
    self.BtnDiscard.Visible = selected ~= nil
    self.BtnDiscardLabel.Visible = selected ~= nil
    self.BtnDiscardLabel.Text = selected and heldSlot == state.selectedSlot
        and '确认丢弃' or '丢弃选中物'
    self:ShowDynamicBait(state)
    self:ShowDynamicWeapons(state)
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

function ScreenHandler:ShowDialogue(payload)
    if type(payload) ~= 'table' or not self.DialogueNodes then return end
    local lines = payload.lines
    if type(lines) ~= 'table' or #lines == 0 then return end
    for _, line in ipairs(lines) do if type(line) ~= 'string' then return end end
    self.DialoguePayload, self.DialoguePage = payload, 1
    for _, node in ipairs(self.DialogueNodes) do node.Visible = true end
    self:ShowDialoguePage()
end

function ScreenHandler:ShowDialoguePage()
    local payload = self.DialoguePayload
    if not payload then return end
    self.DialogueTitle.Text = (payload.title or '钓鱼佬') .. '  ' .. self.DialoguePage .. '/' .. #payload.lines
    local wrapped, count = {}, 0
    for character in payload.lines[self.DialoguePage]:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
        wrapped[#wrapped + 1] = character
        count = character == '\n' and 0 or count + 1
        if count >= self.DialogueColumns then wrapped[#wrapped + 1], count = '\n', 0 end
    end
    self.DialogueBody.Text = table.concat(wrapped)
    self.DialogueNext.TouchEnabled = self.DialoguePage < #payload.lines
    self.DialogueRead.TouchEnabled = true
    self.DialogueReadLabel.Text = payload.readKey and '已读，开始钓鱼' or '知道了'
end

function ScreenHandler:HideDialogue()
    for _, node in ipairs(self.DialogueNodes or {}) do node.Visible = false end
    self.DialoguePayload = nil
end

-- 服务端会发的抛竿阶段（#133 增补 unhooked：脱钩后线还在水里）。白名单外的回包一律丢弃，
-- 免得迟到 / 旧回包把界面拉回一个不存在的状态。
local CAST_PHASES = { idle = true, cast = true, hooked = true, landed = true, unhooked = true }

-- 线还在水里的阶段：还没上钩的 cast，与鱼已脱钩但没收竿的 unhooked；都按「收竿」一次收回
local function lineStillOut(phase)
    return phase == 'cast' or phase == 'unhooked'
end

local function castActionEnabled(self, phase, rod, drop, active)
    return self.IsOpen == true
        and ((rod and phase == 'idle') or drop or lineStillOut(phase) or active == true) or false
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
        or phase == 'landed' and '已上岸' or lineStillOut(phase) and '收竿'
        or drop and '放下' or rod and '抛竿' or '使用'
end

-- #140 特殊道具：空闲且服务端生效效果（SpecialItemState.effect）存在时，
-- 2 号位从钓鱼语义切换为「长按飞行」（风神之翼）/「原子吐息」（哥斯拉）；
-- 冷却用本地墙钟倒计时展示（服务端每次状态推送带来权威剩余秒数）。
local function showSpecialAction(self, effect)
    self.BtnItemAction.Visible = true
    self.BtnItemActionLabel.Visible = true
    self.BtnItemAction.ButtonNormalColor = Color.New(54, 100, 140, 255)
    if effect == 'wings' then
        self.BtnItemAction.TouchEnabled = self.IsOpen == true
        self.BtnItemActionLabel.Text = '长按飞行'
    elseif effect == 'godzilla' then
        local left = self.BreathCooldownUntil and (self.BreathCooldownUntil - World:GetServerTime()) or 0
        local onCooldown = left > 0
        self.BtnItemAction.TouchEnabled = self.IsOpen == true and not onCooldown
        self.BtnItemActionLabel.Text = onCooldown
            and string.format('吐息冷却 %d秒', math.ceil(left)) or '原子吐息'
    end
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

local castFailureText = {
    invalidLanding = '落点不在可钓水域，请重新抛竿',
    noFish = '本次没有鱼上钩，请重新抛竿',
    holding = '先放下鱼再抛竿',
    invalidRod = '请重新选择鱼竿',
    cooldown = '操作太快，请稍后重试',
    baitUnavailable = '鱼饵不足，请重新挂饵',
    unavailable = '暂时无法抛竿，请稍后重试',
    alreadyCasting = '正在钓鱼，请先收竿',
    cannotAct = '现在无法行动，等恢复后再试',
}

function ScreenHandler:ShowCastFailure(result)
    local text = type(result) == 'table' and castFailureText[result.reason]
    if not text or not self.IsOpen then return end
    self.SplashUntil = nil
    self.FailureUntil = World:GetServerTime() + GameCfg.CastFeedback.SplashDurationSec
    self.CastFailureHint.Text = text
    self.FailureLanding = result.reason == 'invalidLanding' and result.landing or nil
    self:UpdateCastFeedback()
    print('[ScreenMain] 抛竿失败', result.reason, text)
end

local function waitingCast(state)
    local landing = state and state.landing
    return state and state.phase == 'cast' and state.zoneId ~= nil
        and type(state.castId) == 'number' and type(landing) == 'table'
        and type(landing.x) == 'number' and type(landing.y) == 'number'
        and type(landing.z) == 'number'
end

function ScreenHandler:UpdateCastFeedback()
    if not self.CastFloat then return end
    local now = (self.FailureUntil or self.SplashUntil) and World:GetServerTime() or 0
    local waiting = self.IsOpen and waitingCast(self.CastState)
    local failing = self.IsOpen and self.FailureUntil ~= nil and now < self.FailureUntil
    self.CastFailureHint.Visible = failing == true
    self.CastWaitHint.Visible = waiting == true and not failing
    self.CastSplashHint.Visible = waiting == true and not failing and self.SplashUntil ~= nil
        and now < self.SplashUntil
    local camera = game:GetService('CameraService')
    local function project(landing, marker)
        if type(landing) ~= 'table' or type(landing.x) ~= 'number'
            or type(landing.y) ~= 'number' or type(landing.z) ~= 'number' or not camera then return false end
        local screen, onScreen = camera:WorldToViewportPoint(Vector3.New(landing.x, landing.y, landing.z))
        if not screen or not onScreen or screen.z <= 0 then return false end
        marker.Position = Vector2.New(screen.x, self.EuiResolution.y - screen.y)
        return true
    end
    self.CastFloat.Visible = waiting == true and not failing
        and project(self.CastState.landing, self.CastFloat) or false
    self.CastFailureMark.Visible = failing == true and self.FailureLanding ~= nil
        and project(self.FailureLanding, self.CastFailureMark) or false
end

function ScreenHandler:ShowCast()
    if not self.BtnItemAction then return end
    local state = self.Snapshot
    local selected = state and state.selectedSlot and state.slots[state.selectedSlot]
    local rod = selected and GameCfg.Items.Definitions[selected.itemId]
        and type(GameCfg.Items.Definitions[selected.itemId].Level) == 'number'
    local phase = self.CastState and self.CastState.phase or 'idle'
    local reel = _G.LocalReelIn
    local active = self.IsOpen and phase == 'hooked' and reel
        and reel.SessionId == self.CastState.reelSession
    -- 头上顶着鱼（#41，以服务端 holding 为准）：空闲时 2 号位是「放下」
    local drop = phase == 'idle' and self.CastState ~= nil and self.CastState.holding ~= nil
    -- 上钩提示（#54）：本收线会话的前 DurationSec 秒按钮呼吸式高亮、文字改为提示语
    local now = active == true and self.HookAlertUntil ~= nil and World:GetServerTime()
    local alerting = now and now < self.HookAlertUntil
    -- #140：空闲且特殊道具生效时按钮让给飞行 / 吐息；钓鱼各阶段保持钓鱼语义
    if phase == 'idle' and not drop and self.SpecialEffect then
        showSpecialAction(self, self.SpecialEffect)
    else
        showCastAction(self, phase, rod, drop, active, alerting and now)
    end
    local progress = castProgress(self, reel, active)
    if type(progress) ~= 'number' or progress ~= progress then progress = 50 end
    progress = math.max(0, math.min(100, progress))
    showCastFeedback(self, phase, active, alerting, progress)
    self:UpdateCastFeedback()
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


-- #124 动态鱼饵：硬编码三键之外的鱼饵按快照生成按钮（策划「弹窗列出背包现有鱼饵」的最小形态），
-- 数量为 0 或快照消失即隐藏。位置与 HookHint 同排，待 #55 截图迭代整体布局。
function ScreenHandler:ShowDynamicBait(state)
    self.BaitDyn = self.BaitDyn or {}
    for _, entry in pairs(self.BaitDyn) do
        entry.Button.Visible = false
        entry.Label.Visible = false
    end
    if type(state.bait) ~= 'table' or not self.UIRoot then return end
    local fixed = { [GameCfg.Items.Id.Worm] = true, [GameCfg.Items.Id.Duck] = true,
        [GameCfg.Items.Id.Sausage] = true }
    local order = {}
    for id, count in pairs(state.bait) do
        if not fixed[id] and type(count) == 'number' and count > 0 then order[#order + 1] = id end
    end
    table.sort(order)
    for i, id in ipairs(order) do
        local entry = self.BaitDyn[id]
        if not entry then
            local x = 120 + (i - 1) * 180
            local btn = button(self.UIRoot, 'BaitDyn_' .. id, x, 800, 170)
            local label = overlay(self.UIRoot, 'BaitDynLabel_' .. id, x, 800, 170, 70,
                '', 24, Color.New(255, 255, 255, 255))
            self.Buttons[#self.Buttons + 1] = btn
            self.Overlays[#self.Overlays + 1] = label
            self:Listen(btn.OnClicked, function() self:Action('SelectBait', id) end)
            entry = { Button = btn, Label = label }
            self.BaitDyn[id] = entry
        end
        local definition = GameCfg.Items.Definitions[id]
        entry.Label.Text = (definition and definition.Name or id) .. ' ×' .. tostring(state.bait[id])
        entry.Button.Visible = true
        entry.Label.Visible = true
    end
end

-- #124 武器独立库存：快照驱动的武器按钮（武器不占普通格），点击走 Operate 两步——
-- 首次切手持，再次由 #129 客户端回包转成 WeaponAction 攻击（结算在 MgrWeapon，服务端权威）。
function ScreenHandler:ShowDynamicWeapons(state)
    self.WeaponBtns = self.WeaponBtns or {}
    for _, entry in pairs(self.WeaponBtns) do
        entry.Button.Visible = false
        entry.Label.Visible = false
    end
    if type(state.weapons) ~= 'table' or not self.UIRoot then return end
    local order = {}
    for id, count in pairs(state.weapons) do
        if type(count) == 'number' and count > 0 then order[#order + 1] = id end
    end
    table.sort(order)
    for i, id in ipairs(order) do
        local entry = self.WeaponBtns[id]
        if not entry then
            local x = 120 + (i - 1) * 180
            local btn = button(self.UIRoot, 'WeaponItem_' .. id, x, 910, 170)
            local label = overlay(self.UIRoot, 'WeaponItemLabel_' .. id, x, 910, 170, 70,
                '', 24, Color.New(255, 255, 255, 255))
            self.Buttons[#self.Buttons + 1] = btn
            self.Overlays[#self.Overlays + 1] = label
            self:Listen(btn.OnClicked, function() self:Operate({ op = 'attack', weapon = id }) end)
            entry = { Button = btn, Label = label }
            self.WeaponBtns[id] = entry
        end
        local definition = GameCfg.Items.Definitions[id]
        entry.Label.Text = (definition and definition.Name or id) .. ' ×' .. tostring(state.weapons[id])
        entry.Button.Visible = true
        entry.Label.Visible = true
    end
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
        -- #137：烤过的物品名字加前缀；CookRate 统一口径（含旧布尔档 saved.cooked==true）
        slot.Label.Text = definition
            and ((GameCfg.Items.CookRate(entry) ~= nil and GameCfg.Grill.CookedPrefix or '') .. definition.Name) or '空'
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
    self.BackpackSlotPos = {}
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
        self.BackpackSlotPos[index] = { x = x, y = y }
        self:bindDrag(btn, GameCfg.Items.ContainerId.Backpack, index)
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
    DamageFloat:Clear()
    FishCombatLabel:Clear()
    self:CloseScreen()
    LocalAttackButton:Destroy()
    for _, connection in ipairs(self.Connections or {}) do connection:Disconnect() end
    for _, node in ipairs(self.Overlays or {}) do node:Destroy() end
    for _, slot in ipairs(self.Slots or {}) do slot.Background:Destroy() end
    for _, node in ipairs(self.Buttons or {}) do node:Destroy() end
    self.Connections = nil
    self.Overlays = nil
    self.Slots = nil
    self.ItemBarSlotPos = nil
    self.BackpackSlots = nil
    self.BackpackSlotPos = nil
    self.BaitDyn = nil
    self.WeaponBtns = nil
    self.DragSource = nil
    self.OpSeq = nil
    self.UIRoot = nil
    self.LastOperateOperation = nil
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
    self.BtnDuck = nil
    self.BtnSausage = nil
    self.BtnItemAction = nil
    self.BtnReelClose = nil
    self.BtnReelCloseLabel = nil
    self.BtnBaitLabel = nil
    self.BtnNoneLabel = nil
    self.BtnEatLabel = nil
    self.BtnDiscardLabel = nil
    self.BtnDuckLabel = nil
    self.BtnSausageLabel = nil
    self.BtnItemActionLabel = nil
    self.HookHint = nil
    self.CastFloat = nil
    self.CastFailureMark = nil
    self.CastFailureHint = nil
    self.EuiResolution = nil
    self.CastWaitHint = nil
    self.CastSplashHint = nil
    self.SplashUntil = nil
    self.AlertedCastId = nil
    self.QuestLabel = nil
    self.DialogueNodes = nil
    self.DialoguePayload = nil
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
    self.EuiResolution = resolution
    local root = self.RootNode
    DamageFloat:Bind(root, resolution)
    FishCombatLabel:Bind(root, resolution)
    self.LabelCoin = root:FindFirstChild('LabelCoin', true)
    local imageCoin = root:FindFirstChild('ImageCoin', true)
    if self.LabelCoin then self.LabelCoin.Visible = true else print('[ScreenMain] 找不到 LabelCoin 节点') end
    if imageCoin then imageCoin.Visible = true end
    self.Slots = {}
    self.ItemBarSlotPos = {}
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
        self.ItemBarSlotPos[index] = { x = x, y = y }
        self:bindDrag(background, GameCfg.Items.ContainerId.ItemBar, index)
        self:BindSlotGesture(background, index)
        self:Listen(background.OnClicked, function()
            if self:ConsumeThrowClick(index) then return end -- 爆炸物已由手势消费本次点击
            self:Action('SelectSlot', index)
        end)
    end
    self.UIRoot = root
    self:BuildBackpack(root, resolution)
    self.BtnBait = button(root, 'BaitWorm', firstX + 80, 540, 170)
    self.BtnNone = button(root, 'BaitNone', firstX + 270, 540, 170)
    self.BtnEat = button(root, 'BaitEat', firstX + 460, 540, 170)
    self.BtnDiscard = button(root, 'ItemDiscard', firstX + 650, 540, 170)
    -- 首领饵挂饵键（#88）：蚯蚓键正上方，数量为零时不可点
    self.BtnDuck = button(root, 'BaitDuck', firstX + 80, 650, 170)
    -- 香肠挂饵键（#90）：鸭子键右侧，虾池鱼饵
    self.BtnSausage = button(root, 'BaitSausage', firstX + 270, 650, 170)
    self.BtnItemAction = button(root, 'ItemAction2', resolution.x - 220, 690, 180)
    self.BtnReelClose = button(root, 'ReelClose', resolution.x - 220, 570, 180)
    for _, node in ipairs({ self.BtnBait, self.BtnNone, self.BtnEat, self.BtnDiscard, self.BtnDuck, self.BtnSausage, self.BtnItemAction, self.BtnReelClose }) do
        self.Buttons[#self.Buttons + 1] = node
    end
    local labels = {
        { 'BtnReelCloseLabel', self.BtnReelClose, '结束收线' },
        { 'BtnBaitLabel', self.BtnBait, '蚯蚓' },
        { 'BtnNoneLabel', self.BtnNone, '不挂鱼饵' },
        { 'BtnEatLabel', self.BtnEat, '吃蚯蚓' },
        { 'BtnDiscardLabel', self.BtnDiscard, '丢弃选中物' },
        { 'BtnDuckLabel', self.BtnDuck, '鸭子' },
        { 'BtnSausageLabel', self.BtnSausage, '香肠' },
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
    local feedback = GameCfg.CastFeedback
    self.CastFloat = overlay(root, 'CastFloat', 0, 0, feedback.FloatSize, feedback.FloatSize,
        '●', 48, color(feedback.FloatColor))
    self.CastWaitHint = overlay(root, 'CastWaitHint', resolution.x - 320, 800, 400, 80,
        '等待上钩…', 32, Color.New(255, 255, 255, 255))
    self.CastSplashHint = overlay(root, 'CastSplashHint', resolution.x / 2, resolution.y - 430, 520, 72,
        '已入水，等待上钩', 32, Color.New(255, 225, 70, 255))
    self.CastFailureHint = overlay(root, 'CastFailureHint', resolution.x / 2, resolution.y - 430, 740, 72,
        '', 32, Color.New(255, 90, 90, 255))
    self.CastFailureMark = overlay(root, 'CastFailureMark', 0, 0, feedback.FloatSize, feedback.FloatSize,
        '●', 48, Color.New(255, 65, 65, 255))
    for _, node in ipairs({ self.CastFloat, self.CastWaitHint, self.CastSplashHint,
        self.CastFailureHint, self.CastFailureMark }) do
        node.Visible = false
        self.Overlays[#self.Overlays + 1] = node
    end
    -- [未查证：任务条位置与 LabelCoin / 血球饥饿球（#53）是否重叠，待 #55 截图迭代]
    self.QuestLabel = overlay(root, 'QuestLabel', 500, resolution.y - 330, 900, 56,
        '', 30, Color.New(255, 255, 255, 255))
    self.QuestLabel.Visible = false
    self.Overlays[#self.Overlays + 1] = self.QuestLabel
    local cx, cy = resolution.x / 2, resolution.y / 2
    local width = math.min(1000, resolution.x - 60)
    self.DialogueColumns = math.max(12, math.floor((width - 80) / 26))
    local panel = World:CreateUnit('EUIImage', {
        Parent = root, Name = 'DialogueBackground', Position = Vector2.New(cx, cy),
        Size = Vector2.New(width, 360), Image = 'official://image/11017',
        Color = Color.New(22, 38, 54, 250),
    })
    panel.TouchEnabled, panel.SwallowTouchEnabled, panel.LocalZOrder = true, true, 20
    self.DialogueTitle = overlay(root, 'DialogueTitle', cx, cy - 120, width - 50, 50,
        '', 30, Color.New(255, 225, 130, 255))
    self.DialogueBody = overlay(root, 'DialogueBody', cx, cy - 10, width - 80, 130,
        '', 26, Color.New(255, 255, 255, 255))
    self.DialogueNext = button(root, 'DialogueNext', cx - 160, cy + 115, 260)
    self.DialogueRead = button(root, 'DialogueRead', cx + 160, cy + 115, 300)
    local nextLabel = overlay(root, 'DialogueNextLabel', cx - 160, cy + 115, 260, 80,
        '下一段', 26, Color.New(255, 255, 255, 255))
    self.DialogueReadLabel = overlay(root, 'DialogueReadLabel', cx + 160, cy + 115, 300, 80,
        '已读，开始钓鱼', 26, Color.New(255, 255, 255, 255))
    self.DialogueNodes = { panel, self.DialogueTitle, self.DialogueBody,
        self.DialogueNext, self.DialogueRead, nextLabel, self.DialogueReadLabel }
    for _, node in ipairs(self.DialogueNodes) do
        if node ~= panel then node.LocalZOrder = 21 end
        if node == nextLabel or node == self.DialogueReadLabel then node.LocalZOrder = 22 end
        node.Visible = false
        self.Overlays[#self.Overlays + 1] = node
    end
    self:Listen(self.DialogueNext.OnClicked, function()
        if not self.DialoguePayload or self.DialoguePage >= #self.DialoguePayload.lines then return end
        self.DialoguePage = self.DialoguePage + 1
        self:ShowDialoguePage()
    end)
    self:Listen(self.DialogueRead.OnClicked, function()
        local payload = self.DialoguePayload
        if not payload then return end
        if not payload.readKey then return self:HideDialogue() end
        self.DialogueReadLabel.Text = '保存已读中…'
        self.DialogueRead.TouchEnabled = false
        _G.REUtil:GetRE('StoryRead'):FireServer({ action = 'read', readKey = payload.readKey })
    end)
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
        -- #140：特殊道具生效且空闲时，点击 = 原子吐息（风神之翼走长按，点击不做事）
        if phase == 'idle' and self.SpecialEffect then
            if self.SpecialEffect == 'godzilla'
                and not (self.BreathCooldownUntil and self.BreathCooldownUntil > World:GetServerTime()) then
                _G.REUtil:GetRE('SpecialItemAction'):FireServer({ action = 'breath' })
            end
            return
        end
        if phase == 'hooked' and self.IsOpen
            and _G.LocalReelIn.SessionId == self.CastState.reelSession then
            _G.LocalReelIn:Click()
            self:ShowCast()
        elseif lineStillOut(phase) then
            _G.REUtil:GetRE('CastAction'):FireServer({ action = 'Reel' })
        elseif phase == 'idle' and self.CastState and self.CastState.holding then
            _G.REUtil:GetRE('CastAction'):FireServer({ action = 'Drop' })
        elseif phase == 'idle' and self.Snapshot then
            local slot = self.Snapshot.selectedSlot
            local entry = slot and self.Snapshot.slots[slot]
            if entry and GameCfg.Items.Definitions[entry.itemId]
                and type(GameCfg.Items.Definitions[entry.itemId].Level) == 'number' then
                _G.REUtil:GetRE('CastAction'):FireServer({
                    action = 'Cast', slot = slot, itemId = entry.itemId,
                })
            else
                self.FailureUntil = nil
                self.FailureLanding = nil
                self:ShowCast()
                self:ShowCastFailure({ reason = 'invalidRod' })
            end
        end
    end)
    self:Listen(self.BtnBait.OnClicked, function() self:Action('SelectBait', GameCfg.Items.Id.Worm) end)
    -- #140 风神之翼：长按升空、松开缓降（按下 / 松开成对发送，服务端以调和为准）
    if self.BtnItemAction.OnTouchBegan and self.BtnItemAction.OnTouchEnded then
        self:Listen(self.BtnItemAction.OnTouchBegan, function()
            if self.IsOpen and self.SpecialEffect == 'wings'
                and (not self.CastState or self.CastState.phase == 'idle') then
                _G.REUtil:GetRE('SpecialItemAction'):FireServer({ action = 'fly', holding = true })
            end
        end)
        self:Listen(self.BtnItemAction.OnTouchEnded, function()
            if self.SpecialEffect == 'wings' then
                _G.REUtil:GetRE('SpecialItemAction'):FireServer({ action = 'fly', holding = false })
            end
        end)
    end
    self:Listen(self.BtnDuck.OnClicked, function() self:Action('SelectBait', GameCfg.Items.Id.Duck) end)
    self:Listen(self.BtnSausage.OnClicked, function() self:Action('SelectBait', GameCfg.Items.Id.Sausage) end)
    self:Listen(self.BtnNone.OnClicked, function() self:Action('SelectBait') end)
    self:Listen(self.BtnEat.OnClicked, function()
        local _, slot = self:SelectedFood()
        if slot then
            self:Operate({ op = 'eat', slot = slot })
        else
            self:Action('EatBait', GameCfg.Items.Id.Worm)
        end
    end)
    self:Listen(self.BtnDiscard.OnClicked, function()
        if self.Snapshot and self.Snapshot.selectedSlot then
            self:Operate({ op = 'discard', slot = self.Snapshot.selectedSlot })
        end
    end)
    self:Listen(_G.REUtil:GetRE('ItemBarState').OnClientEvent, function(state) self:Show(state) end)
    -- #140 特殊道具状态：按钮语义随服务端生效效果切换；冷却按权威剩余秒数起本地倒计时
    self:Listen(_G.REUtil:GetRE('SpecialItemState').OnClientEvent, function(state)
        if type(state) ~= 'table' then return end
        self.SpecialEffect = state.effect
        if type(state.breathRemaining) == 'number' and state.breathRemaining > 0 then
            self.BreathCooldownUntil = World:GetServerTime() + state.breathRemaining
        else
            self.BreathCooldownUntil = nil
        end
        if self.BtnItemAction then self:ShowCast() end
    end)
    _G.REUtil:GetRE('SpecialItemStateRequest'):FireServer() -- 安装状态监听后补取可能丢失的首包
    -- #140 特殊道具回包：冷却 / 未变身 / 未装备翅膀等失败给具体提示
    self:Listen(_G.REUtil:GetRE('SpecialItemResult').OnClientEvent, function(result)
        if type(result) ~= 'table' or result.ok ~= false then return end
        local hints = { cooldown = '原子吐息冷却中', ['not-godzilla'] = '需要选中哥斯拉变身',
            ['not-wings'] = '需要选中风神之翼', ['not-alive'] = '现在不能行动',
            ['no-character'] = '角色未就绪' }
        if _G.LocalMsgNotice then
            _G.LocalMsgNotice(hints[result.reason] or ('操作失败 ' .. tostring(result.reason)))
        end
    end)
    -- #124 操作回包：失败给具体提示；operation 身份随回包带回，凭它可跨重连重试
    self:Listen(_G.REUtil:GetRE('ItemBarResult').OnClientEvent, function(result)
        if type(result) ~= 'table' or result.ok ~= false then return end
        self.LastOperateOperation = result.operation or self.LastOperateOperation
        -- #129：武器已手持时再点武器列表=出击（结算在 MgrWeapon，伤害以服务端为准）
        if result.reason == 'combat-pending' then
            _G.REUtil:GetRE('WeaponAction'):FireServer(WeaponAim:AttackPayload())
            return
        end
        local hints = { empty = '物品已不在格子里', ['cannot-eat'] = '现在不能吃',
            ['drop-unavailable'] = '丢弃通道未就绪（地面物品）', ['drop-rejected'] = '这里丢不下',
            ['potion-capped'] = '这类药水已到上限', ['combat-pending'] = '战斗结算未接入（#128）',
            ['bad-weapon'] = '没有这件武器', ['bad-slot'] = '格子不存在', ['unknown-op'] = '未知操作' }
        if _G.LocalMsgNotice then
            _G.LocalMsgNotice(hints[result.reason] or ('操作失败 ' .. tostring(result.reason)))
        end
    end)
    -- #129 武器结算回包：换弹/空匣/冷却/投掷校验失败给具体提示
    self:Listen(_G.REUtil:GetRE('WeaponResult').OnClientEvent, function(result)
        if type(result) ~= 'table' or result.ok ~= false then return end
        local hints = { ['cannot-act'] = '现在不能攻击', unavailable = '武器未就绪',
            cooldown = '出手太快', reloading = '换弹中', empty = '弹匣已空，自动换弹',
            ['not-a-gun'] = '手持的不是枪械', ['mag-full'] = '弹匣是满的',
            ['bad-slot'] = '格子不存在', ['bad-throwable'] = '这个不能投掷',
            ['bad-target'] = '落点无效', ['bad-weapon'] = '武器未配置' }
        if _G.LocalMsgNotice then
            _G.LocalMsgNotice(hints[result.reason] or ('武器操作失败 ' .. tostring(result.reason)))
        end
    end)
    self:Listen(_G.REUtil:GetRE('CastState').OnClientEvent, function(state)
        if type(state) ~= 'table' then return end
        if state.result then
            if state.castId and self.AlertedCastId and state.castId < self.AlertedCastId then return end
            if state.phase == 'idle' and not state.castId and waitingCast(self.CastState) then return end
            if state.phase == 'idle' and state.castId
                and self.CastState and self.CastState.castId == state.castId then
                self.SplashUntil = nil
                _G.LocalReelIn:Clear(self.CastState and self.CastState.reelSession)
                self.CastState = state
                self:ShowCast()
            end
            self:ShowCastFailure(state.result)
            return
        end
        if not CAST_PHASES[state.phase] then return end
        -- #133：界面被别的界面盖住只是表现问题——收线继续由服务端权威推进，回流后照旧显示，
        -- 所以这里不再因为「界面没开」就去取消收线会话。
        if not self.IsOpen then return end
        if waitingCast(state) then
            if self.AlertedCastId and state.castId < self.AlertedCastId then return end
            self.FailureUntil = nil
            self.FailureLanding = nil
            if self.AlertedCastId ~= state.castId then
                self.AlertedCastId = state.castId
                self.SplashUntil = nil
                if not state.snapshot then
                    self.SplashUntil = World:GetServerTime() + GameCfg.CastFeedback.SplashDurationSec
                    print('[ScreenMain] 已入水，等待上钩', state.castId, state.zoneId)
                end
            end
        else
            self.SplashUntil = nil
            if not state.snapshot or state.phase ~= 'idle' then
                self.FailureUntil = nil
                self.FailureLanding = nil
            end
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
    self:Listen(_G.REUtil:GetRE('DamageNotice').OnClientEvent, function(payload)
        if self.IsOpen then DamageFloat:Show(payload) end
    end)
    self:Listen(_G.REUtil:GetRE('FishCombatState').OnClientEvent, function(payload)
        if self.IsOpen then FishCombatLabel:Apply(payload) end
    end)
    self:Listen(_G.REUtil:GetRE('QuestState').OnClientEvent, function(state) self:ShowQuest(state) end)
    -- 未交付正式 Story 资源时保留阅读界面，由玩家明确确认已读。
    self:Listen(_G.REUtil:GetRE('StoryNotice').OnClientEvent, function(payload)
        self:ShowDialogue(payload)
    end)
    self:Listen(_G.REUtil:GetRE('StoryState').OnClientEvent, function(payload)
        if type(payload) == 'table' and payload.read == true and self.DialoguePayload
            and payload.readKey == self.DialoguePayload.readKey then
            self:HideDialogue()
        elseif type(payload) == 'table' and payload.read == false and self.DialoguePayload
            and payload.readKey == self.DialoguePayload.readKey then
            self.DialogueBody.Text = payload.text or '已读尚未保存'
            self.DialogueReadLabel.Text = '稍后重进再试'
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
            -- #140：吐息冷却中逐帧刷新倒计时文案
            if self.BreathCooldownUntil and self.SpecialEffect == 'godzilla' then
                if self.BreathCooldownUntil > World:GetServerTime() then
                    self:ShowCast()
                else
                    self.BreathCooldownUntil = nil
                    self:ShowCast()
                end
            end
            if self.CastFloat and self.IsOpen then self:UpdateCastFeedback() end
            if self.Starving then self:UpdateStarveFx() end
            DamageFloat:Update()
            FishCombatLabel:Update()
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
    DamageFloat:Bind(self.RootNode, self.EuiResolution)
    FishCombatLabel:Bind(self.RootNode, self.EuiResolution)
    self.IsOpen = true
    LocalAttackButton:SetOpen(true)
    -- #133 重开界面不需要通知收线客户端：会话与进度一直在，界面只是重新显示
    self:ShowCast()
    self:ShowCoin()
    self:ShowVitals()
    _G.REUtil:GetRE('SpecialItemStateRequest'):FireServer()
    _G.REUtil:GetRE('RequestItemBar'):FireServer()
    _G.REUtil:GetRE('RequestCastState'):FireServer()
    _G.REUtil:GetRE('RequestQuest'):FireServer()
    _G.REUtil:GetRE('RequestFishCombat'):FireServer()
    -- 重开可能落在服务端快照限频窗内；延后补取，并让旧界面的请求失效。
    local combatRequest = {}
    self.CombatRequest = combatRequest
    local task = game:GetService('Task')
    if task and task.Delay then
        task:Delay(0.6, function()
            if self.IsOpen and self.CombatRequest == combatRequest then
                _G.REUtil:GetRE('RequestFishCombat'):FireServer()
            end
        end)
    end
    -- 开场对话（#54）：服务端每名玩家本局只播一次，重开界面不重播
    _G.REUtil:GetRE('RequestStory'):FireServer()
end

function ScreenHandler:CloseScreen()
    self:HideDialogue()
    self.CombatRequest = nil
    DamageFloat:Clear()
    FishCombatLabel:Clear()
    self.IsOpen = false
    self.FailureUntil = nil
    self.FailureLanding = nil
    self:EndAim()
    LocalAttackButton:SetOpen(false)
    -- #133 遮挡只影响表现：不主动收线，待发点击先 flush，会话与进度留给重开时接着显示
    if _G.LocalReelIn then _G.LocalReelIn:Suspend() end
    self.CastState = nil
    self.SplashUntil = nil
    self:ShowCast()
end

function ScreenHandler:Destroy()
    self:Cleanup()
    self.RootNode = nil
end

return ScreenHandler

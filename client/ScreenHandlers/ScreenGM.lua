-- 仅调试地图显示的 GM 面板；按钮只发送固定参数，余额与结果以服务端同步为准。
local GameCfg = require('common.GameCfg')
local GameUI = require('client.GameUI')
local REUtil = require('common.REUtil')

local Panel = { Connections = {}, Nodes = {} }

-- 官方正方形纯色块（120×120），配合 Color 叠色成任意底色；不设 Image 时 EUIImage/EUIButton
-- 会渲染默认椭圆贴图，被深色染色后成为遮挡面板的黑色异形块（本面板曾因此不可读）。
local ColorBlockImage = 'official://image/11017'

local FishPageSize = 6
local FishIds = { 'eel', 'alligatorGar' }
local OtherFishIds = {}
for fishId in pairs(GameCfg.Fish) do
    if fishId ~= 'eel' and fishId ~= 'alligatorGar' then OtherFishIds[#OtherFishIds + 1] = fishId end
end
table.sort(OtherFishIds)
for _, fishId in ipairs(OtherFishIds) do FishIds[#FishIds + 1] = fishId end

local FishActions = {}
for index = 1, FishPageSize do FishActions[index] = { fishSlot = index, label = '' } end
FishActions[7] = { fishPage = -1, label = '上一页' }
FishActions[8] = { fishPage = 1, label = '下一页' }

local Groups = {
    { title = '金币', actions = {
        { label = '+100 金币', payload = { action = 'Coin', amount = 100 } },
        { label = '+6300 金币', payload = { action = 'Coin', amount = 6300 } },
    } },
    { title = '物品', actions = {
        { label = '罗非鱼 ×1', payload = { action = 'Item', itemId = GameCfg.Items.Id.Tilapia, count = 1 } },
        { label = '罗非鱼 ×5', payload = { action = 'Item', itemId = GameCfg.Items.Id.Tilapia, count = 5 } },
    } },
    { title = '战斗', actions = {
        { label = '挥砍伤害 +25', payload = { action = 'AddAttack' } },
    } },
    { title = '下一条鱼', actions = FishActions },
    { title = '状态与存档', actions = {
        { label = '打开状态配置', statePage = true },
    } },
}

local function listen(self, signal, callback)
    self.Connections[#self.Connections + 1] = signal:Connect(callback)
end

-- 所有节点都挂 root、用屏幕绝对坐标（与 ScreenMain 一致）；EUIImage 子节点的坐标系
-- 不是相对父中心，嵌套会错位，且 EUIButton 的 ButtonText 在自定义贴图下不渲染。
local function create(self, kind, parent, name, x, y, width, height, props)
    props = props or {}
    props.Parent = parent
    props.Name = name
    local scale = self.Scale or 1
    props.Position = Vector2.New(x, y)
    props.Size = Vector2.New(width * scale, height * scale)
    if props.FontSize then props.FontSize = math.max(12, math.floor(props.FontSize * scale)) end
    local node = game:GetService('World'):CreateUnit(kind, props)
    if not node then error('GM 界面节点创建失败：' .. name) end
    self.Nodes[#self.Nodes + 1] = node
    return node
end

local function label(self, parent, name, text, x, y, width, height, fontSize)
    local node = create(self, 'EUITextLabel', parent, name, x, y, width, height, {
        Text = text, FontSize = fontSize, TextColor = Color.New(255, 255, 255, 255),
    })
    node.TouchEnabled = false
    node.SwallowTouchEnabled = false
    -- 盖在背景与按钮色块之上
    node.LocalZOrder = 1
    return node
end

local function button(self, parent, name, x, y, width, height, callback)
    local node = create(self, 'EUIButton', parent, name, x, y, width, height, {
        -- 显式正方形纯色块，避免默认椭圆贴图；暖橙色系，与 Gameplay 蓝系区分，明示"这是开发工具"
        ButtonText = '',
        NormalImage = ColorBlockImage,
        PressImage = ColorBlockImage,
        DisableImage = ColorBlockImage,
        ButtonNormalColor = Color.New(175, 80, 18, 255),
    })
    node.TouchEnabled = true
    listen(self, node.OnClicked, callback)
    return node
end

local function occupied(slots, capacity)
    local count = 0
    for index = 1, capacity do
        local entry = slots[index]
        if type(entry) == 'table' and type(entry.count) == 'number' and entry.count > 0 then
            count = count + 1
        end
    end
    return count
end

local function boundedInt(value, maximum)
    return type(value) == 'number' and value >= 0 and value <= maximum and value == math.floor(value)
end

function Panel:ShowState(snapshot)
    if type(snapshot) ~= 'table' or type(snapshot.slots) ~= 'table'
        or type(snapshot.backpack) ~= 'table'
        or not boundedInt(snapshot.slotCount, GameCfg.Items.ItemBarSlots)
        or not boundedInt(snapshot.backpackCount, GameCfg.Items.MaxBackpackSlots)
        or not boundedInt(snapshot.upgradeLevel, #GameCfg.Items.UpgradePrices)
        or not boundedInt(snapshot.coin, math.maxinteger) then return end
    self.CoinLabel.Text = '当前金币：' .. tostring(snapshot.coin)
    self.StorageLabel.Text = '扩容等级：' .. tostring(snapshot.upgradeLevel)
    self.CapacityLabel.Text = string.format('道具栏 %d/%d　背包 %d/%d',
        occupied(snapshot.slots, snapshot.slotCount), snapshot.slotCount,
        occupied(snapshot.backpack, snapshot.backpackCount), snapshot.backpackCount)
    self.Snapshot = snapshot
    self:ShowStatus()
    self:ShowSlots()
    local nextPrice = GameCfg.Items.UpgradePrices[snapshot.upgradeLevel + 1]
    local upgrade = nextPrice and ('下级 ' .. nextPrice .. ' 金币；' .. (snapshot.coin >= nextPrice and '金币足够' or '金币不足'))
        or '已升满：再次扩容不得扣金币'
    local barFull = occupied(snapshot.slots, snapshot.slotCount) == snapshot.slotCount
    local allFull = barFull and occupied(snapshot.backpack, snapshot.backpackCount) == snapshot.backpackCount
    self.Guide.Text = upgrade .. '\n收起 GM → 钓场商店亲自扩容\n'
        .. (snapshot.upgradeLevel == 0 and '首级扣100：道具栏2→3，背包5→10\n不足时不扣币、不升级\n' or '')
        .. '背包鱼获不能直接用，须先转入\n'
        .. (barFull and '道具栏满：转入拒绝，鱼获仍在背包' or '道具栏有空格：转入后选中食用')
        .. '\n可食用或丢弃腾格；GM 不代替转入'
        .. '\n' .. (allFull and '拾取提示背包已满：库存与地面鱼获不变' or '先击杀鱼留地面鱼获，再填满空格')
        .. '\n备购买金币 → 钓场商店买鱼竿拒绝且不扣币'
        .. '\n六级价格：100/200/400/800/1600/3200'
        .. '\n背包每级 +5，末级 +10；最终 8/40 格'
end

function Panel:ShowStatus()
    if not self.StatusLabel then return end
    local snapshot = self.Snapshot or {}
    local status = self.Status or {}
    local function slot(value)
        return value == '' and '默认' or tostring(value or '等待同步')
    end
    self.StatusLabel.Text = string.format('金币：%s　扩容等级：%s\n道具栏：%s/%s　背包：%s/%s',
        tostring(snapshot.coin or '—'), tostring(snapshot.upgradeLevel or '—'),
        snapshot.slots and occupied(snapshot.slots, snapshot.slotCount) or '—', snapshot.slotCount or '—',
        snapshot.backpack and occupied(snapshot.backpack, snapshot.backpackCount) or '—',
        snapshot.backpackCount or '—')
        .. '\n当前槽：' .. slot(status.currentSlot) .. '　下次进图：' .. slot(status.nextSlot)
        .. '\n自动保存：' .. (status.autosavePaused == nil and '等待同步'
            or status.autosavePaused and '暂停（临时本局）' or '运行')
end

function Panel:ShowSlots()
    if not self.Snapshot or not self.SlotDetails then return end
    local page = self.SlotPage or 0
    local entries, prefix, first, last
    if page == 0 then
        entries, prefix, first, last = self.Snapshot.slots, '道具栏', 1, self.Snapshot.slotCount
    else
        entries, prefix, first = self.Snapshot.backpack, '背包', (page - 1) * 8 + 1
        last = math.min(first + 7, self.Snapshot.backpackCount)
    end
    local lines = {}
    for index = first, last do
        local entry = entries[index]
        local item = entry and GameCfg.Items.Definitions[entry.itemId]
        lines[#lines + 1] = prefix .. index .. '：' .. (item and item.Name or '空')
            .. (entry and entry.mult and (' ×' .. tostring(entry.mult)) or '')
    end
    self.SlotDetails.Text = table.concat(lines, '\n')
end

local function value(field)
    local text = field and field.Text
    if type(text) ~= 'string' or text == '' then return nil end
    return text
end

function Panel:SendState(action, clear)
    local payload = { action = action }
    if action == 'ApplyState' then
        if value(self.Fields.coin) then payload.coin = tonumber(value(self.Fields.coin)) or value(self.Fields.coin) end
        if value(self.Fields.upgradeLevel) then
            payload.upgradeLevel = tonumber(value(self.Fields.upgradeLevel)) or value(self.Fields.upgradeLevel)
        end
        if value(self.Fields.container) or value(self.Fields.index) or value(self.Fields.itemId) or clear then
            payload.slots = { { container = value(self.Fields.container), index = tonumber(value(self.Fields.index))
                or value(self.Fields.index), clear = clear or nil } }
            if not clear then
                payload.slots[1].itemId = value(self.Fields.itemId)
                payload.slots[1].count = tonumber(value(self.Fields.count)) or value(self.Fields.count)
                payload.slots[1].mult = value(self.Fields.mult)
                    and (tonumber(value(self.Fields.mult)) or value(self.Fields.mult)) or nil
            end
        end
    elseif action == 'SelectSaveSlot' then
        payload.slot = value(self.Fields.slot) or ''
    end
    self.Feedback.Text = '等待服务端确认…'
    REUtil:GetRE('GMAction'):FireServer(payload)
end

function Panel:ShowPage(state)
    self.StatePage = state
    for _, node in ipairs(self.MainNodes or {}) do node.Visible = self.IsOpen and not state end
    for _, node in ipairs(self.StateNodes or {}) do node.Visible = self.IsOpen and state end
    if state and self.IsOpen then self:SendState('GetState') end
    if not state and self.IsOpen then self:UpdateFishPage() end
end

function Panel:UpdateFishPage()
    local pages = math.ceil(#FishIds / FishPageSize)
    self.FishPage = math.max(1, math.min(self.FishPage or 1, pages))
    for index, node in ipairs(self.FishLabels or {}) do
        local fishId = FishIds[(self.FishPage - 1) * FishPageSize + index]
        node.Text = fishId and GameCfg.Fish[fishId].Name or ''
        if self.FishButtons[index] then self.FishButtons[index].Visible = self.IsOpen and fishId ~= nil end
        node.Visible = self.IsOpen and fishId ~= nil
    end
    if self.FishPageLabel then
        self.FishPageLabel.Text = string.format('下一页 (%d/%d)', self.FishPage, pages)
    end
end

function Panel:SelectFish(index)
    local fishId = FishIds[(self.FishPage - 1) * FishPageSize + index]
    if not fishId then return end
    REUtil:GetRE('GMAction'):FireServer({ action = 'NextFish', fishId = fishId })
    self.Feedback.Text = '等待服务端确认：' .. GameCfg.Fish[fishId].Name
    print('[GMPanel] 请求 NextFish', fishId)
end

function Panel:Toggle()
    self.IsOpen = not self.IsOpen
    self.Background.Visible = self.IsOpen
    self:ShowPage(self.StatePage or false)
    self.EntryLabel.Text = self.IsOpen and '收起 GM' or 'GM'
    if self.IsOpen then
        REUtil:GetRE('RequestItemBar'):FireServer()
        REUtil:GetRE('GMAction'):FireServer({ action = 'GetAttack' })
    end
    print('[GMPanel]', self.IsOpen and '展开' or '收起')
end

function Panel:Start()
    if not (GameCfg.Debug and GameCfg.Debug.Enabled) then return end
    local manager = GameUI:GetEuiManager()
    if not manager then return end
    local root = manager:GetRootNode()
    local resolution = manager:GetDeviceResolution()
    local player = game:GetService('Players').LocalPlayer
    if not root or not resolution or not player then return end
    if self.Started then
        if self.Root == root then return end
        self:Destroy()
    end
    local ok, err = pcall(self.Build, self, root, resolution, player)
    if not ok then
        print('[GMPanel] 初始化失败', err)
        self:Destroy()
        return
    end
    self.Root = root
    self.Started = true
end

function Panel:Build(root, resolution, player)
    self.PanelNodes = {}
    self.FishLabels = {}
    self.FishButtons = {}
    self.FishPage = 1
    self.SlotPage = 0
    self.StateNodes = {}
    local width = 560
    -- 右对齐：面板中心距右边缘 16px，最小不小于半宽+16
    local right = math.max(width / 2 + 16, resolution.x - width / 2 - 16)
    local top = resolution.y - 105
    -- 标题、三行状态与反馈；每组增加分组标题和按钮行。
    local height = 784
    for _, group in ipairs(Groups) do
        height = height + 62 + math.ceil(#group.actions / 2) * 96
    end
    local scale = math.min(1, resolution.y / (height + 210), resolution.x / (width + 32))
    self.Scale = scale
    right = resolution.x - (width / 2 + 16) * scale
    top = resolution.y - 105 * scale
    self.Entry = button(self, root, 'GM入口', right, top, 220, 84, function() self:Toggle() end)
    self.EntryLabel = label(self, root, 'GM入口文字', 'GM', right, top, 220, 84, 32)
    local centerY = top - (82 + height / 2) * scale
    self.Background = create(self, 'EUIImage', root, 'GM面板', right, centerY, width, height, {
        Image = ColorBlockImage,
        -- 深色半透明底，白字可读；纯色块叠色，不用默认椭圆图避免黑色异形遮挡
        Color = Color.New(49, 20, 16, 240),
    })
    self.Background.TouchEnabled = false
    self.Background.SwallowTouchEnabled = false
    self.PanelNodes[#self.PanelNodes + 1] = self.Background
    -- 面板内元素：relX/relY 是相对面板中心的偏移，换算成屏幕坐标后挂 root
    local function relY(value) return centerY + value * scale end
    local topRow = height / 2 - 52
    local title = label(self, root, 'GM标题', '调试操作', right, relY(topRow), width - 24, 56, 44)
    self.PanelNodes[#self.PanelNodes + 1] = title
    self.CoinLabel = label(self, root, 'GM金币状态', '当前金币：等待同步', right, relY(topRow - 62),
        width - 24, 48, 36)
    self.PanelNodes[#self.PanelNodes + 1] = self.CoinLabel
    self.StorageLabel = label(self, root, 'GM扩容状态', '扩容等级：等待同步', right,
        relY(topRow - 110), width - 24, 48, 32)
    self.CapacityLabel = label(self, root, 'GM占格状态', '道具栏 / 背包：等待同步', right,
        relY(topRow - 158), width - 24, 48, 30)
    self.PanelNodes[#self.PanelNodes + 1] = self.StorageLabel
    self.PanelNodes[#self.PanelNodes + 1] = self.CapacityLabel
    self.AttackLabel = label(self, root, 'GM挥砍伤害', '当前挥砍伤害：等待服务端确认', right,
        relY(topRow - 206), width - 24, 48, 30)
    self.PanelNodes[#self.PanelNodes + 1] = self.AttackLabel
    local y = topRow - 262
    for _, group in ipairs(Groups) do
        local groupLabel = label(self, root, 'GM分组_' .. group.title, group.title, right, relY(y),
            width - 24, 44, 34)
        self.PanelNodes[#self.PanelNodes + 1] = groupLabel
        y = y - 62
        for index, action in ipairs(group.actions) do
            local item = action
            local column = (index - 1) % 2
            local x = right + (column - 0.5) * 266 * scale
            local rowY = relY(y - math.floor((index - 1) / 2) * 96)
            local btn = button(self, root, 'GM操作_' .. group.title .. index, x, rowY, 250, 76, function()
                if item.fishSlot then
                    self:SelectFish(item.fishSlot)
                elseif item.fishPage then
                    self.FishPage = self.FishPage + item.fishPage
                    self:UpdateFishPage()
                elseif item.statePage then
                    self:ShowPage(true)
                else
                    REUtil:GetRE('GMAction'):FireServer({ action = item.payload.action, amount = item.payload.amount,
                        itemId = item.payload.itemId, count = item.payload.count, scene = item.payload.scene })
                    self.Feedback.Text = '等待服务端确认…'
                    print('[GMPanel] 请求', item.payload.action,
                        item.payload.amount or item.payload.itemId or item.payload.scene, item.payload.count or '')
                end
            end)
            local btnLabel = label(self, root, 'GM操作文字_' .. group.title .. index, item.label,
                x, rowY, 250, 76, item.fishSlot and 23 or 32)
            if item.fishSlot then
                self.FishLabels[item.fishSlot] = btnLabel
                self.FishButtons[item.fishSlot] = btn
            end
            if item.fishPage == 1 then self.FishPageLabel = btnLabel end
            self.PanelNodes[#self.PanelNodes + 1] = btn
            self.PanelNodes[#self.PanelNodes + 1] = btnLabel
        end
        y = y - math.ceil(#group.actions / 2) * 96
    end
    self.Feedback = label(self, root, 'GM反馈', '等待操作', right, relY(y), width - 24, 56, 30)
    self.PanelNodes[#self.PanelNodes + 1] = self.Feedback
    self.Guide = label(self, root, 'GM验收引导', '等待服务端同步验收状态', right,
        relY(y - 220), width - 24, 372, 25)
    self.PanelNodes[#self.PanelNodes + 1] = self.Guide
    self.MainNodes = {}
    for _, node in ipairs(self.PanelNodes) do
        if node ~= self.Background then self.MainNodes[#self.MainNodes + 1] = node end
    end
    self.StateNodes[#self.StateNodes + 1] = self.Feedback
    local function stateLabel(name, text, x, offset, w, h, size)
        local node = label(self, root, name, text, x, relY(offset), w, h, size)
        self.StateNodes[#self.StateNodes + 1] = node
        self.PanelNodes[#self.PanelNodes + 1] = node
        return node
    end
    local function stateButton(name, text, x, offset, callback)
        local node = button(self, root, name, x, relY(offset), 235, 64, callback)
        self.StateNodes[#self.StateNodes + 1] = node
        self.PanelNodes[#self.PanelNodes + 1] = node
        stateLabel(name .. '文字', text, x, offset, 235, 64, 28)
    end
    self.Fields = {}
    stateLabel('GM状态标题', '状态配置与存档', right, topRow, width - 24, 52, 40)
    self.StatusLabel = stateLabel('GM存档状态', '当前槽：等待同步', right, topRow - 112, width - 24, 162, 26)
    stateLabel('GM字段提示', '空白保持原样；单格编辑填写\n容器、格号、物品 ID、件数 1', right,
        topRow - 222, width - 24, 48, 23)
    local fields = {
        { 'coin', '金币（可填 0）' }, { 'upgradeLevel', '扩容等级 0—6' },
        { 'container', '容器 itemBar/backpack' }, { 'index', '格号' },
        { 'itemId', '物品 ID' }, { 'count', '件数 1' },
        { 'mult', '鱼获倍率 1—2（可空）' }, { 'slot', '下次进图槽名（空白为默认槽）' },
    }
    for index, field in ipairs(fields) do
        local row = math.floor((index - 1) / 2)
        local x = right + ((index - 1) % 2 - 0.5) * 266 * scale
        local offset = topRow - 292 - row * 100
        stateLabel('GM字段名_' .. field[1], field[2], x, offset + 25, 250, 42, 22)
        local input = create(self, 'EUIInputField', root, 'GM输入_' .. field[1], x, relY(offset - 20),
            240, 56, { Text = '', FontSize = 28, TextColor = Color.New(255, 255, 255, 255),
                PlaceHolderText = '填写' })
        input.TouchEnabled = true
        self.Fields[field[1]] = input
        self.StateNodes[#self.StateNodes + 1] = input
        self.PanelNodes[#self.PanelNodes + 1] = input
    end
    local left, rightButton = right - 133 * scale, right + 133 * scale
    local actionsY = topRow - 708
    stateButton('GM应用', '应用到本局', left, actionsY, function() self:SendState('ApplyState') end)
    stateButton('GM清格', '明确清空格位', rightButton, actionsY, function() self:SendState('ApplyState', true) end)
    stateButton('GM保存', '保存到存档', left, actionsY - 76, function() self:SendState('SaveState') end)
    stateButton('GM读取', '读取存档', rightButton, actionsY - 76, function() self:SendState('ReadState') end)
    stateButton('GM切槽', '设置下次进图槽', left, actionsY - 152, function() self:SendState('SelectSaveSlot') end)
    stateButton('GM返回', '返回 GM 操作', rightButton, actionsY - 152, function() self:ShowPage(false) end)
    stateButton('GM占格翻页', '查看后续格位', rightButton, actionsY - 230, function()
        self.SlotPage = (self.SlotPage + 1) % 6
        self:ShowSlots()
    end)
    self.SlotDetails = stateLabel('GM格位明细', '等待状态同步', left, actionsY - 340, 245, 245, 21)
    stateLabel('GM暂存提示', '应用后暂停自动保存；正常玩法进度也不落档。\n'
        .. '重进图前须保存，否则本局改动丢失。', right, actionsY - 510, width - 24, 70, 22)
    -- 默认收起，避免遮挡游戏画面；IsOpen 在 Build 里显式初始化
    self.IsOpen = false
    for _, node in ipairs(self.PanelNodes) do node.Visible = false end
    listen(self, REUtil:GetRE('ItemBarState').OnClientEvent, function(snapshot) self:ShowState(snapshot) end)
    listen(self, REUtil:GetRE('GMResult').OnClientEvent, function(result)
        if type(result) ~= 'table' or (result.action ~= 'Coin' and result.action ~= 'Item'
            and result.action ~= 'NextFish' and result.action ~= 'AddAttack' and result.action ~= 'GetAttack'
            and result.action ~= 'ApplyState' and result.action ~= 'SaveState'
            and result.action ~= 'ReadState' and result.action ~= 'SelectSaveSlot'
            and result.action ~= 'GetState') then return end
        if type(result.status) == 'table' then self.Status = result.status self:ShowStatus() end
        if type(result.snapshot) == 'table' then self:ShowState(result.snapshot) end
        if result.ok and (result.action == 'AddAttack' or result.action == 'GetAttack')
            and boundedInt(result.damage, math.maxinteger) then
            self.AttackLabel.Text = '当前挥砍伤害：' .. tostring(result.damage)
        end
        if result.action == 'GetAttack' and result.ok then return end
        self.Feedback.Text = result.ok and (result.action == 'ApplyState' and '已应用到本局；自动保存暂停'
            or result.action == 'SaveState' and '存档写入成功；自动保存恢复'
            or result.action == 'ReadState' and '已读取并替换本局进度'
            or result.action == 'SelectSaveSlot' and '下次进图切槽已保存'
            or result.action == 'GetState' and '状态已同步；填写后点击应用到本局'
            or result.action == 'NextFish' and '服务端确认：下一次上岸鱼种已设置'
            or result.action == 'AddAttack' and '服务端确认：挥砍伤害已增加'
            or ('服务端确认：' .. (result.action == 'Coin' and '金币' or '物品') .. '发放成功'))
            or ('服务端拒绝：' .. tostring(result.reason or '请求未通过'))
        print('[GMPanel] 结果', result.ok and '成功' or '拒绝', tostring(result.reason or ''))
    end)
    REUtil:GetRE('RequestItemBar'):FireServer()
end

function Panel:Destroy()
    for _, connection in ipairs(self.Connections) do connection:Disconnect() end
    for index = #self.Nodes, 1, -1 do self.Nodes[index]:Destroy() end
    self.Connections = {}
    self.Nodes = {}
    self.PanelNodes = {}
    self.Started = false
    self.Root = nil
    self.IsOpen = false
    self.Entry = nil
    self.EntryLabel = nil
    self.Background = nil
    self.CoinLabel = nil
    self.StorageLabel = nil
    self.CapacityLabel = nil
    self.AttackLabel = nil
    self.Feedback = nil
    self.Guide = nil
    self.FishLabels = nil
    self.FishButtons = nil
    self.FishPageLabel = nil
    self.FishPage = nil
    self.StateNodes = nil
    self.MainNodes = nil
    self.Fields = nil
    self.StatusLabel = nil
    self.SlotDetails = nil
    self.Snapshot = nil
    self.Status = nil
    self.StatePage = nil
    self.SlotPage = nil
end

return Panel

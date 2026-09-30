-- 抽奖机界面（#138 T17，GameSpec §14 与策划案抽奖段）：全部节点运行时创建（编辑器侧没有
-- ScreenLottery 预设节点，data/ 只读），根节点名 ScreenLottery 挂 UIRoot，由 MgrGameUI 按名开关。
-- 投注框显示当前选中道具栏格的极品食物与实际价值（含个体倍率，与服务端 SalePrice 同口径）；
-- 结果以服务端 LotteryResult 为准：axes 决定停轴图案，客户端不抽样。滚动 SpinSec 秒后按
-- 左→右→中间隔 AxisStopIntervalSec 停轴；动画期间与等待回包期间抽奖按钮忽略重复点击；
-- 同 operation.id 的重播回调不重置动画；关窗中断动画但保留已落账结果，重开直接展示；
-- recovered（断线重进补推）直接展示不播动画。开奖后不必关窗即可选下一件继续抽。
local GameCfg = require('common.GameCfg')
local Eligibility = require('common.LotteryEligibility')
local REUtil = require('common.REUtil')
local GameUI = require('client.GameUI')

local SquareButtonImage = 'official://image/11017'

local ScreenHandler = { Seq = 0, AnimationStarts = 0 }
ScreenHandler.UINodes = { 'LabelLotteryTitle', 'LabelLotteryBet', 'LabelReelLeft', 'LabelReelRight',
    'LabelReelMiddle', 'LabelLotteryResult', 'BtnLotteryDraw', 'BtnLotteryRule', 'LabelLotteryRule',
    'BtnLotteryClose' }
ScreenHandler.UINodeMap = {}

local FailText = {
    ['not-premium'] = '只有极品食物才能抽奖',
    cooked = '烤过的食物不能抽奖',
    range = '离抽奖机太远了',
    slot = '请先选中一件极品食物',
}

local function patterns()
    return GameCfg.Lottery.Patterns
end

local function patternName(number)
    local pattern = patterns()[number]
    return pattern and pattern.name or '?'
end

local function notice(msg)
    if _G.LocalMsgNotice then _G.LocalMsgNotice(msg) end
end

local function styleButton(button)
    if not button then return end
    button.NormalImage = SquareButtonImage
    button.PressImage = SquareButtonImage
    button.DisableImage = SquareButtonImage
    button.ButtonNormalColor = Color.New(54, 100, 140, 255)
    button.ButtonPressColor = Color.New(36, 130, 94, 255)
    button.ButtonDisableColor = Color.New(120, 120, 120, 255)
end

local function createNode(self, kind, name, x, y, w, h, props)
    props = props or {}
    props.Parent = self.RootNode
    props.Name = name
    props.Position = Vector2.New(x, y)
    props.Size = Vector2.New(w, h)
    local ok, node = pcall(game:GetService('World').CreateUnit, game:GetService('World'), kind, props)
    if not ok or not node then
        print('[ScreenLottery] 节点创建失败', name, tostring(node))
        return nil
    end
    if kind == 'EUITextLabel' then
        node.TouchEnabled = false
        node.SwallowTouchEnabled = false
    end
    self.UINodeMap[name] = node
    return node
end

-- 取节点：优先自建登记表（运行时创建的节点都在），编辑器预设场景兜底 FindFirstChild
function ScreenHandler:Node(name)
    local node = self.UINodeMap[name]
    if node then return node end
    local root = self.RootNode
    if root and root.FindFirstChild then
        local ok, found = pcall(root.FindFirstChild, root, name, true)
        if ok and found then
            self.UINodeMap[name] = found
            return found
        end
    end
    return nil
end

-- 运行时建全部节点；UIRoot 未就绪时有限重试，仍拿不到只记日志（与既有界面同级风险）
function ScreenHandler:BuildNodes()
    local root = GameUI:GetUIRoot()
    if not root then
        print('[ScreenLottery] UIRoot 未就绪，抽奖界面不可用')
        return false
    end
    local resolution = GameUI:GetEuiManager():GetDeviceResolution()
    local x, y = resolution.x / 2, resolution.y / 2
    local ok, layout = pcall(game:GetService('World').CreateUnit, game:GetService('World'), 'EUILayout', {
        Parent = root, Name = 'ScreenLottery',
        Position = Vector2.New(x, y), Size = Vector2.New(900, 640),
    })
    if not ok or not layout then
        print('[ScreenLottery] 根节点创建失败', tostring(layout))
        return false
    end
    layout.Visible = false
    self.RootNode = layout
    createNode(self, 'EUITextLabel', 'LabelLotteryTitle', x, y - 250, 400, 60,
        { Text = '抽奖机', FontSize = 40, TextColor = Color.New(255, 255, 255, 255) })
    createNode(self, 'EUITextLabel', 'LabelLotteryBet', x, y - 160, 700, 60,
        { Text = '', FontSize = 28, TextColor = Color.New(255, 255, 255, 255) })
    createNode(self, 'EUITextLabel', 'LabelReelLeft', x - 220, y - 40, 200, 90,
        { Text = '?', FontSize = 40, TextColor = Color.New(255, 240, 160, 255) })
    createNode(self, 'EUITextLabel', 'LabelReelRight', x + 220, y - 40, 200, 90,
        { Text = '?', FontSize = 40, TextColor = Color.New(255, 240, 160, 255) })
    createNode(self, 'EUITextLabel', 'LabelReelMiddle', x, y - 40, 200, 90,
        { Text = '?', FontSize = 40, TextColor = Color.New(255, 240, 160, 255) })
    createNode(self, 'EUITextLabel', 'LabelLotteryResult', x, y + 80, 800, 60,
        { Text = '', FontSize = 30, TextColor = Color.New(255, 255, 255, 255) })
    local draw = createNode(self, 'EUIButton', 'BtnLotteryDraw', x, y + 180, 300, 80)
    styleButton(draw)
    local rule = createNode(self, 'EUIButton', 'BtnLotteryRule', x - 320, y + 180, 240, 80)
    styleButton(rule)
    local close = createNode(self, 'EUIButton', 'BtnLotteryClose', x + 320, y + 180, 240, 80)
    styleButton(close)
    createNode(self, 'EUITextLabel', 'LabelLotteryDrawTheme', x, y + 180, 300, 80,
        { Text = '抽奖', FontSize = 30, TextColor = Color.New(255, 255, 255, 255) })
    createNode(self, 'EUITextLabel', 'LabelLotteryRuleTheme', x - 320, y + 180, 240, 80,
        { Text = GameCfg.Lottery.RuleHintText, FontSize = 26, TextColor = Color.New(255, 255, 255, 255) })
    createNode(self, 'EUITextLabel', 'LabelLotteryCloseTheme', x + 320, y + 180, 240, 80,
        { Text = '关闭', FontSize = 26, TextColor = Color.New(255, 255, 255, 255) })
    local lines = { '投入一件未烤制的极品食物：' }
    for _, pattern in ipairs(patterns()) do
        local reward = pattern.tripleReward
        local prize
        if reward.kind == 'weaponChoice' then
            -- 武器组三同大奖文案用组名（匕首/斧头/枪械），不枚举组内五件
            local group = ({ '匕首', '斧头', '枪械' })[pattern.number] or '武器'
            prize = '随机' .. group .. '一把'
        else
            prize = reward.itemName
        end
        lines[#lines + 1] = string.format('%s×2=价值×%d金币；%s×3=%s',
            pattern.name, pattern.pairMultiplier, pattern.name, prize)
    end
    lines[#lines + 1] = '三个相同图案优先得大奖，不再另发金币'
    local ruleLabel = createNode(self, 'EUITextLabel', 'LabelLotteryRule', x, y - 20, 860, 480,
        { Text = table.concat(lines, '\n'), FontSize = 24, TextColor = Color.New(230, 230, 230, 255) })
    if ruleLabel then ruleLabel.Visible = false end
    return true
end

-- 当前投注：道具栏选中格的 entry（快照口径，含 mult/cooked）
function ScreenHandler:BetEntry()
    local snapshot = self.Snapshot
    local slot = snapshot and snapshot.selectedSlot
    return slot and snapshot.slots and snapshot.slots[slot] or nil, slot
end

-- 可抽奖：非动画、非等待回包、选中格是合格极品食物
function ScreenHandler:DrawEnabled()
    if self.Spinning or self.Awaiting then return false end
    local entry = self:BetEntry()
    return entry ~= nil and Eligibility.Check(entry) == true
end

function ScreenHandler:RefreshBet()
    local label = self:Node('LabelLotteryBet')
    local entry = self:BetEntry()
    local text
    if not entry then
        text = '请先在道具栏选中一件极品食物'
    elseif Eligibility.Check(entry) then
        local definition = GameCfg.Items.Definitions[entry.itemId]
        local value = GameCfg.Items.SalePrice(entry.itemId, entry.mult) or 0
        text = string.format('投注：%s（价值 %d 金币）', definition and definition.Name or entry.itemId, value)
    else
        local _, reason = Eligibility.Check(entry)
        text = FailText[reason] or '这件物品不能抽奖'
    end
    if label then pcall(function() label.Text = text end) end
    local button = self:Node('BtnLotteryDraw')
    if button then
        local enabled = self:DrawEnabled()
        pcall(function()
            button.TouchEnabled = enabled
            button.Disabled = not enabled
        end)
    end
end

function ScreenHandler:Draw()
    if not self:DrawEnabled() then return false end
    local _, slot = self:BetEntry()
    self.Seq = self.Seq + 1
    self.Awaiting = true
    REUtil:GetRE('LotteryAction'):FireServer({ action = 'Draw', slot = slot, seq = self.Seq })
    return true
end

-- 三轴直接落到结果图案（恢复/重展示用，不播动画）
function ScreenHandler:SettleReels(result)
    local reelNames = { 'LabelReelLeft', 'LabelReelRight', 'LabelReelMiddle' }
    for axis = 1, 3 do
        local node = self:Node(reelNames[axis])
        if node then pcall(function() node.Text = patternName(result.axes[axis]) end) end
    end
end

function ScreenHandler:ShowResult(result)
    self.ResultShown = true
    self.Awaiting = false
    self.Spinning = nil
    self:SettleReels(result)
    local text
    if result.outcome == 'pair' then
        text = string.format('%s ×2！金币 +%d', result.patternName or '', result.coins or 0)
    elseif result.outcome == 'triple' then
        text = string.format('恭喜获得：%s（%s ×3）', result.prize and result.prize.name or '大奖',
            result.patternName or '')
    else
        text = '未中奖，再接再厉'
    end
    local label = self:Node('LabelLotteryResult')
    if label then pcall(function() label.Text = text end) end
    self:RefreshBet()
end

-- LotteryResult 回包：失败给提示；同 operation.id 重播不重置动画与展示；
-- recovered（断线重进补推）直接展示；正常结果进入停轴动画。
function ScreenHandler:NoteResult(result)
    if type(result) ~= 'table' then return end
    if not result.ok then
        self.Awaiting = false
        notice(FailText[result.reason] or '抽奖失败，请稍后再试')
        self:RefreshBet()
        return
    end
    local operationId = result.operation and result.operation.id
    -- 同 operation.id 重播一律忽略：动画中途或已展示都不重置（#123 重放只回原结果）
    if operationId and operationId == self.LastOperationId then return end
    if operationId then self.LastOperationId = operationId end
    self.LastResult = result
    if result.recovered then
        self:ShowResult(result)
        return
    end
    self.Spinning = { t = 0, stopped = { false, false, false }, result = result }
    self.AnimationStarts = self.AnimationStarts + 1
    self.Awaiting = true
    self:RefreshBet()
end

function ScreenHandler:IsSpinning()
    return self.Spinning ~= nil
end

function ScreenHandler:AxisStopped(axis)
    if self.Spinning then return self.Spinning.stopped[axis] == true end
    return self.LastResult ~= nil and self.ResultShown == true
end

-- 停轴动画推进（Heartbeat 驱动；测试直接调用）：滚动 SpinSec 秒后按左→右→中停轴，
-- 停轴图案永远取服务端回包 axes，动画不决定奖项。
function ScreenHandler:UpdateAnim(dt)
    local spinning = self.Spinning
    if not spinning or type(dt) ~= 'number' then return end
    spinning.t = spinning.t + dt
    local cfg = GameCfg.Lottery
    local reelNames = { 'LabelReelLeft', 'LabelReelRight', 'LabelReelMiddle' }
    local allStopped = true
    for axis = 1, 3 do
        if not spinning.stopped[axis] then
            local stopAt = cfg.SpinSec + (axis - 1) * cfg.AxisStopIntervalSec
            local node = self:Node(reelNames[axis])
            if spinning.t >= stopAt then
                spinning.stopped[axis] = true
                if node then
                    pcall(function() node.Text = patternName(spinning.result.axes[axis]) end)
                end
            else
                allStopped = false
                if node then
                    local index = math.floor(spinning.t * 8 + axis * 2) % #patterns() + 1
                    pcall(function() node.Text = patterns()[index].name end)
                end
            end
        end
    end
    if allStopped then self:ShowResult(spinning.result) end
end

function ScreenHandler:NoteItemBar(state)
    if type(state) ~= 'table' then return end
    self.Snapshot = state
    self:RefreshBet()
end

function ScreenHandler:Init()
    if self.Inited and self.BoundRootNode == self.RootNode then return end
    for _, connection in ipairs(self.Connections or {}) do connection:Disconnect() end
    self.Connections = {}
    local function listen(signal, callback)
        if signal then self.Connections[#self.Connections + 1] = signal:Connect(callback) end
    end
    for _, name in ipairs(self.UINodes) do self:Node(name) end
    local draw = self:Node('BtnLotteryDraw')
    if draw then listen(draw.OnClicked, function() self:Draw() end) end
    local close = self:Node('BtnLotteryClose')
    if close then
        listen(close.OnClicked, function() _G.MgrGameUI:CloseScreen('ScreenLottery') end)
    end
    local rule = self:Node('BtnLotteryRule')
    if rule then
        listen(rule.OnClicked, function()
            local label = self:Node('LabelLotteryRule')
            if label then pcall(function() label.Visible = not label.Visible end) end
        end)
    end
    self.BoundRootNode = self.RootNode
    self.Inited = true
    self:RefreshBet()
end

function ScreenHandler:OpenScreen()
    self.IsOpen = true
    self:RefreshBet()
    -- 关窗中断动画不丢结果：重开时直接展示最近一次的已落账结果，不重播动画
    if self.LastResult and not self.Spinning then self:ShowResult(self.LastResult) end
end

function ScreenHandler:CloseScreen()
    self.IsOpen = false
    self.Spinning = nil -- 动画只是表现；结果早已服务端落账
end

function ScreenHandler:Start()
    REUtil:GetRE('LotteryResult').OnClientEvent:Connect(function(result) self:NoteResult(result) end)
    REUtil:GetRE('ItemBarState').OnClientEvent:Connect(function(state) self:NoteItemBar(state) end)
    game:GetService('RunService').Heartbeat:Connect(function(dt) self:UpdateAnim(dt) end)
    -- 断线恢复主动拉取（照 RequestItemBar 握手先例）：服务端 OnPlayerAdded 的补推可能早于
    -- 客户端连接而丢失；这里连上回包通道后请求一次，服务端按操作日志补推 recovered 结果
    REUtil:GetRE('LotteryStateRequest'):FireServer()
    local task = game:GetService('Task')
    task:Spawn(function()
        for _ = 1, 50 do
            if self:BuildNodes() then return end
            task:Wait(0.2)
        end
    end)
end

return ScreenHandler

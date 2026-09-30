-- 盲盒界面（#147 T26，GameSpec §15）：右上角「盲盒」入口开关面板，单抽 10 金豆 / 十连 90 金豆。
-- 结果以服务端 BlindboxResult 为准（服务端先收费、逐抽结算并落账），客户端不抽样。
-- 满格按区落地的「落地前提示」：按 ItemBarState 快照数空格，放不下本次抽数时第一次点击只提示
-- （FullNoticeText），同一抽数再点一次才上行；服务端仍按实际空格逐件决定入库或落地。
-- 等待回包期间忽略重复点击，超过 ResultTimeoutSec（含平台支付等待）自动解锁并提示；
-- 同 operation.id 的重放回包不重复展示；保底计数经 BlindboxStateRequest 握手与每次结果刷新。
-- 节点全部运行时创建（data/ 只读），创建失败只记日志。
local GameCfg = require('common.GameCfg')
local REUtil = require('common.REUtil')
local GameUI = require('client.GameUI')

local ColorBlockImage = 'official://image/11017'

local Screen = { Seq = 0, Nodes = {}, Pity = 0 }

local function cfg()
    return GameCfg.Blindbox
end

local function notice(msg)
    if _G.LocalMsgNotice then _G.LocalMsgNotice(msg) end
end

local function guaranteeAt()
    return cfg().Pity.afterMisses + 1
end

function Screen:Create(kind, parent, name, x, y, w, h, props)
    props = props or {}
    props.Parent = parent
    props.Name = name
    props.Position = Vector2.New(x, y)
    props.Size = Vector2.New(w, h)
    local world = game:GetService('World')
    local ok, node = pcall(world.CreateUnit, world, kind, props)
    if not ok or not node then
        print('[ScreenBlindbox] 节点创建失败', name, tostring(node))
        return nil
    end
    if kind == 'EUITextLabel' then
        node.TouchEnabled = false
        node.SwallowTouchEnabled = false
    end
    self.Nodes[name] = node
    return node
end

function Screen:Button(parent, name, x, y, w, h, text, onClick)
    local button = self:Create('EUIButton', parent, name, x, y, w, h, {
        ButtonText = '', NormalImage = ColorBlockImage, PressImage = ColorBlockImage,
        Color = Color.New(150, 80, 170, 255) })
    if not button then return nil end
    button.TouchEnabled = true
    self:Create('EUITextLabel', button, name .. 'Text', 0, 0, w, h, {
        Text = text, FontSize = 28, TextColor = Color.New(255, 255, 255, 255), LocalZOrder = 1 })
    if button.OnClicked then button.OnClicked:Connect(onClick) end
    return button
end

function Screen:SetText(name, text)
    local node = self.Nodes[name]
    if node then pcall(function() node.Text = text end) end
end

function Screen:BuildNodes()
    local root = GameUI:GetUIRoot()
    if not root then return false end
    local resolution = GameUI:GetEuiManager():GetDeviceResolution() or { x = 1920, y = 1080 }
    local cx, cy = resolution.x / 2, resolution.y / 2
    self:Button(root, 'BtnBlindboxEntry', resolution.x - 120, 180, 160, 70, cfg().HintText,
        function() self:Toggle() end)
    local panel = self:Create('EUIImage', root, 'ScreenBlindbox', cx, cy, 900, 600, {
        Image = ColorBlockImage, Color = Color.New(20, 20, 40, 220), Visible = false })
    if not panel then return false end
    self.Panel = panel
    local single = GameCfg.Platform.Goods.blindboxSingle
    local ten = GameCfg.Platform.Goods.blindboxTen
    local bean = GameCfg.Platform.BeanCurrency
    self:Create('EUITextLabel', panel, 'LabelBlindboxTitle', 0, -250, 600, 60, {
        Text = cfg().HintText, FontSize = 40, TextColor = Color.New(255, 255, 255, 255) })
    self:Create('EUITextLabel', panel, 'LabelBlindboxPity', 0, -180, 800, 50, {
        Text = '', FontSize = 26, TextColor = Color.New(255, 230, 150, 255) })
    self:Create('EUITextLabel', panel, 'LabelBlindboxResult', 0, -20, 860, 240, {
        Text = '', FontSize = 24, TextColor = Color.New(255, 255, 255, 255) })
    self:Button(panel, 'BtnBlindboxSingle', -260, 200, 280, 80,
        string.format('单抽（%d%s）', single.beans, bean), function() self:Draw(1) end)
    self:Button(panel, 'BtnBlindboxTen', 60, 200, 280, 80,
        string.format('十连（%d%s）', ten.beans, bean), function() self:Draw(10) end)
    self:Button(panel, 'BtnBlindboxClose', 330, 200, 160, 80, '关闭', function() self:SetOpen(false) end)
    self:RefreshPity()
    return true
end

function Screen:SetOpen(open)
    self.IsOpen = open
    if self.Panel then pcall(function() self.Panel.Visible = open end) end
    if open then REUtil:GetRE('BlindboxStateRequest'):FireServer() end
end

function Screen:Toggle()
    self:SetOpen(not self.IsOpen)
end

-- 保底奖品名：内容表 Pity.prizeItemKeys 在 Entries 里查 itemName
local function prizeNames()
    local names = {}
    for _, key in ipairs(cfg().Pity.prizeItemKeys or {}) do
        for _, entry in ipairs(cfg().Entries or {}) do
            if entry.itemKey == key then names[#names + 1] = entry.itemName break end
        end
    end
    return table.concat(names, '或')
end

function Screen:RefreshPity()
    local left = math.max(1, guaranteeAt() - (self.Pity or 0))
    self:SetText('LabelBlindboxPity', string.format('已连续 %d 次未出大奖；再抽 %d 次内必出%s',
        self.Pity or 0, left, prizeNames()))
end

-- 道具栏 + 背包空格数（快照口径）；没有快照返回 nil（不拦截，服务端照常按实际空格落地）
function Screen:FreeSlots()
    local snapshot = self.Snapshot
    if type(snapshot) ~= 'table' then return nil end
    local free = 0
    for _, pair in ipairs({ { snapshot.slots, snapshot.slotCount }, { snapshot.backpack, snapshot.backpackCount } }) do
        local slots, capacity = pair[1] or {}, tonumber(pair[2]) or 0
        for index = 1, capacity do
            local entry = slots[index]
            if not entry or (entry.count or 0) <= 0 then free = free + 1 end
        end
    end
    return free
end

function Screen:Draw(count)
    if self.Awaiting then return false end
    local free = self:FreeSlots()
    if free and free < count and self.ConfirmFull ~= count then
        -- 落地前提示：同一抽数再点一次确认
        self.ConfirmFull = count
        notice(cfg().FullNoticeText)
        self:SetText('LabelBlindboxResult', cfg().FullNoticeText .. '\n再点一次确认抽取')
        return false
    end
    self.ConfirmFull = nil
    self.Seq = self.Seq + 1
    self.Awaiting = true
    self.AwaitingElapsed = 0
    REUtil:GetRE('BlindboxAction'):FireServer({ action = 'Draw', count = count, seq = self.Seq })
    return true
end

function Screen:ResultText(result)
    local lines = {}
    for index, draw in ipairs(result.draws or {}) do
        local tags = {}
        if draw.guaranteed then tags[#tags + 1] = '保底' elseif draw.jackpot then tags[#tags + 1] = '大奖' end
        if draw.landed then tags[#tags + 1] = '落在地上' end
        lines[#lines + 1] = string.format('%d. %s%s', index, draw.itemName or draw.itemKey or '?',
            #tags > 0 and ('（' .. table.concat(tags, '，') .. '）') or '')
    end
    return table.concat(lines, '\n')
end

function Screen:NoteResult(result)
    if type(result) ~= 'table' then return end
    if result.action == 'State' then
        self.Pity = tonumber(result.pity) or 0
        self:RefreshPity()
        return
    end
    if not result.ok then
        self.Awaiting, self.AwaitingElapsed = false, nil
        local text = result.reason == 'unavailable' and cfg().UnavailableText
            or GameCfg.Platform.ReasonText[result.reason] or GameCfg.Platform.UnavailableText
        notice(text)
        return
    end
    local operationId = result.operation and result.operation.id
    if operationId and operationId == self.LastOperationId then
        self.Awaiting, self.AwaitingElapsed = false, nil
        return -- 重放回包：原结果已展示过
    end
    self.LastOperationId = operationId
    self.Awaiting, self.AwaitingElapsed = false, nil
    self.Pity = tonumber(result.pityAfter) or self.Pity
    self:RefreshPity()
    self:SetText('LabelBlindboxResult', self:ResultText(result))
    if (result.grounded or 0) > 0 then
        notice(string.format('背包已满：%d 件物品落在面前地上，其他玩家可拾取', result.grounded))
    end
end

-- 回包超时兜底（Heartbeat 驱动；测试直接调用）：服务端可能静默丢弃（限频 / 旧序号）
function Screen:UpdateAwait(dt)
    if not self.Awaiting or type(dt) ~= 'number' then return end
    self.AwaitingElapsed = (self.AwaitingElapsed or 0) + dt
    if self.AwaitingElapsed >= cfg().ResultTimeoutSec then
        self.Awaiting, self.AwaitingElapsed = false, nil
        notice('盲盒回包超时，请再试一次')
    end
end

function Screen:NoteItemBar(state)
    if type(state) == 'table' then self.Snapshot = state end
end

function Screen:Start()
    REUtil:GetRE('BlindboxResult').OnClientEvent:Connect(function(result) self:NoteResult(result) end)
    REUtil:GetRE('ItemBarState').OnClientEvent:Connect(function(state) self:NoteItemBar(state) end)
    game:GetService('RunService').Heartbeat:Connect(function(dt) self:UpdateAwait(dt) end)
    REUtil:GetRE('BlindboxStateRequest'):FireServer() -- 重进握手：拉当前保底计数
    local task = game:GetService('Task')
    task:Spawn(function()
        for _ = 1, 50 do
            if self:BuildNodes() then return end
            task:Wait(0.2)
        end
        print('[ScreenBlindbox] UIRoot 未就绪，盲盒界面不可用')
    end)
end

return Screen

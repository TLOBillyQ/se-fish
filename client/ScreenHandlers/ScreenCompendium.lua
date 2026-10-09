-- 七区图鉴：收集、个人最大钓取重量与唯一通关状态由服务端快照提供。
-- 普通/极品使用各自稳定 ID；盲盒只解锁，未钓取时不推算重量。
local GameCfg = require('common.GameCfg')
local Records = require('common.Records')
local REUtil = require('common.REUtil')
local GameUI = require('client.GameUI')

local Screen = { Page = 1, Seq = 0, RecordSeq = 0, Nodes = {},
    UINodes = {}, UINodeMap = {}, Connections = {} }
local grades = { normal = '普通', rare = '极品', elite = '精英', boss = '首领' }
local rank = { normal = 1, rare = 2, elite = 3, boss = 4 }

-- 公开显示快照，同时供可重跑客户端验收探针读取，不改变收集数据。
function Screen:View()
    local zone = GameCfg.Zones[self.Page] or GameCfg.Zones[1]
    local state = self.State or {}
    local rows, collected, total = {}, 0, 0
    for id, fish in pairs(GameCfg.Fish) do
        total = total + 1
        local unlocked = state.unlocked and state.unlocked[id] == true
        if unlocked then collected = collected + 1 end
        if fish.ZoneId == zone.Id then
            local weight = state.weights and state.weights[id]
            rows[#rows + 1] = { id = id, name = fish.Name, grade = grades[fish.Grade],
                rank = rank[fish.Grade], sourceId = fish.SourceId, silhouette = not unlocked,
                weightText = type(weight) == 'number' and weight == weight and weight > 0 and weight < math.huge
                    and string.format('最大钓取 %.2f 千克', weight) or '未钓取' }
        end
    end
    table.sort(rows, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        if a.sourceId ~= b.sourceId then return a.sourceId < b.sourceId end
        return a.id < b.id
    end)
    local achievementText = state.state ~= 'ready' and '通关成就：数据暂不可用'
        or state.completed == true and (GameCfg.Achievements.final.Name .. '：已完成')
        or (GameCfg.Achievements.final.Name .. '：未完成')
    local recordText = Records.Describe(self.RecordState)
    if self.RecordState and self.RecordState.stale then
        recordText = recordText .. '（上次可信纪录，当前读取失败）'
    end
    return { zone = zone.Name, entries = rows, collected = collected, total = total,
        achievementText = achievementText, recordText = recordText, selectedId = self.SelectedId }
end

function Screen:Request()
    self.Seq = self.Seq + 1
    REUtil:GetRE('CompendiumRequest'):FireServer({ seq = self.Seq })
end

function Screen:NoteState(state)
    if type(state) ~= 'table' or type(state.seq) ~= 'number' or state.seq ~= math.floor(state.seq)
        or state.seq > self.Seq
        or state.seq <= (self.LastStateSeq or 0) then return false end
    if state.state ~= 'ready' and state.state ~= 'loading' and state.state ~= 'unavailable' then return false end
    if type(state.unlocked) ~= 'table' or type(state.weights) ~= 'table'
        or type(state.catches) ~= 'table' or type(state.total) ~= 'number' then return false end
    self.LastStateSeq, self.State = state.seq, state
    if self.Render then self:Render() end
    return true
end

function Screen:SelectFish(id)
    if not GameCfg.Fish[id] then return false end
    self.SelectedId, self.RecordState = id, nil
    self.RecordSeq = self.RecordSeq + 1
    REUtil:GetRE('RecordsRequest'):FireServer({fishId = id, seq = self.RecordSeq})
    if self.Render then self:Render() end
    return true
end

function Screen:NoteRecord(state)
    if type(state) ~= 'table' or state.fishId ~= self.SelectedId
        or state.seq ~= self.RecordSeq then return false end
    if state.state ~= 'missing' and state.state ~= 'unavailable' and state.state ~= 'ok' then return false end
    if state.state == 'ok' and (type(state.weight) ~= 'number'
        or state.weight ~= state.weight or state.weight <= 0 or state.weight == math.huge
        or type(state.holder) ~= 'string') then return false end
    self.RecordState = state
    if self.Render then self:Render() end
    return true
end

local block = 'official://image/11017'

function Screen:Create(kind, parent, name, x, y, width, height, props)
    props = props or {}
    props.Parent, props.Name = parent, name
    props.Position, props.Size = Vector2.New(x, y), Vector2.New(width, height)
    local world = game:GetService('World')
    local ok, node = pcall(world.CreateUnit, world, kind, props)
    if not ok or not node then
        self.BuildFailed = true
        print('[ScreenCompendium] 创建节点失败', name, tostring(node))
        return nil
    end
    self.Nodes[name] = node
    return node
end

function Screen:Label(parent, name, x, y, width, height, text, size)
    return self:Create('EUITextLabel', parent, name, x, y, width, height, {
        Text = text, FontSize = size, TextColor = Color.New(255, 255, 255, 255),
        TouchEnabled = false, SwallowTouchEnabled = false, LocalZOrder = 1,
    })
end

function Screen:Button(parent, name, x, y, width, height, text, callback)
    local node = self:Create('EUIButton', parent, name, x, y, width, height, {
        NormalImage = block, PressImage = block, DisableImage = block, ButtonText = '',
        ButtonNormalColor = Color.New(54, 100, 140, 255),
        ButtonPressColor = Color.New(36, 130, 94, 255),
        TouchEnabled = true, SwallowTouchEnabled = true,
    })
    if not node then return end
    self:Label(node, name .. 'Text', width / 2, height / 2, width - 10, height, text, 24)
    self.NodeConnections[#self.NodeConnections + 1] = node.OnClicked:Connect(callback)
    return node
end

function Screen:SetText(name, text)
    local node = self.Nodes[name]
    if node then node.Text = text end
end

function Screen:Render()
    if not self.Inited or not self.RootNode then return end
    local view = self:View()
    self:SetText('LabelCompendiumTitle', string.format('图鉴 · %s · %d / %d', view.zone, view.collected, view.total))
    self:SetText('LabelCompendiumAchievement', view.achievementText .. '  |  全图鉴为额外收集目标')
    local state = self.State
    local dataText = state and state.state == 'ready' and '盲盒只解锁收集；钓取重量由成功上岸记录'
        or state and state.state == 'loading' and '图鉴正在加载，稍后自动刷新'
        or '个人图鉴暂不可用，稍后自动重试'
    self:SetText('LabelCompendiumHint', dataText)
    self.VisibleEntries = view.entries
    for i, entry in ipairs(view.entries) do
        local button, icon = self.Nodes['BtnCompendiumFish' .. i], self.Nodes['ImageCompendiumFish' .. i]
        if button then
            button.ButtonNormalColor = entry.id == self.SelectedId and Color.New(36, 130, 94, 255)
                or Color.New(54, 100, 140, 255)
        end
        self:SetText('LabelCompendiumFish' .. i, string.format('%s · %s\n%s',
            entry.grade, entry.name, entry.silhouette and '未收集' or '已收集'))
        if icon then
            local fish = GameCfg.Fish[entry.id]
            local drop = fish.Drops and fish.Drops[1]
            local item = GameCfg.Items.Definitions[entry.id] or drop and GameCfg.Items.Definitions[drop.ItemId]
            icon.Image = item and item.Icon or GameCfg.Items.Definitions.tilapia.Icon
            icon.Color = entry.silhouette and Color.New(0, 0, 0, 255) or Color.New(255, 255, 255, 255)
        end
    end
    local selected
    for _, entry in ipairs(view.entries) do if entry.id == self.SelectedId then selected = entry end end
    self:SetText('LabelCompendiumPersonal', selected and (selected.name .. ' · ' .. selected.weightText)
        or '点击条目查看个人最大钓取重量与纪录')
    self:SetText('LabelCompendiumRecord', selected and view.recordText or '')
end

function Screen:SetPage(page)
    if type(page) ~= 'number' or page ~= math.floor(page) or not GameCfg.Zones[page] then return false end
    self.Page, self.SelectedId, self.RecordState = page, nil, nil
    -- 使上一页尚未返回的纪录查询失效。
    self.RecordSeq = self.RecordSeq + 1
    self:Render()
    return true
end

function Screen:Init()
    if self.Inited and self.BoundRootNode == self.RootNode then return end
    self.BoundRootNode, self.Inited = self.RootNode, true
    self:Render()
end

function Screen:OpenScreen()
    self.IsOpen, self.RefreshElapsed = true, 0
    self:Request()
    self:Render()
end

function Screen:CloseScreen()
    self.IsOpen = false
    self.RecordSeq = self.RecordSeq + 1
end

-- 节点属于本 handler；切换 UIRoot 或重启时撤销旧按钮连接，再销毁两棵运行时子树。
function Screen:ClearNodes()
    for _, connection in ipairs(self.NodeConnections or {}) do connection:Disconnect() end
    self.NodeConnections = {}
    for _, node in pairs({ panel = self.RootNode, entry = self.EntryNode }) do
        local ok, err = pcall(function() node:Destroy() end)
        if not ok then print('[ScreenCompendium] 销毁节点失败', tostring(err)) end
    end
    self.Nodes, self.Inited, self.BoundRootNode, self.RootNode, self.EntryNode = {}, nil, nil, nil, nil
    self.IsOpen = false
    self.SelectedId, self.RecordState = nil, nil
    self.RecordSeq = self.RecordSeq + 1
end

function Screen:BuildNodes(uiRoot)
    self:ClearNodes()
    self.BuildFailed = false
    self.UIRoot = uiRoot
    local manager = GameUI:GetEuiManager()
    local resolution = manager and manager:GetDeviceResolution()
    if not resolution then return false end
    local scale = math.min(1, (resolution.x - 40) / 1180, (resolution.y - 40) / 840)
    self.EntryNode = self:Button(uiRoot, 'BtnCompendiumEntry', resolution.x - 120,
        resolution.y - 230, 160, 65, '图鉴', function()
            _G.MgrGameUI:OpenScreen('ScreenCompendium')
        end)
    local panel = self:Create('EUIImage', uiRoot, 'ScreenCompendium', resolution.x / 2,
        resolution.y / 2, 1180, 840, {
            Image = block, Color = Color.New(20, 35, 48, 245), Visible = false,
            Scale = Vector2.New(scale, scale), TouchEnabled = true, SwallowTouchEnabled = true,
            LocalZOrder = 30,
        })
    if not panel or not self.EntryNode then self:ClearNodes() self.UIRoot = nil return false end
    self.RootNode = panel
    self:Label(panel, 'LabelCompendiumTitle', 590, 795, 800, 50, '图鉴', 36)
    self:Button(panel, 'BtnCompendiumClose', 1100, 795, 100, 50, '关闭', function()
        _G.MgrGameUI:CloseScreen('ScreenCompendium')
    end)
    for page, zone in ipairs(GameCfg.Zones) do
        self:Button(panel, 'BtnCompendiumPage' .. page, 95 + (page - 1) * 165,
            735, 145, 48, zone.Name, function() self:SetPage(page) end)
    end
    self:Label(panel, 'LabelCompendiumAchievement', 590, 685, 1120, 40, '', 24)
    for i = 1, 14 do
        -- 左列：六条普通与精英；右列：六条极品与首领，品级不混排。
        local left = i <= 6 or i == 13
        local row = i <= 6 and i - 1 or i <= 12 and i - 7 or 6
        local x, y = left and 300 or 880, 630 - row * 66
        local button = self:Button(panel, 'BtnCompendiumFish' .. i, x, y, 530, 58, '', function()
            local entry = self.VisibleEntries and self.VisibleEntries[i]
            if entry then self:SelectFish(entry.id) end
        end)
        if not button then self:ClearNodes() self.UIRoot = nil return false end
        self:Create('EUIImage', button, 'ImageCompendiumFish' .. i, 36, 29, 46, 46, {
            Image = GameCfg.Items.Definitions.tilapia.Icon, Color = Color.New(0, 0, 0, 255),
            TouchEnabled = false, SwallowTouchEnabled = false, LocalZOrder = 1,
        })
        self:Label(button, 'LabelCompendiumFish' .. i, 305, 29, 440, 56, '', 22)
    end
    self:Label(panel, 'LabelCompendiumPersonal', 590, 175, 1100, 45, '', 26)
    self:Label(panel, 'LabelCompendiumRecord', 590, 125, 1100, 45, '', 24)
    self:Label(panel, 'LabelCompendiumHint', 590, 65, 1100, 45, '', 22)
    if self.BuildFailed then self:ClearNodes() self.UIRoot = nil return false end
    _G.MgrGameUI:GetScreen('ScreenCompendium') -- 由界面管理器绑定与初始化 handler
    _G.MgrGameUI:CloseScreen('ScreenCompendium') -- Root 更换后同时清除管理器旧的已打开状态
    return true
end

function Screen:Update(dt)
    self.RootElapsed = (self.RootElapsed or 0) + dt
    if self.RootElapsed >= GameCfg.Compendium.RootPollSec then
        self.RootElapsed = 0
        local root = GameUI:GetUIRoot()
        if root and (root ~= self.UIRoot or not self.RootNode) then self:BuildNodes(root) end
    end
    if not self.IsOpen then return end
    self.RefreshElapsed = (self.RefreshElapsed or 0) + dt
    if self.RefreshElapsed >= GameCfg.Compendium.RefreshSec then
        self.RefreshElapsed = 0
        self:Request()
        if self.SelectedId then
            self.RecordSeq = self.RecordSeq + 1
            REUtil:GetRE('RecordsRequest'):FireServer({ fishId = self.SelectedId, seq = self.RecordSeq })
        end
    end
end

function Screen:Stop()
    for _, connection in ipairs(self.Connections) do connection:Disconnect() end
    self.Connections = {}
    if self.RootNode and self.UIRoot == GameUI:GetUIRoot() then
        _G.MgrGameUI:CloseScreen('ScreenCompendium')
    end
    self:ClearNodes()
    self.UIRoot, self.RootElapsed = nil, 0
end

function Screen:Start()
    self:Stop()
    self.Connections = {
        REUtil:GetRE('CompendiumState').OnClientEvent:Connect(function(state) self:NoteState(state) end),
        REUtil:GetRE('RecordsState').OnClientEvent:Connect(function(state) self:NoteRecord(state) end),
        game:GetService('RunService').Heartbeat:Connect(function(dt) self:Update(dt) end),
    }
    local root = GameUI:GetUIRoot()
    if root then self:BuildNodes(root) end
end

return Screen

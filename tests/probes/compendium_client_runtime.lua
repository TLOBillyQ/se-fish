-- #39 真实客户端图鉴验收，先执行本文件，再截图并保留当轮 log trace。
-- 默认打开当前页并验证七区 98 条；_G.Compendium39Page=1..7 选择截图页。
-- _G.Compendium39Action='restart' 验证重复 Start 不产生重复入口/面板；
-- _G.Compendium39Action='close' 关闭。探针不修改收集/重量/成就或伪造平台纪录。
local screen = require('client.ScreenHandlers.ScreenCompendium')
local task = game:GetService('Task')
task:Spawn(function()
    if _G.Compendium39Action == 'close' then
        _G.MgrGameUI:CloseScreen('ScreenCompendium')
        print('COMPENDIUM39_CLOSED')
        return
    end
    if _G.Compendium39Action == 'restart' then screen:Start() screen:Start() end
    local attempts = 0
    while not screen.RootNode and attempts < 30 do
        attempts = attempts + 1
        task:Wait(0.2)
    end
    assert(screen.RootNode, '图鉴运行时节点未建立')
    local entryCount, panelCount = 0, 0
    for _, child in ipairs(screen.UIRoot:GetChildren()) do
        if child.Name == 'BtnCompendiumEntry' then entryCount = entryCount + 1 end
        if child.Name == 'ScreenCompendium' then panelCount = panelCount + 1 end
    end
    assert(entryCount == 1 and panelCount == 1, '重复入口或面板')
    local total, ids = 0, {}
    for page = 1, 7 do
        assert(screen:SetPage(page))
        local view = screen:View()
        assert(#view.entries == 14, '本页不是 14 条')
        for _, row in ipairs(view.entries) do
            assert(not ids[row.id], '跨页重复鱼 ID')
            ids[row.id], total = true, total + 1
        end
        print('COMPENDIUM39_PAGE', page, view.zone, #view.entries)
    end
    assert(total == 98)
    screen:SetPage(_G.Compendium39Page or 1)
    _G.MgrGameUI:OpenScreen('ScreenCompendium')
    task:Wait(4)
    local view = screen:View()
    print('COMPENDIUM39_STATE', screen.State and screen.State.state, view.collected, view.total,
        view.achievementText, 'entry=' .. entryCount, 'panel=' .. panelCount)
    for _, row in ipairs(view.entries) do
        print('COMPENDIUM39_ENTRY', row.id, row.grade, row.silhouette and 'silhouette' or 'collected', row.weightText)
    end
    print('COMPENDIUM39_READY', screen.Page, screen.RootNode.Visible)
end)

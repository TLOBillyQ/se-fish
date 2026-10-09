-- #39 失败方式：七区漏条/重条、普通与极品合并、未收集泄漏完整图像、
-- 盲盒显示伪重量、纪录不可用变成零、旧回包覆盖新数据、通关受全图鉴阻塞。
-- 接缝：ScreenCompendium 的公开快照消费与页面显示数据；引擎边界另经编辑器 E2E。
local lu = require('luaunit')

TestCompendiumUI = {}

function TestCompendiumUI:setUp()
    self.previousRE = package.loaded['common.REUtil']
    self.previousUI = package.loaded['client.GameUI']
    package.loaded['common.REUtil'] = { GetRE = function()
        return { FireServer = function() end }
    end }
    package.loaded['client.GameUI'] = {}
end

function TestCompendiumUI:test_blindbox_has_collection_without_weight_and_late_snapshot_cannot_undo_completion()
    local screen = assert(loadfile('client/ScreenHandlers/ScreenCompendium.lua'))()
    screen:Request()
    screen:Request()
    lu.assertTrue(screen:NoteState({seq=2, state='ready', unlocked={item7=true},
        weights={}, catches={}, total=0, completed=true}))
    lu.assertFalse(screen:NoteState({seq=1, state='ready', unlocked={}, weights={}, catches={}, total=0}))
    local view = screen:View()
    lu.assertFalse(view.entries[7].silhouette)
    lu.assertEquals(view.entries[7].weightText, '未钓取')
    lu.assertEquals(view.collected, 1)
    lu.assertEquals(view.achievementText, '通关成就：已完成')
    lu.assertFalse(screen:NoteState({seq=3, state='ready', unlocked=true, weights={}}))
end

function TestCompendiumUI:test_record_missing_unavailable_and_stale_are_distinct_and_late_selection_is_ignored()
    local screen = assert(loadfile('client/ScreenHandlers/ScreenCompendium.lua'))()
    screen:SelectFish('goldfish')
    lu.assertTrue(screen:NoteRecord({fishId='goldfish',seq=1,state='missing'}))
    lu.assertEquals(screen:View().recordText, '全服纪录：暂无')
    screen:SelectFish('goldfish')
    lu.assertTrue(screen:NoteRecord({fishId='goldfish',seq=2,state='unavailable'}))
    lu.assertEquals(screen:View().recordText, '全服纪录：暂不可用')
    screen:SelectFish('goldfish')
    lu.assertTrue(screen:NoteRecord({fishId='goldfish',seq=3,state='ok',
        weight=0.2,holder='钓鱼佬',stale=true}))
    lu.assertStrContains(screen:View().recordText, '0.20')
    lu.assertStrContains(screen:View().recordText, '上次可信')
    screen:SelectFish('carp')
    lu.assertFalse(screen:NoteRecord({fishId='goldfish',seq=3,state='ok',weight=9,holder='旧回包'}))
    lu.assertEquals(screen:View().recordText, '全服纪录：暂不可用')
end

function TestCompendiumUI:tearDown()
    package.loaded['common.REUtil'] = self.previousRE
    package.loaded['client.GameUI'] = self.previousUI
end

function TestCompendiumUI:test_seven_pages_show_98_distinct_entries_with_separate_grades()
    local screen = assert(loadfile('client/ScreenHandlers/ScreenCompendium.lua'))()
    local seen, total = {}, 0
    for page = 1, 7 do
        screen.Page = page
        local view = screen:View()
        lu.assertEquals(#view.entries, 14)
        lu.assertEquals(view.entries[1].grade, '普通')
        lu.assertEquals(view.entries[7].grade, '极品')
        lu.assertEquals(view.entries[13].grade, '精英')
        lu.assertEquals(view.entries[14].grade, '首领')
        for _, entry in ipairs(view.entries) do
            lu.assertNil(seen[entry.id])
            seen[entry.id], total = true, total + 1
            lu.assertTrue(entry.silhouette)
            lu.assertEquals(entry.weightText, '未钓取')
        end
    end
    lu.assertEquals(total, 98)
end

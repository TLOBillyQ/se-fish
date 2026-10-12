-- 原生 Busted（#87 迁移自 tests/gameplay/compendium_ui_test.lua 的 TestCompendiumUI）。
-- #39 失败方式：七区漏条/重条、普通与极品合并、未收集泄漏完整图像、
-- 盲盒显示伪重量、纪录不可用变成零、旧回包覆盖新数据、通关受全图鉴阻塞。
-- 接缝：ScreenCompendium 的公开快照消费与页面显示数据；引擎边界另经编辑器 E2E。
-- 迁移说明：案例按旧 LuaUnit 实际执行序（方法名字典序）逐个 it 注册；
--   旧文件的 tearDown 声明夹在两个用例之间，LuaUnit 仍按每例 setUp/tearDown 运行，
--   原生侧统一为 describe 内的 before_each/after_each，语义一致。
--   lu.assertStrContains 省略第 3 参即 plain 子串查找，映射为 assert.matches(sub, s, 1, true)。
local RandomGuard = require("tests.support.random_guard")

local MODULE_KEYS = { "common.REUtil", "client.GameUI" }

--- 换掉图鉴界面依赖的两个模块缓存；调用方负责 cleanup() 还回原引用。
local function newWorld()
  local env = {}
  env.previous = {}
  for _, name in ipairs(MODULE_KEYS) do
    env.previous[name] = package.loaded[name]
  end
  package.loaded["common.REUtil"] = {
    GetRE = function()
      return { FireServer = function() end }
    end,
  }
  package.loaded["client.GameUI"] = {}

  function env:cleanup()
    for _, name in ipairs(MODULE_KEYS) do
      package.loaded[name] = self.previous[name]
    end
  end

  return env
end

describe("图鉴界面表现（ScreenCompendium）", function()
  local env
  before_each(function()
    env = newWorld()
  end)
  after_each(function()
    RandomGuard.restore()
    if env then
      env:cleanup()
      env = nil
    end
  end)

  it("test_blindbox_has_collection_without_weight_and_late_snapshot_cannot_undo_completion", function()
    local screen = assert(loadfile("client/ScreenHandlers/ScreenCompendium.lua"))()
    screen:Request()
    screen:Request()
    assert.is_true(screen:NoteState({
      seq = 2, state = "ready", unlocked = { item7 = true },
      weights = {}, catches = {}, total = 0, completed = true,
    }))
    assert.is_false(screen:NoteState({
      seq = 1, state = "ready", unlocked = {}, weights = {}, catches = {}, total = 0,
    }))
    local view = screen:View()
    assert.is_false(view.entries[7].silhouette)
    assert.same("未钓取", view.entries[7].weightText)
    assert.same(1, view.collected)
    assert.same("通关成就：已完成", view.achievementText)
    assert.is_false(screen:NoteState({ seq = 3, state = "ready", unlocked = true, weights = {} }))
  end)

  it("test_record_missing_unavailable_and_stale_are_distinct_and_late_selection_is_ignored", function()
    local screen = assert(loadfile("client/ScreenHandlers/ScreenCompendium.lua"))()
    screen:SelectFish("goldfish")
    assert.is_true(screen:NoteRecord({ fishId = "goldfish", seq = 1, state = "missing" }))
    assert.same("全服纪录：暂无", screen:View().recordText)
    screen:SelectFish("goldfish")
    assert.is_true(screen:NoteRecord({ fishId = "goldfish", seq = 2, state = "unavailable" }))
    assert.same("全服纪录：暂不可用", screen:View().recordText)
    screen:SelectFish("goldfish")
    assert.is_true(screen:NoteRecord({
      fishId = "goldfish", seq = 3, state = "ok", weight = 0.2, holder = "钓鱼佬", stale = true,
    }))
    assert.matches("0.20", screen:View().recordText, 1, true)
    assert.matches("上次可信", screen:View().recordText, 1, true)
    screen:SelectFish("carp")
    assert.is_false(screen:NoteRecord({
      fishId = "goldfish", seq = 3, state = "ok", weight = 9, holder = "旧回包",
    }))
    assert.same("全服纪录：暂不可用", screen:View().recordText)
  end)

  it("test_seven_pages_show_98_distinct_entries_with_separate_grades", function()
    local screen = assert(loadfile("client/ScreenHandlers/ScreenCompendium.lua"))()
    local seen, total = {}, 0
    for page = 1, 7 do
      screen.Page = page
      local view = screen:View()
      assert.same(14, #view.entries)
      assert.same("普通", view.entries[1].grade)
      assert.same("极品", view.entries[7].grade)
      assert.same("精英", view.entries[13].grade)
      assert.same("首领", view.entries[14].grade)
      for _, entry in ipairs(view.entries) do
        assert.is_nil(seen[entry.id])
        seen[entry.id], total = true, total + 1
        assert.is_true(entry.silhouette)
        assert.same("未钓取", entry.weightText)
      end
    end
    assert.same(98, total)
  end)
end)

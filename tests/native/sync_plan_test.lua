-- 纯模块单测：回同步计划（回灌哪些文件、行尾归一、data/ 的 stale 集合）。
-- 不碰文件系统、不起子进程；真实文件系统行为由 tests/native/slow/sync_transport_test.lua
-- 从 CLI 那一侧覆盖。
-- 迁移自 tests/tooling/sync_plan_test.lua（#92，LuaUnit → 原生 Busted）；
-- 案例顺序沿用旧入口的类名 + 方法名字典序。
local plan = require("tools.sync_plan")

describe("TestSyncPlan", function()
  -- 二进制（含 NUL）不能过行尾归一，否则 0x0D0A 字节序列会被就地改写。
  it("test_binary_content_is_untouched", function()
    assert.are.equal("PNG\r\n\0\r\n", plan.normalize_eol("PNG\r\n\0\r\n"))
  end)

  it("test_crlf_is_normalized_to_lf", function()
    assert.are.equal("a\nb\n", plan.normalize_eol("a\r\nb\r\n"))
  end)

  it("test_data_dir_is_the_editor_export_tree", function()
    assert.are.equal("data", plan.DATA_DIR)
  end)

  it("test_lf_content_is_untouched", function()
    assert.are.equal("a\nb\n", plan.normalize_eol("a\nb\n"))
    assert.are.equal("", plan.normalize_eol(""))
  end)

  it("test_lone_cr_is_normalized_too", function()
    assert.are.equal("a\nb", plan.normalize_eol("a\rb"))
  end)

  -- 回灌清单就是编辑器侧产物：工程绑定 + 两份 API 存根（本工程比 se-defense 多一份）。
  it("test_root_files_are_the_editor_side_products", function()
    assert.same({ "eggy.json", "EggyAPI.lua", "EggyEditorAPI.lua" }, plan.ROOT_FILES)
  end)

  -- 镜像纪律：仓库侧有而宿主侧没有的就是 stale，跟着消失；交集不产生删除。
  it("test_stale_files_are_repo_only_entries", function()
    assert.same({ "stale.lua" }, plan.stale_files({ "keep.lua" }, { "keep.lua", "stale.lua" }))
    assert.same({}, plan.stale_files({ "a.lua" }, {}))
    assert.same({ "m.lua", "z.lua" }, plan.stale_files({}, { "z.lua", "m.lua" }))
  end)
end)

-- 纯模块单测：回同步计划（回灌哪些文件、行尾归一、data/ 的 stale 集合）。
-- 不碰文件系统、不起子进程；真实文件系统行为由 tests/sync_transport_test.lua
-- 从 CLI 那一侧覆盖。
local lu = require("luaunit")
local plan = require("tools.sync_plan")

TestSyncPlan = {}

-- 回灌清单就是编辑器侧产物：工程绑定 + 两份 API 存根（本工程比 se-defense 多一份）。
function TestSyncPlan:test_root_files_are_the_editor_side_products()
  lu.assertEquals(plan.ROOT_FILES, { "eggy.json", "EggyAPI.lua", "EggyEditorAPI.lua" })
end

function TestSyncPlan:test_data_dir_is_the_editor_export_tree()
  lu.assertEquals(plan.DATA_DIR, "data")
end

function TestSyncPlan:test_crlf_is_normalized_to_lf()
  lu.assertEquals(plan.normalize_eol("a\r\nb\r\n"), "a\nb\n")
end

function TestSyncPlan:test_lone_cr_is_normalized_too()
  lu.assertEquals(plan.normalize_eol("a\rb"), "a\nb")
end

function TestSyncPlan:test_lf_content_is_untouched()
  lu.assertEquals(plan.normalize_eol("a\nb\n"), "a\nb\n")
  lu.assertEquals(plan.normalize_eol(""), "")
end

-- 二进制（含 NUL）不能过行尾归一，否则 0x0D0A 字节序列会被就地改写。
function TestSyncPlan:test_binary_content_is_untouched()
  lu.assertEquals(plan.normalize_eol("PNG\r\n\0\r\n"), "PNG\r\n\0\r\n")
end

-- 镜像纪律：仓库侧有而宿主侧没有的就是 stale，跟着消失；交集不产生删除。
function TestSyncPlan:test_stale_files_are_repo_only_entries()
  lu.assertEquals(plan.stale_files({ "keep.lua" }, { "keep.lua", "stale.lua" }), { "stale.lua" })
  lu.assertEquals(plan.stale_files({ "a.lua" }, {}), {})
  lu.assertEquals(plan.stale_files({}, { "z.lua", "m.lua" }), { "m.lua", "z.lua" })
end

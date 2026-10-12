-- 回同步的回归护栏：断言都从 CLI 那一侧（真 Lua 子进程 + EGGY_WORKSPACE 指向临时
-- 宿主目录）打进去，断言外部行为——回灌后的文件树、行尾归一、stale 删除、退出码；
-- 不断言内部函数调用。目的地是「当前目录=仓库根」，所以子进程统一 cd 进临时假仓库
-- （LUA_PATH 指回本仓库，让 tools/cli.lua 能 require 到真模块），真仓库不被碰。
-- 迁移自 tests/tooling/slow/sync_transport_test.lua（#92，LuaUnit → 原生 Busted）。
-- 平台条件：命令行是 cmd.exe 语法（rmdir /s /q、md、`&` 链、反斜杠路径），只在 Windows 可跑；
-- 非 Windows 逐案例登记为 pending（名称保留旧方法名，`--list` 行数不变、运行时报 pending 而非失败）。
local shell = require("tools.win_shell")
local interpreter = require("tests.support.interpreter")

local WINDOWS = package.config:sub(1, 1) == "\\"
local SKIP = "仅 Windows 可跑（真实 cmd 子进程）"

local function slurp(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local body = f:read("a")
  f:close()
  return body
end

-- 本仓库根的绝对路径：LUA_PATH 与 cli.lua 的位置都从它拼。
local REPO = (io.popen("cd"):read("l"))
local ROOT = REPO .. "\\tmp\\sync-transport-test"
local HOST = ROOT .. "\\host"
local FAKE_REPO = ROOT .. "\\repo"
local OUT = ROOT .. ".out"

local function code_of(cmd)
  local _, _, code = os.execute(cmd)
  return code
end

local function rmrf(path)
  code_of("if exist " .. shell.q(path) .. " rmdir /s /q " .. shell.q(path) .. " >nul 2>&1")
end

local function write_file(path, body)
  local dir = path:match("^(.-)[/\\][^/\\]*$")
  if dir then code_of("if not exist " .. shell.q(dir) .. " md " .. shell.q(dir) .. " >nul 2>&1") end
  local f = assert(io.open(path, "wb"), path .. " 建不出来")
  f:write(body)
  f:close()
end

local function write_host(rel, body)
  write_file(HOST .. "\\" .. rel, body)
end

local function write_repo(rel, body)
  write_file(FAKE_REPO .. "\\" .. rel, body)
end

-- 跑 CLI 的 lua 解释器：取启动本 runner 的那个，不走 PATH 猜。
-- 解释器在 arg 里的下标会随启动选项前移（覆盖率模式下 `-e` 的语句原文正占着最后一格），
-- 所以交给 tests/support/interpreter.lua 逐格往回找。
local function lua_bin()
  return interpreter.path()
end

-- 真 CLI 子进程：cd 进假仓库再跑 sync，拿回 stdout+stderr 与退出码。
-- 重定向前缀遵循 tools/win_shell.lua 的 cmd 引号解析规则 2。
local function run_sync(args, cwd)
  local parts = {
    "cd .",
    'set "EGGY_WORKSPACE=' .. HOST .. '"',
    'set "LUA_PATH=' .. REPO .. '\\?.lua;' .. REPO .. '\\?\\init.lua;;"',
    "cd /d " .. shell.q(cwd or FAKE_REPO),
    "> " .. shell.q(OUT) .. " 2>&1 " .. shell.q(lua_bin()) .. " "
      .. shell.q(REPO .. "/tools/cli.lua") .. " sync" .. (args and (" " .. args) or ""),
  }
  local code = code_of(table.concat(parts, " & "))
  return slurp(OUT) or "", code
end

-- 临时宿主目录：三个根文件 + data/（含嵌套子目录）全是 CRLF；unit_scripts/ 是
-- 宿主侧非回同步内容。临时假仓库：eggy.json 是旧内容，EggyAPI.lua 与宿主归一后
-- 一致（造「未变」），data/ 里有旧内容、有 stale，server/ 是仓库自有内容。
local function seed_and_sync()
  rmrf(ROOT)
  rmrf(OUT)
  write_host("eggy.json", '{\r\n  "projectName": "fixture"\r\n}\r\n')
  write_host("EggyAPI.lua", "-- 宿主目录里的 API 存根\r\n")
  write_host("EggyEditorAPI.lua", "-- 宿主目录里的编辑时 API 存根\r\n")
  write_host("data\\FontData.lua", "-- 字体\r\n")
  write_host("data\\Prefab.lua", "-- 预制\r\n")
  write_host("data\\sub\\Nested.lua", "-- 嵌套\r\n")
  write_host("unit_scripts\\keep.lua", "-- 只活在宿主目录里\r\n")
  write_repo("eggy.json", "old-binding\n")
  write_repo("EggyAPI.lua", "-- 宿主目录里的 API 存根\n")
  write_repo("data\\Prefab.lua", "-- 旧预制\n")
  write_repo("data\\Stale.lua", "-- 宿主侧已经删了\n")
  write_repo("server\\main.lua", "-- 仓库自有内容\n")
  return run_sync(nil)
end

describe("TestSyncCli", function()
  local out, code
  if WINDOWS then
    before_each(function()
      rmrf(ROOT)
      code_of("md " .. shell.q(FAKE_REPO) .. " >nul 2>&1")
    end)
    after_each(function()
      rmrf(ROOT)
      rmrf(OUT)
      out, code = nil, nil
    end)
  end

  it("test_extra_argument_is_a_usage_error", function()
    if not WINDOWS then return pending("test_extra_argument_is_a_usage_error: " .. SKIP) end
    out, code = run_sync("extra")
    assert.are.equal(2, code, out)
    assert.matches("未知参数", out, 1, true)
  end)

  it("test_help_is_a_success", function()
    if not WINDOWS then return pending("test_help_is_a_success: " .. SKIP) end
    out, code = run_sync("--help")
    assert.are.equal(0, code, out)
    assert.matches("sync", out, 1, true)
  end)

  -- 宿主目录不存在是业务失败（1），不是用法错误（2）。
  it("test_missing_workspace_is_a_business_failure", function()
    if not WINDOWS then return pending("test_missing_workspace_is_a_business_failure: " .. SKIP) end
    out, code = run_sync(nil, nil)
    assert.are.equal(1, code, out)
    assert.matches("编辑器宿主目录不存在", out, 1, true)
  end)
end)

describe("TestSyncIdempotent", function()
  local out, code
  if WINDOWS then
    before_each(function()
      seed_and_sync()
      out, code = run_sync(nil)
    end)
    after_each(function()
      rmrf(ROOT)
      rmrf(OUT)
      out, code = nil, nil
    end)
  end

  -- 幂等：内容没变时不产生改动，第二轮没有写入也没有删除。
  it("test_second_run_changes_nothing", function()
    if not WINDOWS then return pending("test_second_run_changes_nothing: " .. SKIP) end
    assert.are.equal(0, code, "sync 输出:\n" .. out)
    assert.matches("0 写入, 0 删除,", out, 1, true)
    assert.is_nil(out:find("write ", 1, true))
    assert.is_nil(out:find("delete ", 1, true))
  end)
end)

-- 缺一个源就整体不写：错误可读，仓库侧保持原样。
describe("TestSyncMissingSource", function()
  local out, code
  if WINDOWS then
    before_each(function()
      rmrf(ROOT)
      rmrf(OUT)
      write_host("eggy.json", "{}\r\n")
      write_host("EggyAPI.lua", "-- 存根\r\n")
      write_host("data\\FontData.lua", "-- 字体\r\n")
      write_repo("eggy.json", "sentinel\n")
      write_repo("data\\Stale.lua", "-- 还活着\n")
      out, code = run_sync(nil)
    end)
    after_each(function()
      rmrf(ROOT)
      rmrf(OUT)
      out, code = nil, nil
    end)
  end

  it("test_missing_source_is_a_business_failure", function()
    if not WINDOWS then return pending("test_missing_source_is_a_business_failure: " .. SKIP) end
    assert.are.equal(1, code, out)
    assert.matches("EggyEditorAPI.lua", out, 1, true)
  end)

  it("test_nothing_is_written", function()
    if not WINDOWS then return pending("test_nothing_is_written: " .. SKIP) end
    assert.are.equal("sentinel\n", slurp(FAKE_REPO .. "\\eggy.json"))
    assert.is_false(shell.exists(FAKE_REPO .. "\\data\\FontData.lua"), "缺源还落了半截")
    assert.is_true(shell.exists(FAKE_REPO .. "\\data\\Stale.lua"), "缺源还删了文件")
  end)
end)

-- 官方包回灌：通过真实 CLI 验证字节保真、镜像删除与来源不完整时的写入闸门。
describe("TestSyncPackages", function()
  local out, code
  if WINDOWS then
    before_each(function()
      seed_and_sync()
      write_repo("eggy.json", "sentinel\n")
      for _, side in ipairs({ "server", "client", "common" }) do
        write_host(side .. "\\packages\\fixture\\api.lua", "-- 官方包\r\nreturn {}\r\n")
        write_repo(side .. "\\packages\\README.md", "-- 保留说明\n")
        write_repo(side .. "\\packages\\old\\stale.lua", "-- 旧包\n")
      end
    end)
    after_each(function()
      rmrf(ROOT)
      rmrf(OUT)
      out, code = nil, nil
    end)
  end

  it("test_default_sync_does_not_touch_packages", function()
    if not WINDOWS then return pending("test_default_sync_does_not_touch_packages: " .. SKIP) end
    out, code = run_sync(nil)
    assert.are.equal(0, code, out)
    assert.is_nil(slurp(FAKE_REPO .. "\\server\\packages\\fixture\\api.lua"))
    assert.are.equal("-- 旧包\n", slurp(FAKE_REPO .. "\\server\\packages\\old\\stale.lua"))
  end)

  it("test_empty_package_source_aborts_before_any_write", function()
    if not WINDOWS then return pending("test_empty_package_source_aborts_before_any_write: " .. SKIP) end
    rmrf(HOST .. "\\common\\packages")
    shell.ensure_dir(HOST .. "\\common\\packages")
    out, code = run_sync("--packages")
    assert.are.equal(1, code, out)
    assert.matches("common/packages", out, 1, true)
    assert.are.equal("sentinel\n", slurp(FAKE_REPO .. "\\eggy.json"))
    assert.is_true(shell.exists(FAKE_REPO .. "\\server\\packages\\old\\stale.lua"))
  end)

  it("test_missing_package_source_aborts_before_any_write", function()
    if not WINDOWS then return pending("test_missing_package_source_aborts_before_any_write: " .. SKIP) end
    rmrf(HOST .. "\\client\\packages")
    out, code = run_sync("--packages")
    assert.are.equal(1, code, out)
    assert.matches("client/packages", out, 1, true)
    assert.are.equal("sentinel\n", slurp(FAKE_REPO .. "\\eggy.json"))
    assert.is_nil(slurp(FAKE_REPO .. "\\server\\packages\\fixture\\api.lua"))
    assert.is_true(shell.exists(FAKE_REPO .. "\\common\\packages\\old\\stale.lua"))
  end)

  it("test_package_source_with_only_readme_is_rejected", function()
    if not WINDOWS then return pending("test_package_source_with_only_readme_is_rejected: " .. SKIP) end
    rmrf(HOST .. "\\common\\packages")
    write_host("common\\packages\\README.md", "-- 空包说明\n")
    out, code = run_sync("--packages")
    assert.are.equal(1, code, out)
    assert.are.equal("sentinel\n", slurp(FAKE_REPO .. "\\eggy.json"))
  end)

  it("test_packages_are_mirrored_as_bytes_and_readmes_are_preserved", function()
    if not WINDOWS then
      return pending("test_packages_are_mirrored_as_bytes_and_readmes_are_preserved: " .. SKIP)
    end
    write_host("server\\packages\\README.md", "-- 宿主说明\r\n")
    local again
    out, code = run_sync("--packages")
    assert.are.equal(0, code, out)
    for _, side in ipairs({ "server", "client", "common" }) do
      local rel = side .. "\\packages\\fixture\\api.lua"
      assert.are.equal(slurp(HOST .. "\\" .. rel), slurp(FAKE_REPO .. "\\" .. rel))
      assert.is_nil(slurp(FAKE_REPO .. "\\" .. side .. "\\packages\\old\\stale.lua"))
      assert.are.equal("-- 保留说明\n", slurp(FAKE_REPO .. "\\" .. side .. "\\packages\\README.md"))
    end
    again, code = run_sync("--packages")
    assert.are.equal(0, code, again)
    assert.matches("0 写入, 0 删除,", again, 1, true)
  end)

  it("test_packages_can_be_imported_into_absent_repo_tree", function()
    if not WINDOWS then return pending("test_packages_can_be_imported_into_absent_repo_tree: " .. SKIP) end
    rmrf(FAKE_REPO .. "\\client\\packages")
    out, code = run_sync("--packages")
    assert.are.equal(0, code, out)
    assert.are.equal(slurp(HOST .. "\\client\\packages\\fixture\\api.lua"),
      slurp(FAKE_REPO .. "\\client\\packages\\fixture\\api.lua"))
  end)
end)

describe("TestSyncTransport", function()
  local out, code
  if WINDOWS then
    before_each(function()
      out, code = seed_and_sync()
    end)
    after_each(function()
      rmrf(ROOT)
      rmrf(OUT)
      out, code = nil, nil
    end)
  end

  -- 宿主侧是 CRLF 的产物落进仓库后是 LF，git status 才不会有行尾噪音。
  it("test_crlf_is_normalized_to_lf", function()
    if not WINDOWS then return pending("test_crlf_is_normalized_to_lf: " .. SKIP) end
    for _, rel in ipairs({ "eggy.json", "EggyEditorAPI.lua", "data\\FontData.lua" }) do
      assert.is_nil((slurp(FAKE_REPO .. "\\" .. rel) or ""):find("\r", 1, true), rel .. " 里还有 CR")
    end
  end)

  it("test_data_dir_is_mirrored_recursively", function()
    if not WINDOWS then return pending("test_data_dir_is_mirrored_recursively: " .. SKIP) end
    assert.are.equal("-- 字体\n", slurp(FAKE_REPO .. "\\data\\FontData.lua"))
    assert.are.equal("-- 预制\n", slurp(FAKE_REPO .. "\\data\\Prefab.lua"))
    assert.are.equal("-- 嵌套\n", slurp(FAKE_REPO .. "\\data\\sub\\Nested.lua"))
  end)

  -- 宿主目录是源，sync 一个字节都不许往回写；非回同步内容（unit_scripts/ 等）不进仓库。
  it("test_host_side_is_untouched", function()
    if not WINDOWS then return pending("test_host_side_is_untouched: " .. SKIP) end
    assert.are.equal('{\r\n  "projectName": "fixture"\r\n}\r\n', slurp(HOST .. "\\eggy.json"))
    assert.is_true(shell.exists(HOST .. "\\unit_scripts\\keep.lua"))
    assert.is_false(shell.exists(FAKE_REPO .. "\\unit_scripts"), "宿主侧非回同步内容进了仓库")
  end)

  it("test_root_files_are_synced", function()
    if not WINDOWS then return pending("test_root_files_are_synced: " .. SKIP) end
    assert.are.equal('{\n  "projectName": "fixture"\n}\n', slurp(FAKE_REPO .. "\\eggy.json"))
    assert.are.equal("-- 宿主目录里的编辑时 API 存根\n", slurp(FAKE_REPO .. "\\EggyEditorAPI.lua"))
  end)

  it("test_stale_repo_files_are_deleted", function()
    if not WINDOWS then return pending("test_stale_repo_files_are_deleted: " .. SKIP) end
    assert.is_false(shell.exists(FAKE_REPO .. "\\data\\Stale.lua"), "stale 文件没被抹掉")
    assert.matches("delete data/Stale.lua", out, 1, true)
  end)

  it("test_sync_succeeds", function()
    if not WINDOWS then return pending("test_sync_succeeds: " .. SKIP) end
    assert.are.equal(0, code, "sync 输出:\n" .. out)
    assert.matches("sync ok", out, 1, true)
  end)

  it("test_unrelated_repo_content_is_untouched", function()
    if not WINDOWS then return pending("test_unrelated_repo_content_is_untouched: " .. SKIP) end
    assert.are.equal("-- 仓库自有内容\n", slurp(FAKE_REPO .. "\\server\\main.lua"))
  end)

  it("test_write_is_reported", function()
    if not WINDOWS then return pending("test_write_is_reported: " .. SKIP) end
    assert.matches("write data/Prefab.lua", out, 1, true)
  end)
end)

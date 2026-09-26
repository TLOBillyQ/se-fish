-- 回同步的回归护栏：断言都从 CLI 那一侧（真 Lua 子进程 + EGGY_WORKSPACE 指向临时
-- 宿主目录）打进去，断言外部行为——回灌后的文件树、行尾归一、stale 删除、退出码；
-- 不断言内部函数调用。目的地是「当前目录=仓库根」，所以子进程统一 cd 进临时假仓库
-- （LUA_PATH 指回本仓库，让 tools/cli.lua 能 require 到真模块），真仓库不被碰。
local lu = require("luaunit")
local shell = require("tools.win_shell")

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

-- 跑 CLI 的 lua 解释器：取启动本 runner 的那个（Lua 把解释器路径记在 arg[-1]），不走 PATH 猜。
local function lua_bin()
  local exe = arg and arg[-1]
  if type(exe) == "string" and exe ~= "" and not exe:match("^%-") then return exe end
  return "lua"
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

TestSyncTransport = {}

function TestSyncTransport:setUp()
  self.out, self.code = seed_and_sync()
end

function TestSyncTransport:tearDown()
  rmrf(ROOT)
  rmrf(OUT)
end

function TestSyncTransport:test_sync_succeeds()
  lu.assertEquals(self.code, 0, "sync 输出:\n" .. self.out)
  lu.assertStrContains(self.out, "sync ok")
end

function TestSyncTransport:test_root_files_are_synced()
  lu.assertEquals(slurp(FAKE_REPO .. "\\eggy.json"), '{\n  "projectName": "fixture"\n}\n')
  lu.assertEquals(slurp(FAKE_REPO .. "\\EggyEditorAPI.lua"), "-- 宿主目录里的编辑时 API 存根\n")
end

-- 宿主侧是 CRLF 的产物落进仓库后是 LF，git status 才不会有行尾噪音。
function TestSyncTransport:test_crlf_is_normalized_to_lf()
  for _, rel in ipairs({ "eggy.json", "EggyEditorAPI.lua", "data\\FontData.lua" }) do
    lu.assertNotStrContains(slurp(FAKE_REPO .. "\\" .. rel), "\r", rel .. " 里还有 CR")
  end
end

function TestSyncTransport:test_data_dir_is_mirrored_recursively()
  lu.assertEquals(slurp(FAKE_REPO .. "\\data\\FontData.lua"), "-- 字体\n")
  lu.assertEquals(slurp(FAKE_REPO .. "\\data\\Prefab.lua"), "-- 预制\n")
  lu.assertEquals(slurp(FAKE_REPO .. "\\data\\sub\\Nested.lua"), "-- 嵌套\n")
end

function TestSyncTransport:test_stale_repo_files_are_deleted()
  lu.assertFalse(shell.exists(FAKE_REPO .. "\\data\\Stale.lua"), "stale 文件没被抹掉")
  lu.assertStrContains(self.out, "delete data/Stale.lua")
end

function TestSyncTransport:test_write_is_reported()
  lu.assertStrContains(self.out, "write data/Prefab.lua")
end

-- 宿主目录是源，sync 一个字节都不许往回写；非回同步内容（unit_scripts/ 等）不进仓库。
function TestSyncTransport:test_host_side_is_untouched()
  lu.assertEquals(slurp(HOST .. "\\eggy.json"), '{\r\n  "projectName": "fixture"\r\n}\r\n')
  lu.assertTrue(shell.exists(HOST .. "\\unit_scripts\\keep.lua"))
  lu.assertFalse(shell.exists(FAKE_REPO .. "\\unit_scripts"), "宿主侧非回同步内容进了仓库")
end

function TestSyncTransport:test_unrelated_repo_content_is_untouched()
  lu.assertEquals(slurp(FAKE_REPO .. "\\server\\main.lua"), "-- 仓库自有内容\n")
end

TestSyncIdempotent = {}

function TestSyncIdempotent:setUp()
  seed_and_sync()
  self.out, self.code = run_sync(nil)
end

function TestSyncIdempotent:tearDown()
  rmrf(ROOT)
  rmrf(OUT)
end

-- 幂等：内容没变时不产生改动，第二轮没有写入也没有删除。
function TestSyncIdempotent:test_second_run_changes_nothing()
  lu.assertEquals(self.code, 0, "sync 输出:\n" .. self.out)
  lu.assertStrContains(self.out, "0 写入, 0 删除,")
  lu.assertNotStrContains(self.out, "write ")
  lu.assertNotStrContains(self.out, "delete ")
end

-- 缺一个源就整体不写：错误可读，仓库侧保持原样。
TestSyncMissingSource = {}

function TestSyncMissingSource:setUp()
  rmrf(ROOT)
  rmrf(OUT)
  write_host("eggy.json", "{}\r\n")
  write_host("EggyAPI.lua", "-- 存根\r\n")
  write_host("data\\FontData.lua", "-- 字体\r\n")
  write_repo("eggy.json", "sentinel\n")
  write_repo("data\\Stale.lua", "-- 还活着\n")
  self.out, self.code = run_sync(nil)
end

function TestSyncMissingSource:tearDown()
  rmrf(ROOT)
  rmrf(OUT)
end

function TestSyncMissingSource:test_missing_source_is_a_business_failure()
  lu.assertEquals(self.code, 1, self.out)
  lu.assertStrContains(self.out, "EggyEditorAPI.lua")
end

function TestSyncMissingSource:test_nothing_is_written()
  lu.assertEquals(slurp(FAKE_REPO .. "\\eggy.json"), "sentinel\n")
  lu.assertFalse(shell.exists(FAKE_REPO .. "\\data\\FontData.lua"), "缺源还落了半截")
  lu.assertTrue(shell.exists(FAKE_REPO .. "\\data\\Stale.lua"), "缺源还删了文件")
end

TestSyncCli = {}

function TestSyncCli:setUp()
  rmrf(ROOT)
  code_of("md " .. shell.q(FAKE_REPO) .. " >nul 2>&1")
end

function TestSyncCli:tearDown()
  rmrf(ROOT)
  rmrf(OUT)
end

function TestSyncCli:test_help_is_a_success()
  local out, code = run_sync("--help")
  lu.assertEquals(code, 0, out)
  lu.assertStrContains(out, "sync")
end

function TestSyncCli:test_extra_argument_is_a_usage_error()
  local out, code = run_sync("extra")
  lu.assertEquals(code, 2, out)
  lu.assertStrContains(out, "未知参数")
end

-- 宿主目录不存在是业务失败（1），不是用法错误（2）。
function TestSyncCli:test_missing_workspace_is_a_business_failure()
  local out, code = run_sync(nil, nil)
  lu.assertEquals(code, 1, out)
  lu.assertStrContains(out, "编辑器宿主目录不存在")
end

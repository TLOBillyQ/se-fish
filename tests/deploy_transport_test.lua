-- 传输组的回归护栏：镜像与 --clean 的断言都从 CLI 那一侧（真 Lua 子进程 +
-- EGGY_WORKSPACE 指向临时工作区）打进去，断言外部行为——镜像后的文件树、没被碰过的
-- 非自有内容、退出码；不断言内部函数调用。编辑器不在场也要跑绿：临时工作区没有
-- eggy.json，deploy 的编辑器收尾自己跳过；带编辑器的真机收尾由 acceptance 覆盖。
-- 收尾里的纯文本解析（changelist）没法从 CLI 侧造出真编辑器场景，单独直测。
local lu = require("luaunit")
local finalize = require("tools.editor_finalize")
local shell = require("tools.win_shell")

local WS = "tmp/deploy-transport-test"
local OUT = "tmp/deploy-transport-test.out"
local CLI = "tools/cli.lua"

local function code_of(cmd)
  local _, _, code = os.execute(cmd)
  return code
end

local function rmrf(path)
  code_of("if exist " .. shell.q(path) .. " rmdir /s /q " .. shell.q(path) .. " >nul 2>&1")
end

local function slurp(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local body = f:read("a")
  f:close()
  return body
end

local function write_file(path, body)
  local dir = path:match("^(.-)/[^/]*$")
  if dir then code_of("if not exist " .. shell.q(dir) .. " md " .. shell.q(dir) .. " >nul 2>&1") end
  local f = assert(io.open(path, "wb"), path .. " 建不出来")
  f:write(body)
  f:close()
end

local function write(rel, body)
  write_file(WS .. "/" .. rel, body)
end

-- 跑 CLI 的 lua 解释器：取启动本 runner 的那个（Lua 把解释器路径记在 arg[-1]），不走 PATH 猜。
local function lua_bin()
  local exe = arg and arg[-1]
  if type(exe) == "string" and exe ~= "" and not exe:match("^%-") then return exe end
  return "lua"
end

-- 真 CLI 子进程，拿回 stdout+stderr 与退出码。
-- 前缀那条 `cd .` 不是装饰：重定向要跟命令走（写在 `&` 链末尾），而命令行一旦以引号
-- 开头，cmd /c 会按解析规则 2 剥掉首尾引号、把命令行解析坏（见 tools/win_shell.lua）。
local function run_cli(args, env)
  local parts = { "cd ." }
  for _, kv in ipairs(env or {}) do parts[#parts + 1] = 'set "' .. kv .. '"' end
  parts[#parts + 1] = "> " .. shell.q(OUT) .. " 2>&1 " .. shell.q(lua_bin()) .. " " .. CLI .. " " .. args
  local code = code_of(table.concat(parts, " & "))
  return slurp(OUT) or "", code
end

-- 临时工作区：非自有内容齐活，自有子树里埋一个幽灵文件。
local function seed_and_deploy()
  rmrf(WS)
  code_of("md " .. shell.q(WS) .. " >nul 2>&1")
  write("EggyAPI.lua", "-- 宿主目录里的 API 存根\n")
  write("data/FontData.lua", "-- 编辑器侧产物\n")
  write("client/host_only/keep.lua", "-- 只活在宿主目录里的一级子树\n")
  write("server/Mgr/Ghost.lua", "-- 自有子树里的幽灵文件\n")
  return run_cli("deploy", { "EGGY_WORKSPACE=tmp/deploy-transport-test" })
end

TestDeployTransport = {}

function TestDeployTransport:setUp()
  self.out, self.code = seed_and_deploy()
end

function TestDeployTransport:tearDown()
  rmrf(WS)
end

function TestDeployTransport:test_mirror_succeeds()
  lu.assertEquals(self.code, 0, "deploy 输出:\n" .. self.out)
  lu.assertStrContains(self.out, "deploy ok")
end

function TestDeployTransport:test_every_target_is_mirrored_via_robocopy()
  local targets = 0
  for line in self.out:gmatch("[^\r\n]+") do
    if line:match("^%S+/%S+: %d+ 个文件 %(") then
      targets = targets + 1
      lu.assertStrContains(line, "(robocopy)")
    end
  end
  lu.assertTrue(targets > 0, "部署没有报告任何子树:\n" .. self.out)
end

function TestDeployTransport:test_mirror_lands_the_repo_tree()
  for _, rel in ipairs({ "client/main.lua", "common/Util.lua", "server/main.lua",
                         "server/Mgr/MgrFish.lua", "server/Mgr/MgrAbility.lua",
                         "server/packages/ability_system/api.lua",
                         "client/ScreenHandlers/ScreenFishing.lua" }) do
    lu.assertTrue(shell.exists(WS .. "/" .. rel), rel .. " 未落到宿主目录")
  end
end

function TestDeployTransport:test_mirror_is_byte_identical()
  for _, rel in ipairs({ "common/GameCfg.lua", "server/_trigger/GlobalVars.lua" }) do
    lu.assertEquals(slurp(WS .. "/" .. rel), slurp(rel), rel .. " 落盘后内容不一致")
  end
end

-- 宿主目录里的非自有内容（eggy.json、API 存根、data/、编辑器生成物）与仓库根白名单之外
-- 的内容同规则：不进部署计划就不许碰。
function TestDeployTransport:test_non_owned_content_is_untouched()
  for _, rel in ipairs({ "EggyAPI.lua", "data/FontData.lua", "client/host_only/keep.lua" }) do
    lu.assertTrue(shell.exists(WS .. "/" .. rel), rel .. " 被 deploy 碰掉了")
  end
end

-- 重置粒度是一级子树：自有子树内部按镜像纪律抹平，宿主目录多出来的整棵子树则保留。
function TestDeployTransport:test_owned_subtree_loses_ghost_files()
  lu.assertFalse(shell.exists(WS .. "/server/Mgr/Ghost.lua"), "自有子树里的幽灵文件没被抹掉")
end

function TestDeployTransport:test_editor_finalization_is_skipped_without_a_binding()
  lu.assertStrContains(self.out, "编辑器收尾跳过")
  lu.assertStrContains(self.out, "没有 eggy.json")
  lu.assertNotStrContains(self.out, "validate")
end

TestDeployClean = {}

function TestDeployClean:setUp()
  self.out, self.code = seed_and_deploy()
  self.out, self.code = run_cli("deploy --clean", { "EGGY_WORKSPACE=tmp/deploy-transport-test" })
end

function TestDeployClean:tearDown()
  rmrf(WS)
end

function TestDeployClean:test_clean_succeeds_and_reports_removals()
  lu.assertEquals(self.code, 0, "deploy --clean 输出:\n" .. self.out)
  lu.assertStrContains(self.out, "deploy --clean ok")
  lu.assertStrContains(self.out, "removed client/main.lua")
  lu.assertStrContains(self.out, "removed server/Mgr")
end

function TestDeployClean:test_clean_drops_owned_subtrees()
  -- 目录与文件都问 shell.exists：io.open 对目录一律失败，拿它断言「目录没了」会假绿。
  for _, rel in ipairs({ "client/main.lua", "common/Util.lua", "server/main.lua", "server/Mgr" }) do
    lu.assertFalse(shell.exists(WS .. "/" .. rel), rel .. " 没被 --clean 清掉")
  end
end

function TestDeployClean:test_clean_leaves_non_owned_content()
  for _, rel in ipairs({ "EggyAPI.lua", "data/FontData.lua", "client/host_only/keep.lua" }) do
    lu.assertTrue(shell.exists(WS .. "/" .. rel), rel .. " 被 --clean 误伤")
  end
end

-- 只清不装：清空后的工作区绝不能再去 push，否则等于把地图侧代码删空。
function TestDeployClean:test_clean_never_runs_the_editor_finalization()
  lu.assertNotStrContains(self.out, "validate")
  lu.assertNotStrContains(self.out, "code push")
end

TestDeployCli = {}

function TestDeployCli:test_help_lists_the_closed_command_set()
  local out, code = run_cli("--help")
  lu.assertEquals(code, 0, out)
  lu.assertStrContains(out, "deploy")
end

function TestDeployCli:test_unknown_subcommand_is_a_usage_error()
  local _, code = run_cli("nope")
  lu.assertEquals(code, 2)
end

function TestDeployCli:test_unknown_option_is_a_usage_error()
  local _, code = run_cli("deploy --nope")
  lu.assertEquals(code, 2)
end

-- 宿主目录不存在是业务失败（1），不是用法错误（2）。
function TestDeployCli:test_missing_workspace_is_a_business_failure()
  local out, code = run_cli("deploy", { "EGGY_WORKSPACE=tmp/__no_such_workspace__" })
  lu.assertEquals(code, 1, out)
  lu.assertStrContains(out, "编辑器宿主目录不存在")
end

-- editor-cli.exe 不在也是跳过 + 退出码 0。用假 USERPROFILE 造出「没有
-- %USERPROFILE%\.eggitor\cli\editor-cli.exe」的环境，本机装没装 editor-cli 都测得出。
function TestDeployCli:test_missing_editor_cli_is_a_skip_not_a_failure()
  local home, ws = "tmp/deploy-fake-home", "tmp/deploy-bound-workspace"
  rmrf(home)
  rmrf(ws)
  code_of("md " .. shell.q(home) .. " >nul 2>&1")
  -- 工作区带 eggy.json：跳过理由是 exe 不在，而不是工作区没绑定
  write_file(ws .. "/eggy.json", '{ "projectName": "fixture" }\n')

  local out, code = run_cli("deploy", { "EGGY_WORKSPACE=" .. ws, "USERPROFILE=" .. shell.win(home) })
  lu.assertEquals(code, 0, out)
  lu.assertStrContains(out, "未找到 editor-cli.exe")

  rmrf(home)
  rmrf(ws)
end

-- 收尾里的纯文本解析：编辑器在场时的「有差异才 push、push 后复核」全靠它判。
TestEditorFinalize = {}

-- `editor-cli code diff` 文本里的那一行：
-- changelist: only-local=0 differs=2 only-on-map=86 unchanged=3
local DIFF_TEXT = table.concat({
  "map: C:\\maps\\YXF__pc (id=6aab8e60ee615830184f4963)",
  "codec=mm channel=offline",
  "changelist: only-local=1 differs=2 only-on-map=86 unchanged=3",
  "  only-on-map  client/main.lua",
}, "\n")

function TestEditorFinalize:test_changelist_counts_are_parsed()
  local cl = finalize.parse_changelist(DIFF_TEXT)
  lu.assertEquals(cl["only-local"], 1)
  lu.assertEquals(cl["differs"], 2)
  lu.assertEquals(cl["only-on-map"], 86)
  lu.assertEquals(cl["unchanged"], 3)
end

function TestEditorFinalize:test_no_changelist_line_means_no_verdict()
  lu.assertNil(finalize.parse_changelist("No valid eggy.json found from 'C:\\ws'\n  next: code init\n"))
  lu.assertNil(finalize.parse_changelist(""))
end

-- 落后 = 本地独有 + 两侧不同；地图侧多出的不算（deploy 不删）。
function TestEditorFinalize:test_behind_counts_only_what_the_map_is_missing()
  lu.assertEquals(finalize.behind_count({ ["only-local"] = 1, differs = 2,
    ["only-on-map"] = 86, unchanged = 3 }), 3)
  lu.assertEquals(finalize.behind_count({ ["only-on-map"] = 86, unchanged = 3 }), 0)
end

-- 全新树（没有 tmp/ 的树：全新 clone、`git worktree add` 出来的树）与「镜像说成功却没搬字节」
-- 的回归护栏，对应 issue #21。
--
-- issue #21 的链路：镜像命令把 robocopy 输出重定向到 cwd 下的 tmp/robocopy.log，而 tmp/ 原来
-- 只有「捕获输出」那条路径会顺手建（tmp/ 是 gitignored，全新树里没有）→ cmd 报 The system
-- cannot find the path specified.、robocopy 根本没执行、退出码 1 被 code < 8 当成 robocopy 的
-- 成功码 → 零字节搬运却照旧打印 deploy ok。两条护栏：重定向落点由写日志的那一方保证存在；
-- 镜像后用目标侧文件集合比对兜住「退出码说成功但没搬字节」。
--
-- 断言都从 CLI 那一侧打进去（真 Lua 子进程 + EGGY_WORKSPACE 指临时工作区），不断言内部调用。
local lu = require("luaunit")
local deploy = require("tools.deploy")
local plan = require("tools.deploy_plan")
local shell = require("tools.win_shell")

-- 全新 clone 的替身树与临时宿主目录；树里故意没有 tmp/ —— 镜像命令的重定向落点必须自己建出来，
-- 不能指望前一跑留下的目录。
local TREE = "tmp/deploy-fresh-tree"
local WS = "tmp/deploy-fresh-tree-ws"
local OUT = "tmp/deploy-fresh-tree.out"

local function code_of(cmd)
  local _, _, code = os.execute(cmd)
  return code
end

local function rmrf(path)
  code_of("if exist " .. shell.q(path) .. " rmdir /s /q " .. shell.q(path) .. " >nul 2>&1")
end

local function rmf(path)
  code_of("if exist " .. shell.q(path) .. " del /f /q " .. shell.q(path) .. " >nul 2>&1")
end

local function mkdir(path)
  code_of("if not exist " .. shell.q(path) .. " md " .. shell.q(path) .. " >nul 2>&1")
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
  if dir then mkdir(dir) end
  local f = assert(io.open(path, "wb"), path .. " 建不出来")
  f:write(body)
  f:close()
end

local function copy_file(from, to)
  local body = slurp(from)
  assert(body, from .. " 读不出来")
  write_file(to, body)
end

-- 跑 CLI 的 lua 解释器：取启动本 runner 的那个（Lua 把解释器路径记在 arg[-1]），不走 PATH 猜。
local function lua_bin()
  local exe = arg and arg[-1]
  if type(exe) == "string" and exe ~= "" and not exe:match("^%-") then return exe end
  return "lua"
end

-- 全新 clone 的替身：tools/ 与三端（client/ common/ server/）照着仓库检出整棵复制一份，
-- 树里没有 tmp/（也不建）。复制而不是链接：万一 deploy 写错方向，坏的是 tmp/ 下的副本。
local function build_fresh_tree()
  rmrf(TREE)
  mkdir(TREE)
  for _, rel in ipairs(shell.list_files("tools") or {}) do
    copy_file("tools/" .. rel, TREE .. "/tools/" .. rel)
  end
  for _, realm in ipairs(plan.REALMS) do
    for _, rel in ipairs(shell.list_files(realm) or {}) do
      copy_file(realm .. "/" .. rel, TREE .. "/" .. realm .. "/" .. rel)
    end
  end
end

-- 在树里跑真 CLI：先 cd 进树（同盘相对 cd 即可），再起 lua。
-- 输出文件写成 `%CD%` 展开的绝对路径：整行在 cd 之前就展开好了，落点与树里的相对路径无关——
-- 树里恰恰没有 tmp/，测试自己的输出文件不能也踩这个坑（命令行开头那条 `cd .`、「重定向写在
-- 命令前面」的规矩见 tools/win_shell.lua）。
local function run_cli_in_tree(env, args)
  local parts = { "cd " .. shell.win(TREE) }
  for _, kv in ipairs(env or {}) do parts[#parts + 1] = 'set "' .. kv .. '"' end
  parts[#parts + 1] = '> "%CD%\\' .. shell.win(OUT) .. '" 2>&1 '
    .. shell.q(lua_bin()) .. " tools/cli.lua " .. args
  local code = code_of(table.concat(parts, " & "))
  return slurp(OUT) or "", code
end

TestFreshTreeDeploy = {}

function TestFreshTreeDeploy:setUp()
  build_fresh_tree()
  rmrf(WS)
  mkdir(WS)
  self.out, self.code = run_cli_in_tree({ "EGGY_WORKSPACE=../deploy-fresh-tree-ws" }, "deploy")
end

function TestFreshTreeDeploy:tearDown()
  rmrf(TREE)
  rmrf(WS)
  rmf(OUT)
end

-- 前置校验：这条不跑 deploy（setUp 已经把部署跑过了），所以自己重建一次干净的替身树。
function TestFreshTreeDeploy:test_the_stand_in_tree_really_has_no_tmp_dir()
  build_fresh_tree()
  lu.assertFalse(shell.is_dir(TREE .. "/tmp"), "前置：全新树的替身里不该有 tmp/")
end

function TestFreshTreeDeploy:test_first_deploy_lands_every_file()
  lu.assertEquals(self.code, 0, "deploy 输出:\n" .. self.out)
  lu.assertStrContains(self.out, "deploy ok")
  for _, realm in ipairs(plan.REALMS) do
    local src, dst = shell.list_files(TREE .. "/" .. realm), shell.list_files(WS .. "/" .. realm)
    lu.assertNotNil(src, "替身树里没有 " .. realm)
    lu.assertEquals(dst, src, realm .. " 落盘后的文件集合与源不一致")
    for _, rel in ipairs(src) do
      lu.assertEquals(slurp(WS .. "/" .. realm .. "/" .. rel),
        slurp(TREE .. "/" .. realm .. "/" .. rel), realm .. "/" .. rel .. " 落盘后内容不一致")
    end
  end

  -- 进度行的 N 是目标侧实际文件数（旧实现数的是源，容易在空转时看着一切正常）。
  -- 同一次部署不重复起进程，所以这一条搭在上面那次运行的输出上。
  local printed = {}
  for line in self.out:gmatch("[^\r\n]+") do
    local rel, n = line:match("^(%S+/%S+): (%d+) 个文件 %(robocopy%)$")
    if rel then printed[rel] = tonumber(n) end
  end
  local targets = plan.targets(WS, shell.list_entries)
  lu.assertTrue(#targets > 0, "部署计划是空的")
  for _, t in ipairs(targets) do
    local want = t.dir and #(shell.list_files(t.dst) or {}) or 1
    lu.assertEquals(printed[t.rel], want, t.rel .. " 的进度行不是目标侧文件数")
  end
end

-- 重定向落点的约定是 cwd 下的 tmp/（见 tools/win_shell.lua）：全新树里首次镜像必须自己把它
-- 建出来。没有这一条，命令的重定向会被 cmd 挡掉，整条 deploy 又回到静默空转。
function TestFreshTreeDeploy:test_mirror_creates_the_dir_it_redirects_into()
  lu.assertTrue(shell.is_dir(TREE .. "/tmp"), "镜像命令没有建出自己的日志落点 tmp/")
end

-- 假 robocopy 的两副面孔（都用横幅与退出码 3 冒充成功——issue #21 那种「退出码说成功、字节
-- 没动」的现场；真 robocopy 每次都会打横幅，除非 /NJH）：
--   LIE_NOTHING  一个字节都不搬，deploy 得在第一个目标就响亮失败；
--   LIE_TOP_ONLY 只搬一级文件、子目录整棵漏掉，deploy 得靠目录目标的文件集合比对兜住。
local LIE_BIN = "tmp/deploy-lying-robocopy-bin"
local LIE_WS = "tmp/deploy-lying-robocopy-ws"
local LIE_OUT = "tmp/deploy-lying-robocopy.out"

local LIE_BANNER = {
  "@echo off",
  "echo -------------------------------------------------------------------------------",
  "echo    ROBOCOPY     ::     Robust File Copy for Windows",
  "echo -------------------------------------------------------------------------------",
}

local LIE_NOTHING = table.concat(LIE_BANNER, "\r\n") .. "\r\nexit /b 3\r\n"
-- 参数形状与 tools/win_shell.mirror_cmd 一致：目录目标 %1=src %2=dst %3=/MIR，单文件目标
-- %1=src 目录 %2=dst 目录 %3=文件名。
local LIE_TOP_ONLY = table.concat(LIE_BANNER, "\r\n") .. table.concat({
  "",
  'if not exist "%~2" md "%~2" >nul 2>&1',
  'if not "%~3"=="/MIR" goto onefile',
  'copy /y "%~1\\*.*" "%~2\\" >nul 2>&1',
  "goto done",
  ":onefile",
  'copy /y "%~1\\%~3" "%~2\\" >nul 2>&1',
  ":done",
  "exit /b 3",
  "",
}, "\r\n")

-- 部署计划里第一个「子树带子目录」的目录目标：假 robocopy 只搬一级文件，到它才会露馅
-- （没有子目录的目录目标会被整棵搬完，deploy 也就走过去了）。
local function first_nested_target(ws)
  for _, t in ipairs(plan.targets(ws, shell.list_entries)) do
    if t.dir then
      for _, rel in ipairs(shell.list_files(t.src) or {}) do
        if rel:find("/") then return t, rel end
      end
    end
  end
end

-- 装一副假 robocopy 进临时 bin，把 PATH 前置后跑一次真 deploy，拿回输出与退出码。
local function deploy_with_fake_robocopy(payload)
  rmrf(LIE_BIN)
  mkdir(LIE_BIN)
  write_file(LIE_BIN .. "/robocopy.cmd", payload)
  rmrf(LIE_WS)
  mkdir(LIE_WS)
  local parts = { "cd ." }
  -- PATH 前置：这个临时 bin 里的 robocopy.cmd 会盖住 System32 的真 robocopy（只对本次子进程生效）
  parts[#parts + 1] = 'set "PATH=' .. shell.win(LIE_BIN) .. ';%PATH%"'
  parts[#parts + 1] = 'set "EGGY_WORKSPACE=' .. LIE_WS .. '"'
  parts[#parts + 1] = "> " .. shell.q(LIE_OUT) .. " 2>&1 " .. shell.q(lua_bin()) .. " tools/cli.lua deploy"
  local code = code_of(table.concat(parts, " & "))
  return slurp(LIE_OUT) or "", code
end

TestDeployLyingMirror = {}

function TestDeployLyingMirror:tearDown()
  rmrf(LIE_BIN)
  rmrf(LIE_WS)
  rmf(LIE_OUT)
end

function TestDeployLyingMirror:test_robocopy_that_copies_nothing_is_a_loud_failure()
  local out, code = deploy_with_fake_robocopy(LIE_NOTHING)
  local targets = plan.targets(LIE_WS, shell.list_entries)
  lu.assertEquals(code, 1, "deploy 输出:\n" .. out)
  lu.assertNotStrContains(out, "deploy ok")
  lu.assertStrContains(out, targets[1].rel)
  lu.assertStrContains(out, "命令: robocopy")
  lu.assertStrContains(out, "不一致")
end

function TestDeployLyingMirror:test_robocopy_that_skips_subdirs_is_a_loud_failure()
  local out, code = deploy_with_fake_robocopy(LIE_TOP_ONLY)
  local t, nested = first_nested_target(LIE_WS)
  lu.assertNotNil(t, "部署计划里没有一个带子目录的目录目标")
  lu.assertEquals(code, 1, "deploy 输出:\n" .. out)
  lu.assertNotStrContains(out, "deploy ok")
  lu.assertStrContains(out, t.rel)
  -- 前提：一级文件搬到了（所以 deploy 才走到这个目标），嵌套文件一个没到。
  lu.assertFalse(shell.exists(t.dst .. "/" .. nested), "嵌套文件也搬过去了，测试前提不成立")
  lu.assertStrContains(out, "目标侧缺")
end

-- 真失败：目标侧落点被占成一个文件，robocopy 报 ERROR 267、退出码 16。
-- 就在那棵没有 tmp/ 的全新树里跑——「没有 tmp/」+「真失败」得同时成立：打不出 deploy ok、
-- 退出码 1、输出里能看到命令原文与受影响的目标。
TestDeployBlockedTarget = {}

function TestDeployBlockedTarget:setUp()
  build_fresh_tree()
  rmrf(WS)
  mkdir(WS)
  local blocked
  for _, t in ipairs(plan.targets(WS, shell.list_entries)) do
    if t.dir then blocked = t; break end
  end
  lu.assertNotNil(blocked, "部署计划里一个目录目标都没有")
  write_file(WS .. "/" .. blocked.rel, "占位文件：目标侧落点不是目录\n")
  self.blocked = blocked
  self.out, self.code = run_cli_in_tree({ "EGGY_WORKSPACE=../deploy-fresh-tree-ws" }, "deploy")
end

function TestDeployBlockedTarget:tearDown()
  rmrf(TREE)
  rmrf(WS)
  rmf(OUT)
end

function TestDeployBlockedTarget:test_blocked_target_is_a_loud_failure()
  lu.assertEquals(self.code, 1, "deploy 输出:\n" .. self.out)
  lu.assertNotStrContains(self.out, "deploy ok")
  -- 失败之前有目标真的搬成了（进度行是每个目标核验通过之后才打的）：证明这次是「跑起来了、
  -- 到某个目标才失败」，不是命令压根没执行——没有 tmp/ 时重定向落点建不出来就是那种静默空转。
  local landed = 0
  for line in self.out:gmatch("[^\r\n]+") do
    if line:match("^%S+/%S+: %d+ 个文件 %(robocopy%)$") then landed = landed + 1 end
  end
  lu.assertTrue(landed > 0, "失败之前一个目标都没搬成，看不出 deploy 跑起来过:\n" .. self.out)
  lu.assertStrContains(self.out, self.blocked.rel)
  lu.assertStrContains(self.out, "命令: robocopy")
  lu.assertStrContains(self.out, "退出码")
end

-- 源/目标文件集合比对：镜像说成功之后，还得拿目标侧真实文件集合对一遍。
TestDeployFileSetDiff = {}

function TestDeployFileSetDiff:test_identical_sets_have_no_diff()
  local missing, extra = deploy.file_set_diff({ "a.lua", "b.lua" }, { "b.lua", "a.lua" })
  lu.assertEquals(missing, {})
  lu.assertEquals(extra, {})
end

function TestDeployFileSetDiff:test_missing_and_extra_are_reported_sorted()
  local missing, extra = deploy.file_set_diff(
    { "b.lua", "a.lua", "c.lua" }, { "c.lua", "z.lua", "b.lua" })
  lu.assertEquals(missing, { "a.lua" })
  lu.assertEquals(extra, { "z.lua" })
end

function TestDeployFileSetDiff:test_nil_lists_count_as_empty()
  local missing, extra = deploy.file_set_diff(nil, { "a.lua" })
  lu.assertEquals(missing, {})
  lu.assertEquals(extra, { "a.lua" })
  missing, extra = deploy.file_set_diff({ "a.lua" }, nil)
  lu.assertEquals(missing, { "a.lua" })
  lu.assertEquals(extra, {})
end

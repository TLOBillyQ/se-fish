-- deploy 子命令：把仓库的三端一级子树字节镜像进编辑器宿主目录。
-- 在仓库根执行 `lua tools/cli.lua deploy`；直接 `lua tools/deploy.lua` 亦可。
-- 反方向回同步见 tools/sync.lua；先例：se-defense tools/deploy.lua（WSL 接缝版）。
--
-- 本模块只管搬字节：哪些子树归本仓库（部署规则）在 tools/deploy_plan 回答，宿主目录在哪
-- 在 tools/eggy_workspace，Windows 侧怎么跑在 tools/win_shell，编辑器收尾在
-- tools/editor_finalize。
--
-- 部署树：<端>/<child>/... → 宿主目录 <端>/<child>/...（端 = 白名单 client/common/server，
-- 官方强制的 SE 工作区根，仓库根直接对齐；重置粒度是每端下的一级子树）。
-- 仓库根白名单之外的内容（docs/、tools/、tests/ 等）不部署；宿主目录其余内容
-- （eggy.json、两份 API 存根、data/、unit_scripts/、编辑器生成物）不碰。

package.path = "./?.lua;./?/init.lua;" .. package.path

local workspace = require("tools.eggy_workspace")
local plan = require("tools.deploy_plan")
local shell = require("tools.win_shell")
local finalize = require("tools.editor_finalize")

local M = {}

-- 业务失败统一 error 出去，由 main 收成 stderr + 退出码 1。
local function fail(msg)
  error("deploy: " .. msg, 0)
end

local function require_dir(path, msg)
  if not shell.is_dir(path) then
    fail(msg .. "（缺 " .. path .. "）")
  end
end

function M.usage()
  return table.concat({
    "用法: lua tools/cli.lua deploy",
    "",
    "把仓库根 <端>/<child> 字节镜像进编辑器宿主目录 <端>/<child>（先重置目标子树）。",
    "端为白名单 " .. table.concat(plan.REALMS, "/") .. "（官方强制的工作区根，仓库根直接对齐）；",
    "仓库根其他内容不部署，宿主目录其余内容不碰。",
    "传输一律 robocopy /MIR 增量镜像（退出码 0–7 成功、>= 8 失败，失败即整条命令失败），",
    "镜像完自动做编辑器收尾：code validate → code diff → 有差异才 push → 复核；",
    "editor-cli 不在或编辑器没开该地图时打印跳过并以退出码 0 结束（磁盘已是最新）。",
    "地图侧多出的文件只提示，不删。",
    "宿主目录默认 " .. workspace.DEFAULT .. "，环境变量 EGGY_WORKSPACE 可覆盖。",
    "",
    "选项：",
    "  --clean   只清不装：删掉宿主目录里本仓库拥有的全部子树，不拷贝、不做收尾。",
    "            宿主目录其余内容（eggy.json、data/ 等）不碰。",
    "",
  }, "\n") .. "\n"
end

local function run_deploy(clean_only)
  local WS = workspace.resolve()
  for _, realm in ipairs(plan.REALMS) do
    require_dir(realm, "本仓库缺部署根 " .. realm)
  end
  require_dir(WS, "编辑器宿主目录不存在；可用环境变量 EGGY_WORKSPACE 覆盖")

  local targets = plan.targets(WS, shell.list_entries)

  if clean_only then
    for _, t in ipairs(targets) do
      shell.remove(t)
      print("removed " .. t.rel)
    end
    print("deploy --clean ok → " .. WS)
    return
  end

  for _, t in ipairs(targets) do
    local ok, code, detail = shell.mirror(t)
    if not ok then
      detail = detail or ""
      fail("robocopy 失败（退出码 " .. tostring(code) .. "）: " .. t.rel
        .. (detail ~= "" and (":\n" .. detail) or ""))
    end
    print(t.rel .. ": " .. shell.file_count(t.src, t.dir) .. " 个文件 (robocopy)")
  end

  print("deploy ok → " .. WS)

  local ok, err = finalize.run(WS)
  if not ok then fail(err) end
end

-- 退出码：0 成功 / 1 业务失败 / 2 用法错误。
function M.main(args)
  args = args or {}
  local clean_only = false
  for _, a in ipairs(args) do
    if a == "--help" or a == "-h" then
      io.write(M.usage())
      return 0
    elseif a == "--clean" then
      clean_only = true
    else
      io.stderr:write("deploy: 未知参数: " .. a .. "\n")
      return 2
    end
  end
  local ok, err = pcall(run_deploy, clean_only)
  if not ok then
    io.stderr:write(tostring(err) .. "\n")
    return 1
  end
  return 0
end

if ... == "tools.deploy" then
  return M
end

os.exit(M.main(arg))

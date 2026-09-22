-- deploy 子命令：把仓库的三端一级子树字节镜像进编辑器宿主目录。
-- 在仓库根执行 `lua tools/cli.lua deploy`；直接 `lua tools/deploy.lua` 亦可。
-- 反方向回同步见 tools/sync.lua；先例：se-defense tools/deploy.lua（WSL 接缝版）。
--
-- 本模块只管搬字节并核验搬运结果：哪些子树归本仓库（部署规则）在 tools/deploy_plan 回答，
-- 宿主目录在哪在 tools/eggy_workspace，Windows 侧怎么跑在 tools/win_shell，编辑器收尾在
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
    "传输一律 robocopy /MIR 增量镜像；每个目标镜像完都拿源/目标的文件集合对一遍，",
    "命令没执行成、退出码 >= 8、或目标侧文件集合与源不一致，都算整条命令失败（退出码 1）；",
    "镜像完自动做编辑器收尾：code validate → code diff → 有差异才 push → 复核；",
    "editor-cli 不在或编辑器没开该地图时打印跳过并以退出码 0 结束（磁盘已是最新）。",
    "地图侧多出的文件只提示，不删。",
    "宿主目录默认 " .. workspace.DEFAULT .. "，环境变量 EGGY_WORKSPACE 可覆盖。",
    "",
    "选项：",
    "  --clean   只清不装：删掉宿主目录里本仓库拥有的全部子树，不拷贝、不做收尾。",
    "            宿主目录其余内容（eggy.json、data/ 等）不碰。",
    "            编辑器开着该地图时：宿主目录的删除不保证会反映进编辑器内存（实测有残留），",
    "            清地图侧要用 editor-cli code push --delete --yes。",
    "",
  }, "\n") .. "\n"
end

-- 源/目标文件集合差异（/ 分隔的相对路径清单，顺序无关）：missing = 源有目标无，extra = 目标有源无，
-- 两张清单都按名排序；nil 当空清单。robocopy 说成功之后靠它确认字节真的到了目标侧。
function M.file_set_diff(src, dst)
  local in_src, in_dst = {}, {}
  for _, path in ipairs(src or {}) do in_src[path] = true end
  for _, path in ipairs(dst or {}) do in_dst[path] = true end
  local missing, extra = {}, {}
  for path in pairs(in_src) do
    if not in_dst[path] then missing[#missing + 1] = path end
  end
  for path in pairs(in_dst) do
    if not in_src[path] then extra[#extra + 1] = path end
  end
  table.sort(missing)
  table.sort(extra)
  return missing, extra
end

-- 差异清单压成一行：最多列 5 个，多的用省略号收尾。
local function brief(paths)
  local head = {}
  for i = 1, math.min(#paths, 5) do head[i] = paths[i] end
  if #paths > #head then head[#head + 1] = "…" end
  return table.concat(head, ", ")
end

-- 单目标失败文案：目标、命令原文、退出码、原因（命令没执行 / 差异清单），失败时再带命令输出原文。
local function failure_text(t, cmd, code, notes, output)
  local lines = { "镜像失败: " .. t.rel, " 命令: " .. cmd, " 退出码: " .. tostring(code) }
  for _, note in ipairs(notes) do lines[#lines + 1] = " " .. note end
  if output and output ~= "" then lines[#lines + 1] = " 输出:\n" .. output end
  return table.concat(lines, "\n")
end

-- 镜像一个目标并核验搬运结果。两层护栏：
--   * tools/win_shell 的 mirror 保证命令真的执行过、且按 robocopy 口径成功（退出码 0–7）；
--   * 这里再对一遍源/目标的文件集合（/MIR 之后本该一模一样）。robocopy 说成功而字节没到齐
--     （命令被挡掉却回了 1、拷贝中途夭折、残留文件）在这层变成失败，不再落成一句 deploy ok。
-- 返回 目标侧文件数 或 nil, 失败文案。
local function mirror_and_verify(t)
  local ok, res = shell.mirror(t)
  if not ok then
    local notes = {}
    if not res.executed then notes[#notes + 1] = "命令没有执行过（重定向落点建不出来？）" end
    return nil, failure_text(t, res.cmd, res.code, notes, res.output)
  end

  if t.dir then
    local src, dst = shell.list_files(t.src), shell.list_files(t.dst)
    if not src then return nil, failure_text(t, shell.mirror_cmd(t), res,
      { "源目录读不出来: " .. t.src }, nil) end
    local missing, extra = M.file_set_diff(src, dst)
    local notes = {}
    if #missing > 0 or #extra > 0 then
      notes[#notes + 1] = "镜像结果与源不一致"
      if #missing > 0 then notes[#notes + 1] = "目标侧缺 " .. #missing .. " 个文件: " .. brief(missing) end
      if #extra > 0 then notes[#notes + 1] = "目标侧多出 " .. #extra .. " 个文件: " .. brief(extra) end
      return nil, failure_text(t, shell.mirror_cmd(t), res, notes, nil)
    end
    return #dst
  end

  if not shell.exists(t.dst) then
    return nil, failure_text(t, shell.mirror_cmd(t), res,
      { "镜像结果与源不一致", "目标侧缺 1 个文件: " .. t.src:match("[^/]+$") }, nil)
  end
  return 1
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
    local n, err = mirror_and_verify(t)
    if not n then fail(err) end
    print(t.rel .. ": " .. n .. " 个文件 (robocopy)")
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

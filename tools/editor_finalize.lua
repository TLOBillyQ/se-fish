-- 部署收尾：镜像落盘后只执行 code validate → code diff，核对编辑器内代码。
-- CLI 的 excludePatterns 对 code push 不生效；为保留宿主 packages，收尾不执行全工作区 push。
-- 有本地新增或不同文件时报告尚未同步；地图侧独有文件只提示，保留已有内容。
--
-- 本模块依赖正在运行的编辑器与 editor-cli.exe；CLI 缺失、宿主未绑定或地图未打开时
-- 打印跳过，磁盘镜像仍算完成，但不宣称编辑器内代码已同步。
-- 宿主必须有自己的 eggy.json，避免 CLI 向上下层目录寻找绑定而读到别的工程。
--
-- 纯解析部分（parse_changelist / behind_count）单独导出，可脱离编辑器测。
local shell = require("tools.win_shell")

local M = {}

local EXE_REL = [[.eggitor\cli\editor-cli.exe]]

local function exe_path()
  local home = os.getenv("USERPROFILE")
  if not home then return nil end
  return home .. "\\" .. EXE_REL
end

-- 跑一条 code 子命令。必须给 --workspace：不给就按进程 cwd 找绑定，而 cwd 是仓库根。
-- 不用 cd 进宿主目录是为了不让输出重定向跟着切换目录跑。
local function editor_cli(exe, ws, argline)
  return shell.capture(shell.q(exe) .. " " .. argline .. " --workspace " .. shell.q(ws))
end

-- 解析 `code diff` 文本里的 changelist 行：
-- changelist: only-local=N differs=N only-on-map=N unchanged=N
function M.parse_changelist(out)
  local line = out:match("changelist:[^\r\n]*")
  if not line then return nil end
  local cl = {}
  for k, v in line:gmatch("([%w%-]+)=(%d+)") do cl[k] = tonumber(v) end
  return cl
end

-- 落后编辑器的文件数：只有本地独有与两侧不同算落后，地图侧多出的不算（deploy 不删）。
function M.behind_count(cl)
  return (cl["only-local"] or 0) + (cl["differs"] or 0)
end

-- 返回 true 表示收尾完成（含跳过）；失败返回 nil, 原因。
function M.run(ws)
  local exe = exe_path()
  if not exe then
    print("编辑器收尾跳过: 环境变量 USERPROFILE 不在，定位不了 editor-cli.exe")
    return true
  end
  if not shell.exists(exe) then
    print("编辑器收尾跳过: 未找到 editor-cli.exe（" .. exe .. "）")
    return true
  end
  if not shell.exists(ws .. "/eggy.json") then
    print("编辑器收尾跳过: 宿主目录没有 eggy.json（" .. shell.win(ws) .. " 不是编辑器绑定的 Lua 工程）")
    return true
  end

  local code, out = editor_cli(exe, ws, "code validate")
  if not out:find("validate: OK", 1, true) then
    return nil, "code validate 未通过（退出码 " .. tostring(code) .. "）:\n" .. out
  end
  print("validate: OK")

  code, out = editor_cli(exe, ws, "code diff")
  local cl = M.parse_changelist(out)
  if not cl then
    print("编辑器未打开该地图（diff 给不出 changelist），未校验编辑器内代码"
      .. "（磁盘已是最新）")
    return true
  end
  if out:find("channel=offline", 1, true) then
    print("编辑器没开该地图（diff 走的是离线地图目录），未校验编辑器内代码"
      .. "（磁盘已是最新）")
    return true
  end

  local dirty = M.behind_count(cl)
  if dirty > 0 then
    return nil, "尚未同步到编辑器：有 " .. dirty .. " 个本地新增或不同文件；"
      .. "为保留 packages，deploy 不执行全工作区 code push。"
      .. "请使用只读 code diff 核对差异，并另行处理业务代码同步。\n" .. out
  end

  print("编辑器: 已同步（unchanged=" .. (cl["unchanged"] or 0) .. "）")
  local ghosts = cl["only-on-map"] or 0
  if ghosts > 0 then
    print("注意: 地图侧多出 " .. ghosts .. " 个本地没有的文件，deploy 保留这些内容。")
  end
  return true
end

return M

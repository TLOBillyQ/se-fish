-- 部署收尾：镜像落盘后，经 editor-cli 确认编辑器内的代码也是最新的
-- （code validate → code diff → 有差异才 code push → 复核），一步到位，不留下一步。
-- 实测（SE 地图、syncEnabled=true、编辑器开着该地图）：宿主目录新增/改动会即时进编辑器内存
-- （单向：磁盘→内存），删除则不保证反映过去（实测删后 diff 有时仍把文件算成 only-on-map）。
-- 因此落盘后 diff 通常已无落后文件、下面的 push 不触发；push 方向恒为磁盘→地图，留给两者
-- 不一致的场合——何时会不一致未验证（编辑器加载时以磁盘还是地图包为准没有实测），保持兜底。
--
-- 本模块依赖外部设备（正在运行的编辑器 + editor-cli.exe），所以环境不成立时必须能自己
-- 收场，跳过即成功——磁盘已经是镜像后的最新状态，预期编辑器打开该地图时会自己对齐
-- （未实测，见上）：
--   * editor-cli.exe 不在；
--   * 宿主目录没有自己的 eggy.json：editor-cli 会向上下层目录找绑定，可能绑到别的工程
--     （仓库根就有 eggy.json），对着别人的地图 diff/push。
-- 编辑器没开该地图则更晚一步才看出来（diff 走离线地图目录 / 解析不出 changelist）。
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
    print("编辑器没开该地图（diff 走的是离线地图目录），跳过 push"
      .. "（磁盘已是最新）")
    return true
  end

  local dirty = M.behind_count(cl)
  if dirty > 0 then
    print("编辑器落后 " .. dirty .. " 个文件，code push …")
    code, out = editor_cli(exe, ws, "code push")
    if code ~= 0 then
      return nil, "code push 失败（退出码 " .. tostring(code) .. "）:\n" .. out
    end
    code, out = editor_cli(exe, ws, "code diff")
    cl = M.parse_changelist(out)
    if not cl then
      return nil, "push 后复核拿不到 changelist，请手动跑 editor-cli code diff:\n" .. out
    end
    dirty = M.behind_count(cl)
    if dirty ~= 0 then
      return nil, "push 后复核仍有差异（" .. dirty .. "），请手动跑 editor-cli code diff"
    end
  end

  print("编辑器: 已同步（unchanged=" .. (cl["unchanged"] or 0) .. "）")
  local ghosts = cl["only-on-map"] or 0
  if ghosts > 0 then
    print("注意: 地图侧多出 " .. ghosts .. " 个本地没有的文件（deploy 不删）；"
      .. "清理要在宿主目录跑 editor-cli code push --delete --yes")
  end
  return true
end

return M

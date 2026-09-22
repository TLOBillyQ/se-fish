-- ability-presets 子命令：一键重建技能包的编辑器侧预设（不进 git 的地图侧状态）。
-- 在仓库根执行 `lua tools/cli.lua ability-presets [--dry-run] [--editor-instance <pid>]`。
--
-- 依据是 issue #7/#8 的编辑器侧命令记录。本编辑器不认包内 ---@export_prefab_type
-- 自定义预设类型，预设一律「复制官方模板 → 改壳源码 / 属性」：
--   * 技能背包 / 加速技能 / 挥砍技能：duplicate-asset 官方模板即用（壳原样）；
--   * 加速锚点 / 挥砍锚点：duplicate 后重写壳源码（只声明属性、不挂接——壳在实例化时
--     Parent 还是 World 就会抢跑认错宿主，挂接由根 AbilityAPI.AttachAnchor 补做，
--     见 issue #7），再 change-asset-value 写入属性值。
-- 预设 key 的唯一真源是 common/GameCfg.lua 的 GameCfg.Ability：本命令按 key 查预设，
-- 还在就原地重刷壳与属性（可重复执行）；不在就复制模板建新的，并把新 key 回写
-- GameCfg.lua。跑完后照常 lua tools/cli.lua deploy 落地、试玩验证。
--
-- 已知坑（issue #7/#8 实测，脚本使用者不必再踩）：
--   * preset 命令要编辑态，试玩中一律报「需要编辑态」；
--   * 本机有多个编辑器实例时必须 --editor-instance <pid>，否则 INSTANCE_AMBIGUOUS；
--   * 不给预设写中文 Name：change-asset-value 的 Name 会存成 userdata，实例化刷 error；
--   * change-asset-value 改「壳里已声明的属性」不下发到实例（issue #7 坑 2）——锚点壳
--     从模板继承的 StartTime/Duration/Phase/TrackIndex 照录命令记录但不依赖它生效；
--     关键值由 MgrAbility 按 GameCfg.Ability 的 AnchorAttributes 在挂接前运行时覆盖。
--
-- 纯函数部分（parse_gamecfg / plan / json_string / argv_quote / extract_new_id /
-- replace_key）单独导出，由 tests/ability_presets_test.lua 脱离编辑器测。

package.path = "./?.lua;./?/init.lua;" .. package.path

local shell = require("tools.win_shell")

local M = {}

local GAMECFG = "common/GameCfg.lua"
local SHELL_DIR = "tools/ability_presets"
local EXE_REL = [[.eggitor\cli\editor-cli.exe]]

-- 五个预设槽位的规格。template 是复制源（官方模板，issue #7 硬假设 2 确认在本图）；
-- shell 与 attrs 只有锚点有（技能与背包的壳用模板原样）。attrs 一批一条
-- change-asset-value，元素是原样的 key=<json>（与 issue #7/#8 命令记录一致）。
local TEMPLATE_ABILITY = "map://preset/uc57b9f26db1463083f9ace34d6db0d5"
local TEMPLATE_ANCHOR = "map://preset/uccfb9dbe3f4428bb972096ba01f1f25"

local function fail(msg)
  error("ability-presets: " .. msg, 0)
end

M.SPECS = {
  { slot = "manager", template = "map://preset/u014968df4aa4427aebac4388ed79bf7" },
  { slot = "speed_ability", template = TEMPLATE_ABILITY },
  { slot = "speed_anchor", template = TEMPLATE_ANCHOR, shell = "anchor_speed_add.lua", attrs = {
    { "StartTime=0.0", "Duration=0.0", "Phase=2", "TrackIndex=0",
      "ABILITY_ANOSTATE_WALK_SPEED=6.0" },
  } },
  { slot = "melee_ability", template = TEMPLATE_ABILITY },
  { slot = "melee_anchor", template = TEMPLATE_ANCHOR, shell = "anchor_melee_hit.lua", attrs = {
    { "ABILITY_ANOSTATE_BULLET_DAMAGE=25.0", "ABILITY_ANOSTATE_HITPOWER=0.0",
      'ABILITY_ANOSTATE_USE_PERFAB=""', 'ABILITY_ANOSTATE_ANIMKEY=""',
      'ABILITY_ANOSTATE_HIT_SFX=""', "ABILITY_ANOSTATE_FACE_SYNC=true" },
    { 'ABILITY_ANOSTATE_HITBOX_OFFSET={"x":0.0,"y":1.0,"z":2.0}',
      'ABILITY_ANOSTATE_HITBOX_SCALE={"x":3.0,"y":2.0,"z":3.0}' },
  } },
}

-- 从 GameCfg.lua 文本里取出五个预设 key（slot → key）；取不到的槽位值为 nil。
-- 结构约定见 common/GameCfg.lua 的 GameCfg.Ability：技能条目里 AssetId/Anchor 出现在
-- AnchorBehavior 之前、且中间没有嵌套表，所以按 `{` 起、不跨 `{` 截到 AnchorBehavior。
function M.parse_gamecfg(text)
  local keys = {}
  keys.manager = text:match('ManagerPreset%s*=%s*"(map://preset/u[0-9a-f]+)"')
  local behaviors = { speed_add = "speed", melee_hit = "melee" }
  for behavior, prefix in pairs(behaviors) do
    local entry = text:match('{[^{]-AnchorBehavior%s*=%s*"' .. behavior .. '"')
    if entry then
      keys[prefix .. "_ability"] = entry:match('AssetId%s*=%s*"(map://preset/u[0-9a-f]+)"')
      keys[prefix .. "_anchor"] = entry:match('Anchor%s*=%s*"(map://preset/u[0-9a-f]+)"')
    end
  end
  return keys
end

-- 把 GameCfg 文本里的旧 key 换成新 key；旧 key 必须恰好出现一次，否则返回 nil, 原因。
function M.replace_key(text, old_id, new_id)
  local first = text:find(old_id, 1, true)
  if not first then
    return nil, "GameCfg.lua 里找不到旧 key " .. old_id
  end
  if text:find(old_id, first + 1, true) then
    return nil, "旧 key 在 GameCfg.lua 里出现多次，不敢回写: " .. old_id
  end
  return text:sub(1, first - 1) .. new_id .. text:sub(first + #old_id)
end

-- 纯规划：按「预设是否还在」决定每个槽位干什么。
-- exists 是 slot → bool；返回与 SPECS 同序的动作表：
--   keep    预设还在且无需重刷（背包 / 技能）
--   reapply 预设还在，原地重刷壳源码与属性（锚点）
--   rebuild 预设不在，复制模板建新的（随后同样刷壳与属性）
function M.plan(exists)
  local actions = {}
  for _, spec in ipairs(M.SPECS) do
    local op
    if not exists[spec.slot] then
      op = "rebuild"
    elseif spec.shell then
      op = "reapply"
    else
      op = "keep"
    end
    actions[#actions + 1] = { slot = spec.slot, op = op, spec = spec }
  end
  return actions
end

-- Lua 字符串 → JSON 字符串字面量（change-asset-value 的值按 JSON 解析）。
function M.json_string(s)
  local escapes = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
  return '"' .. (s:gsub('[%c\\"]', function(c)
    return escapes[c] or string.format("\\u%04x", c:byte())
  end)) .. '"'
end

-- 把一个 argv 元素编码进 cmd 命令行：包双引号，内部按 CommandLineToArgvW 规则转义
-- （反斜杠只在 " 或 \ 前特殊；结尾的反斜杠在收尾引号前翻倍）。
function M.argv_quote(s)
  local out = {}
  local run = 0
  for i = 1, #s do
    local c = s:sub(i, i)
    if c == "\\" then
      run = run + 1
    elseif c == '"' then
      out[#out + 1] = string.rep("\\", run * 2 + 1) .. '"'
      run = 0
    else
      out[#out + 1] = string.rep("\\", run) .. c
      run = 0
    end
  end
  out[#out + 1] = string.rep("\\", run * 2)
  return '"' .. table.concat(out) .. '"'
end

-- cmd 侧保护：argv_quote 保证的是目标程序（CommandLineToArgvW）拿到的 argv 正确，
-- 但 cmd 自己先按「每个 " 朴素翻转引号态」扫一遍命令行——argv_quote 产生的 \" 序列
-- 会把 cmd 的引号态翻出内容区，落在「引号外」的 cmd 元字符（如壳注释里的 `> 0`）会被
-- 当成重定向/管道执行（实测：命令本身成功，cmd 额外报「系统找不到指定的路径」并把
-- 整条命令的退出码顶成 1）。这里按 cmd 的引号态给引号外的元字符补 ^ 转义；
-- ^ 在引号外会被 cmd 吃掉、不进 argv，对目标程序透明。
-- % 不处理（cmd /c 命令行也做 %var% 展开）：目前所有值都不含 %，见了直接报错。
local CMD_META = { ["&"] = true, ["|"] = true, ["<"] = true, [">"] = true,
  ["("] = true, [")"] = true, ["^"] = true }

function M.cmd_protect(fragment)
  if fragment:find("%%") then
    fail("命令行里出现 %（cmd 会做 %var% 展开，本工具不支持）: " .. fragment:sub(1, 80))
  end
  local out = {}
  local in_quotes = false
  for i = 1, #fragment do
    local c = fragment:sub(i, i)
    if c == '"' then
      in_quotes = not in_quotes
      out[#out + 1] = c
    elseif not in_quotes and CMD_META[c] then
      out[#out + 1] = "^" .. c
    else
      out[#out + 1] = c
    end
  end
  return table.concat(out)
end

-- duplicate-asset 的输出里找新预设 id：与模板 id 不同的那个 map://preset/ 串。
function M.extract_new_id(out, template)
  local found = nil
  for id in out:gmatch("map://preset/u[0-9a-f]+") do
    if id ~= template then found = id end
  end
  return found
end

-- editor-cli --json 输出是否成功。
function M.succeeded(out)
  return out:match('"success"%s*:%s*true') ~= nil
end

local function exe_path()
  local home = os.getenv("USERPROFILE")
  if not home then return nil end
  return home .. "\\" .. EXE_REL
end

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local body = f:read("a")
  f:close()
  return body
end

-- 跑一条 preset 子命令；extra 是 --editor-instance 这类透传参数。
local function run_preset(ctx, args)
  local parts = { shell.q(ctx.exe), "preset" }
  for _, a in ipairs(args) do
    parts[#parts + 1] = M.cmd_protect(M.argv_quote(a))
  end
  for _, e in ipairs(ctx.extra) do
    parts[#parts + 1] = M.argv_quote(e)
  end
  return shell.capture(table.concat(parts, " "))
end

-- 跑一步并检查成功；失败带输出原文 error 出去。
local function step(ctx, desc, args)
  local code, out = run_preset(ctx, args)
  if code ~= 0 or not M.succeeded(out) then
    fail(desc .. " 失败（退出码 " .. tostring(code) .. "）:\n" .. out)
  end
  return out
end

local function preset_exists(ctx, key)
  local code, out = run_preset(ctx, { "get-asset-value", key, "SourceCode", "--json" })
  return code == 0 and M.succeeded(out)
end

-- 给锚点预设重刷壳源码与属性（rebuild / reapply 共用）。
local function apply_shell(ctx, spec, key, dry_run)
  local source = read_file(SHELL_DIR .. "/" .. spec.shell)
  if not source then
    fail("缺锚点壳文件 " .. SHELL_DIR .. "/" .. spec.shell)
  end
  if dry_run then
    print("  [dry-run] 写壳源码 " .. spec.shell .. " → " .. key)
  else
    step(ctx, "写壳源码 " .. key,
      { "change-asset-value", key, "SourceCode=" .. M.json_string(source), "--yes", "--json" })
    print("  壳源码已写入（" .. spec.shell .. "）")
  end
  for _, batch in ipairs(spec.attrs) do
    local args = { "change-asset-value", key }
    for _, kv in ipairs(batch) do args[#args + 1] = kv end
    args[#args + 1] = "--yes"
    args[#args + 1] = "--json"
    if dry_run then
      print("  [dry-run] 写属性 " .. table.concat(batch, " ") .. " → " .. key)
    else
      step(ctx, "写属性 " .. key, args)
      print("  属性已写入（" .. #batch .. " 项）")
    end
  end
end

function M.usage()
  return table.concat({
    "用法: lua tools/cli.lua ability-presets [--dry-run] [--editor-instance <pid>]",
    "",
    "重建技能包的编辑器侧预设（技能背包 / 加速技能 / 加速锚点 / 挥砍技能 / 挥砍锚点）：",
    "GameCfg.Ability 里的 key 还在就原地重刷壳与属性（可重复执行）；不在就复制官方模板",
    "建新的，并把新 key 回写 common/GameCfg.lua。",
    "要求编辑器开着本地图且处于编辑态（preset 命令试玩中不可用）；多个编辑器实例时",
    "用 --editor-instance <pid> 指定。",
    "跑完后：lua tools/cli.lua deploy 落地，试玩验证，再把 GameCfg.lua 的 key 变更提交。",
    "",
    "选项：",
    "  --dry-run              只做只读探测并打印计划，不写编辑器、不改 GameCfg.lua",
    "  --editor-instance <pid>  透传给每条 editor-cli 命令（多实例时必填）",
    "",
  }, "\n") .. "\n"
end

local function run(args)
  local dry_run = false
  local extra = {}
  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--dry-run" then
      dry_run = true
    elseif a == "--editor-instance" then
      i = i + 1
      if not args[i] then fail("--editor-instance 缺 pid") end
      extra[#extra + 1] = "--editor-instance"
      extra[#extra + 1] = args[i]
    else
      io.stderr:write("ability-presets: 未知参数: " .. a .. "\n")
      return 2
    end
    i = i + 1
  end

  local exe = exe_path()
  if not exe or not shell.exists(exe) then
    fail("未找到 editor-cli.exe（" .. tostring(exe) .. "）")
  end

  local body = read_file(GAMECFG)
  if not body then fail("读不到 " .. GAMECFG) end
  local keys = M.parse_gamecfg(body)
  for _, spec in ipairs(M.SPECS) do
    if not keys[spec.slot] then
      fail("从 " .. GAMECFG .. " 取不到预设 key: " .. spec.slot .. "（GameCfg.Ability 结构变了？）")
    end
  end

  local ctx = { exe = exe, extra = extra }

  -- 连通性 + 编辑态探针：编辑器没开本地图、或在试玩中，都在这一步报出来。
  -- get-all-asset-ids / get-asset-value 都是只读，dry-run 也照跑——
  -- 这样 dry-run 打印的计划和湿跑一致（不然已有预设也会被列成「重建」）。
  step(ctx, "连通性检查（编辑器没开本地图或在试玩中？preset 命令要编辑态）",
    { "get-all-asset-ids", "--json" })

  local exists = {}
  for _, spec in ipairs(M.SPECS) do
    exists[spec.slot] = preset_exists(ctx, keys[spec.slot])
  end

  local actions = M.plan(exists)
  local replacements = {}
  for _, action in ipairs(actions) do
    local spec, key = action.spec, keys[action.slot]
    if action.op == "keep" then
      print(action.slot .. ": 预设在，保持不动（" .. key .. "）")
    elseif action.op == "reapply" then
      print(action.slot .. ": 预设在，原地重刷壳与属性（" .. key .. "）")
      apply_shell(ctx, spec, key, dry_run)
    else
      print(action.slot .. ": 预设不在，复制模板 " .. spec.template .. " 重建")
      local new_key
      if dry_run then
        new_key = "<新 key>"
        print("  [dry-run] duplicate-asset " .. spec.template)
      else
        local out = step(ctx, "复制模板 " .. spec.template,
          { "duplicate-asset", spec.template, "--yes", "--json" })
        new_key = M.extract_new_id(out, spec.template)
        if not new_key then
          fail("duplicate-asset 的输出里找不到新预设 id:\n" .. out)
        end
        print("  新预设 " .. new_key)
        replacements[#replacements + 1] = { old = key, new = new_key }
      end
      if spec.shell then
        apply_shell(ctx, spec, new_key, dry_run)
      end
    end
  end

  if #replacements > 0 then
    for _, r in ipairs(replacements) do
      local new_body, err = M.replace_key(body, r.old, r.new)
      if not new_body then fail(err) end
      body = new_body
    end
    local f = io.open(GAMECFG, "wb")
    if not f then fail("写不回 " .. GAMECFG) end
    f:write(body)
    f:close()
    print(GAMECFG .. " 已回写 " .. #replacements .. " 个新 key；请跑 deploy 落地、试玩验证后提交。")
  end

  if dry_run then
    print("dry-run 结束（只读探测，未写编辑器、未改 " .. GAMECFG .. "）")
  else
    print("ability-presets ok")
  end
  return 0
end

-- 退出码：0 成功 / 1 业务失败 / 2 用法错误。
function M.main(args)
  args = args or {}
  for _, a in ipairs(args) do
    if a == "--help" or a == "-h" then
      io.write(M.usage())
      return 0
    end
  end
  local ok, err = pcall(run, args)
  if not ok then
    io.stderr:write(tostring(err) .. "\n")
    return 1
  end
  if type(err) == "number" then return err end
  return 0
end

if ... == "tools.ability_presets" then
  return M
end

os.exit(M.main(arg))

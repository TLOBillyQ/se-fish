-- ability-presets 子命令：一键重建技能包的编辑器侧预设（不进 git 的地图侧状态）。
-- 在仓库根执行 `lua tools/cli.lua ability-presets [--dry-run] [--editor-instance <pid>]`，
-- 或 `lua tools/cli.lua ability-presets --fix-names [--dry-run] [--editor-instance <pid>]`
-- 修预设的 Name 类型（见下面「Name 类型」一节）。
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
-- 已知坑（issue #7/#8 实测，Name 那条由 issue #22 运行期探针复核，脚本使用者不必再踩）：
--   * preset 命令要编辑态，试玩中一律报「需要编辑态」；
--   * 本机有多个编辑器实例时必须 --editor-instance <pid>，否则 INSTANCE_AMBIGUOUS；
--   * **别用 change-asset-value 写预设的 Name**（#22 运行期探针复核）：写进去的值落成编辑器侧
--     unicode 对象、实例化时 Name setter 只收 Lua string。已经中招的预设用 `--fix-names` 修，
--     完整原理、四步配方与验证方法见下面「Name 类型」一节；常规重建（duplicate-asset 继承模板
--     的 string Name）与重刷（只写 SourceCode + attrs）都不碰 Name，日常跑不会新污染；
--   * change-asset-value 改「壳里已声明的属性」不下发到实例（issue #7 坑 2）——锚点壳
--     从模板继承的 StartTime/Duration/Phase/TrackIndex 照录命令记录但不依赖它生效；
--     关键值由 MgrAbility 按 GameCfg.Ability 的 AnchorAttributes 在挂接前运行时覆盖；
--   * 预设改动不用存盘就进下一场试玩（#22 实测：编辑器内存里改完立刻 play start，运行期已拿到
--     新值）；但 `deploy` 只镜像 Lua 源码，与预设无关。
--
-- ---------------------------------------------------------------------------
-- Name 类型：为什么不能写、怎么查、怎么修（issue #22 闭环 / #30，--fix-names 的实现依据）
-- ---------------------------------------------------------------------------
-- 症状：每次进图 1 条 `Error setting property 'Name': ... expected String, got userdata`，
-- 且该预设实例化出来的单位运行时名字为空（日志里显示 <>）。
--
-- 根因（#22 实测）：值经 ChangeAssetValue 写入时在 API 实现层被转成编辑器侧的 unicode 对象。
-- CLI（preset change-asset-value）与编辑态 exec 直调 AssetService:ChangeAssetValue 都一样；
-- **中文/ASCII 内容都中招**——变的是类型不是内容。Name setter 只收 Lua string，于是实例化时
-- 赋值失败。官方模板继承来的 Name 是 string，所以 duplicate-asset 建出来的预设名字一直正常。
--
-- 查类型（唯一可信的口径是编辑器/运行时的 typeof；CLI 的 get-asset-value 只回内容、没有类型位）：
--   * 编辑态：editor-cli exec 'local AS=editor:GetService("AssetService");
--       local v=AS:GetAssetValue("<预设 id>","Name"); return typeof(v).."|"..tostring(v)'
--     → `String|技能背包`（正常）/ `userdata|u'\u52a0\u901f\u6280\u80fd'`（中招）；
--   * 试玩期：读 MapData:GetAssetData(预设 id) 的根单位 Name 的 type()，再看实例出来的单位名是否为空。
--   实测提醒：写脏的值经 preset get-asset-value 照样显示「加速技能」，看不出类型；告警条数也
--   数不出中招个数——同一条告警一个 Lua VM 只打一次。
--
-- 修（`--fix-names` 跑的就是这四步，全在编辑器内存态，不动 GameCfg、保原预设 id、不存盘）：
--   0. 读原名：preset get-asset-value <预设> Name —— 拿到内容（内容本身就是好的，坏的是类型）；
--   1. preset create-unit-by-asset <预设> --position 0,100,0 --yes —— 从预设建场景单位，
--      返回的 unit_ids 连子单位一起给，根 = 父不在这一批里的那个；
--   2. editor-unit rename <根 unit-id> <原名> --yes —— 单位名走「plain string」通道（CLI help
--      明写），落的是真正的 Lua string；
--   3. exec --file <脚本> --expect-edit-mode —— 脚本里 AssetService:SyncAssetFromUnit(单位) 把
--      单位数据（含 string Name）同步回预设；脚本走 --file 传，中文名不进 cmd 命令行；
--   4. editor-unit delete <根 unit-id> --recursive --yes —— 删掉场景单位（子单位跟着根走）。
--   收尾回读步骤 0 的探针，确认 typeof 已是 String。
--   前置约束：场景里不能已有同名单位（第 3 步按名字 FindFirstChild 找单位，重名会同步错对象）
--   ——工具先查 editor-unit list --name，见到就报错不猜。
--   副作用（实测，用 export-preset 的 .bin 前后对比，本机 2026-09-22）：第 3 步是「用场景单位
--   重刷整个预设」，所以
--     * 预设根单位的 Guid 会换成新单位的 Guid（.bin 里就这一处变，重复修不漂移）；
--     * **只存在于预设、不随单位往返的属性会被丢掉**——实测用 change-asset-value 写在预设上的
--       自定义属性在修复后消失；SourceCode / CompiledCode / Name 内容、壳里 ---@type 声明的值
--       都不变（锚点壳 2496 字节 .bin 逐字节比对，只差 Guid）。要补写这类属性就在修完之后写。
--   预设改动不存盘就进下一场试玩，所以修完当场生效；但本工具**绝不调 map save**（地图上通常
--   有人类未存的手动改动），要持久化由人类自己手动存盘。
--
-- 纯函数部分（parse_gamecfg / plan / json_string / argv_quote / extract_new_id /
-- replace_key / parse_probe / plan_name_fixes / extract_unit_ids / parse_unit_get /
-- roots_of / lua_quote / sync_script）单独导出，由 tests/tooling/ability_presets_test.lua
-- 脱离编辑器测；真编辑器行为只能人工验（编辑器开着本图、编辑态）。

package.path = "./?.lua;./?/init.lua;" .. package.path

local shell = require("tools.win_shell")

local M = {}

local GAMECFG = "common/GameCfg.lua"
local SHELL_DIR = "tools/ability_presets"
local EXE_REL = [[.eggitor\cli\editor-cli.exe]]

-- --fix-names 用：建场景单位的位置（离地高、跑完就删）与两个 exec 脚本落点
-- （tmp/ 是 gitignored）。exec 的 Lua 一律走 --file：脚本体是多行，内联进 cmd 命令行会被
-- 换行切断（实测：后面那些参数被吃成另一条命令，exec 只回了纯文本 "Execution succeeded."）。
local FIX_POSITION = "0,100,0"
local PROBE_SCRIPT = "tmp/ability_presets_probe.lua"
local EXEC_SCRIPT = "tmp/ability_presets_sync.lua"

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

-- 以下是 --fix-names 的纯函数部分（解析探针 / 规划 / 解析 unit id / 生成同步脚本），
-- 由单测覆盖；真编辑器调用在下面 fix_names 里。

-- fail() 的消息都带 "ability-presets: " 前缀；跨 pcall 再包一层时先剥掉，别叠成两层前缀。
function M.strip_prefix(err)
  return (tostring(err):gsub("^ability%-presets: ", ""))
end

-- 类型探针的 exec 输出 → 类型与值。探针固定 `return typeof(v) .. "|" .. tostring(v)`，
-- 所以结果形态是 `<typeof>|<tostring>`；取不到管道符（exec 没跑成 / API 改名了）返回 nil。
-- 注意 JSON 里的 tostring 部分是转义过的（unicode 值显示成 u'\\u52a0...'），本函数不解转义
-- ——只用来判类型与打印，要拿原名一律走 preset get-asset-value。
function M.parse_probe(text)
  if not text then return nil end
  local kind, value = text:match("^([%w_]+)|(.*)$")
  if not kind then return nil end
  return kind, value
end

-- preset get-asset-value 的纯文本输出 → 名字内容（只有尾部的 CRLF 要剪，正文里的字符照留）。
function M.clean_name(text)
  if not text then return nil end
  return (text:gsub("[\r\n]+$", ""))
end

-- 修复计划：probes 是 slot → { kind=, name= }（kind 是编辑态探针的 typeof，name 是
-- preset get-asset-value 读到的原名内容）。返回与 SPECS 同序：
--   { slot=, name=, op="skip"       Name 已是 Lua string，不动
--                       | "fix"     Name 不是 string，跑四步配方
--                       | "unreadable" 探针没读出来 / 名字为空，报错不猜 }
function M.plan_name_fixes(probes)
  local actions = {}
  for _, spec in ipairs(M.SPECS) do
    local probe = probes[spec.slot] or {}
    local op
    if probe.kind == "String" then
      op = "skip"
    elseif probe.kind ~= nil and probe.name ~= nil and probe.name ~= "" then
      op = "fix"
    else
      op = "unreadable"
    end
    actions[#actions + 1] = { slot = spec.slot, op = op, name = probe.name }
  end
  return actions
end

-- create-unit-by-asset 的 --json 输出 → unit_ids（按下标顺序，父在前）。
function M.extract_unit_ids(out)
  local ids = {}
  local body = out and out:match('"unit_ids"%s*:%s*%[(.-)%]')
  if not body then return ids end
  for id in body:gmatch("%d+") do ids[#ids + 1] = id end
  return ids
end

-- editor-unit get 的 --json 输出 → { id=, parent= }（顶层单位没有 parent_unit_id）；
-- 输出里没有 unit_id 返回 nil。
function M.parse_unit_get(out)
  if not out then return nil end
  local id = out:match('"unit_id"%s*:%s*"(.-)"')
  if not id then return nil end
  local parent = out:match('"parent_unit_id"%s*:%s*"(.-)"')
  return { id = id, parent = parent }
end

-- 从一批刚建出来的单位里挑根：父不在这批里的（或没有父的）就是根。create-unit-by-asset
-- 连子单位一起返回，删的时候只删根（--recursive），否则删子会 EDITOR_UNIT_NOT_FOUND。
function M.roots_of(units)
  local in_batch = {}
  for _, u in ipairs(units) do in_batch[u.id] = true end
  local roots = {}
  for _, u in ipairs(units) do
    if not u.parent or not in_batch[u.parent] then roots[#roots + 1] = u.id end
  end
  return roots
end

-- Lua 字符串字面量（同步脚本里要嵌预设名字）。控制字符走 \ddd 十进制转义：
-- 别用 \u{...}，编辑器运行时的 Lua 版本不保证认。
function M.lua_quote(s)
  return '"' .. (s:gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' end
    if c == "\\" then return "\\\\" end
    return string.format("\\%03d", c:byte())
  end)) .. '"'
end

-- 四步配方第 3 步的 exec 脚本体：编辑态按名字找刚 rename 过的单位，把它的数据（含
-- string Name）同步回预设。成功时返回 `sync=true`（sync_succeeded 认这个标记）；
-- 失败返回 `ERROR: ...`，脚本自己 pcall，不让 exec 侧只回一句泛泛的失败。
function M.sync_script(key, name)
  return table.concat({
    "-- ability-presets --fix-names 第 3 步：把场景单位的 string Name 同步回预设（工具生成，勿手改）",
    'local World = editor:GetService("World")',
    'local AssetService = editor:GetService("AssetService")',
    "local unit = World:FindFirstChild(" .. M.lua_quote(name) .. ")",
    'if unit == nil then return "ERROR: 场景里找不到单位" end',
    "local ok, r = pcall(AssetService.SyncAssetFromUnit, AssetService, unit)",
    'if not ok then return "ERROR: " .. tostring(r) end',
    'return "sync=" .. tostring(r) .. " asset=" .. ' .. M.lua_quote(key),
  }, "\n") .. "\n"
end

-- exec 的 --json 输出里是不是 `sync=true`（第 3 步的自检标记）。
function M.sync_succeeded(out)
  return out ~= nil and out:match('"result"%s*:%s*"sync=true') ~= nil
end

-- --json 输出里 result 字段的文本（探针结果就是从这里取的）。
function M.exec_result(out)
  return out and out:match('"result"%s*:%s*"(.-)"')
end

-- 类型探针的 exec 脚本体：返回 `<typeof>|<tostring>`。脚本落 tmp/ 后用 --file 传
-- （见 PROBE_SCRIPT；多行内联进 cmd 会被换行切断）。
function M.probe_script(key)
  return table.concat({
    'local AssetService = editor:GetService("AssetService")',
    "local v = AssetService:GetAssetValue(" .. M.lua_quote(key) .. ', "Name")',
    'return typeof(v) .. "|" .. tostring(v)',
  }, "\n")
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

-- 跑一条 editor-cli 命令；extra 是 --editor-instance 这类透传参数。
local function run_cli(ctx, args)
  local parts = { shell.q(ctx.exe) }
  for _, a in ipairs(args) do
    parts[#parts + 1] = M.cmd_protect(M.argv_quote(a))
  end
  for _, e in ipairs(ctx.extra) do
    parts[#parts + 1] = M.argv_quote(e)
  end
  return shell.capture(table.concat(parts, " "))
end

-- 跑一条 preset 子命令。
local function run_preset(ctx, args)
  local full = { "preset" }
  for _, a in ipairs(args) do full[#full + 1] = a end
  return run_cli(ctx, full)
end

-- 跑一步并检查成功；失败带输出原文 error 出去。
local function step(ctx, desc, args)
  local code, out = run_cli(ctx, args)
  if code ~= 0 or not M.succeeded(out) then
    fail(desc .. " 失败（退出码 " .. tostring(code) .. "）:\n" .. out)
  end
  return out
end

-- GetAssetValue 对不存在的预设也返回 success=true,value=null；存在性以 ID 清单为准。
function M.preset_exists(out, key)
  if not key or not M.succeeded(out) then return false end
  local ids = out:match('"asset_ids"%s*:%s*%[([^%]]*)%]')
  if not ids then error("预设 ID 清单缺少 asset_ids，无法判定存在性") end
  for id in ids:gmatch('"([^"]+)"') do
    if id == key then return true end
  end
  return false
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
      { "preset", "change-asset-value", key, "SourceCode=" .. M.json_string(source),
        "--yes", "--json" })
    print("  壳源码已写入（" .. spec.shell .. "）")
  end
  for _, batch in ipairs(spec.attrs) do
    local args = { "preset", "change-asset-value", key }
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

local function write_file(path, body)
  shell.ensure_dir("tmp")
  local f = io.open(path, "wb")
  if not f then fail("写不了 " .. path) end
  f:write(body)
  f:close()
end

-- 只读探针：预设 Name 的 typeof。CLI 的 get-asset-value 只回内容、看不出类型，所以类型必须
-- 走编辑态 exec；exec 本身是 mutating 命令，脚本只 GetAssetValue，并带 --expect-edit-mode。
local function probe_name_kind(ctx, key)
  write_file(PROBE_SCRIPT, M.probe_script(key))
  local out = step(ctx, "读 Name 类型 " .. key,
    { "exec", "--file", shell.win(PROBE_SCRIPT), "--expect-edit-mode", "--json" })
  local kind, value = M.parse_probe(M.exec_result(out))
  if not kind then
    fail("认不出 " .. key .. " 的类型探针输出:\n" .. out)
  end
  return { kind = kind, value = value }
end

-- 四步配方（--fix-names 的核心）：从预设建场景单位 → 用 plain string 改名 → 同步回预设 →
-- 删场景单位。全程编辑器内存态：不改 GameCfg.lua、不存盘、保原预设 id。
local function apply_name_fix(ctx, key, name, dry_run)
  -- 第 3 步按名字 FindFirstChild 找单位，场景里已有同名（或名字含同串的）单位会同步错对象
  -- ——先查，见到就停。list --name 是子串匹配，宁可保守拦下也不要同步错对象。
  local _, listed = run_cli(ctx, { "editor-unit", "list", "--name", name, "--json" })
  local total = tonumber(listed and listed:match('"total"%s*:%s*(%d+)'))
  if total and total > 0 then
    fail("场景里已有 " .. total .. " 个名字含「" .. name .. "」的单位，不敢跑配方（第 3 步按名字找"
      .. "单位，会同步错对象）：先处理掉同名单位再重跑")
  end

  print("  配方: preset create-unit-by-asset → editor-unit rename → exec SyncAssetFromUnit"
    .. " → editor-unit delete --recursive")
  print("  位置 " .. FIX_POSITION .. "，单位名「" .. name .. "」，预设 " .. key)

  if dry_run then
    print("    [dry-run] 1/4 preset create-unit-by-asset " .. key .. " --position " .. FIX_POSITION)
    print("    [dry-run] 2/4 editor-unit rename <根 unit-id> " .. name)
    print("    [dry-run] 3/4 exec --file " .. EXEC_SCRIPT
      .. " --expect-edit-mode（AssetService:SyncAssetFromUnit(单位)）")
    print("    [dry-run] 4/4 editor-unit delete <根 unit-id> --recursive")
    print("    [dry-run] 5 回读 typeof，确认已是 String")
    return
  end

  local out = step(ctx, "1/4 从预设建场景单位 " .. key,
    { "preset", "create-unit-by-asset", key, "--position", FIX_POSITION, "--yes", "--json" })
  local ids = M.extract_unit_ids(out)
  if #ids == 0 then fail("create-unit-by-asset 没回 unit_ids:\n" .. out) end

  local units = {}
  for _, id in ipairs(ids) do
    local u = M.parse_unit_get(step(ctx, "1/4 读新建单位 " .. id,
      { "editor-unit", "get", id, "--json" }))
    if not u then fail("认不出 editor-unit get " .. id .. " 的输出") end
    units[#units + 1] = u
  end
  local roots = M.roots_of(units)
  if #roots ~= 1 then
    for _, id in ipairs(roots) do
      run_cli(ctx, { "editor-unit", "delete", id, "--recursive", "--yes", "--json" })
    end
    fail("预设 " .. key .. " 建出 " .. #roots .. " 个根单位，不确定哪个对应预设根单位（要拿它改名"
      .. "再同步），已删掉建出来的单位；请人工核对该预设的层级")
  end

  local root = roots[1]
  local ok, err = pcall(function()
    step(ctx, "2/4 用 plain string 改名 " .. root,
      { "editor-unit", "rename", root, name, "--yes", "--json" })
    write_file(EXEC_SCRIPT, M.sync_script(key, name))
    local sync_out = step(ctx, "3/4 同步回预设 " .. key,
      { "exec", "--file", shell.win(EXEC_SCRIPT), "--expect-edit-mode", "--json" })
    if not M.sync_succeeded(sync_out) then
      fail("SyncAssetFromUnit 没回 sync=true:\n" .. sync_out)
    end
    step(ctx, "4/4 删场景单位 " .. root,
      { "editor-unit", "delete", root, "--recursive", "--yes", "--json" })
  end)
  if not ok then
    -- 别把刚建的场景单位留在地图里：尽力删一次（删不掉也不盖原始错误）。
    run_cli(ctx, { "editor-unit", "delete", root, "--recursive", "--yes", "--json" })
    error(M.strip_prefix(err) .. "\n（已尽力删除刚建的场景单位 " .. root .. "）", 0)
  end

  local after = probe_name_kind(ctx, key)
  print("  Name 类型修后: " .. after.kind .. " | " .. tostring(after.value))
  if after.kind ~= "String" then
    fail("修完 " .. key .. " 的 Name 类型还是 " .. after.kind .. "，配方没生效？")
  end
end

-- --fix-names：对 GameCfg.Ability 引用的每个预设查 Name 类型，该修就修，逐个报告前后。
-- 返回失败的预设个数（0 才算全成功）。先只读探完五个预设再动手：计划按初始状态定，
-- 不会边探边改。
local function fix_names(ctx, keys, dry_run)
  local probes = {}
  for _, spec in ipairs(M.SPECS) do
    local key = keys[spec.slot]
    local _, name_out = run_cli(ctx, { "preset", "get-asset-value", key, "Name" })
    local probe = probe_name_kind(ctx, key)
    probe.name = M.clean_name(name_out)
    probes[spec.slot] = probe
  end

  print("修复计划：")
  local actions = M.plan_name_fixes(probes)
  for _, action in ipairs(actions) do
    local probe = probes[action.slot]
    local head = string.format("  %-13s %s  Name 修前: typeof=%s tostring=%s",
      action.slot, keys[action.slot], probe.kind, tostring(probe.value))
    if action.op == "skip" then
      print(head .. " → 已是 Lua string，跳过")
    elseif action.op == "unreadable" then
      print(head .. " → 读不出类型 / 名字为空（预设不在本图？），跳过不猜")
    else
      print(head .. " → 要修（原名「" .. tostring(action.name) .. "」）")
    end
  end

  local failed = 0
  for _, action in ipairs(actions) do
    if action.op == "unreadable" then
      failed = failed + 1
    elseif action.op == "fix" then
      print("")
      print(string.format("%s（%s）", action.slot, keys[action.slot]))
      local ok, err = pcall(apply_name_fix, ctx, keys[action.slot], action.name, dry_run)
      if not ok then
        failed = failed + 1
        io.stderr:write("ability-presets: " .. M.strip_prefix(err) .. "\n")
      end
    end
  end

  print("")
  if dry_run then
    print("dry-run 结束（只读探测，未写编辑器、未改 " .. GAMECFG .. "）")
  end
  if failed > 0 then
    fail(failed .. " 个预设没能处理（见上面输出）")
  end
  if not dry_run then
    print("ability-presets --fix-names ok：GameCfg.Ability 引用的预设 Name 全是 Lua string")
    print("（编辑器内存态已修好，未存盘；试玩即时生效，持久化由人类手动存盘决定）")
  end
  return 0
end

function M.usage()
  return table.concat({
    "用法: lua tools/cli.lua ability-presets [--fix-names] [--dry-run] [--editor-instance <pid>]",
    "",
    "重建技能包的编辑器侧预设（技能背包 / 加速技能 / 加速锚点 / 挥砍技能 / 挥砍锚点）：",
    "GameCfg.Ability 里的 key 还在就原地重刷壳与属性（可重复执行）；不在就复制官方模板",
    "建新的，并把新 key 回写 common/GameCfg.lua。",
    "加 --fix-names 则改跑 Name 类型修复：对 GameCfg.Ability 引用的每个预设查 Name 类型，",
    "不是 Lua string 的按「create-unit-by-asset → editor-unit rename → SyncAssetFromUnit →",
    "删场景单位」四步修回来（保原预设 id、不改 GameCfg.lua、不存盘）。",
    "两种模式都要求编辑器开着本地图且在编辑态（preset 命令试玩中不可用）；多个编辑器实例时",
    "用 --editor-instance <pid> 指定。",
    "常规模式跑完后：lua tools/cli.lua deploy 落地，试玩验证，再把 GameCfg.lua 的 key 变更提交。",
    "",
    "选项：",
    "  --fix-names            修预设 Name 的类型（见上），不再跑重建/重刷",
    "  --dry-run              只做只读探测并打印计划，不写编辑器、不改 GameCfg.lua",
    "  --editor-instance <pid>  透传给每条 editor-cli 命令（多实例时必填）",
    "",
    "两者都不调 map save：预设改动进下一场试玩即时生效，持久化由人类自己手动存盘。",
    "",
  }, "\n") .. "\n"
end

local function run(args)
  local dry_run = false
  local fix = false
  local extra = {}
  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--dry-run" then
      dry_run = true
    elseif a == "--fix-names" then
      fix = true
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
  local asset_ids = step(ctx, "连通性检查（编辑器没开本地图或在试玩中？preset 命令要编辑态）",
    { "preset", "get-all-asset-ids", "--json" })

  -- --fix-names 只跑 Name 修复，不碰重建/重刷（两者都要写编辑器，别混在一轮里）。
  if fix then
    return fix_names(ctx, keys, dry_run)
  end

  local exists = {}
  for _, spec in ipairs(M.SPECS) do
    exists[spec.slot] = M.preset_exists(asset_ids, keys[spec.slot])
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
          { "preset", "duplicate-asset", spec.template, "--yes", "--json" })
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

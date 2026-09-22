-- 纯模块单测：ability-presets 的 GameCfg key 解析 / 回写、动作规划、命令行编码，以及
-- --fix-names 的探针解析 / 修复计划 / unit id 与四步脚本生成（issue #30）。
-- 不碰编辑器、不起子进程；真实 editor-cli 行为只能在本机编辑器开着地图、编辑态时人工验。
local lu = require("luaunit")
local ap = require("tools.ability_presets")

TestAbilityPresetsParse = {}

local FIXTURE = [[
GameCfg.Ability = {
    ManagerPreset = "map://preset/ubdb4a7e737d4eddb87729e9055ba375",
    InitialAbilities = {
        {
            AssetId = "map://preset/uf7fac66639546e2aa376151835cf3a6",
            Index = 0,
            Anchor = "map://preset/uaf2781161d6460990a4941b12ad30c2",
            AnchorBehavior = "speed_add",
        },
        {
            AssetId = "map://preset/u0d0b1993faa482b93e806d23715b73e",
            Index = 1,
            Anchor = "map://preset/ucc500ac3aac4b749fd9bee03b57e4d5",
            AnchorBehavior = "melee_hit",
            AnchorAttributes = {
                ABILITY_ANOSTATE_HITBOX_OFFSET = { x = 0, y = 1, z = 2 },
            },
        },
    },
}
]]

function TestAbilityPresetsParse:test_fixture_yields_all_five_keys()
  local keys = ap.parse_gamecfg(FIXTURE)
  lu.assertEquals(keys.manager, "map://preset/ubdb4a7e737d4eddb87729e9055ba375")
  lu.assertEquals(keys.speed_ability, "map://preset/uf7fac66639546e2aa376151835cf3a6")
  lu.assertEquals(keys.speed_anchor, "map://preset/uaf2781161d6460990a4941b12ad30c2")
  lu.assertEquals(keys.melee_ability, "map://preset/u0d0b1993faa482b93e806d23715b73e")
  lu.assertEquals(keys.melee_anchor, "map://preset/ucc500ac3aac4b749fd9bee03b57e4d5")
end

-- 嵌套表（AnchorAttributes 的 Vector3 表）不能干扰条目截取。
function TestAbilityPresetsParse:test_nested_table_does_not_confuse_entry_matching()
  local keys = ap.parse_gamecfg(FIXTURE)
  lu.assertEquals(keys.melee_anchor, "map://preset/ucc500ac3aac4b749fd9bee03b57e4d5")
end

-- 真源对得上：直接读仓库的 common/GameCfg.lua，五个 key 都要在、互不重复。
-- GameCfg.Ability 结构改动时这条先红，脚本不会在编辑器侧白跑。
function TestAbilityPresetsParse:test_real_gamecfg_parses()
  local f = io.open("common/GameCfg.lua", "rb")
  lu.assertNotNil(f)
  local body = f:read("a")
  f:close()
  local keys = ap.parse_gamecfg(body)
  local seen = {}
  for _, slot in ipairs({ "manager", "speed_ability", "speed_anchor", "melee_ability", "melee_anchor" }) do
    local key = keys[slot]
    lu.assertNotNil(key, slot)
    lu.assertStrMatches(key, "^map://preset/u[0-9a-f]+$")
    lu.assertNil(seen[key], slot .. " 的 key 与别的槽位重复")
    seen[key] = slot
  end
end

TestAbilityPresetsReplace = {}

function TestAbilityPresetsReplace:test_replaces_exactly_once()
  local out = ap.replace_key(FIXTURE,
    "map://preset/ubdb4a7e737d4eddb87729e9055ba375", "map://preset/u0000000000000000000000000000000a")
  lu.assertStrContains(out, "map://preset/u0000000000000000000000000000000a")
  lu.assertNil(out:find("map://preset/ubdb4a7e737d4eddb87729e9055ba375", 1, true))
end

function TestAbilityPresetsReplace:test_missing_old_key_is_an_error()
  local out, err = ap.replace_key(FIXTURE, "map://preset/uffffffffffffffffffffffffffffffff", "x")
  lu.assertNil(out)
  lu.assertStrContains(err, "找不到")
end

function TestAbilityPresetsReplace:test_repeated_old_key_is_an_error()
  local dup = FIXTURE .. "\n-- map://preset/ubdb4a7e737d4eddb87729e9055ba375\n"
  local out, err = ap.replace_key(dup,
    "map://preset/ubdb4a7e737d4eddb87729e9055ba375", "x")
  lu.assertNil(out)
  lu.assertStrContains(err, "多次")
end

TestAbilityPresetsPlan = {}

function TestAbilityPresetsPlan:test_all_present_keeps_skills_and_reapplies_anchors()
  local actions = ap.plan({
    manager = true, speed_ability = true, speed_anchor = true,
    melee_ability = true, melee_anchor = true,
  })
  local ops = {}
  for _, a in ipairs(actions) do ops[a.slot] = a.op end
  lu.assertEquals(ops, {
    manager = "keep", speed_ability = "keep", speed_anchor = "reapply",
    melee_ability = "keep", melee_anchor = "reapply",
  })
end

function TestAbilityPresetsPlan:test_missing_preset_is_rebuilt()
  local actions = ap.plan({ manager = false })
  local ops = {}
  for _, a in ipairs(actions) do ops[a.slot] = a.op end
  lu.assertEquals(ops.manager, "rebuild")
  lu.assertEquals(ops.speed_anchor, "rebuild")
end

TestAbilityPresetsEncoding = {}

function TestAbilityPresetsEncoding:test_json_string_escapes()
  lu.assertEquals(ap.json_string("abc"), '"abc"')
  lu.assertEquals(ap.json_string('a"b'), '"a\\"b"')
  lu.assertEquals(ap.json_string("a\nb"), '"a\\nb"')
  lu.assertEquals(ap.json_string("a\\b"), '"a\\\\b"')
  lu.assertEquals(ap.json_string("a\tb\r"), '"a\\tb\\r"')
end

-- argv_quote 按 CommandLineToArgvW 规则编码：反斜杠只在 " 或 \ 前特殊，
-- 收尾引号前的反斜杠要翻倍。
function TestAbilityPresetsEncoding:test_argv_quote()
  lu.assertEquals(ap.argv_quote("abc"), '"abc"')
  lu.assertEquals(ap.argv_quote('a"b'), '"a\\"b"')
  lu.assertEquals(ap.argv_quote("a\\b"), '"a\\b"')
  lu.assertEquals(ap.argv_quote('a\\"b'), '"a\\\\\\"b"')
  lu.assertEquals(ap.argv_quote("a\\"), '"a\\\\"')
  lu.assertEquals(ap.argv_quote('{"x":0.0}'), '"{\\"x\\":0.0}"')
end

-- cmd_protect 按 cmd 的朴素引号态（每个 " 都翻转）给引号外的元字符补 ^；
-- 引号内的一律不动。
function TestAbilityPresetsEncoding:test_cmd_protect()
  -- 引号内的 > 不动
  lu.assertEquals(ap.cmd_protect('"a>b"'), '"a>b"')
  -- \" 序列会把 cmd 的引号态翻出去，后面的 > 要补 ^
  lu.assertEquals(ap.cmd_protect('"a\\"b>c"'), '"a\\"b^>c"')
  -- 引号外的 ^ 自身翻倍，引号内的不动
  lu.assertEquals(ap.cmd_protect('"a\\"^b"'), '"a\\"^^b"')
  lu.assertEquals(ap.cmd_protect('"a^b"'), '"a^b"')
end

-- 管线合起来：壳注释里的 `> 0` 经过 json_string + argv_quote + cmd_protect 后，
-- 必须在 cmd 层面被 ^ 保护（这是 issue #9 实跑踩出来的坑）。
function TestAbilityPresetsEncoding:test_full_pipeline_protects_gt_in_shell_comment()
  local fragment = ap.cmd_protect(ap.argv_quote("SourceCode=" .. ap.json_string("melee_hit 要求 > 0")))
  lu.assertStrContains(fragment, "^>")
end

TestAbilityPresetsOutput = {}

function TestAbilityPresetsOutput:test_extract_new_id_picks_the_non_template_id()
  local out = '{"success":true,"data":{"source":"map://preset/uccfb9dbe3f4428bb972096ba01f1f25",'
    .. '"asset_id":"map://preset/uaf2781161d6460990a4941b12ad30c2"}}'
  lu.assertEquals(ap.extract_new_id(out, "map://preset/uccfb9dbe3f4428bb972096ba01f1f25"),
    "map://preset/uaf2781161d6460990a4941b12ad30c2")
end

function TestAbilityPresetsOutput:test_extract_new_id_returns_nil_when_only_template_shows()
  lu.assertNil(ap.extract_new_id(
    "map://preset/uccfb9dbe3f4428bb972096ba01f1f25", "map://preset/uccfb9dbe3f4428bb972096ba01f1f25"))
end

function TestAbilityPresetsOutput:test_succeeded()
  lu.assertTrue(ap.succeeded('{"success":true}'))
  lu.assertTrue(ap.succeeded('{ "success" : true }'))
  lu.assertFalse(ap.succeeded('{"success":false}'))
  lu.assertFalse(ap.succeeded("garbage"))
end

-- --fix-names 的纯函数部分（issue #30）。真编辑器那几步靠人工在编辑器开着本图时验，
-- 这里只测「探针怎么解析、计划怎么定、四步里的 id 与脚本体怎么来」。
TestAbilityPresetsFixNamesProbe = {}

-- 编辑态 exec 探针固定 `typeof(v) .. "|" .. tostring(v)`：好的是 String，
-- 中招的是编辑器侧 unicode 对象（typeof 为 userdata、tostring 是 u'...'）。
function TestAbilityPresetsFixNamesProbe:test_parse_probe_reads_type_and_value()
  local kind, value = ap.parse_probe("String|技能背包")
  lu.assertEquals(kind, "String")
  lu.assertEquals(value, "技能背包")

  local bad_kind, bad_value = ap.parse_probe("userdata|u'\\u52a0\\u901f\\u6280\\u80fd'")
  lu.assertEquals(bad_kind, "userdata")
  lu.assertEquals(bad_value, "u'\\u52a0\\u901f\\u6280\\u80fd'")
end

-- 名字里带 | 也不该切错：类型只取第一个 | 之前那段。
function TestAbilityPresetsFixNamesProbe:test_parse_probe_keeps_pipes_inside_the_value()
  local kind, value = ap.parse_probe("String|a|b")
  lu.assertEquals(kind, "String")
  lu.assertEquals(value, "a|b")
end

-- exec 没跑成时输出是别的形态（实测多行内联会被 cmd 换行切断，只回 "Execution succeeded."）。
function TestAbilityPresetsFixNamesProbe:test_parse_probe_rejects_foreign_output()
  lu.assertNil(ap.parse_probe("Execution succeeded."))
  lu.assertNil(ap.parse_probe(nil))
end

-- get-asset-value 的纯文本输出只剪尾部换行：正文（含内部空格）照留。
function TestAbilityPresetsFixNamesProbe:test_clean_name_trims_trailing_newlines_only()
  lu.assertEquals(ap.clean_name("技能背包\r\n"), "技能背包")
  lu.assertEquals(ap.clean_name("技能背包\n"), "技能背包")
  lu.assertEquals(ap.clean_name("a b"), "a b")
  lu.assertEquals(ap.clean_name(""), "")
  lu.assertNil(ap.clean_name(nil))
end

TestAbilityPresetsFixNamesPlan = {}

local function probes_for(kind_by_slot, name)
  local probes = {}
  for slot, kind in pairs(kind_by_slot) do
    probes[slot] = { kind = kind, name = name or ("name-" .. slot) }
  end
  return probes
end

-- 五个预设全是 string：一个都不动（这是本图现在的常态，工具跑完应报「无需修」）。
function TestAbilityPresetsFixNamesPlan:test_all_string_is_all_skips()
  local kinds = {}
  for _, spec in ipairs(ap.SPECS) do kinds[spec.slot] = "String" end
  local actions = ap.plan_name_fixes(probes_for(kinds))
  lu.assertEquals(#actions, #ap.SPECS)
  for i, action in ipairs(actions) do
    lu.assertEquals(action.slot, ap.SPECS[i].slot, "计划顺序应与 SPECS 同序")
    lu.assertEquals(action.op, "skip")
    lu.assertEquals(action.name, "name-" .. action.slot)
  end
end

function TestAbilityPresetsFixNamesPlan:test_non_string_goes_to_fix_with_the_read_back_name()
  local kinds = {}
  for _, spec in ipairs(ap.SPECS) do kinds[spec.slot] = "String" end
  kinds.speed_anchor = "userdata"
  local actions = ap.plan_name_fixes(probes_for(kinds, "加速锚点"))
  local ops = {}
  for _, action in ipairs(actions) do ops[action.slot] = action.op end
  lu.assertEquals(ops.speed_anchor, "fix")
  lu.assertEquals(ops.manager, "skip")
  for _, action in ipairs(actions) do
    if action.slot == "speed_anchor" then
      lu.assertEquals(action.name, "加速锚点", "改名的名字取自 get-asset-value 的内容")
    end
  end
end

-- 探针没读出来 / 名字为空 → unreadable（报错不猜），不能当成 skip 蒙过去。
function TestAbilityPresetsFixNamesPlan:test_unreadable_probe_is_not_a_skip()
  local actions = ap.plan_name_fixes({ speed_ability = { kind = nil, name = "加速技能" } })
  local ops = {}
  for _, action in ipairs(actions) do ops[action.slot] = action.op end
  lu.assertEquals(ops.speed_ability, "unreadable")
  lu.assertEquals(ops.melee_ability, "unreadable")

  local empty = ap.plan_name_fixes({ speed_ability = { kind = "userdata", name = "" } })
  lu.assertEquals(empty[2].op, "unreadable")
end

TestAbilityPresetsFixNamesUnits = {}

-- create-unit-by-asset 回的是 { "unit_ids": [...] }（本机实测：技能预设建出 3 个 = 根 + 两个子）。
function TestAbilityPresetsFixNamesUnits:test_extract_unit_ids()
  local out = '{\n  "success": true,\n  "unit_ids": [\n    1872427231,\n    1301180818,\n    1703852413\n  ]\n}'
  lu.assertEquals(ap.extract_unit_ids(out), { "1872427231", "1301180818", "1703852413" })
  lu.assertEquals(ap.extract_unit_ids('{"success":true,"unit_ids":[]}'), {})
  lu.assertEquals(ap.extract_unit_ids('{"success":true}'), {})
  lu.assertEquals(ap.extract_unit_ids(nil), {})
end

function TestAbilityPresetsFixNamesUnits:test_parse_unit_get()
  local root = ap.parse_unit_get('{"data":{"unit":{"name":"u\\u52a0","unit_id":"1872427231"}}}')
  lu.assertEquals(root.id, "1872427231")
  lu.assertNil(root.parent, "顶层单位没有 parent_unit_id")

  local child = ap.parse_unit_get(
    '{"data":{"unit":{"unit_id":"1301180818","parent_unit_id":"1872427231"}}}')
  lu.assertEquals(child.id, "1301180818")
  lu.assertEquals(child.parent, "1872427231")

  lu.assertNil(ap.parse_unit_get("garbage"))
  lu.assertNil(ap.parse_unit_get(nil))
end

-- 删的时候只删根：create-unit-by-asset 连子单位一起返回，删子会 EDITOR_UNIT_NOT_FOUND。
function TestAbilityPresetsFixNamesUnits:test_roots_of_keeps_only_ids_whose_parent_is_outside()
  local roots = ap.roots_of({
    { id = "1", parent = nil },
    { id = "2", parent = "1" },
    { id = "3", parent = "1" },
  })
  lu.assertEquals(roots, { "1" })
end

-- 预设层级不止一个根时（本图的 5 个预设都不是），roots_of 会把它们都挑出来，
-- apply_name_fix 见到 #roots ~= 1 就报错不敢猜。
function TestAbilityPresetsFixNamesUnits:test_roots_of_reports_every_root()
  lu.assertEquals(ap.roots_of({ { id = "1" }, { id = "2", parent = "1" }, { id = "9" } }),
    { "1", "9" })
  lu.assertEquals(ap.roots_of({}), {})
end

TestAbilityPresetsFixNamesScript = {}

TestAbilityPresetsExistence = {}

function TestAbilityPresetsExistence:test_missing_preset_is_rebuilt_despite_successful_query()
  local listed = '{"success":true,"asset_ids":["map://preset/ukeep"]}'
  lu.assertTrue(ap.preset_exists(listed, "map://preset/ukeep"))
  lu.assertFalse(ap.preset_exists(listed, "map://preset/umissing"))
  local actions = ap.plan({manager=true, speed_ability=true, speed_anchor=true,
    melee_ability=ap.preset_exists(listed, "map://preset/umissing"), melee_anchor=true})
  for _, action in ipairs(actions) do
    if action.slot == "melee_ability" then lu.assertEquals(action.op, "rebuild") end
  end
end

function TestAbilityPresetsExistence:test_invalid_inventory_cannot_silently_rebuild_everything()
  lu.assertError(ap.preset_exists, '{"success":true,"value":null}', "map://preset/ux")
  lu.assertFalse(ap.preset_exists('{"success":false}', "map://preset/ux"))
  lu.assertFalse(ap.preset_exists('{"success":true,"asset_ids":[]}', "map://preset/ux"))
end

function TestAbilityPresetsFixNamesScript:test_lua_quote()
  lu.assertEquals(ap.lua_quote("技能背包"), '"技能背包"')
  lu.assertEquals(ap.lua_quote('a"b'), '"a\\"b"')
  lu.assertEquals(ap.lua_quote("a\\b"), '"a\\\\b"')
  lu.assertEquals(ap.lua_quote("a\nb"), '"a\\010b"')
  lu.assertEquals(ap.lua_quote("a\tb"), '"a\\009b"')
end

-- 引号/反斜杠/控制字符混在一起也要能原样回读：脚本里嵌的就是这个字面量。
function TestAbilityPresetsFixNamesScript:test_lua_quote_round_trips()
  local loader = loadstring or load
  local s = 'ke"y\\na"b\r\n\t'
  local chunk = loader("return " .. ap.lua_quote(s))
  lu.assertNotNil(chunk)
  lu.assertEquals(chunk(), s)
end

-- fail() 的消息带 "ability-presets: " 前缀，跨 pcall 重抛时先剥掉，别叠成两层。
function TestAbilityPresetsFixNamesScript:test_strip_prefix()
  lu.assertEquals(ap.strip_prefix("ability-presets: 场景里已有 1 个同名单位"), "场景里已有 1 个同名单位")
  lu.assertEquals(ap.strip_prefix("别的错误"), "别的错误")
end

-- 四步里的第 3 步：脚本要按 rename 后的名字找单位、把数据同步回指定的那个预设。
function TestAbilityPresetsFixNamesScript:test_sync_script_targets_unit_and_asset()
  local key = "map://preset/uaf2781161d6460990a4941b12ad30c2"
  local src = ap.sync_script(key, "加速锚点")
  lu.assertStrContains(src, "World:FindFirstChild(\"加速锚点\")")
  lu.assertStrContains(src, "AssetService.SyncAssetFromUnit")
  lu.assertStrContains(src, '"' .. key .. '"')
  lu.assertStrContains(src, 'return "sync="')
end

-- 脚本自己 pcall 并回 `sync=true` 标记，工具认这个标记判成败（exec 的 success 只说明脚本跑过了）。
function TestAbilityPresetsFixNamesScript:test_sync_script_failure_returns_error_text()
  lu.assertStrContains(ap.sync_script("map://preset/ux", "n"), "return \"ERROR:")
end

function TestAbilityPresetsFixNamesScript:test_sync_succeeded_reads_the_marker()
  lu.assertTrue(ap.sync_succeeded('{"success":true,"result":"sync=true asset=map://preset/ux"}'))
  lu.assertFalse(ap.sync_succeeded('{"success":true,"result":"ERROR: 场景里找不到单位"}'))
  lu.assertFalse(ap.sync_succeeded('{"success":true,"result":"sync=false"}'))
  lu.assertFalse(ap.sync_succeeded("Execution succeeded."))
  lu.assertFalse(ap.sync_succeeded(nil))
end

function TestAbilityPresetsFixNamesScript:test_probe_script_returns_typeof()
  local src = ap.probe_script("map://preset/uaf2781161d6460990a4941b12ad30c2")
  lu.assertStrContains(src, "typeof(v)")
  lu.assertStrContains(src, 'GetAssetValue("map://preset/uaf2781161d6460990a4941b12ad30c2", "Name")')
end

function TestAbilityPresetsFixNamesScript:test_exec_result_extracts_json_result()
  lu.assertEquals(ap.exec_result('{"success":true,"result":"String|技能背包"}'), "String|技能背包")
  lu.assertNil(ap.exec_result('{"success":true}'))
  lu.assertNil(ap.exec_result(nil))
end

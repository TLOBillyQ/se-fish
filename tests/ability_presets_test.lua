-- 纯模块单测：ability-presets 的 GameCfg key 解析 / 回写、动作规划与命令行编码。
-- 不碰编辑器、不起子进程；真实 editor-cli 行为只能在本机编辑器开着地图时人工验。
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

-- 纯模块单测：ability-presets 的 GameCfg key 解析 / 回写、动作规划、命令行编码，以及
-- --fix-names 的探针解析 / 修复计划 / unit id 与四步脚本生成（issue #30）。
-- 不碰编辑器、不起子进程；真实 editor-cli 行为只能在本机编辑器开着地图、编辑态时人工验。
-- 迁移自 tests/tooling/ability_presets_test.lua（#92，LuaUnit → 原生 Busted）；
-- 案例顺序沿用旧入口的类名 + 方法名字典序，保证与迁移前后可逐条对账。
local ap = require("tools.ability_presets")

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

describe("TestAbilityPresetsEncoding", function()
  -- argv_quote 按 CommandLineToArgvW 规则编码：反斜杠只在 " 或 \ 前特殊，
  -- 收尾引号前的反斜杠要翻倍。
  it("test_argv_quote", function()
    assert.are.equal('"abc"', ap.argv_quote("abc"))
    assert.are.equal('"a\\"b"', ap.argv_quote('a"b'))
    assert.are.equal('"a\\b"', ap.argv_quote("a\\b"))
    assert.are.equal('"a\\\\\\"b"', ap.argv_quote('a\\"b'))
    assert.are.equal('"a\\\\"', ap.argv_quote("a\\"))
    assert.are.equal('"{\\"x\\":0.0}"', ap.argv_quote('{"x":0.0}'))
  end)

  -- cmd_protect 按 cmd 的朴素引号态（每个 " 都翻转）给引号外的元字符补 ^；
  -- 引号内的一律不动。
  it("test_cmd_protect", function()
    -- 引号内的 > 不动
    assert.are.equal('"a>b"', ap.cmd_protect('"a>b"'))
    -- \" 序列会把 cmd 的引号态翻出去，后面的 > 要补 ^
    assert.are.equal('"a\\"b^>c"', ap.cmd_protect('"a\\"b>c"'))
    -- 引号外的 ^ 自身翻倍，引号内的不动
    assert.are.equal('"a\\"^^b"', ap.cmd_protect('"a\\"^b"'))
    assert.are.equal('"a^b"', ap.cmd_protect('"a^b"'))
  end)

  -- 管线合起来：壳注释里的 `> 0` 经过 json_string + argv_quote + cmd_protect 后，
  -- 必须在 cmd 层面被 ^ 保护（这是 issue #9 实跑踩出来的坑）。
  it("test_full_pipeline_protects_gt_in_shell_comment", function()
    local fragment = ap.cmd_protect(ap.argv_quote("SourceCode=" .. ap.json_string("melee_hit 要求 > 0")))
    assert.matches("^>", fragment, 1, true)
  end)

  it("test_json_string_escapes", function()
    assert.are.equal('"abc"', ap.json_string("abc"))
    assert.are.equal('"a\\"b"', ap.json_string('a"b'))
    assert.are.equal('"a\\nb"', ap.json_string("a\nb"))
    assert.are.equal('"a\\\\b"', ap.json_string("a\\b"))
    assert.are.equal('"a\\tb\\r"', ap.json_string("a\tb\r"))
  end)
end)

describe("TestAbilityPresetsExistence", function()
  it("test_invalid_inventory_cannot_silently_rebuild_everything", function()
    assert.error(function() return ap.preset_exists('{"success":true,"value":null}', "map://preset/ux") end)
    assert.is_false(ap.preset_exists('{"success":false}', "map://preset/ux"))
    assert.is_false(ap.preset_exists('{"success":true,"asset_ids":[]}', "map://preset/ux"))
  end)

  it("test_missing_preset_is_rebuilt_despite_successful_query", function()
    local listed = '{"success":true,"asset_ids":["map://preset/ukeep"]}'
    assert.is_true(ap.preset_exists(listed, "map://preset/ukeep"))
    assert.is_false(ap.preset_exists(listed, "map://preset/umissing"))
    local actions = ap.plan({ manager = true, speed_ability = true, speed_anchor = true,
      melee_ability = ap.preset_exists(listed, "map://preset/umissing"), melee_anchor = true })
    for _, action in ipairs(actions) do
      if action.slot == "melee_ability" then assert.are.equal("rebuild", action.op) end
    end
  end)
end)

describe("TestAbilityPresetsFixNamesPlan", function()
  local function probes_for(kind_by_slot, name)
    local probes = {}
    for slot, kind in pairs(kind_by_slot) do
      probes[slot] = { kind = kind, name = name or ("name-" .. slot) }
    end
    return probes
  end

  -- 五个预设全是 string：一个都不动（这是本图现在的常态，工具跑完应报「无需修」）。
  it("test_all_string_is_all_skips", function()
    local kinds = {}
    for _, spec in ipairs(ap.SPECS) do kinds[spec.slot] = "String" end
    local actions = ap.plan_name_fixes(probes_for(kinds))
    assert.are.equal(#ap.SPECS, #actions)
    for i, action in ipairs(actions) do
      assert.are.equal(ap.SPECS[i].slot, action.slot, "计划顺序应与 SPECS 同序")
      assert.are.equal("skip", action.op)
      assert.are.equal("name-" .. action.slot, action.name)
    end
  end)

  it("test_non_string_goes_to_fix_with_the_read_back_name", function()
    local kinds = {}
    for _, spec in ipairs(ap.SPECS) do kinds[spec.slot] = "String" end
    kinds.speed_anchor = "userdata"
    local actions = ap.plan_name_fixes(probes_for(kinds, "加速锚点"))
    local ops = {}
    for _, action in ipairs(actions) do ops[action.slot] = action.op end
    assert.are.equal("fix", ops.speed_anchor)
    assert.are.equal("skip", ops.manager)
    for _, action in ipairs(actions) do
      if action.slot == "speed_anchor" then
        assert.are.equal("加速锚点", action.name, "改名的名字取自 get-asset-value 的内容")
      end
    end
  end)

  -- 探针没读出来 / 名字为空 → unreadable（报错不猜），不能当成 skip 蒙过去。
  it("test_unreadable_probe_is_not_a_skip", function()
    local actions = ap.plan_name_fixes({ speed_ability = { kind = nil, name = "加速技能" } })
    local ops = {}
    for _, action in ipairs(actions) do ops[action.slot] = action.op end
    assert.are.equal("unreadable", ops.speed_ability)
    assert.are.equal("unreadable", ops.melee_ability)

    local empty = ap.plan_name_fixes({ speed_ability = { kind = "userdata", name = "" } })
    assert.are.equal("unreadable", empty[2].op)
  end)
end)

describe("TestAbilityPresetsFixNamesProbe", function()
  -- get-asset-value 的纯文本输出只剪尾部换行：正文（含内部空格）照留。
  it("test_clean_name_trims_trailing_newlines_only", function()
    assert.are.equal("技能背包", ap.clean_name("技能背包\r\n"))
    assert.are.equal("技能背包", ap.clean_name("技能背包\n"))
    assert.are.equal("a b", ap.clean_name("a b"))
    assert.are.equal("", ap.clean_name(""))
    assert.is_nil(ap.clean_name(nil))
  end)

  -- 名字里带 | 也不该切错：类型只取第一个 | 之前那段。
  it("test_parse_probe_keeps_pipes_inside_the_value", function()
    local kind, value = ap.parse_probe("String|a|b")
    assert.are.equal("String", kind)
    assert.are.equal("a|b", value)
  end)

  -- 编辑态 exec 探针固定 `typeof(v) .. "|" .. tostring(v)`：好的是 String，
  -- 中招的是编辑器侧 unicode 对象（typeof 为 userdata、tostring 是 u'...'）。
  it("test_parse_probe_reads_type_and_value", function()
    local kind, value = ap.parse_probe("String|技能背包")
    assert.are.equal("String", kind)
    assert.are.equal("技能背包", value)

    local bad_kind, bad_value = ap.parse_probe("userdata|u'\\u52a0\\u901f\\u6280\\u80fd'")
    assert.are.equal("userdata", bad_kind)
    assert.are.equal("u'\\u52a0\\u901f\\u6280\\u80fd'", bad_value)
  end)

  -- exec 没跑成时输出是别的形态（实测多行内联会被 cmd 换行切断，只回 "Execution succeeded."）。
  it("test_parse_probe_rejects_foreign_output", function()
    assert.is_nil(ap.parse_probe("Execution succeeded."))
    assert.is_nil(ap.parse_probe(nil))
  end)
end)

describe("TestAbilityPresetsFixNamesScript", function()
  it("test_exec_result_extracts_json_result", function()
    assert.are.equal("String|技能背包", ap.exec_result('{"success":true,"result":"String|技能背包"}'))
    assert.is_nil(ap.exec_result('{"success":true}'))
    assert.is_nil(ap.exec_result(nil))
  end)

  it("test_lua_quote", function()
    assert.are.equal('"技能背包"', ap.lua_quote("技能背包"))
    assert.are.equal('"a\\"b"', ap.lua_quote('a"b'))
    assert.are.equal('"a\\\\b"', ap.lua_quote("a\\b"))
    assert.are.equal('"a\\010b"', ap.lua_quote("a\nb"))
    assert.are.equal('"a\\009b"', ap.lua_quote("a\tb"))
  end)

  -- 引号/反斜杠/控制字符混在一起也要能原样回读：脚本里嵌的就是这个字面量。
  it("test_lua_quote_round_trips", function()
    local loader = loadstring or load
    local s = 'ke"y\\na"b\r\n\t'
    local chunk = loader("return " .. ap.lua_quote(s))
    assert.is_not_nil(chunk)
    assert.are.equal(s, chunk())
  end)

  -- 四步里的第 3 步：脚本要按 rename 后的名字找单位、把数据同步回指定的那个预设。
  it("test_probe_script_returns_typeof", function()
    local src = ap.probe_script("map://preset/uaf2781161d6460990a4941b12ad30c2")
    assert.matches("typeof(v)", src, 1, true)
    assert.matches('GetAssetValue("map://preset/uaf2781161d6460990a4941b12ad30c2", "Name")', src, 1, true)
  end)

  -- fail() 的消息带 "ability-presets: " 前缀，跨 pcall 重抛时先剥掉，别叠成两层。
  it("test_strip_prefix", function()
    assert.are.equal("场景里已有 1 个同名单位", ap.strip_prefix("ability-presets: 场景里已有 1 个同名单位"))
    assert.are.equal("别的错误", ap.strip_prefix("别的错误"))
  end)

  -- 脚本自己 pcall 并回 `sync=true` 标记，工具认这个标记判成败（exec 的 success 只说明脚本跑过了）。
  it("test_sync_script_failure_returns_error_text", function()
    assert.matches('return "ERROR:', ap.sync_script("map://preset/ux", "n"), 1, true)
  end)

  it("test_sync_script_targets_unit_and_asset", function()
    local key = "map://preset/uaf2781161d6460990a4941b12ad30c2"
    local src = ap.sync_script(key, "加速锚点")
    assert.matches('World:FindFirstChild("加速锚点")', src, 1, true)
    assert.matches("AssetService.SyncAssetFromUnit", src, 1, true)
    assert.matches('"' .. key .. '"', src, 1, true)
    assert.matches('return "sync="', src, 1, true)
  end)

  it("test_sync_succeeded_reads_the_marker", function()
    assert.is_true(ap.sync_succeeded('{"success":true,"result":"sync=true asset=map://preset/ux"}'))
    assert.is_false(ap.sync_succeeded('{"success":true,"result":"ERROR: 场景里找不到单位"}'))
    assert.is_false(ap.sync_succeeded('{"success":true,"result":"sync=false"}'))
    assert.is_false(ap.sync_succeeded("Execution succeeded."))
    assert.is_false(ap.sync_succeeded(nil))
  end)
end)

describe("TestAbilityPresetsFixNamesUnits", function()
  -- create-unit-by-asset 回的是 { "unit_ids": [...] }（本机实测：技能预设建出 3 个 = 根 + 两个子）。
  it("test_extract_unit_ids", function()
    local out = '{\n  "success": true,\n  "unit_ids": [\n    1872427231,\n    1301180818,\n    1703852413\n  ]\n}'
    assert.same({ "1872427231", "1301180818", "1703852413" }, ap.extract_unit_ids(out))
    assert.same({}, ap.extract_unit_ids('{"success":true,"unit_ids":[]}'))
    assert.same({}, ap.extract_unit_ids('{"success":true}'))
    assert.same({}, ap.extract_unit_ids(nil))
  end)

  it("test_parse_unit_get", function()
    local root = ap.parse_unit_get('{"data":{"unit":{"name":"u\\u52a0","unit_id":"1872427231"}}}')
    assert.are.equal("1872427231", root.id)
    assert.is_nil(root.parent, "顶层单位没有 parent_unit_id")

    local child = ap.parse_unit_get(
      '{"data":{"unit":{"unit_id":"1301180818","parent_unit_id":"1872427231"}}}')
    assert.are.equal("1301180818", child.id)
    assert.are.equal("1872427231", child.parent)

    assert.is_nil(ap.parse_unit_get("garbage"))
    assert.is_nil(ap.parse_unit_get(nil))
  end)

  -- 删的时候只删根：create-unit-by-asset 连子单位一起返回，删子会 EDITOR_UNIT_NOT_FOUND。
  it("test_roots_of_keeps_only_ids_whose_parent_is_outside", function()
    local roots = ap.roots_of({
      { id = "1", parent = nil },
      { id = "2", parent = "1" },
      { id = "3", parent = "1" },
    })
    assert.same({ "1" }, roots)
  end)

  -- 预设层级不止一个根时（本图的 5 个预设都不是），roots_of 会把它们都挑出来，
  -- apply_name_fix 见到 #roots ~= 1 就报错不敢猜。
  it("test_roots_of_reports_every_root", function()
    assert.same({ "1", "9" }, ap.roots_of({ { id = "1" }, { id = "2", parent = "1" }, { id = "9" } }))
    assert.same({}, ap.roots_of({}))
  end)
end)

describe("TestAbilityPresetsOutput", function()
  it("test_extract_new_id_picks_the_non_template_id", function()
    local out = '{"success":true,"data":{"source":"map://preset/uccfb9dbe3f4428bb972096ba01f1f25",'
      .. '"asset_id":"map://preset/uaf2781161d6460990a4941b12ad30c2"}}'
    assert.are.equal("map://preset/uaf2781161d6460990a4941b12ad30c2",
      ap.extract_new_id(out, "map://preset/uccfb9dbe3f4428bb972096ba01f1f25"))
  end)

  it("test_extract_new_id_returns_nil_when_only_template_shows", function()
    assert.is_nil(ap.extract_new_id(
      "map://preset/uccfb9dbe3f4428bb972096ba01f1f25", "map://preset/uccfb9dbe3f4428bb972096ba01f1f25"))
  end)

  it("test_succeeded", function()
    assert.is_true(ap.succeeded('{"success":true}'))
    assert.is_true(ap.succeeded('{ "success" : true }'))
    assert.is_false(ap.succeeded('{"success":false}'))
    assert.is_false(ap.succeeded("garbage"))
  end)
end)

describe("TestAbilityPresetsParse", function()
  it("test_fixture_yields_all_five_keys", function()
    local keys = ap.parse_gamecfg(FIXTURE)
    assert.are.equal("map://preset/ubdb4a7e737d4eddb87729e9055ba375", keys.manager)
    assert.are.equal("map://preset/uf7fac66639546e2aa376151835cf3a6", keys.speed_ability)
    assert.are.equal("map://preset/uaf2781161d6460990a4941b12ad30c2", keys.speed_anchor)
    assert.are.equal("map://preset/u0d0b1993faa482b93e806d23715b73e", keys.melee_ability)
    assert.are.equal("map://preset/ucc500ac3aac4b749fd9bee03b57e4d5", keys.melee_anchor)
  end)

  -- 嵌套表（AnchorAttributes 的 Vector3 表）不能干扰条目截取。
  it("test_nested_table_does_not_confuse_entry_matching", function()
    local keys = ap.parse_gamecfg(FIXTURE)
    assert.are.equal("map://preset/ucc500ac3aac4b749fd9bee03b57e4d5", keys.melee_anchor)
  end)

  -- 真源对得上：直接读仓库的 common/GameCfg.lua，五个 key 都要在、互不重复。
  -- GameCfg.Ability 结构改动时这条先红，脚本不会在编辑器侧白跑。
  it("test_real_gamecfg_parses", function()
    local f = io.open("common/GameCfg.lua", "rb")
    assert.is_not_nil(f)
    local body = f:read("a")
    f:close()
    local keys = ap.parse_gamecfg(body)
    local seen = {}
    for _, slot in ipairs({ "manager", "speed_ability", "speed_anchor", "melee_ability", "melee_anchor" }) do
      local key = keys[slot]
      assert.is_not_nil(key, slot)
      assert.matches("^map://preset/u[0-9a-f]+$", key)
      assert.is_nil(seen[key], slot .. " 的 key 与别的槽位重复")
      seen[key] = slot
    end
  end)
end)

describe("TestAbilityPresetsPlan", function()
  it("test_all_present_keeps_skills_and_reapplies_anchors", function()
    local actions = ap.plan({
      manager = true, speed_ability = true, speed_anchor = true,
      melee_ability = true, melee_anchor = true,
    })
    local ops = {}
    for _, a in ipairs(actions) do ops[a.slot] = a.op end
    assert.same({
      manager = "keep", speed_ability = "keep", speed_anchor = "reapply",
      melee_ability = "keep", melee_anchor = "reapply",
    }, ops)
  end)

  it("test_missing_preset_is_rebuilt", function()
    local actions = ap.plan({ manager = false })
    local ops = {}
    for _, a in ipairs(actions) do ops[a.slot] = a.op end
    assert.are.equal("rebuild", ops.manager)
    assert.are.equal("rebuild", ops.speed_anchor)
  end)
end)

describe("TestAbilityPresetsReplace", function()
  it("test_missing_old_key_is_an_error", function()
    local out, err = ap.replace_key(FIXTURE, "map://preset/uffffffffffffffffffffffffffffffff", "x")
    assert.is_nil(out)
    assert.matches("找不到", err, 1, true)
  end)

  it("test_repeated_old_key_is_an_error", function()
    local dup = FIXTURE .. "\n-- map://preset/ubdb4a7e737d4eddb87729e9055ba375\n"
    local out, err = ap.replace_key(dup,
      "map://preset/ubdb4a7e737d4eddb87729e9055ba375", "x")
    assert.is_nil(out)
    assert.matches("多次", err, 1, true)
  end)

  it("test_replaces_exactly_once", function()
    local out = ap.replace_key(FIXTURE,
      "map://preset/ubdb4a7e737d4eddb87729e9055ba375", "map://preset/u0000000000000000000000000000000a")
    assert.matches("map://preset/u0000000000000000000000000000000a", out, 1, true)
    assert.is_nil(out:find("map://preset/ubdb4a7e737d4eddb87729e9055ba375", 1, true))
  end)
end)

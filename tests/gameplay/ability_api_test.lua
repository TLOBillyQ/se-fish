-- 纯模块单测：双端根 AbilityAPI 的转发名单，与包内 api.lua 的导出对齐，且转发行为正确。
-- 不 require 包内模块（它们依赖引擎服务，只能在试玩里验证），只读源码文本校对名单——
-- 包整包 vendor 不改，升级后改名/删名必须在这条接缝上立刻暴露。
local lu = require("luaunit")
local AbilityAPIBase = require("common.AbilityAPIBase")

local function exported_names(path, table_name)
  local names = {}
  for line in io.lines(path) do
    local name = line:match("^function " .. table_name .. "%.([%w_]+)%s*%(")
    if name then
      names[#names + 1] = name
    end
  end
  return names
end

local function sorted(list)
  local copy = {}
  for i, v in ipairs(list) do
    copy[i] = v
  end
  table.sort(copy)
  return copy
end

TestAbilityAPIBase = {}

function TestAbilityAPIBase:test_server_names_are_the_package_exports()
  lu.assertEquals(
    sorted(AbilityAPIBase.SERVER_API),
    sorted(exported_names("server/packages/ability_system/api.lua", "AbilityServerAPI"))
  )
end

function TestAbilityAPIBase:test_client_names_are_the_package_exports()
  lu.assertEquals(
    sorted(AbilityAPIBase.CLIENT_API),
    sorted(exported_names("client/packages/ability_system/api.lua", "AbilityClientAPI"))
  )
end

function TestAbilityAPIBase:test_build_exposes_only_the_listed_names()
  local impl = {}
  for _, name in ipairs(AbilityAPIBase.SERVER_API) do
    impl[name] = function() end
  end

  local api = AbilityAPIBase.build(impl, AbilityAPIBase.SERVER_API)

  local count = 0
  for _ in pairs(api) do
    count = count + 1
  end
  lu.assertEquals(count, #AbilityAPIBase.SERVER_API)
end

function TestAbilityAPIBase:test_build_forwards_arguments_and_return_values()
  local got
  local api = AbilityAPIBase.build({
    Ping = function(a, b)
      got = { a, b }
      return a, b
    end,
  }, { "Ping" })

  lu.assertEquals({ api.Ping(2, 3) }, { 2, 3 })
  lu.assertEquals(got, { 2, 3 })
end

function TestAbilityAPIBase:test_missing_api_fails_loudly_at_build_time()
  lu.assertErrorMsgContains(
    "技能包缺少接口: Nope",
    function() AbilityAPIBase.build({}, { "Nope" }) end
  )
end

-- 聚合入口的锚点补挂还依赖两个包内模块：框架 anchor_logic 与各锚点行为模块。
-- 它们不在 api.lua 的导出名单里，所以单独拿文件存在性兜底：包升级改名时这里一起断。
local function file_exists(path)
  local handle = io.open(path, "rb")
  if not handle then
    return false
  end
  handle:close()
  return true
end

function TestAbilityAPIBase:test_anchor_framework_module_exists()
  lu.assertTrue(file_exists("server/packages/ability_system/anchor_logic.lua"),
    "包内锚点框架 anchor_logic.lua 不在预期路径")
end

function TestAbilityAPIBase:test_every_configured_anchor_behavior_module_exists()
  local GameCfg = require("common.GameCfg")
  for _, entry in ipairs(GameCfg.Ability.InitialAbilities or {}) do
    if entry.AnchorBehavior then
      local path = entry.AnchorBehavior == "melee_hit"
        and "server/AbilityBehaviors/melee_hit.lua"
        or "server/packages/ability_system/anchors/" .. entry.AnchorBehavior .. ".lua"
      lu.assertTrue(file_exists(path), path .. " 不存在（行为模块名写错或包升级改名）")
    end
  end
end

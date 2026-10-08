-- 纯模块单测：#153 三个新 vendor 包的双端根聚合入口转发名单，与包内 api.lua 的导出对齐。
-- 与 ability_api_test 同一思路：不 require 包内模块（依赖引擎服务，只能在试玩里验证），
-- 只读源码文本校对名单——包整包 vendor 不改，升级后改名/删名必须在这条接缝上立刻暴露。
-- attr_rule / official_ai_feature 的导出嵌在 return 表的 Funcs 里（facade 拍平转发），
-- modifier_system 平铺；Enums / Configs 等表字段由 facade 原样透传，不在名单里。
local lu = require("luaunit")

-- 从 api.lua 末尾的 return 表里提取自赋值导出（`Name = Name,`）；
-- Enums / Configs 是表字段透传，不是函数，排除在名单外。
local function exported_names(path)
  local handle = assert(io.open(path, "rb"), path .. " 读不到")
  local text = handle:read("a")
  handle:close()
  local block = text:match("return%s*{%s*(.-)%s*}%s*$")
  assert(block, path .. " 没找到 return 表")
  -- Prefabs 是嵌套表（PresetLink 载体类透传），其自赋值条目不是函数，先整块剔除。
  block = block:gsub("Prefabs%s*=%s*{.-}", "")
  local names = {}
  for key, value in block:gmatch("([%w_]+)%s*=%s*([%w_]+)%s*,") do
    if key == value and key ~= "Enums" and key ~= "Configs" then
      names[#names + 1] = key
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

-- 名单 ↔ 包内 api.lua 路径对照：base 模块的 field 名单须与 path 的导出一致。
local CASES = {
  { base = "common.AttrAPIBase", field = "SERVER_API", path = "server/packages/attr_rule/api.lua" },
  { base = "common.AttrAPIBase", field = "CLIENT_API", path = "client/packages/attr_rule/api.lua" },
  { base = "common.ModifierAPIBase", field = "SERVER_API", path = "server/packages/modifier_system/api.lua" },
  { base = "common.ModifierAPIBase", field = "CLIENT_API", path = "client/packages/modifier_system/api.lua" },
  { base = "common.AiAPIBase", field = "SERVER_API", path = "server/packages/official_ai_feature/api.lua" },
}

TestPackageAPI = {}

function TestPackageAPI:test_names_match_package_exports()
  for _, case in ipairs(CASES) do
    local base = require(case.base)
    lu.assertEquals(
      sorted(base[case.field]),
      sorted(exported_names(case.path)),
      case.base .. "." .. case.field .. " 与 " .. case.path .. " 导出不一致"
    )
  end
end

function TestPackageAPI:test_build_labels_failure_with_package_name()
  lu.assertErrorMsgContains(
    "[AttrAPI] 属性规则包缺少接口: Nope",
    function() require("common.AttrAPIBase").build({}, { "Nope" }) end
  )
end

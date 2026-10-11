local lu = require("luaunit")
local bootstrap = require("tools.acceptance.bootstrap")
local sources = require("tools.quality.sources")

TestQuality = {}

function TestQuality:test_fixed_commits_and_unknown_tool_failure()
  lu.assertEquals(bootstrap.pins.acceptance4lua, "8dd107144a7635596d75e4fccfce35121dc67570")
  lu.assertEquals(bootstrap.pins.dry4lua, "1dd42d73116921cd54a00c7b132a9b097e4a288a")
  local ok = bootstrap.ensure("unknown4lua")
  lu.assertNil(ok)
end

function TestQuality:test_only_owned_lua_sources()
  lu.assertTrue(sources.owned("common/RateLimit.lua"))
  lu.assertTrue(sources.owned("client/main.lua"))
  lu.assertTrue(sources.owned("server/Mgr/MgrFishUnit.lua"))
  lu.assertFalse(sources.owned("tools/quality/report.lua"))
  lu.assertFalse(sources.owned("tests/run.lua"))
  lu.assertFalse(sources.owned("server/packages/ability_system/init.lua"))
  lu.assertFalse(sources.owned("client/packages/ability_system/init.lua"))
  lu.assertFalse(sources.owned("common/packages/attr_rule/init.lua"))
  lu.assertFalse(sources.owned("server/_trigger/fish.lua"))
  lu.assertFalse(sources.owned("data/Prefab.lua"))
  lu.assertFalse(sources.owned("build/generated.lua"))
end

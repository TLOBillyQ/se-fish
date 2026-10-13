-- 质量工具的固定提交与业务源码范围（#92 迁移自 tests/tooling/quality_test.lua）。
-- 案例顺序沿用旧入口的类名 + 方法名字典序。
-- `bootstrap.ensure("unknown4lua")` 只查登记表，不访问网络、不需要 .toolcache，跨平台可跑。
local bootstrap = require("tools.acceptance.bootstrap")
local sources = require("tools.quality.sources")

describe("TestQuality", function()
  it("test_fixed_commits_and_unknown_tool_failure", function()
    assert.are.equal("8dd107144a7635596d75e4fccfce35121dc67570", bootstrap.pins.acceptance4lua)
    assert.are.equal("1dd42d73116921cd54a00c7b132a9b097e4a288a", bootstrap.pins.dry4lua)
    -- ensure 返回 (nil, err)；先取第一个返回值，避免 err 被当成断言消息。
    local ok = bootstrap.ensure("unknown4lua")
    assert.is_nil(ok)
  end)

  it("test_only_owned_lua_sources", function()
    assert.is_true(sources.owned("common/RateLimit.lua"))
    assert.is_true(sources.owned("client/main.lua"))
    assert.is_true(sources.owned("server/Mgr/MgrFishUnit.lua"))
    assert.is_false(sources.owned("tools/quality/report.lua"))
    -- 样本一律取现存路径：owned() 是纯路径模式判断，死路径不影响判别力，
    -- 但会让读者以为这条样例已失效（旧 tests/run.lua 已随 #93 删除）。
    assert.is_false(sources.owned("tests/native/helper.lua"))
    assert.is_false(sources.owned("server/packages/ability_system/api.lua"))
    assert.is_false(sources.owned("client/packages/ability_system/api.lua"))
    assert.is_false(sources.owned("common/packages/attr_rule/utils.lua"))
    assert.is_false(sources.owned("server/_trigger/function_0.lua"))
    assert.is_false(sources.owned("data/Prefab.lua"))
    assert.is_false(sources.owned("build/generated.lua"))
  end)
end)

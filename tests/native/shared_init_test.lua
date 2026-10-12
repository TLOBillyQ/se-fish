-- 迁移自 tests/tooling/shared_init_test.lua（#93，LuaUnit → 原生 Busted）。
-- 只保留「共享基线接缝 tests/support/baseline.lua 与 Busted helper」这部分：
-- 旧文件里测双 runner 车道顺序、聚合入口 plan 的 3 个用例随旧入口一起消失（无被测对象）。
-- 失败方式（先列后写）：
--   1. helper 不走共享接缝、改在入口里直接写基线值（改一处忘另一处，两套结果不可比）；
--   2. apply() 不幂等，重复调用丢掉 InitialGrants 引用；
--   3. 部分 setup 失败（测试体根本没跑）时 restore() 不还原，脏配置泄漏到后续案例。
local baseline = require("tests.support.baseline")
local GameCfg = require("common.GameCfg")

describe("共享初始化：基线接缝", function()
  it("helper 与基线共用同一个接缝，不在入口里直接写基线值", function()
    assert.are.equal(type(baseline.apply), "function", "共享基线必须暴露 apply()")

    baseline.apply()
    assert.is_true(GameCfg.Debug.Enabled)
    assert.is_not_nil(GameCfg.Debug.InitialGrants)
    assert.are.equal(GameCfg.Save.AcceptanceSlot, "")

    -- 入口必须调用同一接缝，而不是自己复制两行配置。
    local path = "tests/native/helper.lua"
    local source = assert(io.open(path, "rb")):read("a")
    assert.is_not_nil(source:find("tests.support.baseline", 1, true),
      path .. " 没有使用共享基线接缝")
    assert.is_nil(source:find("AcceptanceSlot%s*=%s*[\"']", 1),
      path .. " 仍在入口里直接写基线值，基线会漂移")
  end)

  it("重复 apply 幂等且保住 InitialGrants 引用", function()
    baseline.apply()
    local grants = GameCfg.Debug.InitialGrants
    baseline.apply()
    assert.are.equal(GameCfg.Debug.InitialGrants, grants, "重复 apply 丢失 InitialGrants 引用")
    assert.is_true(GameCfg.Debug.Enabled)
  end)

  it("部分 setup 失败时快照还原仍然生效", function()
    baseline.apply()
    local snapshot = baseline.snapshot()
    GameCfg.Debug = { Enabled = false }
    GameCfg.Save.AcceptanceSlot = "dirty"
    -- 部分 setup 失败：清理必须在测试体根本没跑的情况下也把基线恢复。
    baseline.restore(snapshot)
    assert.is_true(GameCfg.Debug.Enabled)
    assert.are.equal(GameCfg.Save.AcceptanceSlot, "")
  end)
end)

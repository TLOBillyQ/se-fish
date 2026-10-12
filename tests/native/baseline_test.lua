-- 原生案例（#81）：helper 必须在案例加载前建立与 tests/run.lua 相同的离线基线，
-- 并在每案例后恢复共享配置，成功案例的修改也不泄漏到后续案例。
local GameCfg = require("common.GameCfg")

describe("native shared baseline", function()
  it("helper establishes Debug and AcceptanceSlot baseline before cases load", function()
    assert.is_true(GameCfg.Debug.Enabled)
    assert.is_table(GameCfg.Debug.InitialGrants)
    assert.is_true(#GameCfg.Debug.InitialGrants > 0)
    assert.are.equal("", GameCfg.Save.AcceptanceSlot)
  end)

  it("a passing case may dirty the shared config", function()
    GameCfg.Debug = { Enabled = false }
    GameCfg.Save.AcceptanceSlot = "dirty"
    assert.is_false(GameCfg.Debug.Enabled)
  end)

  it("helper restores the shared config after the previous case", function()
    assert.is_true(GameCfg.Debug.Enabled)
    assert.is_table(GameCfg.Debug.InitialGrants)
    assert.are.equal("", GameCfg.Save.AcceptanceSlot)
  end)
end)

-- 验收槽 CLI 的配置文本替换与参数约束；测试不写真实 GameCfg。
-- 迁移自 tests/tooling/acceptance_slot_test.lua（#92，LuaUnit → 原生 Busted）；
-- 案例顺序沿用旧入口的类名 + 方法名字典序。
local slot = require('tools.acceptance_slot')

local sample = table.concat({
  "GameCfg.Save = {",
  "    Store = 'sefish_save_v1',",
  "    AcceptanceSlot = '',",
  "    MaxRetries = 3,",
  "}",
}, '\n')

describe("TestAcceptanceSlot", function()
  it("test_rejects_invalid_slots_and_ambiguous_config", function()
    for _, name in ipairs({ '../x', 'a b', 'a.b', string.rep('x', 41) }) do
      assert.is_false(slot.valid_slot(name))
    end
    assert.is_false(slot.valid_slot(''))
    assert.is_true(slot.valid_slot('qa93-first'))
    assert.is_nil(slot.replace_slot('GameCfg.Save = {\n}\n', 'qa93'))
    assert.is_nil(slot.replace_slot(sample:gsub('    MaxRetries', "    AcceptanceSlot = 'extra',\n    MaxRetries"), 'qa93'))
    local commented = sample:gsub("    AcceptanceSlot = '',", "    -- AcceptanceSlot = 'old',\n    AcceptanceSlot = 'real',")
    assert.are.equal('real', slot.current_slot(commented))
    local updated = assert(slot.replace_slot(commented, 'next'))
    assert.matches("-- AcceptanceSlot = 'old'", updated, 1, true)
    assert.are.equal('next', slot.current_slot(updated))
    assert.is_nil(slot.replace_slot(sample:gsub("AcceptanceSlot = ''", 'AcceptanceSlot = "real"'), 'next'))
  end)

  it("test_replaces_only_save_slot_and_can_restore_off", function()
    local input = "local AcceptanceSlot = 'other'\n" .. sample
    local updated = assert(slot.replace_slot(input, 'qa93-first'))
    assert.are.equal('other', updated:match("local AcceptanceSlot = '([^']*)'"))
    assert.are.equal('qa93-first', slot.current_slot(updated))
    assert.are.equal(input, assert(slot.replace_slot(updated, '')))
  end)
end)

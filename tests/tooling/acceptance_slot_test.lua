-- 验收槽 CLI 的配置文本替换与参数约束；测试不写真实 GameCfg。
local lu = require('luaunit')
local slot = require('tools.acceptance_slot')

TestAcceptanceSlot = {}

local sample = table.concat({
  "GameCfg.Save = {",
  "    Store = 'sefish_save_v1',",
  "    AcceptanceSlot = '',",
  "    MaxRetries = 3,",
  "}",
}, '\n')

function TestAcceptanceSlot:test_replaces_only_save_slot_and_can_restore_off()
  local input = "local AcceptanceSlot = 'other'\n" .. sample
  local updated = assert(slot.replace_slot(input, 'qa93-first'))
  lu.assertEquals(updated:match("local AcceptanceSlot = '([^']*)'"), 'other')
  lu.assertEquals(slot.current_slot(updated), 'qa93-first')
  lu.assertEquals(assert(slot.replace_slot(updated, '')), input)
end

function TestAcceptanceSlot:test_rejects_invalid_slots_and_ambiguous_config()
  for _, name in ipairs({ '../x', 'a b', 'a.b', string.rep('x', 41) }) do
    lu.assertFalse(slot.valid_slot(name))
  end
  lu.assertFalse(slot.valid_slot(''))
  lu.assertTrue(slot.valid_slot('qa93-first'))
  lu.assertNil(slot.replace_slot('GameCfg.Save = {\n}\n', 'qa93'))
  lu.assertNil(slot.replace_slot(sample:gsub('    MaxRetries', "    AcceptanceSlot = 'extra',\n    MaxRetries"), 'qa93'))
  local commented = sample:gsub("    AcceptanceSlot = '',", "    -- AcceptanceSlot = 'old',\n    AcceptanceSlot = 'real',")
  lu.assertEquals(slot.current_slot(commented), 'real')
  local updated = assert(slot.replace_slot(commented, 'next'))
  lu.assertStrContains(updated, "-- AcceptanceSlot = 'old'")
  lu.assertEquals(slot.current_slot(updated), 'next')
  lu.assertNil(slot.replace_slot(sample:gsub("AcceptanceSlot = ''", 'AcceptanceSlot = "real"'), 'next'))
end

-- hook 失败清理核查（#81）：在子进程中执行故意失败的夹具，断言事件序列，
-- 避免本套件自身引入失败。覆盖契约关键点：
-- before_each 失败时测试体不执行；after_each 从失败的最近层向上执行；
-- 更深层的 after_each 不执行；兄弟分支不受影响；helper 在失败案例后仍恢复共享配置。
describe("native hook failure cleanup", function()
  it("after_each runs from the failed ancestor upward and config is restored", function()
    local command = "busted --output plainTerminal tests/native/fixtures/hook_failure_case.lua 2>&1"
    local handle = assert(io.popen(command, "r"))
    local output = assert(handle:read("a"))
    local ok, _, code = handle:close()
    assert.is_falsy(ok)
    assert.is_true(code ~= 0, "夹具故意失败，子进程退出码必须非零")

    -- 内层 before_each 失败：内层与外层 after_each 都执行，测试体不执行。
    assert.matches("EV:inner_before", output, nil, true)
    assert.matches("EV:inner_after", output, nil, true)
    assert.matches("EV:outer_after", output, nil, true)
    assert.is_not_matches("EV:test_body", output, nil, true)
    -- 更深层的 after_each 与测试体不执行（失败层之下不做清理）。
    assert.is_not_matches("EV:deeper_after", output, nil, true)
    assert.is_not_matches("EV:deeper_body", output, nil, true)
    -- 兄弟分支不受失败影响。
    assert.matches("EV:sibling_body", output, nil, true)
    assert.matches("EV:sibling_after", output, nil, true)
    -- 失败案例污染的共享配置由 helper 恢复。
    assert.matches("EV:cfg_enabled=true", output, nil, true)
    assert.matches("EV:cfg_slot=EMPTY", output, nil, true)
  end)
end)

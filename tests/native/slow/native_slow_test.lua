-- slow 车道哨兵（#81）：只被 full 车道发现（tests/native/slow 仅在 full 的 ROOT 内），
-- 用于以 `busted --run=<车道> --list` 证明 fast 排除 slow、full 包含 slow。
describe("native slow sentinel", function()
  it("is discovered only by the full lane", function()
    assert.is_true(true)
  end)
end)

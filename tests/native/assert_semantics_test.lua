-- 断言语义探针（#81）：固定 Luassert 1.9.0 与 LuaUnit 的迁移映射语义。
-- 只验证迁移映射依赖的行为，不替代逐案例迁移审查。
describe("native assertion semantics", function()
  it("same performs deep comparison and ignores metatables", function()
    assert.same({ 1, 2, { 3, 4 } }, { 1, 2, { 3, 4 } })
    local mt = { __eq = function() return false end }
    assert.same(setmetatable({ 1 }, mt), setmetatable({ 1 }, mt))
  end)

  it("equals is plain ==, not a deep comparison", function()
    local t = { 1 }
    assert.equals(t, t)
    assert.has_error(function() assert.equals({ 1 }, { 1 }) end)
    local mt = { __eq = function() return true end }
    assert.equals(setmetatable({}, mt), setmetatable({}, mt))
  end)

  it("near compares numbers within tolerance", function()
    assert.near(1.0, 1.05, 0.1)
    assert.near(1.0, 0.9, 0.1)
    assert.has_error(function() assert.near(1.0, 1.2, 0.1) end)
  end)

  it("error strips the first path:line prefix and requires exact equality", function()
    assert.error(function() error("boom") end, "boom")
    assert.error(function() error("plain", 0) end, "plain")
    assert.has_error(function()
      assert.error(function() error("boom") end, "boo")
    end)
  end)

  it("error_matches defaults to Lua pattern, plain=true means substring", function()
    assert.error_matches(function() error("status 42") end, "status %d+")
    assert.error_matches(function() error("a+b failed", 0) end, "a+b", nil, true)
    assert.has_error(function()
      -- pattern 模式下 "a+b" 是“一个以上 a 接 b”，不是字面量
      assert.error_matches(function() error("a+b failed", 0) end, "a+b")
    end)
  end)

  it("matches defaults to Lua pattern, plain=true means literal find", function()
    assert.matches("%d+", "abc123")
    assert.matches("50%%", "hit 50% rate")
    assert.matches("50%", "hit 50% rate", nil, true)
    assert.has_error(function() assert.matches("%d+", "abc") end)
  end)
end)

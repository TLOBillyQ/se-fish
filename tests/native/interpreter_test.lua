-- 迁移自 tests/tooling/shared_init_test.lua（#93，LuaUnit → 原生 Busted）。
-- 这是 tests/support/interpreter.lua 负索引修复的唯一直接回归：旧 tooling 车道随 #93 删除后，
-- 没有它「覆盖率模式下把 -e 语句原文当解释器」会重新长回来。
-- 失败方式（先列后写）：
--   1. 退回顾 arg[-1] 的写法 → `lua -e 语句 s.lua` 形态下取到语句原文，所有起 lua 子进程的
--      临时仓库回归只在 --coverage 下整片失败；
--   2. 找不到解释器时不回落 "lua"，而是报错或返回 nil；
--   3. 新增起子进程的回归绕开 tests.support.interpreter、自己读 arg。
local interpreter = require("tests.support.interpreter")

-- 从当前进程的 arg 里找一个真实存在的解释器路径：判据与搜索上界都取自接缝模块，
-- 这里只负责自己扫一遍 arg（不写死下标范围，模块改 MAX_BACK 时自动跟随）。
-- 回归的真正强度在三段 shape 上：取错下标时 path() 会返回语句原文而不是这个路径。
local function exe_from_arg()
  for index = -1, -interpreter.MAX_BACK, -1 do
    if interpreter.looks_like_exe(arg[index]) then
      return arg[index]
    end
  end
  return nil
end

describe("共享初始化：解释器接缝", function()
  it("任意启动形态都取到真正的解释器", function()
    local exe = exe_from_arg()
    assert.is_not_nil(exe, "回归进程应当能从 arg 里定位解释器")

    local shapes = {
      { [-1] = exe },                    -- lua s.lua
      { [-1] = "-lluacov", [-2] = exe }, -- lua -lluacov s.lua
      { [-1] = "local r=require('luacov.runner')", [-2] = "-e", [-3] = exe }, -- lua -e 语句 s.lua
    }
    for _, shape in ipairs(shapes) do
      assert.are.equal(interpreter.path(shape), exe,
        "取错解释器（arg[-1] = " .. tostring(shape[-1]) .. "）")
    end
  end)

  it("没有像解释器的条目时回落到 lua", function()
    assert.are.equal(interpreter.path({ [-1] = "-e", [-2] = "local x = 1" }), "lua")
    assert.are.equal(interpreter.path({ [-1] = "not-a-real-lua-binary-xyz" }), "lua")
    assert.are.equal(interpreter.path({}), "lua", "空 arg 也要回落")
  end)

  it("起子进程的回归统一走解释器接缝", function()
    -- 防止退回顾 arg[-1] 的写法：起真实 lua 子进程的回归必须从接缝取解释器。
    local path = "tests/native/slow/sync_transport_test.lua"
    local source = assert(io.open(path, "rb")):read("a")
    assert.is_not_nil(source:find("tests.support.interpreter", 1, true),
      path .. " 没有用解释器接缝取 lua")
    assert.is_nil(source:find("arg[-1]", 1, true),
      path .. " 仍直接读 arg[-1]，覆盖率模式下会取到 -e 语句")
  end)
end)

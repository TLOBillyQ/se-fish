-- 随机函数守卫（#87 迁移夹具）。
-- 旧 LuaUnit 是单进程顺序跑，业务侧 MgrSave / MgrLoot 会直接读全局 math.random()，
-- 因此任何案例替换 math.random 后没还回去，后续案例的随机结果就会被前一例接管。
-- 原生逐例隔离后把这件事显式化：在本模块加载时（helper 基线之后、任何案例之前）抓一次
-- 原生引用，每个案例结束后按引用还原；未替换时还原是空操作。
-- 用法：在 spec 的 describe 体内写 `after_each(RandomGuard.restore)`，与其它逐案例清理同层。
local M = {}

-- 加载期快照：native 车道里没有任何文件在顶层替换 math.random，此刻即原生 C 函数。
local pristine = { random = rawget(math, "random"), randomseed = rawget(math, "randomseed") }

--- 把 math.random / math.randomseed 还原为加载期的引用。
function M.restore()
  rawset(math, "random", pristine.random)
  rawset(math, "randomseed", pristine.randomseed)
  return true
end

--- 当前 math.random 是否仍是加载期的原生函数（供案例自检，不做替换）。
function M.isPristine()
  return rawequal(rawget(math, "random"), pristine.random)
    and rawequal(rawget(math, "randomseed"), pristine.randomseed)
end

return M

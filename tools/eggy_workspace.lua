-- 编辑器宿主目录定位：deploy 与 sync 共用的唯一真源。
-- 宿主目录 = 编辑器 `code init` 绑定的本地 Lua 工程（根有 eggy.json），仓库只往里镜像
-- 白名单子树，不往里写别的东西。默认写死钓鱼图宿主目录；EGGY_WORKSPACE 可覆盖
-- （测试与临时场景用，这样临时工作区不会被误当成真宿主目录）。
local M = {}

M.DEFAULT = [[C:\Users\Lzx_8\Desktop\dev\eggy\LuaSource_钓鱼怎么这么危险啊喂！]]

function M.resolve()
  return os.getenv("EGGY_WORKSPACE") or M.DEFAULT
end

return M

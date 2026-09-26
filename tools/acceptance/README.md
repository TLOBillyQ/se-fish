# Gherkin 验收入口

```sh
bash tools/acceptance/run_acceptance.sh
```

脚本在任意目录都可调用，使用 Lua 5.4（可通过 `ACCEPTANCE_LUA_BIN` 指定）。目前没有 feature：打印“features/ 下没有 feature 文件，跳过验收”，清理旧生成物并成功退出；不会安装依赖或生成报告。质量门禁当前不运行空的验收阶段。

新增场景放在 `features/<车道>/<名字>.feature`，以 `# language: zh-CN` 开头，并在 `tools/acceptance/steps.lua` 登记对应步骤模块。存在 feature 时，入口逐个执行 parse → dry-check（advisory）→ generate → run；先清 `build/acceptance/generated/`，避免运行旧 spec。失败返回非零；`ACCEPTANCE_STRICT_TOOLS=1` 会让 dry-check 工具错误也使运行失败。

`tools/acceptance/bootstrap.lua` 在有场景需要执行时按需安装固定版本的 `acceptance4lua`；生成内容在被 Git 忽略的 `build/acceptance/`，依赖缓存位于 `.toolcache/`。不需要 luarocks 或 WSL。

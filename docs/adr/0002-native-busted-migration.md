# 0002 Full native Busted migration

**Status**: accepted

结束状态（#93）：Lua 侧已完成全量切换——`tests/run.lua`、`tests/run_migration.lua`、`tests/lanes.lua` 与 vendored LuaUnit 已删除，根目录 `.busted` 是唯一 Lua 测试入口；测试文件放 `tests/native/`（slow 车道 `tests/native/slow/`），共享夹具放 `tests/support/`，手工探针放 `tests/probes/`（不入任何车道）。`commands.coverage` / `commands.mutation_test` 直接指向 Busted，覆盖率单段写仓库根 `luacov.stats.out`；Python 回归仍独立保留在 `tests/tooling/slow/`，由 `tools/quality/verify.ps1` 的 `unittest discover` 运行。

se-fish 全部 Lua 测试全面改写为原生 Busted：116 个测试文件、约 1,297 个案例、7,191 处 LuaUnit 断言，移除 LuaUnit 依赖及桥接层。断言深比较/身份比较/容差语义、执行顺序、共享环境与失败清理行为在迁移后保留；`.busted` 定义 full（coverage）与 fast（mutation）命名任务；Python tooling 回归独立保留。

备选方案（拒绝）：Busted 调度 + LuaUnit 断言桥接——长期保留两套断言体系，语义复杂度不减反增；仅保留 LuaUnit——标准工具默认 runner 为 Busted，配置适配负担持续存在。

后果：测试 runner 的 Windows `dir` 发现与全局加载由 Busted 发现机制替换；`.busted` 配置替代 `tests/run.lua`；现有部署、同步等 Windows 专用 tooling/slow 测试明确标注适用平台，跨平台改造另行处理；Busted、LuaCov、LCOV reporter 纳入固定依赖安装与 doctor 契约。

# 0002 Full native Busted migration

**Status**: accepted

se-fish 全部 Lua 测试全面改写为原生 Busted：116 个测试文件、约 1,297 个案例、7,191 处 LuaUnit 断言，移除 LuaUnit 依赖及桥接层。断言深比较/身份比较/容差语义、执行顺序、共享环境与失败清理行为在迁移后保留；`.busted` 定义 full（coverage）与 fast（mutation）命名任务；Python tooling 回归独立保留。

备选方案（拒绝）：Busted 调度 + LuaUnit 断言桥接——长期保留两套断言体系，语义复杂度不减反增；仅保留 LuaUnit——标准工具默认 runner 为 Busted，配置适配负担持续存在。

后果：测试 runner 的 Windows `dir` 发现与全局加载由 Busted 发现机制替换；`.busted` 配置替代 `tests/run.lua`；现有部署、同步等 Windows 专用 tooling/slow 测试明确标注适用平台，跨平台改造另行处理；Busted、LuaCov、LCOV reporter 纳入固定依赖安装与 doctor 契约。

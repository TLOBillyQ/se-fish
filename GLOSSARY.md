# se-fish

单上下文术语表，覆盖 Lua 游戏代码、质量工具与 viewer 接入词汇。

## Language

**se-fish**:
Fish Work Mini 系列 Lua 游戏代码与质量工具项目，源码分 client/common/server 三端。

**quality gate**:
se-fish 的质量发布规则：coverage 失败即停止并使旧 LCOV 失效；CRAP 始终全业务树刷新；mutation 差分/全量参数原样转发，源码变动时拒绝发布快照。

**业务树**:
`client`、`common`、`server` 三端业务源码；排除 `packages`、`server/_trigger` 等非业务目录。

**Busted migration**:
将全部 Lua 测试全面改写为原生 Busted 的过程：移除 LuaUnit 依赖及桥接层，保留断言含义、执行顺序、共享环境与失败清理行为；full 用于 coverage、fast 用于 mutation。

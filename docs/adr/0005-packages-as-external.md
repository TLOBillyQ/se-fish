# 0005 各端 packages/ 在架构图上作为外部节点

**Status**: accepted

三端 `packages/` 是网易官方作者版包：整包替换、包内无版本号、不由本仓库维护（见 [packages-reference](../packages-reference.md)）。此前 `policy.edn` 只排除 `_trigger`，包被当普通源码扫进图：94 个包内类并入 `client`/`common`/`server` 三棵树，包内热点（CRAP 最高 8219.6）与官方内部依赖都画在业务树上。viewer 升到 `5404057` 后（[ADR-0004](0004-viewer-herdr-version-floor.md)）聚合语义改为按函数数加权，缺 mutation 快照的类**按每个函数算一次失败试验**，包内 533 个函数便成了三棵树分数里的假失败。现决定：`policy.edn` 的 `:exclude` 加 `"packages"`，包不建类；业务代码对包的 `require` 收成外部椭圆，`:foreign` 取三个端级前缀 `client.packages`、`common.packages`、`server.packages`，三端 `packages/` 整体都是 vendor，每端收成一个椭圆（当前 client、server 各 1 个；`common` 没有业务代码引用包，不出椭圆）。

备选方案（拒绝）：给包跑差分 mutation——整包升级即作废，包内覆盖率只有 0.6%–5%；让包在顶层自成第四棵树——包 id 一旦离开 `client.packages.*` 命名空间，`.metrics/crap.edn` 与 `.metrics/mutate/*.edn` 按类 `:ns` 的 join 全断；改上游把「无数据」与「失败试验」分开——要再动 viewer pin 并写上游 ADR，收益不足。

后果：图上只剩业务树（116 个类 = 114 业务 + 2 椭圆），顶层多出 2 条「端盒子 → 椭圆」的箭头。包内依赖与包内热点不再可见，需要时另立 policy 生成第二份图（本次不做）。`tools/quality/project.json` 的采集范围不动：CRAP 与 DRY 仍含包，674 条包内函数记录（78 个 namespace）留在 `.metrics` 里，因没有同名 class 在叠加时被忽略——不报错、不变红。同一份 `.metrics` 只换图后的实测：Client CRAP μ 17.7→15.9、mut-gap 296→42；Common 7.5→5.9、138→3；Server μ 22.3→9.2、max 8219.6→441.9、mut-gap 311→10（剩余缺口是业务里真缺快照的类）。`:foreign` 按端级前缀匹配，新增包不需要改 policy，不存在逐包白名单被静默丢弃的问题。呈现上的细节：钻进单端后只保留该端**可见**模块引用的椭圆（server 有，client 与 common 没有），因为 client 引用包的 3 个聚合入口（`client.AbilityAPI`、`client.AttrAPI`、`client.ModifierAPI`）以及 `server.AttrAPI`、`server.ModifierAPI` 都在 `:omit` 里——`:omit` 的既有理由（无函数、恒缺指标）未变，本轮不动。

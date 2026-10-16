# 0004 Viewer 固定版本升到接受 Herdr >= 0.9.3

**Status**: accepted

本机 Herdr 已升到 0.9.5，而 se-fish 固定的 viewer（`79c8d56`）版本预检只认字面量 `herdr 0.9.3`，`.\uml.ps1` 在预检阶段直接失败、companion 起不来。决定把 `tools/quality/project.json` 的 `tools.viewer.commit` 升到 `54040575390d68746da241a1e0477726f48ec7cc`（来源检出 `../uml-viewer` 的 `lua` 分支尖端），再用 `.\tools\quality\install.ps1` 重装。该提交上的质量分发声明（`uml-quality.json` v1 的 `operations`）、`policy.edn` 与 `.metrics/crap.edn` 加 `.metrics/mutate/*.edn` 的路径契约都没变，只有指标聚合语义变了。

备选方案（拒绝）：把本机 Herdr 降回 0.9.3 并保留旧 pin——等于把版本钉在上游已放宽的下限上，Herdr 每次自更新都要重新降级；在 PATH 上同时放 0.9.3 与 0.9.5 两个 Herdr——旧版 Windows 上 `Get-Command herdr -CommandType Application` 的 `.Source` 取到的是数组，companion 启动的 `Start-Process` 直接报类型错，属旧版缺陷，不是使用方式问题。

后果：Herdr 侧只保证 `>= 0.9.3` 且 `protocol == 22`，预发布版与更高协议仍拒绝，平台仍限原生 Windows/macOS；图上分数语义随之改变（CRAP 由「取子树里最差的一个类」改为按函数数加权合并 μ/σ/max，mutation 由「取最差比率」改为求和并按函数数补 `:mut-gap` 失败试验），`docs/uml/se-fish.edn` 与类卡片分数会和升级前不同，需重新生成并复核；`docs/agents/workflow.md` 的 Herdr 条目同步改写为版本下限与候选选择。

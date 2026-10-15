# 02–07 区灰盒施工落盘核验（#102）

- 最新基线：`evidence/issue65/zone-baseline-rows-post-p3.csv`（394 行 = 表头 + 393 节点）。
- 最新基线 SHA256：`7373c088f6a90a2a49b09766e57603c5fa9ff64f6a5ec3951a9fdf7c304cb5e0`。
- 核验方式：`tools/verify-issue102-reopen.ps1`（只读：跑 `tests/probes/zone_baseline_inventory.lua` → `log grep P2BASE65V2` → `tools/baseline_csv.lua` → 逐行对齐）。
- 03–07 区此前基线为 364 节点，SHA256 `a11b9d85cbd75bfb47acd60fbc7c0c056ac1aafd106c148cd76ec9474e8edaef`；本轮新增虾池施工后更新快照。

## 结论：冷加载 **PASS**（2026-10-15，重做施工后）

| 时刻 | 事件 | 回读结果 |
|---|---|---|
| 10-14 17:2x | 首次施工后、同一编辑器进程内回读 | 与存档逐行一致（未重启进程，不算冷加载） |
| 10-15 14:29 | 编辑器重启（pid 13444）后首次冷加载 | **施工丢失**：`zoneNodes=264`，03–07 区逐行等于 P2 施工前基线 `zone-baseline-rows.csv`（0/0 差异）；与存档相比仅存档有 169 行、仅现场有 69 行 |
| 10-15 14:34 | 重放 `tests/probes/zone_layout_apply.lua`（数据块与规划器同步） | `created=50 moved=49 miss=0 failed=0`；回读 `zoneNodes=364`，与存档 0/0 |
| 10-15 14:35 | `map save` → `map reopen --force`（新进程 pid 37268） | `save_result.status=success`；冷加载回读 `zoneNodes=364`，单份载荷转出的 CSV 与存档 **SHA256 逐字节相同** |
| 10-15 14:36 | `verify-issue102-reopen.ps1 -EditorInstance 37268` | 去重后 358/358，仅存档有 0、仅重开有 0，退出码 0 |
| 10-15 14:45–14:48 | 虾池按 ADR 0003 施工并修正水面预设 | 新建 15 个根单位；末次幂等执行 `ops=123 created=0 moved=123 miss=0 failed=0`；水面网格 `59269`、80×1×24、无碰撞、无附带子件 |
| 10-15 14:48–14:50 | `map save` → `map reopen --force`（新进程 pid 35760） | 冷加载回读 393 节点；单份载荷生成最新基线，03–07 区无额外变化 |
| 10-15 14:50:53 | `verify-issue102-reopen.ps1 -EditorInstance 35760` | 去重后 387/387，仅存档有 0、仅重开有 0，退出码 0；原始回执见 `reopen-verification.txt` |
| 10-15 14:51 | 配置引用与水面属性只读核查 | `P2CFG65`：142 条引用，132 命中，10 条鱼塘计划锚点缺失，其余异常全 0；`SHRIMPWATER102`：虾池与蟹湖水面均为 mesh `59269`、`CanCollide=false`、`children=0` |
| 10-15 15:03–15:07 | 运行时试探（playtest 27150b6） | 当前试玩存档 `ticket=0`，未完成正常扣票登船；步行跨区尝试中角色停在 (65.33,−36.01,−55.33)。本会话 `log trace` 为 0 错误 0 警告，但未验证虾池落地与抛竿，不能算逐区试玩通过；该验收仍归 #107 |
| 10-15 15:12 | 水面外观补查 | `SHRIMPWATER102`：Z2/Z3 均 `UseCustomAppearance=false`、`CustomAppearanceId` 为空、`ModelAlpha=1`；BodyType 分别为 Static/Kinematic，均非动态受力体。SkinSlots 内容未完成序列化对照，未作渲染一致性结论 |

七区空间指标与同步差值分别见 `zone-space-contract-post-sync.txt`、`anchor-sync-after-post-p3.txt`：94 条已建锚点差值全 0；02–07 区通道最窄 10.50、战斗净空间零侵占、支撑 100%。01 鱼塘保持原样，含交互范围通道最窄为 0，四个贴岸战斗候选均未同时满足零侵占与完整支撑，不能标为七区全部达标。`Scene.State` 保留 `planned`，碰撞与逐区试玩仍归 #107。

## 口径声明

- 首次施工为什么丢失**没有查清**：当时 `map save` 同样回执 `success`，进程退出与再次打开之间发生了什么不可考。由此得出的规矩：**保存回执不能当持久化证据，施工后必须 `map reopen` 冷加载回读**。
- `map dirty` 在保存后仍报 `dirty=true`（`cmd_stack_unsaved`/`cmd_stack_manual`），是本图既有现象；所以 `map reopen` 必须带 `--force`。`--verify` 对本图返回 `VERIFY_UNAVAILABLE`，以探针回读代替。
- `verify-issue102-reopen.ps1` 的 CSV 行数会因日志窗口累积多份载荷而翻倍，脚本按去重后逐行对齐判定；文件哈希直接比对预期为「不同」。
- 属性/几何口径的读回一致**不等于**运行时角色碰撞或踩踏体感，后者归 #107 的逐区试玩。

## 复跑

```powershell
.\tools\verify-issue102-reopen.ps1 -EditorInstance <本图 pid 或端口>   # 退出码 0 = 0/0 差异
.\tools\verify-issue102-reopen.ps1 -KeepArtifacts                       # 保留中间产物与原始日志
```

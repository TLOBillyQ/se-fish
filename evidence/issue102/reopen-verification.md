# 03–07 区灰盒施工落盘核验（#102 第一项）

- 基线存档：`evidence/issue65/zone-baseline-rows-post-p3.csv`（365 行 = 表头 + 364 节点）
- 基线 SHA256：`a11b9d85cbd75bfb47acd60fbc7c0c056ac1aafd106c148cd76ec9474e8edaef`（自 `06c7538` 起未变）
- 核验方式：`tools/verify-issue102-reopen.ps1`（只读：跑 `tests/probes/zone_baseline_inventory.lua` → `log grep P2BASE65V2` → `tools/baseline_csv.lua` → 逐行对齐）

## 结论：冷加载 **PASS**（2026-10-15，重做施工后）

| 时刻 | 事件 | 回读结果 |
|---|---|---|
| 10-14 17:2x | 首次施工后、同一编辑器进程内回读 | 与存档逐行一致（未重启进程，不算冷加载） |
| 10-15 14:29 | 编辑器重启（pid 13444）后首次冷加载 | **施工丢失**：`zoneNodes=264`，03–07 区逐行等于 P2 施工前基线 `zone-baseline-rows.csv`（0/0 差异）；与存档相比仅存档有 169 行、仅现场有 69 行 |
| 10-15 14:34 | 重放 `tests/probes/zone_layout_apply.lua`（数据块与规划器同步） | `created=50 moved=49 miss=0 failed=0`；回读 `zoneNodes=364`，与存档 0/0 |
| 10-15 14:35 | `map save` → `map reopen --force`（新进程 pid 37268） | `save_result.status=success`；冷加载回读 `zoneNodes=364`，单份载荷转出的 CSV 与存档 **SHA256 逐字节相同** |
| 10-15 14:36 | `verify-issue102-reopen.ps1 -EditorInstance 37268` | 去重后 358/358，仅存档有 0、仅重开有 0，退出码 0（原始输出见 `reopen-verification.txt`） |

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

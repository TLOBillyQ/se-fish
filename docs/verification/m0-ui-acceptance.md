# M0 剩余人工项验收（issue #25）

日期：2026-09-22。验收基准：仓库 `11a4c1c`；地图「钓鱼怎么这么危险啊喂！」，SE，地图 ID `6aab8e60ee615830184f4963`，编辑器 pid 35948。

本记录区分实际 UI 核查、运行时验证与待人类接受的降级。Agent 代操作、读截图，不冒充真人签字。

**20:44 最终更新：已同步当前 main 及本轮修复，补齐三客户端同时死亡后约 5.082 秒复活、300 满血、实际鼠标点击攻击 50→25→0、受击体隐藏截图对照。出生点 Capacity=3 和重建后的技能预设均已保存，临时启动探针已移除。技术实测详见 §6；降级签收仍以 §7 为准。§1–§5 保留先前时点的基线和诊断过程。**

## 判据与手段

| 项 | 现象 → 预期 | 手段 |
|---|---|---|
| V6 / D-12 | 打开死亡及复位规则 → 核实 5 个实际字段，重生时间及复位冷却均为 5 秒 | 操作编辑器 UI、完整桌面截图 |
| V6 / D-12 | 选中出生点 → 核实容纳上限实际值 | 属性面板截图 |
| V7 | 3 个客户端同图 → 每人有可控角色，死亡后约 5 秒复活 | UI 本地多人测试、运行时探针及截图 |
| M18-3 | 鱼载体存在且受击 → 受击体不露模型 | 游戏截图 |
| M18-5 | 实际点击攻击按钮 → 客户端请求、服务端命中扣血直至死亡 | OS 鼠标输入、两端日志 |
| 降级签收 | 每项降级有理由、影响与归属 → 不将未测标为通过 | 台账审阅；取舍由用户接受 |

## 1. V6 / D-12：面板实际值已核查

| 字段 | UI 文案 | 实际值 | 结论 |
|---|---|---|---|
| RespawnTime | 重生时间 | 5.000 | 符合 5 秒预期 |
| LivesCount | 命数（-1 无限重生） | -1 | 无限重生 |
| CorpseLifetime | 尸体存在时间 | 1.000 | 已记录 |
| ResetCamera | 复位重置相机 | False | 已记录 |
| ResetCD | 复位冷却时间 | 5.000 | 符合 5 秒预期 |
| Capacity | 出生点：容纳上限 | 1 | 实际值确认；不能据此推定多人会被阻塞或不会被阻塞 |

证据：仓库 `tmp/qa25/death-rules.png`、`tmp/qa25/spawn-capacity.png`。本次只读属性，没有修改这些值。操作者为 Agent；若要求具体人员签字，这两张截图可供用户复核。

注意：`editor-cli screenshot editor` 本轮没有包含独立的规则对话框，完整桌面截图才包含实际规则面板。只看 CLI 视口截图会漏掉它。

## 2. V7：找到本地多人测试 UI，旧降级理由需修正

编辑器左上【试玩下拉 → 测试】实际包含：

- 本地多人测试：人数输入框（初始为 2，可输入 3）及开始按钮。
- 共建多人测试：开始按钮。

证据：`tmp/qa25/test-options.png`、`tmp/qa25/three-player-option.png`。

所以原台账 §6/§7 的推论应缩窄为 **CLI 的 `play start` 没有多客户端参数**；不能由此推导“编辑器没有同图多客户端能力”。`start` 不重复启动同一地图，也不能排除编辑器 UI 内置的本地多人测试入口。

**实际启动失败（19:43）**：人数设为 3 后点击本地多人测试的【开始】，编辑器弹窗原文：

> 出生点少于多人测试客户端数量，无法开始

证据：`tmp/qa25/multiplayer-start.png`（错误弹窗与左侧出生点属性 Capacity=1 同屏）。没有进入试玩，无法继续测三人出生、死亡和 5 秒复活。这是启动前的地图配置校验失败，与缺失的鱼载体 Lua 模块无关；但本次仍未同步 main，因此不声称已完成 main 的端到端验收。

V7 判定 **未通过**：当前地图的出生点配置不能启动 3 客户端本地测试。修复候选为增加到至少 3 个出生点，或先验证提高单点 Capacity 是否满足启动校验；弹窗说的是“出生点”，不能未经验证就断言只改 Capacity 有效。此轮只验收，没有改出生点、没有存盘。错误弹窗关闭后恢复编辑态。

## 3. 当前代码基准差异

宿主目录预检返回 `DIFF_NOT_CLEAN`：8 个 only-local、5 个 differs、0 个 only-on-map。缺失模块包含 `server/Mgr/MgrFishCarrier.lua`、`client/LocalAttackButton.lua`；地图内代码尚未包含本轮 M0 的全部实现。不能直接把当前地图试玩结果记成 main 的验收。

完整差异留在 `tmp/qa25/code-diff.json`（含 patch 路径）；拉取预览在 `tmp/qa25/pull-preview.json`，没有执行拉取覆盖。已请求用户选择以 main 同步还是保留地图代码。此时地图 `map dirty` 为 false。

## 4. 降级签收状态

| 原条目 | 本轮处置 |
|---|---|
| D-1 真实多客户端 | 已找到本地多人 UI；启动被出生点校验拒绝，不能沿用“无多人途径”的降级理由 |
| D-2 出生点容量 | 实际值已确认 1；3 客户端启动直接被拒，V7 未通过，待修地图配置并复验 |
| D-3 饥饿度回满 | 当前模块未实现，不能验成通过；仍由 M1/M4 回补 |
| D-4 真人抓举按键 | 服务端探针不等于实际按钮操作；待补按钮路径证据 |
| D-5 R-7 限流压测 | 既有书面判断只能解释为何未测，不能提供真实平台阈值；取舍待用户接受 |
| D-6 面板字段 | 本轮补齐 6 个 UI 实际值和截图；人类署名仍由用户决定 |
| D-7 克隆鱼抓举 | 仍未覆盖；生产采用 CreateUnit 的既定路线，M2 归属不变 |
| D-8 性能范围 | 原 0.0740 ms/帧仍仅代表单客户端逻辑开销，不外推多人网络及渲染 |

本记录不关闭 issue #25，不把“帮我验收”解释为用户已接受所有未测风险。

## 5. diagnosing-bugs：出生容量的因果验证与修复

### 反馈循环

临时诊断工具集中在明确的调试目录 `tmp/qa25/`，没有注入业务代码。调用：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tmp/qa25/repro-spawn.ps1 -Clients 3 -Label red-three
```

脚本通过 OS 鼠标与键盘操作实际 UI，使用 Windows UI Automation 读取完整错误文本，不依赖截图猜测。检测到“出生点少于多人测试客户端数量，无法开始”就打印 RED、退出码 1；检测到本轮新建 3 个客户端进程才报告启动 GREEN、退出码 0；无明确结果退出码 2，不误报通过。进程启动后另以三名角色同屏和服务端三次 OnPlayerAdded 确认出生。

脚本使用本轮进程/窗口 ID，属于临时复现工具；重开编辑器后要重新定位窗口。出生点预设保存在地图，不在仓库，luaunit 无法执行编辑器本地多人启动校验；没有添加只验证 `3 >= 3` 的浅层单测。

### 最小复现与候选

最小多人用例：一个 Capacity=1 的出生点，启动 2 个客户端，稳定出现同一弹窗。无需运行玩法 Lua。读取过 CONTEXT.md，本仓库没有 docs/adr 目录。

测试前给出的排名：① 数量门槛（需要多个出生点）；② 总容量门槛（提高单点容量就放行）；③ 有效出生点受阵营/启用条件过滤。每次只改 Capacity，不改点数、位置、阵营或 Lua。

| 轮次 | 配置 | 实际结果 | 证据 |
|---|---|---|---|
| 基线 | 1 个出生点，Capacity=1，3 客户端 | RED：同一错误弹窗 | `tmp/qa25/red-three.png` |
| 最小复现 | 1 个出生点，Capacity=1，2 客户端 | RED：同一错误弹窗 | `tmp/qa25/red-two.png` |
| 单变量实验 | 1 个出生点，Capacity=3，3 客户端 | GREEN：新进程 9312、22016、37948；三名玩家均出生 | `tmp/qa25/capacity-three.png`、`multiplayer-loaded.png`、`three-players.log` |
| 反向回归 | 改回 Capacity=1，3 客户端 | RED：同一错误弹窗 | `tmp/qa25/regression-capacity-one.png` |
| 最终修复 | 恢复 Capacity=3，3 客户端 | GREEN：新进程 24616、27896、38944；再次记录三名玩家入场 | `tmp/qa25/regression-capacity-three.png`、`regression-three-players.log` |

最终轮次服务端日志（`C:/FeverApps/party_pc/logs/editor_38944.log`，session `31ee709`）：

```text
[20:16:11.529] [info/server] "[MgrPlayerData] OnPlayerAdded" <伯乐好马！1><Player>(Player)
[20:16:16.148] [info/server] "[MgrPlayerData] OnPlayerAdded" <伯乐好马！2><Player>(Player)
[20:16:21.622] [info/server] "[MgrPlayerData] OnPlayerAdded" <伯乐好马！3><Player>(Player)
```

第一轮截图显示三名角色处于同一场景中。三个客户端加载完成时间不同，不能将上述日志解释为三人同一帧出生。

### 根因与修复

**根因是当前唯一出生点的可用容量 1 不足以支持请求的 3 个客户端。** 单点容量提高到 3 即可放行，证明本场景不要求三个独立出生点。错误弹窗的“出生点少于”不能按单位数量字面解释。

已将 `/World/出生点` 的容纳上限设为 3 并保存；没有改位置、复制出生点或改动业务 Lua。保存调用 `map save --editor-instance 35948 --json` 返回 `state=finished`、`save_result.status=success`。这次修复替代 §2 当时的未修复状态，§1 的 Capacity=1 保留为修改前基线。

### 限制与清理

- 本地多人模式的 `exec -p server` 与 `exec -p client` 均返回 `success=false`、`fast_reconnect before connect, conn: Connection`。准备好的死亡探针未执行，因此多人死亡、5 秒复活、复活满血不在这轮已证范围内。
- 两轮沿用地图内旧代码；未绕过上一轮待确认的 main 同步决定。日志中仍有预设 Name 告警和客户端 Camp 设置错误，不能据此宣称最新代码端到端通过。
- 原始编辑器 pid 35948 保留。两轮创建的测试进程已清理；主控试玩通过 `play stop` 结束，剩余测试客户端按明确的本轮 PID 回收。
- 没有添加运行时日志或业务探针，失败提交的 `[QA25]` 脚本没有执行；临时脚本和截图留在 `tmp/qa25/` 供复核。
- 本次只修改验收文档与编辑器场景配置，未修改仓库 Lua；不以 luaunit 代替真实多人入口的两轮回归。

## 6. 当前代码上的补充验收（20:26–20:44）

用户继续验收后，以 main 为基准 deploy，补齐先前地图缺失的 M0 模块。最终保留的代码修改只有工具存在性修复、对应单测、GameCfg 的两个新预设 key；业务包内代码未改。

### 6.1 预设缺失及工具误判：已修复

同步后 session `310d4a9` 报：`[MgrAbility] 装备技能超时: map://preset/u0d0b1993faa482b93e806d23715b73e`。

旧挥砍技能与锚点均不在 `get-all-asset-ids` 清单内，但 `get-asset-value <旧key> SourceCode` 返回 `success=true,value=null`。工具 `preset_exists` 只看 success，因而错误地报告“预设在，保持不动”。这也是当轮 dry-run 的实际错误输出。

修复：`tools/ability_presets.lua` 改为复用已有的资产 ID 清单，按 key 精确匹配存在性；缺少清单字段直接报错，避免把协议异常当成所有预设缺失。`tests/ability_presets_test.lua` 补存在性到重建计划的回归，以及异常清单检查。

修正后的 dry-run 正确列出两个重建动作；正式重建得到：

- 挥砍技能：`map://preset/ucc31d1999a543a7ab329eff1fd3c00d`。
- 挥砍锚点：`map://preset/u471a1004c1f43f1ae6ebe4ee2bcd080`。

工具已回写 `common/GameCfg.lua`；deploy 同步。预设与代码最终保存成功。既有加速锚点按工具纪律原地重刷壳和属性。

### 6.2 实际攻击按钮：通过

Session `6adb038`，用当前 `MgrFishCarrier:Spawn` 创建官方模型 7000544 的鱼，测试血量 50，BodyType=2（沿用 M18 伤害接缝的稳定夹具），没有直接调用攻击处理函数、没有直接扣鱼血。

OS 鼠标实际点击红色攻击按钮两次，日志：

```text
20:34:50.753 [LocalAttackButton] 请求挥砍 slot=1
20:34:50.789 [QA25C] fish-health 25.0
20:35:13.552 [LocalAttackButton] 请求挥砍 slot=1
20:35:13.585 [QA25C] fish-died 0.0 true
```

证明 UI 点击 → 客户端请求 → 服务端挥砍 → 鱼受击 → 死亡接缝成立。死亡日志恰好一次。

证据：`tmp/qa25/attack-result.log`、`attack-click-real.png`、`fish-after-two-clicks.png`。该用例验证鼠标点击路径，不冒称人类亲自点击；没有覆盖动态鱼漂移、NaN 或正式鱼血条表现。

附带视觉发现：攻击按钮的字在截图中显示不完整；点击行为通过，文字显示质量留 M1/M2 界面验收，不标成视觉全通过。

### 6.3 V7 三客户端出生、死亡、复活：通过本地并发用例

使用原始编辑器 UI【测试 → 本地多人测试 → 3】，创建三个真实本地客户端进程 33756、39824、45532，不是两个人造 Player 替身。该结果不代表三台设备或公网弱网覆盖。

由于在线 exec 通道仍无法连接多人运行时，本轮把带唯一标记的临时启动探针仅追加到**宿主目录**的 `server/main.lua`，push 预览确认只更新这一文件。探针等待三个角色及 Controller 就绪后，设置 MaxHealth=300、Health=20，三人同步每秒 TakeDamage(5)。记录 Died，0.1 秒采样复活，不代替引擎执行复活。结束后 deploy 用仓库源码覆盖、push 移除探针。

主控 session `1a793e2`，日志 `C:/FeverApps/party_pc/logs/editor_33756.log`：

| 玩家 | 血量下降 | 服务端 Died | 死亡到复活 | 复活血量 | 复活位置 |
|---|---|---|---|---|---|
| 伯乐好马！1 | 20→15→10→5→0 | 20:37:29 | 5.082346916 s | 300/300 | (-2.537,4.965,33.622) |
| 伯乐好马！2 | 20→15→10→5→0 | 20:37:29 | 5.082223892 s | 300/300 | (-2.856,4.965,33.765) |
| 伯乐好马！3 | 20→15→10→5→0 | 20:37:29 | 5.082416058 s | 300/300 | (-2.813,4.965,33.381) |

```text
[20:37:43.278] [info/server] "[QA25MULTI] RESULT players" 3 "revived_full" 3
```

三人均在原出生点附近复活，没有被单个出生点阻塞。三个客户端日志会收到相同服务端日志，统计只取主控一份，不能将转发副本算成多次死亡。

证据：`tmp/qa25/multiplayer-result.log`、`multiplayer-death-progress.png`；探针源码 `multiplayer-auto.lua`。此用例替代 §5 的“多人复活未覆盖”。

### 6.4 受击体隐藏：静态截图对照通过

Session `251e2d3`，将测试鱼放在角色侧前方无遮挡处，按 MgrFishCarrier 默认 Visible=false 截图；仅切换 Receiver.Visible=true 再截图。

- `tmp/qa25/receiver-hidden.png`：侧前方只看到鱼，无附加蛋仔模型。
- `tmp/qa25/receiver-shown-control.png`：同一位置出现受击体的黄色蛋仔模型。

已人工视图（Agent 读图）比较两图，随后恢复 false 并结束试玩。证明本次姿态下默认隐藏有效；不扩张成所有动画、视角逐帧验收。

### 6.5 实际抓举按钮：限制已实测记录

同一 session，OS 点击内置举起按钮，客户端收到 `ClickEggyLift`。第一次鱼已漂出范围，判为无效用例，不用它给按钮定性。

随后用临时夹具把动态鱼维持在玩家面前（局部 (0,0.5,2)），再次实际点击：20:42:00.538 收到 `ClickEggyLift`，未出现 OnLiftedBegin。20:42:25 将同一条鱼置于相同近处，对照调用服务端不指定强制对象的 `Controller:Lift()`，20:42:25.431/433 收到 `CTRL_BEGIN` 与 `BEGIN`。较早那次指定目标、远距离强制抓举不作为同条件对照。

结论限定于本用例：UI 输入到达，但默认客户端抓举没有完成；服务端近处抓举可行。M2 仍须落实“客户端请求 → 服务端抓举”的已定生产纪律。没有替 M2 在此新增正式抓举业务。

证据：`tmp/qa25/lift-visibility-result.log`、`lift-fixture.lua`、`lift-unforced.lua`。V2 的“真人按键档已知限制记录”现在有实际鼠标输入证据，不能改写为原生按钮举鱼已通过。

## 7. 最终剩余项与签收边界

| 项 | 最终处置 |
|---|---|
| D-1 / D-2 本地三客户端与出生容量 | 已实测闭环，不再需要“1 真人+2 模拟”的降级；跨设备/公网不在本轮覆盖范围 |
| D-6 规则面板 | 6 个实际字段截图齐全；出生点容量后续修为 3 |
| M18-3 / M18-5 | 隐藏静态对照、OS 点击攻击链路已补证据 |
| D-4 抓举按键 | 客户端默认路径限制已实际点击复核；生产桥接由 M2 落地 |
| D-3 复活饥饿度 300 | 当前尚无饥饿度实现，仍由 M1/M4 回补，不能标绿 |
| D-5 上行阈值/超限行为/载荷上限 | 仍只有既有书面判断，平台极限未压测，须用户接受该覆盖范围 |
| D-7 克隆鱼抓举 | 未覆盖；生产按 CreateUnit，仍由 M2 承接 |
| D-8 多人性能范围 | 旧 0.0740 ms/帧仅逻辑开销，仍不包含网络与渲染，须用户接受该覆盖范围 |
| 动态鱼漂移/NaN | 沿用 M18-2 交 M2；本轮伤害用例使用运动学夹具，不称已修 |
| 非致命旧日志 | 预设 Name 类型告警仍存在；多人启动有 `Player Camp can only be set on server`，未阻止三人死亡复活；本轮未消音 |

未代用户签署降级，未关闭 issue #25。需要签收的是上表未覆盖范围及归属，不是再操作已通过的按钮和多人复活用例。

**用户签收（2026-09-22，对话中原话「签收」）**：用户已接受上表全部未覆盖范围及归属——D-3 饥饿度由 M1/M4 回补、D-5 上行阈值仅以书面判断为准、D-7 克隆鱼抓举归 M2（CreateUnit 路线）、D-8 多人性能范围不含网络与渲染。issue #25 据此关闭。

## 8. 最终验证与清理

- `lua tests/run.lua`：163 successes, 0 failures，OK（新增 2 个工具回归用例）。
- `bash tools/acceptance/run_acceptance.sh`：3 passed, 0 failed，acceptance run OK。
- `common/GameCfg.lua`、`tools/ability_presets.lua`、`tests/ability_presets_test.lua` 逐个 loadfile 通过。
- 最终 deploy 后宿主 `code validate --strict --json`：valid=true，issues=[]。
- `code diff`：only-local=[]、differs=[]、only-on-map=[]、unchanged=99。
- 临时宿主启动探针已由 deploy 移除；仓库 server/main.lua 未改，测试用例与日志保留在 `tmp/qa25/`。
- 试玩均已结束，测试子进程清理，原编辑器回到 idle；地图保存成功、dirty=false。
- 原始 diff 与本轮输出均留存。没有改 vendor 包内代码，没有推送提交或发布 issue 评论。

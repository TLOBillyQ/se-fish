# RemoteEvent 频率与包大小上限的官方口径

**上下文指针**：本调研解决 issue #14「调研：RemoteEvent 频率与包大小上限的官方口径」（`Part of #11`，wayfinder 地图「渔力全开 MVP 路线图」）；下游消费方是 issue #15「决策：收线交互与高频输入策略」——它要用这里的口径定客户端聚合窗口与服务端校验策略。

调研时间 2026-09-22，编辑器 CLI 0.18.0，仓库 HEAD `0966052`。本文件所在分支 `research/remoteevent-limits` 是一次性调研分支。

## 0. 结论速览

| 问题 | 结论 | 依据 |
|---|---|---|
| 上行（`FireServer`）频率上限 | **无官方口径**（正文、教程、更新日志、公告、本地存根均无数值） | §2.1–§2.5 |
| 包大小上限 | **无官方口径**；页面只约束"单载荷 / 不支持 CFrame"，不给字节数 | §2.2、§2.3 |
| 超限时的行为（限流 / 丢弃 / 报错） | **无官方口径**（对比 `MessageService` 明说"否则将引发错误"） | §2.6、§2.8 |
| 官方要求的服务端校验 | **有**：五层校验表「身份 / 类型 / 频率 / 业务条件 / 结果下发」，频率校验必须自建 | §2.3 |
| 官方给出的频率数值 | 只有一个**教程示例值**：`REQUEST_COOLDOWN = 0.5`（同一玩家 0.5 秒内只处理一次只读快照请求）；另有 HUD 刷新节流 1 秒的示例 | §2.3、§2.7 |
| 双端同步节奏 | **有**：SE 逻辑帧约 30 Hz（另有"逻辑帧 30fps"） | §2.4 |
| 服务端权威时钟 | **有**：`World:GetServerTime()` | §2.4 |
| RemoteEvent 实例 / 通道数量上限 | **无官方口径**；且本图在用的 `game:CreateRemoteEvent` 未进文档 | §2.7 |
| 相邻数值限制（对照，不属于 RemoteEvent） | `MessageService.PublishAsync` 单条 ≤ 1 KB、topic 1–80 字符 | §2.8 |

一句话：**官方从未公布 RemoteEvent 的频率、包大小或限流数值；官方给的是"服务端必须自建频率校验"的协议设计规范，不是平台配额。**

## 1. 来源与调研口径

按优先级取正文（不是搜索索引摘要）：

1. 本地 SE API 存根 `EggyAPI.lua`（仓库根；与 `~/.eggitor/eggy_api/api_lua_doc/EggyAPI.lua` 内容一致，仅行尾差异，`api_lua_doc/version.json` = `0.0.7`）。
2. 官方手册站点 `https://u5-creator.s3.game.163.com/manual/se/`：`game_api/data/RemoteEvent.html`、`game_api/changelog/changelog_20260709…20260918.html`（12 篇）、`update/0716…0917se_update.html`（10 篇）、`lua/00–22`（24 篇）、`rules/rules.html`、`game_api/README.html`，以及相邻服务的页面（`MessageService` / `ReplicatedStorage` / `Players` / `World`）。
3. `editor-cli docs search`（与站点同源，无 URL）作为交叉检索：只用它定位站点页面，数值与结论一律以站点正文为准。

复核命令（可重跑）：

```bash
curl -sSL "https://u5-creator.s3.game.163.com/manual/se/game_api/data/RemoteEvent.html" -o re.html
curl -sSL "https://u5-creator.s3.game.163.com/manual/se/lua/08-client-server-remote-event.html" -o ch8.html
editor-cli docs search "RemoteEvent 每秒最大次数 上限 限流" --docset manual --limit 3
grep -n "RemoteEvent" EggyAPI.lua
```

站点是 VitePress 静态站，`.../se/` 目录索引（`index.html`）不存在，必须直接取具体页面 `.html`。

## 2. 逐条证据

### 2.1 本地存根：API 面本身没有频率/大小参数

`EggyAPI.lua:1993-2020` 是 RemoteEvent 的全部声明：

- 类注释（`:1993`）：「远程事件，用于客户端与服务端之间的异步单向通信，可由服务端发送给指定客户端或所有客户端，也可由客户端发送给服务端。」
- 只有四个函数：`FireAllClients(args)`（`:2003`）、`FireClient(player, args)`（`:2009`）、`FireServer(args)`（`:2014`）、`New(eventName)`（`:2020`）。
- 参数类型一律是可选的 `Any`，**没有任何频率、字节数、批量、超时或返回错误码参数**；也没有 `RemoteFunction`（全仓 grep `RemoteFunction` 零命中，站点 `game_api/data/RemoteFunction.html` 返回 404）。
- 全存根中"限流/吞吐/流量"只出现在 DataStore 与 MemoryStore 的错误码里（`:2972-2977` 的 `ReadThrottle/WriteThrottle/…`、`:3269` 的 `RequestThrottled=108`），与 RemoteEvent 无关。

结论：**存根层无口径**（这一条与 `docs/技术难点识别.md:78` §9 一致，本次复核仍成立）。

### 2.2 官方手册 RemoteEvent 页：只有行为约束，没有数值

页面：`<站点>/game_api/data/RemoteEvent.html`。

- §概览：`Kind = Data`、`Realm = common`（两端可用）。
- §适用场景：「典型场景是本地交互先行、权威状态后置：客户端在本地产生一次操作后调用 `FireServer` 上报，服务端在 `OnServerEvent` 中处理后，再用 `FireClient` 或 `FireAllClients` 把结果同步回客户端界面。」
- §注意事项（原文）：「当前版本不支持直接传递 `CFrame` 参数，请拆分为 position(Vector3) 与 rotation(Quaternion/Vector3) 等可序列化字段，或转换为 table 后再传递。服务端必须把 `OnServerEvent` 的 args 视为不可信客户端输入，校验类型、取值范围和玩家权限后才能修改权威状态。」
- 全文（含四个函数的签名表、示例）**没有任何频率、字节数、并发数、超限行为的描述**。

结论：**包大小无官方口径**；官方只给了两条可操作约束——单载荷、`CFrame` 不支持（需拆字段或转 table）。`docs/技术难点识别.md:78` 的「每次只能带一个 payload，且不支持直接传 `CFrame`」在此得到机制确认（payload 单参数那半句的原文在 §2.3）。

### 2.3 官方 Lua 教程第 8 章：频率校验是"必须自建"，示例值是 0.5 秒

页面：`<站点>/lua/08-client-server-remote-event.html`（标题「第 8 章：客户端与服务端通信」）。这是全部来源里对"高频输入"最有指导性的一页。

- §核心原则 + 载荷约束：「当前 RemoteEvent 公开签名每次只接受一个可选的 Any 载荷。需要传多个字段时，把它们装进同一个 table；不要照搬支持任意位置参数的其他事件系统。」——即 `docs/技术难点识别.md:78` 所指的 payload 限制。
- §校验层（官方给出的五层协议模板，逐字）：

  | 校验层 | 要问的问题 | 官方示例 |
  |---|---|---|
  | 身份 | 这个请求是谁发来的？ | 从 `OnServerEvent(player, payload)` 拿真实玩家，不让客户端传 player |
  | 类型 | 参数类型是否符合预期？ | payload 必须是 table，且字段类型正确 |
  | 频率 | 是否刷得太快？ | **同一玩家 0.5 秒内只处理一次 HUD 快照请求** |
  | 业务条件 | 玩家是否真的满足条件？ | 是否在回合中、是否碰到目标、是否有足够货币 |
  | 结果下发 | 客户端应该看到什么？ | 服务端读取权威状态后再 `FireClient` / `FireAllClients` |

- 服务端示例代码给出具体写法（`local lastRequestTime = {}`、`local REQUEST_COOLDOWN = 0.5`、`-- 2. 频率校验：同一玩家不能无限连发。`，用 `World:GetServerTime()` 取 now、按 `player.UserId` 记录、`Players.PlayerRemoving` 时清表）。
- §常见错误：「错误：服务端不校验 —— 客户端是不可信的。所有奖励、扣血、购买、传送、存档请求都必须在服务端校验参数、频率和业务条件。」另有一条「错误：脚本一加载就 `FireServer`」（玩法动作必须由按键/按钮/交互触发）。
- §练习任务第 5 条：「给自己的一个 RemoteEvent 写一张"身份 / 类型 / 频率 / 业务条件 / 结果下发"校验表。」
- §期望结果第 6 条：「玩家按 B 键时可以再次刷新；0.5 秒内的重复请求会被忽略。」

**注意口径边界**：`0.5` 是教程为**只读、幂等**的快照请求选的示例值，教程明确说写操作（购买/奖励/伤害/传送/存档）还要补完整业务条件。它是"官方认可的写法"，**不是平台强制的频率上限**，教程也没说超过它会怎样。

### 2.4 官方教程第 3 章 / 第 2 章：同步节奏是 ~30 Hz

- `<站点>/lua/03-world-client-server-loop.html` §逻辑帧时序（原文）：「SE 的逻辑帧通常每秒约 30 次，按以下顺序执行。实际间隔可能波动，因此需要按时间推进的逻辑应读取事件给出的 deltaTime，不要把"一帧"硬编码成固定秒数。」顺序为 `PreSimulation → 物理模拟 → PostSimulation → Heartbeat → FrameUpdate → PostFrameUpdate`。
- 同页 §常见错误：「Heartbeat 每秒触发约 30 次，如果不节流，日志会被刷屏。用 nextLogTime 控制打印频率。」
- `<站点>/lua/02-objects-properties-coordinates-enums.html` §坐标系同样写「逻辑帧 30fps。」

这是本次调研找到的**唯一官方"节奏"数值**：它约束服务端处理能力的量级（每帧约 33 ms），不约束 RemoteEvent 本身。

### 2.5 服务端权威时钟：`World:GetServerTime()`

`<站点>/game_api/service/World.html` §GetServerTime：`GetServerTime() -> Float（服务器时间，单位为秒）`。教程第 3、8、22 章都用它做倒计时与频率校验的服务端时间基准。issue #15 要"用 `World:GetServerTime()` 校验 CD"，其 API 依据在此。

### 2.6 更新日志（0709–0918）与更新公告（0716–0917）：没有网络限流条目

- `game_api/changelog/changelog_20260709…20260918.html` 共 12 篇逐篇核查：**没有任何 RemoteEvent 频率/大小/限流相关的变更**。唯一出现 "RemoteEvent" 的是 `changelog_20260910.html` 里 `Player` 类描述的措辞统一（「…也是 RemoteEvent 网络消息通信的唯一标识」），与限制无关。
- `update/0716se_update.html … update/0917se_update.html` 共 10 篇：与网络相关的只有 `update/0820se_update.html` §3「其他功能更新」两条——「编辑状态下支持模拟弱网环境，可在【设置】-【通用设置】-【网络设置】中开启。」与 Bug 修复区的「调整了客户端网络参数配置。」**没有任何限流/配额数值公开**。
- `<站点>/rules/rules.html`（玩法规则页）只列规则项名称（组件互动、相机、物品、死亡、复位、观战、匹配与匹配参数、乐园岛匹配等），**无网络类规则**。

### 2.7 明确的"无官方口径"清单

以下项目在 §1 的全部来源里都查不到，按 issue 要求逐项记明：

| 项目 | 状态 |
|---|---|
| `FireServer` 每秒次数上限（每玩家 / 每地图 / 每服务器） | **无官方口径** |
| 单次载荷的字节上限 | **无官方口径**（只有"单载荷、`CFrame` 不支持"） |
| `FireAllClients` / `FireClient` 下行频率或带宽上限 | **无官方口径** |
| 超限时的行为（静默丢弃 / 报错 / 断连 / 降级） | **无官方口径** |
| RemoteEvent 实例（通道）数量上限 | **无官方口径**；`game:CreateRemoteEvent(eventName)`（`common/REUtil.lua:14`、`client/packages/ability_system/component_scripts/box_component_fix.lua:24` 在用）**在站点与存根中均无文档**（`editor-cli docs search "CreateRemoteEvent" --docset game-api` 返回「未找到匹配条目」），存根只有 `RemoteEvent.New` |
| 客户端"一帧内多次 `FireServer` 是否合并" | **无官方口径** |
| 官方推荐的聚合窗口数值 | **无官方口径**；官方只给"节流"手法示例（教程第 8 章 0.5 秒、第 22 章 HUD 刷新 1 秒——见 `lua/22-capstone-projects.html` 的 `nextUpdateTime = now + 1`） |
| 压测口径（多少消息算高负载） | **无官方口径** |

### 2.8 对照：官方**会**写数值的地方（说明"没写"是刻意的，不是文档省略）

同一批来源里，凡是有硬限制的接口都明确给数字，可见 RemoteEvent 的无数值不是漏写：

- `MessageService.PublishAsync`（`<站点>/game_api/service/MessageService.html`）：`topic` 长度限制 1–80 个字符；`message`「序列化后大小不能超过 1k 字节, 否则将引发错误」；注意事项重申「消息体序列化后不能超过 1KB」。**同类的"消息"接口有字节上限，RemoteEvent 没有。**
- DataStore/MemoryStore：错误码齐全（`EggyAPI.lua:2931-3008` `DataStoreErrorCode`、`:3259-3295` `MemoryStoreErrorCode`，含"单键名读取/写入流量超限""吞吐量队列已满"等），但同样**只有语义、没有阈值数值**。
- 资源体积：图片 ≤ 3 MB / 1920×1080、音频 ≤ 1 MB / 60 秒（`docs/技术难点识别.md:86` §11，引 `<站点>/assets/image.html`、`assets/audio.html`）。

## 3. 对本图（收线玩法）的工程结论

**以下是从官方来源推出的工程判断，不是官方口径**，标注为「推断」的地方需靠压测或问官方收口。

1. 上一档结论：**约 10 次/秒/人 的上行没有任何官方背书的余量证明**。8 人同图即 80 msg/s，若未来放到常驻房间规模（`docs/技术难点识别.md` §12）还会线性放大。设计上必须按"平台随时可能限流且不告知"来做，即由本图自己设定上行预算（推断）。
2. 聚合窗口的可行下界受逻辑帧约束：服务端约 30 Hz（§2.4），短于 ~33 ms 的窗口不可能被服务端逐帧消化。**建议窗口取 100 ms（10 Hz 上行，比逐次点击降一个数量级）**，窗口内累计点击次数/位移增量后打成一个载荷——载荷必须是单个 table（§2.3 核心原则）。窗口具体值留 issue #15 定，本调研只给下界与依据。
3. 服务端校验按教程五层表落地（§2.3），时间基准用 `World:GetServerTime()`（§2.5），不要信任客户端时间戳或次数。
4. 仓库里已有可复用的雏形：`common/REUtil.lua:23` `CheckRECD(player, reName, duration)` 已实现「按玩家 × 事件名」的服务端 CD 拦截（默认 1 秒，`PlayerRemoving` 清理）。高频输入若走这条路径，需要把它从"单事件 CD"扩展成"滑动窗/次数上限"（推断）。
5. 由于超限行为无官方口径（§2.7），**服务端不能假设"限流时客户端一定能收到错误"**；脱钩/上岸这类结果必须由服务端权威判定后主动下发，客户端只做表现降级（推断，与教程第 8 章"客户端只发请求"一致）。
6. 验收手段：`update/0820se_update.html` 的**编辑状态模拟弱网**（【设置】-【通用设置】-【网络设置】）是官方给的唯一网络劣化工具，可作为聚合窗口与重传策略的测试环境；真实阈值仍需压测（推断）。
7. 不要用"每帧 `FireServer`"（如 `Heartbeat` 内直接上报）实现连续点击：教程第 3 章明确要求 `Heartbeat` 内节流（§2.4）。

## 4. 与 `docs/技术难点识别.md` 的关系

- §9「高频输入」（`docs/技术难点识别.md:78`）的结论**复核成立**：频率与包大小上限在本地注释、官方页、教程里都没有数值。本次新增的支撑是「官方在所有有硬限制的接口（`MessageService` 1 KB / topic 1–80 字符）都会写数字，RemoteEvent 页没有」这一反证，以及 changelog 0709–0918、update 0716–0917 的逐篇排除。
- §9 的「每次只能带一个 payload，且不支持直接传 `CFrame`」**已确证**，原文见 §2.2 与 §2.3。
- §9 的「客户端按时间窗聚合，服务端用 `World:GetServerTime()` 校验 CD 与次数上限」是**教程第 8 章的官方写法**（不是本图的臆断），有 `<站点>/lua/08-client-server-remote-event.html` 可引；本文 §3 只补了窗口下界（≥ 1 逻辑帧 ≈ 33 ms）这一条。
- 「仍未决事项」表里 `docs/技术难点识别.md:118` 的「RemoteEvent 频率 / 大小」行**维持原判**：仍应写「无数值 → 压测；问官方」。本调研没有把它变成已决，只是把"查过了、确实没有、官方要求自建"这一层固定下来。若要把 §9 的表述升级，建议只补一句出处指向本文件，不改结论。

## 5. 未决与后续

| 事项 | 面向 | 途径 |
|---|---|---|
| 上行频率的真实限流阈值、超限行为（丢弃/报错/断连） | 本图所有高频链路 | 已发布测试图压测（爬坡发 `FireServer`，看丢包与报错）；问官方 |
| 单次载荷的真实字节上限 | 收线/枪械载荷编码 | 同上（逐步加大 table 大小直到无效或不达） |
| `game:CreateRemoteEvent` 的可用性与通道数量上限 | `common/REUtil.lua`、ability_system 包内通道 | 问官方（文档缺页） |
| 聚合窗口与次数上限的具体取值 | issue #15 | 由 #15 决策后按本文 §3 的边界定参 |

## 6. 来源清单

本地：

- `EggyAPI.lua:1993-2020`（RemoteEvent 声明）、`:2931-3008`（`DataStoreErrorCode`，对照）、`:3259-3295`（`MemoryStoreErrorCode`，对照）
- `common/REUtil.lua:14`、`:23-40`（既有 `game:CreateRemoteEvent` 与 `CheckRECD` 服务端 CD 实现）
- `docs/技术难点识别.md:76-78`（§9 高频输入）、`:118`（未决事项行）

站点（正文，2026-09-22 取）：

- `https://u5-creator.s3.game.163.com/manual/se/game_api/data/RemoteEvent.html`（§概览 / §适用场景 / §使用要点 / §注意事项 / §函数）
- `https://u5-creator.s3.game.163.com/manual/se/lua/08-client-server-remote-event.html`（§核心原则 / §校验层 / §服务端代码 / §常见错误 / §练习任务 / §期望结果）
- `https://u5-creator.s3.game.163.com/manual/se/lua/03-world-client-server-loop.html`（§逻辑帧时序 / §常见错误）
- `https://u5-creator.s3.game.163.com/manual/se/lua/02-objects-properties-coordinates-enums.html`（§坐标系：逻辑帧 30fps）
- `https://u5-creator.s3.game.163.com/manual/se/lua/22-capstone-projects.html`（HUD 刷新节流 `nextUpdateTime = now + 1`；server 校验 schema 和频率）
- `https://u5-creator.s3.game.163.com/manual/se/game_api/service/World.html`（§GetServerTime）
- `https://u5-creator.s3.game.163.com/manual/se/game_api/service/MessageService.html`（1 KB / 1–80 字符，对照）
- `https://u5-creator.s3.game.163.com/manual/se/game_api/service/ReplicatedStorage.html`（§注意事项：自动复制 ≠ 远程调用）
- `https://u5-creator.s3.game.163.com/manual/se/game_api/changelog/changelog_20260709.html` … `changelog_20260918.html`（12 篇，无 RemoteEvent 限制条目）
- `https://u5-creator.s3.game.163.com/manual/se/update/0716se_update.html` … `update/0917se_update.html`（10 篇；`update/0820se_update.html` 含弱网模拟与客户端网络参数配置）
- `https://u5-creator.s3.game.163.com/manual/se/rules/rules.html`（玩法规则清单，无网络类规则）

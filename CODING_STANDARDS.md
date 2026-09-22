# 编码规范

编写或审查本仓库 SE 业务 Lua 时，按本次改动涉及的章节检查。本文的运行时限制不适用于宿主机工具和独立 Lua 测试进程；存量代码仅在本次触及时按相关规则修订。

**约束**指官方公开契约；**项目规则**指本仓库采用的工程做法。教程中的命名、示例数值和完整生命周期方法集不作为额外要求。

接入管理器、界面、技能包，或修改配置、导出物时，先查 [AGENTS.md 的代码结构](AGENTS.md#代码结构)；命名和玩家文案查 [CONTEXT.md](CONTEXT.md)。这些约定在原文维护。

## API 与运行端

**约束**（[S0]、[S1]）：

- 使用 SE 公开 API，核对成员签名、对象类型和运行端。查询结果可能为空时先判空；位置、碰撞、文本等成员须从具有该能力的具体类型访问，普通 table 不能替代引擎数据类型。
- `game`、`Enums`、`Vector3`、`Color`、`Quaternion`、`CFrame`、`RemoteEvent` 是全局入口；`EggyAPI.lua` 仅作类型存根，不作为模块加载。
- `require` 路径包含工程目录前缀，大小写与文件一致。client 与 server 互不加载；common 不依赖任一端专属模块。
- SE 沙盒移除了 `io`、`os`、`package`、`debug`；`require` 仅加载工程模块。`setmetatable` 不支持 `__mode`、`__gc`，`getmetatable` 只支持 table。
- common 模块在双端独立运行，Lua table 的修改不会自动跨端同步；普通 Lua 变量也不提供跨对局持久化。

**项目规则**：新增或变更 API 调用时，按 [AGENTS.md 的查 API 顺序](AGENTS.md#查-api-的顺序) 核对。完成条件是签名、语义与运行端都有依据；未查到的名称标 `[未查证]`，不作为已可用接口交付。发生文档与实例差异时记录并验证；CLI 命中的编辑时 `editor:GetService(...)` 示例不能用于玩法运行时。

## 模块与状态归属

**项目规则**（依据 [S0]、[S8]、[S19]）：

- server 持有权威玩法状态，负责校验、结算与存储；client 处理输入、UI、相机和本地表现；common 放双端配置、协议与可共用逻辑。客户端提交操作意图，由服务端判定血量、奖励和存档等结果。
- `main.lua` 组装模块、分发生命周期；业务逻辑归对应模块。依赖通过 `local X = require(...)` 显式取得，保持单向；需要协调多个模块时由入口注入依赖。
- 模块加载阶段定义表、函数和必要的通信协议；事件绑定、UI 创建、玩家读取及玩法启动放入显式生命周期入口。纯配置模块加载时不获取 Service。
- 接入服务端管理器时检查 [当前入口](server/main.lua)：它先处理已在线玩家，再分发 `Start`，因此 `OnPlayerAdded` 不能依赖 `Start` 已执行。管理器以 `pairs` 遍历，跨管理器的初始化依赖须显式安排。
- 修改现有文件时沿用其命名、缩进与引号风格，格式调整限于本次修改范围。
- 新增或修改 `pcall` 时处理失败结果，记录模块、操作、必要对象标识与错误内容；失败后按业务返回或清理，不能继续报告成功。

## 跨端通信

**约束**：RemoteEvent 每次传一个可选 payload，多字段合成 table；`OnServerEvent` 的 `player` 由引擎注入，服务端以它确认请求者身份。[S8]

| 方向 | 发送 | 接收回调 |
| --- | --- | --- |
| client → server | `FireServer(payload?)` | `OnServerEvent(player, payload)` |
| server → 指定 client | `FireClient(player, payload?)` | `OnClientEvent(payload)` |
| server → 全部 client | `FireAllClients(payload?)` | `OnClientEvent(payload)` |

载荷使用可序列化字段。CLI 的 `RemoteEvent.mdx` 说明 `CFrame` 需拆成位置、旋转等字段或转换为 table；该索引未标适用版本，见[查证记录](#查证记录)。

**项目规则**（依据 [S8]）：

- 通过 [REUtil](common/REUtil.lua) 获取已有事件，双端共用事件名与协议定义。修改旧的多实参消息时，同时迁移发送端与接收端。
- 服务端校验 payload 类型、字段取值、玩家权限、玩法条件和请求频率后，才修改权威状态。`CheckRECD` 返回 `true` 表示拦截；限频不代替其他校验，阈值按业务配置。
- 客户端先监听响应，再发请求；收到快照先检查结构，再更新显示。需要覆盖迟加入或重连时，提供只读、幂等的 ready / snapshot 握手，读取当前状态。
- 玩家离开时清理按玩家保存的限频表和临时请求状态。

## 事件与异步生命周期

**约束**（[S6]）：

- `Signal`、`BindableEvent` 是同端通知；`Signal` 没有 `Wait()`。
- `Task` 使用协作式协程，`Task:Wait` 在协程中调用。异步接口是等待还是回调，以公开签名为准。
- `TimerService:CreateTimer` 返回的 Timer 已启动；停止用 `Cancel()`，暂停与续跑用 `Pause()` / `Resume()`。周期回调不保证准点触发。

**项目规则**（依据 [S6]、[S19]）：

- 事件连接、Timer、异步任务、临时对象和玩家状态均指定拥有者与收尾入口。只实现实际需要的初始化、启动、重置、销毁职责。
- 持续监听保存 `Connect` 返回值，结束时 `Disconnect()`；自建 BindableEvent 不再使用时销毁，Signal 断开监听后释放引用。重置或重复启动时清理旧资源，避免叠加监听；需跨局保留的状态明确标注。
- 初始化或启动中途失败时，按依赖反向清理已成功的部分。完成条件是再次启动不会残留上一轮连接、计时器或临时状态。
- 延迟回调执行前重新确认对象与流程仍有效；可重播流程用代次或等效机制使旧任务失效，防止上一轮回调修改新一轮状态。
- 关键结果由显式状态与去重控制，不依赖同帧事件的隐含顺序。触碰等可重复事件按业务去重；计数用整数，倒计时按结束时间计算或用越界判断结束。

## 验证与交付

对本次修改涉及的每条规则，检查实现及相应失败路径；验证命令取自 [AGENTS.md 的工具链](AGENTS.md#工具链)。

| 改动 | 完成条件 |
| --- | --- |
| 纯 Lua 规则 | 单测通过，关键分支有相应验证 |
| 引擎交互、通信、生命周期 | 试玩验证修改涉及的双端行为、非法请求或重复进入等路径；单测不替代运行时验证 |
| 工具链 | 按 [验收说明](tools/acceptance/README.md) 跑相关 feature |
| 文档 | 引用可解析，命令和项目约定已核对 |

交付说明实际执行的验证与仍未验证的行为。

## 查证记录

以下用于复查规则来源或处理版本差异。核查日期为 2026-09-22，CLI 版本为 `0.18.0`；本次文字修订沿用已核实来源。

| 官方章节 | 支持内容 |
| --- | --- |
| [S0：从可视化编辑器到状态同步 Lua][S0] | 公开 API、对象类型、双端状态 |
| [S1：脚本工程与运行入口][S1] | require、全局类型、沙盒 |
| [S6：事件、Timer 与 Task][S6] | 调度语义、异步生命周期 |
| [S8：客户端与服务端通信][S8] | RemoteEvent、校验、快照握手 |
| [S19：可复用系统][S19] | 模块依赖、生命周期、失败清理 |

CLI 检索使用 `--docset manual --json`。复查时执行 `editor-cli docs search "<查询>" --docset manual --limit <数量> --json`：

| 实际查询 | 数量 | 采用条目 |
| --- | --- | --- |
| SE Lua 代码规范 模块 require 全局变量 服务端 客户端 | 3 | 第 1、8 章 |
| SE RemoteEvent 客户端 参数 校验 服务端 安全 | 3 | 第 8 章 |
| SE Lua 生命周期 事件 Disconnect Task 计时器 清理 | 3 | 第 19 章、Connection.mdx、Timer.mdx |
| SE Lua 模块 require 副作用 循环依赖 Manager Init Start | 2 | 第 19 章 |
| SE RemoteEvent FireServer FireClient 参数 table 限制 | 2 | RemoteEvent.mdx |

CLI 结果的 canonical URL、构建号、更新时间和适用编辑器版本为空，索引新鲜度未确认。教程条目已与上述网页交叉核对；RemoteEvent、Connection、Timer 的相关签名已与仓库 `EggyAPI.lua` 核对。

[S0]: https://u5-creator.s3.game.163.com/manual/se/lua/00-from-editor-to-se-lua.html
[S1]: https://u5-creator.s3.game.163.com/manual/se/lua/01-project-setup-and-entrypoints.html
[S6]: https://u5-creator.s3.game.163.com/manual/se/lua/06-events-task-timer.html
[S8]: https://u5-creator.s3.game.163.com/manual/se/lua/08-client-server-remote-event.html
[S19]: https://u5-creator.s3.game.163.com/manual/se/lua/19-reusable-systems-managers.html

# 钓鱼怎么这么危险啊喂！

蛋仔派对状态同步（SE）地图的 Lua 源码。

## 代码结构

- `server/`：`main.lua` 的 `MgrMap`（`server/main.lua:12`）注册 `server/Mgr/` 下的管理器，由它统一分发 `Start` / `OnPlayerAdded` / `OnPlayerRemoving` / `Update`，新管理器加进 `MgrMap`。`server/_trigger/` 是编辑器触发器系统的运行时脚本（`GlobalVars` 是它的变量库）。
- `client/`：`main.lua` 启动本地逻辑（`LocalMgrUtil` / `LocalMotorUnitCtrl` / `LocalAttackButton` / `LocalReelIn`），并打开 `ScreenMain`；旧钓鱼入口 `LocalFishEnter` 已退役、不再启动。界面交给 `MgrGameUI`；每个界面一个 handler 放 `client/ScreenHandlers/`，文件名要与 EUI 节点同名（`MgrGameUI:GetScreen` 按节点名 require handler）。
- `common/`：双端共享，`GameCfg.lua` 是数值配置（鱼等级、鱼竿等级等），`Util` / `REUtil` / `FXUtil` / `TeleportUtil` 是工具模块。
- `server/packages/` / `client/packages/` / `common/packages/`：官方技能包 `ability_system` 整包 vendor，内部代码只读。业务层经双端根入口 `server/AbilityAPI.lua` / `client/AbilityAPI.lua` 用技能包，装配在 `server/Mgr/MgrAbility.lua`，配置在 `GameCfg.Ability`。碰技能包、改接缝或建编辑器侧预设前读 `docs/ability_system-vendor.md`。
- `data/`：编辑器插件导出（Prefab / UI 节点 / 字体 ID），只读，改动回编辑器重新导出、用 sync 回灌。
- `unit_scripts/`：引擎侧生成，内容不在本仓库管理。
- `tests/`：luaunit 单测（`tests/lib/` 是 vendored 的 luaunit）。
- `features/`：Gherkin 验收 feature（`features/<车道>/<名字>.feature`，`# language: zh-CN` 开头）。
- `EggyAPI.lua` / `EggyEditorAPI.lua`：运行时 / 编辑时 API 声明。

## 工具链

参数见 `lua tools/cli.lua <子命令> --help`。

| 任务 | 命令 | 要点 |
|---|---|---|
| 仓库代码 → 宿主目录 | `lua tools/cli.lua deploy` | 字节镜像三端；编辑器开着本图时收尾 validate → diff → 有差异才 push，否则跳过并以 0 退出 |
| 宿主目录产物 → 仓库 | `lua tools/cli.lua sync` | 回灌 `eggy.json`、两份 API 存根、`data/` |
| 重建技能包编辑器预设 | `lua tools/cli.lua ability-presets` | 预设在就原地重刷，不在就重建并把新 key 回写 `GameCfg.lua`；要编辑器开着本图且在编辑态 |
| 修技能包预设 Name | `lua tools/cli.lua ability-presets --fix-names` | 症状：每场 1 条 `expected String, got userdata`、预设单位名空（issue #22） |
| 单测 | `lua tests/run.lua` | |
| 验收 | `bash tools/acceptance/run_acceptance.sh` | 跑全部 Gherkin feature，见 `tools/acceptance/README.md` |
| 质量报告 / 变异 | `bash tools/quality/run.sh`、`tools/quality/mutate.sh`、`tools/acceptance/mutate.sh` | 只出报告，不设门槛；结果在 `build/` |

宿主目录默认 `C:\Users\<用户名>\Desktop\dev\eggy\LuaSource_钓鱼怎么这么危险啊喂！`，`EGGY_WORKSPACE` 可覆盖；它只做镜像目标，别往里放别的东西。

### 编辑器工程 ≠ 仓库检出

编辑器只认 `code init` 绑定过的宿主目录为工程；任何仓库检出（含 `.tower/worktrees/wt-N`）里跑 code-* 都返回 `CODE_BINDING_INVALID`，根上的 `eggy.json` 只是 `sync` 回灌的 `isSEMap` 真源。自己敲 code-* 时加 `--workspace` 指宿主目录（`deploy` 已自带）：

```bash
"$USERPROFILE/.eggitor/cli/editor-cli.exe" code validate --strict --json --workspace "<宿主目录>"
```

### 测试纪律

- 测试首选 E2E，即编辑器试玩验证（做法见 `eggy-lua` 的「试玩验收」），尽量只用这一种测法，复杂功能能不能用靠它证明。每次试玩跑完都要留下可核验、可重复的产物：触发步骤（`input` 命令、探针文件）照着能重跑，取证结果（`log grep` 命中行、截图路径）能对得上。
- 非得单独测某个系统时，先把它所有可能失败的方式写下来，再写代码。代码写完后绝不补写单测。
- 开发期间只试玩正在改的功能；全套试玩验证留到收尾，列在下面的完成判据里。

### 完成判据

在仓库检出里改完代码，逐条跑，全部满足才算过：

| 命令 | 预期输出 |
|---|---|
| `lua tests/run.lua` | 统计行 `0 failures`，末行 `OK` |
| `bash tools/acceptance/run_acceptance.sh` | `N passed, 0 failed`，末行 `acceptance run OK` |
| `lua -e "assert(loadfile('<file>'))"`（每个改过的 `.lua` 跑一次） | 无输出、退出码 0 |
| `lua tools/cli.lua deploy` 后跑上节的 `code validate` | `{"ok":true,"data":{"valid":true,"is_se_map":true,"issues":[]},"meta":{"warnings":[]}}`；不过说明镜像或同步出了问题 |
| 全套试玩验证（validate 通过后） | 每条验收现象都有取证产物；`log trace` 本轮窗口有效且无错误 |

所有 `lua` 命令都要 Lua 5.4，先 `lua -v` 核对（验收脚本自己也会拦；`ACCEPTANCE_LUA_BIN` 可指别的解释器）。5.5 把 `for` 循环变量当 `const`，会对 `for line in handle:lines() do line = line:gsub(...)` 这类正常写法报假错 `attempt to assign to const variable`（如 `tests/run.lua:15`）——见到它就是解释器版本错了，代码没错。

## 文档

- `design`：指向 `eggitor/1_开发中/渔力全开` 的符号链接，不在本仓库管理；玩法与系统设计以它为准。
- `CONTEXT.md`：领域术语表，给出每个玩法概念该说的词与该避开的说法；起名、读设计案、写玩家可见文案前先查。
- `docs/`：`技术难点识别.md` 是已识别的技术难点，`to-questionnaire-策划案内部矛盾.md` 是待策划确认的矛盾；写技术方案或怀疑策划案自相矛盾时先看。
- issue：自建 Gitea `lzxsvn:3000` 的 `qinyuanj/se-fish`，用 `tea` 操作；读写 issue 前看 `docs/agents/issue-tracker.md`，打 triage 标签前看 `docs/agents/triage-labels.md`。
- 执行过程产物（调研全文、验证台账、验收记录、开发计划）贴进对应 issue 的评论，不落进仓库；`docs/` 只留长期有效的参考（术语、技术难点、vendor 说明、ADR）。`eggy-dev-plan` 默认落 `docs/plan/`，本仓库改为贴 issue。
- ADR 放 `docs/adr/`；探索代码前该读什么见 `docs/agents/domain.md`。

<!-- 本节以上是手写部分，CLAUDE.md 里有一份副本（eggy/teamai-netease#51 的过渡办法），改动时一起改。 -->

<!-- [teamai:rules:start] -->
<!-- DO NOT EDIT: This section is auto-managed by teamai -->

# netease 团队基线：语言

适用于所有任务。

1. **思考与回复使用中文。**
2. **产出物用中文。** 写入仓库的文档、代码注释、commit 信息、PR 描述、写给 agent 的文件（SKILL.md、rules）用中文；代码标识符与文件名用英文。
3. **专有名词与代码原样保留。** SE、FS、editor-cli、skill 名、命令、路径、代码片段不翻译。
4. **用户明确要求其他语言时以用户为准。** 引用英文原文时保留原文，并附中文说明。

# 蛋仔（eggy）工程

工程根 AGENTS.md 与本规则冲突时，以工程为准。

## 术语

- SE / FS：状态同步 / 帧同步地图，由工程根 `eggy.json` 的 `isSEMap` 判定（`true` 为 SE）。
- 资源（Resource）：图片、模型、动画等素材。单位（Unit）：单个逻辑物件。资产（Asset）：一个或多个单位的集合。
- editor-cli：操作编辑器的命令行，位于 Windows 用户目录的 `.eggitor\cli\editor-cli.exe`；WSL 里调用 `/mnt/c/Users/<Windows 用户名>/.eggitor/cli/editor-cli.exe`（WSL 家目录下的 Linux 版连不上 Windows 编辑器）。子命令与参数以 `editor-cli <命令> --help` 为准。

## 路由

接到下表任务，先按名字调用对应 skill；调用不了就直接读工程根下 agent 技能目录里的 `<名字>/SKILL.md`——Claude 是 `.claude/skills/`、Codex 是 `.codex/skills/`、Kimi 是 `.kimi-code/skills/`、ZCode 是 `.zcode/skills/`、DSH（DeepSeek Harness）是 `.dsh/skills/`。

| 任务 | skill |
|---|---|
| 写玩法设计案、策划案 | `eggy-design` |
| 写技术方案、开发计划、拆任务 | `eggy-dev-plan` |
| 把 AIGC 模型从 FS 搬进 SE（导入组件、贴图、尺寸） | `eggy-aigc-model` |

## 查 API 的顺序

1. grep 工程自带的 API 存根：SE 是 editor-cli 同一用户目录下的 `.eggitor/eggy_api/api_lua_doc/EggyAPI.lua`，FS 是工程根目录的 `EggyAPI.lua`（两份不是一套：SE 图上工程根也有一份，与 SE 存根 md5 一致，grep 哪份都行；FS 存根 9953 行、SE 存根 7406 行）。
2. 编辑器在线时用 `editor-cli api get <名字>` 确认签名（SE、FS 都覆盖）。
3. 语义和用法查 `editor-cli docs search "<问题>"`。

三步都查不到的 API 名标 `[未查证]`。（本文路径与命令验证：2026-09-19，editor-cli 0.18.0；两份存根不同与 FS 存根位置在 2026-09-19 核实；五个 agent 的技能目录核实：前四个按 teamai-cli 0.24.1 的安装目标，DSH 的 `.dsh/skills` 于 2026-09-21 在本机 0.24.2 实测）

# 蛋仔 SE 程序

接到下表任务，按常驻规则"路由"一节的方式调用对应 skill。

| 任务 | skill |
|---|---|
| 实现功能、写或改 Lua、同步代码、试玩 | `eggy-lua` |
| 试玩报错、运行期报错、修 bug | `eggy-debug` |
| 改场景（摆单位、移动、改属性、删除、存盘） | `eggy-editor-cli` |
| 做或改 EUI 界面 | `eggy-se-eui` |
| 上传图片 / 音频 / FBX、发布单资产 | `eggy-se-editor-cli` |
| 测试验证、回归测试 | `eggy-qa` |
| 性能优化、卡顿 | `eggy-perf` |
| 做编辑器插件 | `eggy-se-plugin-dev` |

SE 专属的是差异层 `eggy-se-lua`、`eggy-se-editor-cli` 加 `eggy-se-eui`、`eggy-se-plugin-dev`：改场景、写 Lua、做界面或插件前先读它们。公共层（`eggy-lua`、`eggy-debug`、`eggy-editor-cli`、`eggy-qa`、`eggy-perf`）的流程对 SE 同样适用。
<!-- [teamai:rules:end] -->

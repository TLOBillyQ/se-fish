# 钓鱼怎么这么危险啊喂！

蛋仔派对状态同步（SE）地图的 Lua 源码。

## 代码结构

- `server/`：`main.lua` 的 `MgrMap`（`server/main.lua:12`）注册 `server/Mgr/` 下的管理器，由它统一分发 `Start` / `OnPlayerAdded` / `OnPlayerRemoving` / `Update`，新管理器加进 `MgrMap`。`server/_trigger/` 是编辑器触发器系统的运行时脚本（`GlobalVars` 是它的变量库）。
- `client/`：`main.lua` 启动本地逻辑（`LocalMgrUtil` / `LocalMotorUnitCtrl` / `LocalFishEnter`），界面交给 `MgrGameUI`；每个界面一个 handler 放 `client/ScreenHandlers/`，文件名要与 EUI 节点同名（`MgrGameUI:GetScreen` 按节点名 require handler）。
- `common/`：双端共享，`GameCfg.lua` 是数值配置（鱼等级、鱼竿等级等），`Util` / `REUtil` / `FXUtil` / `TeleportUtil` 是工具模块。
- `data/`：编辑器插件导出（Prefab / UI 节点 / 字体 ID），只读，改动回编辑器重新导出、用 sync 回灌。
- `unit_scripts/`：引擎侧生成，内容不在本仓库管理。
- `tools/`：本仓库的工具链，在仓库根执行；`lua tools/cli.lua deploy` 把 `client/` `common/` `server/` 的一级子树镜像进编辑器宿主目录（默认 `dev/eggy/LuaSource_钓鱼怎么这么危险啊喂！`，`EGGY_WORKSPACE` 可覆盖）；反方向 `lua tools/cli.lua sync` 把宿主目录的 `eggy.json`、两份 API 存根与 `data/` 回灌仓库（落盘前 CRLF→LF 归一，`data/` 整目录镜像）。宿主目录本身不是本仓库，只镜像、不往里放别的东西。
- `tests/`：luaunit 单测，`lua tests/run.lua` 一条命令跑完；`tests/lib/` 是 vendored 的 luaunit。
- `EggyAPI.lua` / `EggyEditorAPI.lua`：运行时 / 编辑时 API 声明。

## 文档

- `design`：指向 `eggitor/1_开发中/渔力全开` 的符号链接，不在本仓库管理；玩法与系统设计以它为准。
- `CONTEXT.md`：领域术语表，给出每个玩法概念该说的词与该避开的说法；起名、读设计案、写玩家可见文案前先查。
- `docs/`：`技术难点识别.md` 是已识别的技术难点，`to-questionnaire-策划案内部矛盾.md` 是待策划确认的矛盾；写技术方案或怀疑策划案自相矛盾时先看。

## Agent skills

### Issue tracker

issue 住在自建 Gitea `lzxsvn:3000` 的 `qinyuanj/se-fish`，用 `tea` CLI 操作。见 `docs/agents/issue-tracker.md`。

### Triage labels

五个标准 triage 标签，标签串与角色同名（五个都已建在仓库里）。见 `docs/agents/triage-labels.md`。

### Domain docs

单 context：根目录 `CONTEXT.md`，ADR 放 `docs/adr/`。见 `docs/agents/domain.md`。

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

接到下表任务，先按名字调用对应 skill；调用不了就直接读工程根下 agent 技能目录里的 `<名字>/SKILL.md`——Claude 是 `.claude/skills/`、Codex 是 `.codex/skills/`、Kimi 是 `.kimi-code/skills/`、ZCode 是 `.zcode/skills/`。

| 任务 | skill |
|---|---|
| 写玩法设计案、策划案 | `eggy-design` |
| 写技术方案、开发计划、拆任务 | `eggy-dev-plan` |

## 查 API 的顺序

1. grep 工程自带的 API 存根：SE 是 editor-cli 同一用户目录下的 `.eggitor/eggy_api/api_lua_doc/EggyAPI.lua`，FS 是工程根目录的 `EggyAPI.lua`（两份不是一套：SE 图上工程根也有一份，与 SE 存根 md5 一致，grep 哪份都行；FS 存根 9953 行、SE 存根 7406 行）。
2. 编辑器在线时用 `editor-cli api get <名字>` 确认签名（SE、FS 都覆盖）。
3. 语义和用法查 `editor-cli docs search "<问题>"`。

三步都查不到的 API 名标 `[未查证]`。（本文路径与命令验证：2026-09-19，editor-cli 0.18.0；两份存根不同与 FS 存根位置在 2026-09-19 核实；四个 agent 的技能目录按 teamai-cli 0.24.1 的安装目标核实）

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

# 钓鱼怎么这么危险啊喂！

蛋仔派对状态同步（SE）地图的 Lua 源码。

## 代码结构

- `server/`：`main.lua` 的 `MgrMap`（`server/main.lua:12`）注册 `server/Mgr/` 下的管理器，由它统一分发 `Start` / `OnPlayerAdded` / `OnPlayerRemoving` / `Update`，新管理器加进 `MgrMap`。`server/_trigger/` 是编辑器触发器系统的运行时脚本（`GlobalVars` 是它的变量库）。
- `client/`：`main.lua` 启动本地逻辑（`LocalMgrUtil` / `LocalMotorUnitCtrl` / `LocalAttackButton` / `LocalReelIn`），并打开 `ScreenMain`；旧钓鱼入口 `LocalFishEnter` 已退役、不再启动。界面交给 `MgrGameUI`；每个界面一个 handler 放 `client/ScreenHandlers/`，文件名要与 EUI 节点同名（`MgrGameUI:GetScreen` 按节点名 require handler）。
- `common/`：双端共享，`GameCfg.lua` 是数值配置（鱼等级、鱼竿等级等），`Util` / `REUtil` / `FXUtil` / `TeleportUtil` 是工具模块。
- `packages/`：官方技能包 `ability_system` 整包 vendor（`server/` / `client/` / `common/` 各一份），内部代码一行不改；来源、升级纪律与首期启用范围见 `docs/ability_system-vendor.md`。业务层不直接 require 包内模块——技能包的接缝是双端根聚合入口 `server/AbilityAPI.lua` 与 `client/AbilityAPI.lua`（转发名单在 `common/AbilityAPIBase.lua`，单测拿包内源码校对；`AbilityAPI.AttachAnchor` 是本图为锚点补挂加的包外接口）。装配由 `server/Mgr/MgrAbility.lua` 负责：进图建技能管理器、装初始技能、挂锚点，配置在 `GameCfg.Ability`。本编辑器不认包内的 `---@export_prefab_type` 自定义预设类型，编辑器侧资产（技能 / 技能背包 / 锚点预设）怎么建见 issue #7（加速链路）与 #8（挥砍链路，含锚点实例属性覆盖与触发盒 57450 结论）；各端 `packages/` 下有 README 汇总来源与纪律。预设建在图里、不进 git，一键重建用 `lua tools/cli.lua ability-presets`（issue #9）。
- `data/`：编辑器插件导出（Prefab / UI 节点 / 字体 ID），只读，改动回编辑器重新导出、用 sync 回灌。
- `unit_scripts/`：引擎侧生成，内容不在本仓库管理。
- `tools/`：本仓库的工具链（deploy / sync、acceptance 与 quality 设施），入口见下面「工具链」。
- `tests/`：luaunit 单测，`lua tests/run.lua` 一条命令跑完；`tests/lib/` 是 vendored 的 luaunit。
- `features/`：Gherkin 验收 feature（`features/<车道>/<名字>.feature`，`# language: zh-CN` 开头），由 `bash tools/acceptance/run_acceptance.sh` 跑。
- `EggyAPI.lua` / `EggyEditorAPI.lua`：运行时 / 编辑时 API 声明。

## 工具链

在仓库根执行，命令名照抄即可：

| 任务 | 命令 | 入口 |
|---|---|---|
| 仓库代码 → 编辑器宿主目录 | `lua tools/cli.lua deploy` | 三端一级子树 robocopy 字节镜像；编辑器开着该地图时收尾 validate → diff → 有差异才 push，编辑器不在或没开该地图则跳过并以 0 退出；`--clean` 只清不装。收尾的 code-* 由工具自己指好宿主目录；自己手敲 code-* 必须加 `--workspace`，见下节「编辑器工程 ≠ 仓库检出」 |
| 宿主目录产物 → 仓库 | `lua tools/cli.lua sync` | 回灌 `eggy.json`、两份 API 存根、`data/` 整目录，落盘前 CRLF→LF 归一 |
| 重建技能包编辑器预设 | `lua tools/cli.lua ability-presets` | 按 `GameCfg.Ability` 的 key 查：预设还在就原地重刷锚点壳与属性，不在就复制官方模板重建并把新 key 回写 `GameCfg.lua`；要编辑器开着本图且在编辑态，多实例加 `--editor-instance <pid>`，`--dry-run` 只打印计划 |
| 修技能包预设的 Name 类型 | `lua tools/cli.lua ability-presets --fix-names` | 预设 Name 被 change-asset-value 写成编辑器侧 unicode 后（症状：每场 1 条 `expected String, got userdata`、该预设单位名空，见 issue #22）用 `create-unit-by-asset → editor-unit rename → SyncAssetFromUnit → 删场景单位` 四步把 Name 修回 Lua string，逐个报修前/修后类型；要编辑器开着本图且在编辑态，`--dry-run` 只打印计划；保原预设 id、不改 `GameCfg.lua`、**全程不存盘** |
| 单测 | `lua tests/run.lua` | luaunit，跑 `tests/*_test.lua` |
| 验收 / 回归 | `bash tools/acceptance/run_acceptance.sh` | Gherkin 车道，目前只有 `features/engineering/deploy-mirror.feature`；`acceptance4lua` 固定提交缓存在 `.toolcache/`，不需要 luarocks、不依赖 WSL，详见 `tools/acceptance/README.md` |
| Gherkin 示例值变异 | `bash tools/acceptance/mutate.sh` | 独立 runner-worker 车道，变异 feature 副本；`build/acceptance/mutation/report.json` 报告存活 / 杀死，故障失败，存活不设门槛 |
| 四项质量检查 | `bash tools/quality/run.sh` | Git Bash + Lua 5.4；固定缓存四个 4lua 工具及依赖，跑验收、luacov 单测、CRAP 和 DRY 分析；排除 `packages/`，结果在 `build/quality/`；仅报告存量质量问题，工具故障返回失败 |
| 独立变异检查 | `bash tools/quality/mutate.sh` | 在 `build/quality/mutation/` 的副本上测 `common/RateLimit.lua`，工作区源码不改；`build/quality/mutate.json` 记录存活变异，首期不设门槛 |

宿主目录默认 `C:\Users\<用户名>\Desktop\dev\eggy\LuaSource_钓鱼怎么这么危险啊喂！`，`EGGY_WORKSPACE` 可覆盖；宿主目录本身不是本仓库，只镜像、不往里放别的东西。

### 编辑器工程 ≠ 仓库检出

编辑器只认 `editor-cli code init` 绑定过的那个目录为工程，也就是 `CONTEXT.md` 的「宿主目录」条；仓库检出（主检出与 `.tower/worktrees/wt-N` 一样）不是工程——仓库根的 `eggy.json` 是 `sync` 回灌进来的 `isSEMap` 真源，不是工程绑定。所以在仓库检出里跑 `editor-cli code validate` / `code diff` / `code push` 一律返回 `CODE_BINDING_INVALID`（实测），带不带 `--strict`、编辑器开没开都一样，且主检出与每个 worktree 表现完全相同。这是「仓库检出 ≠ 编辑器工程」的架构事实，不是 worktree 特有，别照 worktree 特有去诊断。

在仓库检出里要跑 code-* 命令，只能显式指 `--workspace` 宿主目录，或先 `cd` 进宿主目录再跑（`editor-cli` 不在 PATH 上时用全路径，下面这个 `$USERPROFILE` 前缀在 Git Bash 里可直接抄）：

```bash
"$USERPROFILE/.eggitor/cli/editor-cli.exe" code validate --strict --json --workspace "<宿主目录>"
```

`lua tools/cli.lua deploy` 内部已经把 `--workspace` 指到宿主目录，不用手加；只有自己敲 code-* 命令时才要写。

### 完成判据

在仓库检出里改完代码，逐条跑，全部满足才算过：

| 命令 | 预期输出 |
|---|---|
| `lua tests/run.lua` | 统计行 `0 failures`（当前 `193 successes, 0 failures`），末行 `OK` |
| `bash tools/acceptance/run_acceptance.sh` | `N passed, 0 failed`（当前 `3 passed, 0 failed`），末行 `acceptance run OK` |
| `lua -e "assert(loadfile('<file>'))"`（每个改过的 `.lua` 跑一次） | 无输出、退出码 0；有语法错时抛 `loadfile` 的报错 |
| `"$USERPROFILE/.eggitor/cli/editor-cli.exe" code validate --strict --json --workspace "<宿主目录>"`（`deploy` 之后） | `{"ok":true,"data":{"valid":true,"is_se_map":true,"issues":[]},"meta":{"warnings":[]}}` |

- 语法检查用 `lua -e "assert(loadfile('<file>'))"`，不要用 `luac -p`：本机 `lua` 是 5.4.6、`luac` 是 5.5.0（实测），5.5 把 `for` 循环变量当 `const`，会对 `for line in handle:lines() do line = line:gsub(...)` 这种正常写法报假错 `attempt to assign to const variable`（现成例子：`tools/win_shell.lua:63`、`tests/run.lua:15` 的 `luac -p` 都报错，`lua` 5.4 都通过）。
- 最后那条 `code validate` 检查的是**宿主目录**里那份（`deploy` 镜像过去、收尾再 push 进地图的代码），不是仓库检出——它验的是「同步进编辑器的代码结构合法」，所以只在 `deploy` 之后才有意义，通不过说明镜像或同步那一步出了问题。

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

# 钓鱼怎么这么危险啊喂！

蛋仔派对状态同步（SE）地图的 Lua 源码。

## 按任务读取

- **探索代码**：先读 `docs/agents/domain.md`，按其中指引读取领域资料；ADR 放在 `docs/adr/`。
- **玩法与术语**：玩法与系统设计以 `design` 为准（指向仓库外 `eggitor/1_开发中/渔力全开` 的符号链接）；起名、读设计案或写玩家可见文案前查 `CONTEXT.md`。
- **技术方案**：先读 `docs/技术难点识别.md`；涉及策划矛盾时读 `docs/to-questionnaire-策划案内部矛盾.md`。
- **编码与审查**：编写或审查 SE 业务 Lua 前，读 `CODING_STANDARDS.md`；测试与收尾按下文执行。
- **技能包接入**：使用 `ability_system`、修改业务接缝或创建编辑器侧预设前，读 `docs/ability_system-vendor.md`。
- **Issue**：读写前看 `docs/agents/issue-tracker.md`；打 triage 标签前看 `docs/agents/triage-labels.md`。本项目使用 Gitea `lzxsvn:3000` 的 `qinyuanj/se-fish`，通过 `tea` 操作。

## 修改边界

- **管理器**：新增服务端管理器须加入 `server/main.lua` 的 `MgrMap`，由入口统一分发 `Start` / `OnPlayerAdded` / `OnPlayerRemoving` / `Update`。
- **界面**：由 `MgrGameUI` 管理；handler 放在 `client/ScreenHandlers/`，文件名与 EUI 节点同名，供 `MgrGameUI:GetScreen` 按节点名加载。
- **共享配置**：数值配置集中在 `common/GameCfg.lua`；技能配置在 `GameCfg.Ability`。
- **官方技能包只读**：`server/packages/`、`client/packages/`、`common/packages/` 是 `ability_system` 的 vendor。业务层经 `server/AbilityAPI.lua`、`client/AbilityAPI.lua` 接入，在 `server/Mgr/MgrAbility.lua` 装配。
- **生成内容**：`data/` 只读，修改须回编辑器重新导出，再用 `sync` 回灌；`unit_scripts/` 由引擎生成，不在本仓库管理。
- **验收文件**：Gherkin 放在 `features/<车道>/<名字>.feature`，以 `# language: zh-CN` 开头。

## 工具链

Lua 命令使用 **Lua 5.4**，执行前用 `lua -v` 核对；验收脚本可用 `ACCEPTANCE_LUA_BIN` 指定解释器。Lua 5.5 对循环变量重新赋值会报 `attempt to assign to const variable`，遇到此错误先检查版本。

- `lua tools/cli.lua deploy`：将三端代码字节镜像到宿主目录；编辑器开着本图时执行 validate → diff → 有差异才 push。
- `lua tools/cli.lua sync`：将宿主目录的 `eggy.json`、API 存根、`data/` 回灌仓库。
- 技能包预设命令见 `lua tools/cli.lua ability-presets --help`；验收脚本说明见 `tools/acceptance/README.md`。
- 质量与变异脚本位于 `tools/quality/`、`tools/acceptance/mutate.sh`，只出报告，不设门槛。

**宿主目录专用于镜像。** 默认 `C:\Users\<用户名>\Desktop\dev\eggy\LuaSource_钓鱼怎么这么危险啊喂！`，可用 `EGGY_WORKSPACE` 覆盖。

**编辑器工程 ≠ 仓库检出。** `eggy.json` 回灌不等于 `code init` 绑定；手动执行 code-* 时用 `--workspace` 指向已绑定的宿主目录，否则会报 `CODE_BINDING_INVALID`。`deploy` 已带此参数。Git Bash 验证命令：

```bash
"$USERPROFILE/.eggitor/cli/editor-cli.exe" code validate --strict --json --workspace "<宿主目录>"
```

## 测试纪律

- **试玩优先**：新增验证尽量只用编辑器 E2E，复杂功能以试玩证明可用；操作见 `eggy-lua` 的「试玩验收」。
- **先列失败方式**：确需单独测试某个系统时，先列出所有可能失败的方式，再写代码；代码写完后不补写单测。
- **局部开发、全量收尾**：开发期间只试玩当前改动的功能，收尾执行下面的全部检查。
- **可复现取证**：每次试玩保留可重跑的触发步骤（`input` 命令、探针文件）与对应证据（`log grep` 命中行、截图路径）。

## 完成判据

代码改动按顺序执行，全部通过才算完成：

| 检查 | 通过条件 |
|---|---|
| `lua tests/run.lua` | 统计行 `0 failures`，末行 `OK` |
| `bash tools/acceptance/run_acceptance.sh` | `N passed, 0 failed`，末行 `acceptance run OK` |
| 每个改过的 `.lua` 执行 `lua -e "assert(loadfile('<file>'))"` | 无输出、退出码 0 |
| `lua tools/cli.lua deploy` 后执行上面的 `code validate` | `ok=true`、`data.valid=true`、`data.is_se_map=true`，`data.issues` 与 `meta.warnings` 均为空 |
| validate 通过后全套试玩 | 每条验收现象都有取证产物；`log trace` 本轮窗口有效且无错误 |

## 产物归属

执行过程产物（调研全文、验证台账、验收记录、开发计划）贴进对应 issue 的评论；`docs/` 只留长期参考（术语、技术难点、vendor 说明、ADR）。`eggy-dev-plan` 默认的 `docs/plan/` 输出在本仓库改为 issue 评论。

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

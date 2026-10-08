# 钓鱼怎么这么危险啊喂！

蛋仔派对状态同步（SE）地图的 Lua 源码。

## 按任务读取

- **探索代码**：先读 `docs/agents/domain.md`，按其中指引读取领域资料；ADR 放在 `docs/adr/`。
- **玩法与术语**：玩法与系统设计以 `design` 为准（指向仓库外 `eggitor/1_开发中/渔力全开` 的符号链接）；起名、读设计案或写玩家可见文案前查 `CONTEXT.md`。
- **技术方案**：先读 `docs/技术难点识别.md`；涉及策划矛盾时读 `docs/to-questionnaire-策划案内部矛盾.md`。
- **编码与审查**：编写或审查 SE 业务 Lua 前，读 `CODING_STANDARDS.md`；测试与收尾按下文执行。
- **官方包接入**：使用 vendor 的官方包（`ability_system`、`attr_rule`、`modifier_system`、`official_ai_feature`）、修改业务接缝或创建编辑器侧预设前，读 `docs/packages-vendor.md`。
- **Issue**：读写前看 `docs/agents/issue-tracker.md`；打 triage 标签前看 `docs/agents/triage-labels.md`。本项目使用 Gitea `lzxsvn:3000` 的 `qinyuanj/se-fish`，通过 `tea` 操作。

## 修改边界

- **管理器**：新增服务端管理器须加入 `server/main.lua` 的 `MgrMap`，由入口统一分发 `Start` / `OnPlayerAdded` / `OnPlayerRemoving` / `Update`。
- **界面**：由 `MgrGameUI` 管理；handler 放在 `client/ScreenHandlers/`，文件名与 EUI 节点同名，供 `MgrGameUI:GetScreen` 按节点名加载。
- **共享配置**：数值配置集中在 `common/GameCfg.lua`；技能配置在 `GameCfg.Ability`。
- **官方包只读**：`server/packages/`、`client/packages/`、`common/packages/` 是官方包 vendor，整棵子树不参与部署或 `--clean`。说明写在 `docs/packages-vendor.md`；保留现有 README，目录内不再新增 README。技能业务经双端 `AbilityAPI.lua` 接入，在 `server/Mgr/MgrAbility.lua` 装配。
- **生成内容**：`data/` 只读，修改须回编辑器重新导出，再用 `sync` 回灌；`unit_scripts/` 由引擎生成，不在本仓库管理。
- **验收文件**：Gherkin 放在 `features/<车道>/<名字>.feature`，以 `# language: zh-CN` 开头。

## 工具链

Lua 命令使用 **Lua 5.4**，执行前用 `lua -v` 核对；验收脚本可用 `ACCEPTANCE_LUA_BIN` 指定解释器。Lua 5.5 对循环变量重新赋值会报 `attempt to assign to const variable`，遇到此错误先检查版本。

- `lua tools/cli.lua deploy`：将三端业务代码字节镜像到宿主目录，排除 `packages/`；编辑器开着本图时执行 validate → 只读 diff。有本地新增或不同文件时报告尚未同步并返回失败；为保留 packages，不执行全工作区 `code push`。
- `lua tools/cli.lua sync`：将宿主目录的 `eggy.json`、API 存根、`data/` 回灌仓库。
- 技能包预设命令见 `lua tools/cli.lua ability-presets --help`；验收脚本说明见 `tools/acceptance/README.md`。
- 质量与变异脚本位于 `tools/quality/`，只出报告，不设门槛。
- 单测按对象放入 `tests/gameplay/` 或 `tests/tooling/`；真实 CLI 子进程用例放入 `tests/tooling/slow/`。日常运行 `lua tests/run.lua fast`；分类运行 `lua tests/run.lua gameplay` 或 `lua tests/run.lua tooling`；完整运行 `lua tests/run.lua`（等价于 `full`）。

**宿主目录专用于镜像。** 默认 `C:\Users\<用户名>\Desktop\dev\eggy\LuaSource_钓鱼怎么这么危险啊喂！`，可用 `EGGY_WORKSPACE` 覆盖。

**编辑器工程 ≠ 仓库检出。** `eggy.json` 回灌不等于 `code init` 绑定；手动执行 code-* 时用 `--workspace` 指向已绑定的宿主目录，否则会报 `CODE_BINDING_INVALID`。`deploy` 已带此参数。Git Bash 验证命令：

```bash
"$USERPROFILE/.eggitor/cli/editor-cli.exe" code validate --strict --json --workspace "<宿主目录>"
```

## 测试纪律

- **试玩优先**：新增验证尽量只用编辑器 E2E，复杂功能以试玩证明可用；操作见 `eggy-lua` 的「试玩验收」。
- **先列失败方式**：确需单独测试某个系统时，先列出所有可能失败的方式，再写代码；代码写完后不补写单测。
- **局部开发、全量收尾**：开发期间用 `lua tests/run.lua fast` 或分类入口验证；业务功能仍按需试玩，收尾执行下面的全部检查。
- **可复现取证**：每次试玩保留可重跑的触发步骤（`input` 命令、探针文件）与对应证据（`log grep` 命中行、截图路径）。

## 完成判据

代码改动按顺序执行，全部通过才算完成：

| 检查 | 通过条件 |
|---|---|
| `lua tests/run.lua fast`（日常） | gameplay 全部用例与不启动真实 CLI 的 tooling 用例，统计行 `0 failures`，末行 `OK` |
| `lua tests/run.lua`（收尾，等价于 `full`） | 所有保留的单测（含回同步传输），统计行 `0 failures`，末行 `OK` |
| `bash tools/quality/run.sh` | 完整单测通过，生成覆盖率与静态质量报告 |
| `bash tools/acceptance/run_acceptance.sh`（有 feature 时） | `N passed, 0 failed`，末行 `acceptance run OK`；无 feature 时提示跳过且返回 0 |
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

# 蛋仔 SE 状态同步工程

工程根 `AGENTS.md` 的约定优先。确认 `eggy.json` 的 `isSEMap=true`；SE 场景由单位和资产构成，游戏运行时分 server / client，通用代码位于 common。CLI 的位置在 Windows 用户目录 `.eggitor/cli/editor-cli.exe`；WSL 调用 Windows 版本，命令参数以 `--help` 为准。

按任务使用本目录的顶层技能；不能调用时直接读已安装的 `<技能名>/SKILL.md`：

| 任务 | 技能 |
|---|---|
| 玩法设计 | `eggy-design` |
| 技术方案与拆任务 | `eggy-dev-plan` |
| Lua 开发、同步与试玩 | `eggy-se-lua-coding` |
| 调试报错 | `eggy-dev-debug` |
| 场景编辑、EUI 节点、资源发布与 AIGC 模型迁入 | `eggy-se-editor-cli` |
| 测试及回归 | `eggy-se-qa` |
| 静态性能优化 | `eggy-se-perf` |
| H5 编辑器插件 | `eggy-se-plugin-dev` |

查 API 先查工程根或编辑器用户目录下的 SE `EggyAPI.lua`，在线时用 `editor-cli api get <名字>` 核对签名，再用 `editor-cli docs search "<问题>" --docset manual` 查语义；查不到标 `[未查证]`。官方资源预设改查 `asset`。从仓库检出运行 code 命令时，先读 `eggy-se-lua-coding` 的绑定工程约定。
<!-- [teamai:rules:end] -->

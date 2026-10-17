# 钓鱼怎么这么危险啊喂！

蛋仔派对状态同步（SE）地图的 Lua 源码。

## 按任务读取

- **探索代码**：先读 `docs/agents/domain.md`，按其中指引读取领域资料；ADR 放在 `docs/adr/`。
- **玩法与术语**：玩法与系统设计以 `design` 为准（指向仓库外 `eggitor/1_开发中/渔力全开` 的符号链接）；起名、读设计案或写玩家可见文案前查 `GLOSSARY.md`。
- **技术方案**：先读 `docs/技术难点识别.md`；涉及策划矛盾时读 `docs/to-questionnaire-策划案内部矛盾.md`。
- **编码与审查**：编写或审查 SE 业务 Lua 前，读 `CODING_STANDARDS.md`。
- **开发工作流**：修改代码、运行测试、同步宿主或操作编辑器前，以及整理过程产物时，读 `docs/agents/workflow.md`（工具链、测试纪律、完成判据、产物归属）。
- **架构导航**：需要模块依赖全景、评估改动影响或从图上发起操作时，用 uml-viewer 打开 `docs/uml/se-fish.edn`；命令与约定见 `docs/agents/workflow.md` 工具链。
- **美术资产**：制作、导出或验收模型与动画资产前，读 `docs/agents/art-pipeline.md`（Blender / Meshy MCP 接入、导出约定与验收），尺寸口径见 `docs/adr/0004-fish-asset-scale.md`。
- **Issue**：读写前看 `docs/agents/issue-tracker.md`；打 triage 标签前看 `docs/agents/triage-labels.md`。本项目在 GitHub `qinyuanj/se-fish` 跟踪单据，通过 `gh` 操作。

## 修改边界

- **管理器**：新增服务端管理器须加入 `server/main.lua` 的 `MgrMap`，由入口统一分发 `Start` / `OnPlayerAdded` / `OnPlayerRemoving` / `Update`。
- **界面**：由 `MgrGameUI` 管理；handler 放在 `client/ScreenHandlers/`，文件名与 EUI 节点同名，供 `MgrGameUI:GetScreen` 按节点名加载。
- **共享配置**：数值配置集中在 `common/GameCfg.lua`；技能配置在 `GameCfg.Ability`。
- **生成内容**：`data/` 只读，修改须回编辑器重新导出，再用 `sync` 回灌；`unit_scripts/` 由引擎生成，不在本仓库管理。
- **验收文件**：Gherkin 放在 `features/<车道>/<名字>.feature`，以 `# language: zh-CN` 开头。

<!-- [teamai:culture:start] -->
<!-- DO NOT EDIT: This section is auto-managed by teamai -->

## Team Culture (teamai)

## Team: netease

# 团队协作约定

适用于所有任务。

1. **思考与回复使用中文。**
2. **产出物用中文。** 仓库文档、代码注释、commit 信息、PR 描述和写给 agent 的文件使用中文；代码标识符与文件名使用英文。
3. **专有名词与代码原样保留。** 工具名、skill 名、命令、路径和代码片段不翻译。Matt skills 保持上游英文原文。
4. **用户明确要求其他语言时以用户为准。** 引用英文原文时保留原文，并附中文说明。

<!-- [teamai:culture:end] -->

<!-- [teamai:recall-rules:start] -->
<!-- DO NOT EDIT: This section is auto-managed by teamai -->

## Team Knowledge Recall (teamai)

**Before** starting a task that involves code changes, debugging,
or design decisions, you **SHOULD** search the team knowledge base
(learnings, docs, skills, rules and the codebase wiki) by running:

```bash
teamai recall "<3-6 high-signal keywords from the task>"
```

unless one of these skip conditions applies:

1. **User already provided context** — the user referenced specific files,
   gave a solution, or said "the answer is in this directory/file".
2. **Local files have the answer** — the task info is directly available
   from the current workspace (e.g. fixing an obvious bug in the current file).
3. **Trivial/local change** — small modifications to known files (typo fix,
   parameter tweak, formatting) that need no additional knowledge.
4. **Task domain is outside team knowledge coverage** — the task is
   unrelated to this team's systems/workflows. `teamai recall --check "<keywords>"`
   answers `RELEVANT` or `NOT_RELEVANT` without reading anything.

Matching is lexical: give each domain term in every language the team
writes in, and keep names, identifiers, error codes and paths as they are.
Read the files recall returns for their full content. If its output contains
`Nothing was searched:`, show that line to the user instead of concluding the
team has no knowledge on the topic.

<!-- [teamai:recall-rules:end] -->

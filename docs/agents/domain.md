# 领域文档（Domain Docs）

工程类 skill 探索本仓库代码前该读什么。

## 探索前先读

- **`CONTEXT.md`**（仓库根）：领域术语表，给出每个玩法概念该说的词与该避开的说法。
- **`docs/adr/`**：读与你要动的区域相关的 ADR（本仓库目前还没有 ADR）。
- 本仓库另外两份工程文档也在 `docs/` 下：`技术难点识别.md`（已识别的技术难点）与 `to-questionnaire-策划案内部矛盾.md`（待策划确认的策划案矛盾）；写技术方案或怀疑策划案自相矛盾时先看（见工程根 `AGENTS.md` 的「文档」一节）。

不存在的文件**静默跳过**：不要报缺，也不要一上来就建议新建。`/domain-modeling`（经 `/grill-with-docs`、`/improve-codebase-architecture` 到达）会在术语或决策真正定下来时按需创建。

## 文件布局

单 context（本仓库就是这个布局）：

```
/
├── CONTEXT.md
├── docs/adr/
│   └── 0001-....md
└── client/  common/  server/     ← 三端代码（官方强制的 SE 工作区根）
```

出现 `CONTEXT-MAP.md` 时才是多 context：根放系统级决策，`<context>/CONTEXT.md` 与 `<context>/docs/adr/` 放各自的。

## 用术语表的词

输出里提到领域概念时（issue 标题、重构提案、假设、测试名），用 `CONTEXT.md` 定义的说法，不要漂到术语表明确避开的同义词。

需要用的概念术语表里没有，是个信号：要么你在发明项目不用的说法（回头想想），要么是真空缺（记下来交给 `/domain-modeling`）。

## ADR 冲突要摆到台面上

输出与既有 ADR 冲突时，明说，不默默覆盖：

> _与 ADR-0007（……）冲突，但值得重开，因为……_

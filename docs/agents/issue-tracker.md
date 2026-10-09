# Issue tracker：GitHub

本仓库的开发任务、缺陷、验收台账与过程产物统一在 GitHub `TLOBillyQ/se-fish` 跟踪，使用 GitHub CLI `gh`。执行时显式指定 `-R TLOBillyQ/se-fish`，避免按本地 remote 推断到其他仓库。

## 操作

- **核对身份**：`gh api user --jq .login`；本项目使用 `TLOBillyQ`。
- **建 issue**：`gh issue create -R TLOBillyQ/se-fish --title "标题" --body-file "<正文.md>"`。
- **读 issue（含评论）**：`gh issue view <编号> -R TLOBillyQ/se-fish --comments`。
- **列 issue**：`gh issue list -R TLOBillyQ/se-fish --state all --label ready-for-agent`。
- **评论**：`gh issue comment <编号> -R TLOBillyQ/se-fish --body-file "<正文.md>"`。
- **打 / 摘标签**：`gh issue edit <编号> -R TLOBillyQ/se-fish --add-label "..." --remove-label "..."`。
- **指派 / 取消指派**：`gh issue edit <编号> -R TLOBillyQ/se-fish --add-assignee <用户名> --remove-assignee <用户名>`。
- **关闭**：先评论验收结果，再执行 `gh issue close <编号> -R TLOBillyQ/se-fish --reason completed`；不再计划处理用 `--reason "not planned"`。
- **PR**：用 `gh pr`；GitHub PR 与 issue 共用编号空间，读取前确认对象类型。

多行正文写入 UTF-8 临时文件，用 `--body-file` 提交；提交后回读确认正文、标签和状态。过程产物贴到对应 issue 评论，临时正文文件留在系统临时目录。

## 跟踪与迁移

skill 要求“发布到 issue tracker”时，在 `TLOBillyQ/se-fish` 建 GitHub issue；默认打 `ready-for-agent`，除非另有指示。标签含义见 `triage-labels.md`，使用前查询实际标签。

skill 要求“取出相关 ticket”时，用上面的 `gh issue view --comments`。

迁移旧单据时，先在 GitHub 建单并回读，再给旧单据评论 GitHub 链接并关闭。迁移关闭不表示缺陷已修复。旧平台编号与 GitHub 编号不能直接互换；通过标题和内容核对对应关系，历史引用注明原平台。

## 依赖与 Wayfinding

- **地图**：一张 issue，正文放 Notes / Decisions-so-far / Fog，使用 `wayfinder:map` 标签。
- **子 ticket**：正文顶部写 `Part of #<地图编号>`，使用 `wayfinder:<类型>` 标签（`research` / `prototype` / `grilling` / `task`）；被认领后指派给驱动的开发者。
- **阻塞**：在 GitHub 中记录依赖。使用原生关系前，核对当前 API 与仓库权限，通过 `gh api` 操作；不可用时在正文顶部写 `Blocked by #<编号>`。所有 blocker 关闭后才可推进。
- **frontier**：读取地图及其子 ticket，排除仍被阻塞或已有 assignee 的项，按地图顺序取第一个。
- **认领**：`gh issue edit <编号> -R TLOBillyQ/se-fish --add-assignee @me`，作为会话首次写操作。
- **结案**：先评论答案及验收结果，再关闭；在地图正文的 Decisions-so-far 中追加结论。

使用 `wayfinder:*` 标签前先查询仓库标签；缺失时按任务需要创建。

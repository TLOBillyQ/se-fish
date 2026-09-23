# Issue tracker：Gitea（自建）

本仓库的 issue 与规格住在自建 Gitea 实例 `http://lzxsvn:3000` 的 `qinyuanj/se-fish` 仓库里。它不是 GitHub 也不是 GitLab，用 Gitea 官方 CLI `tea` 做日常操作；`tea` 没覆盖的能力（原生阻塞关系）走 REST API。

## 环境

- `tea` 0.15.1 已安装，已配置登录项 `qinyuanj`（`tea login list` 可查）。
- 在 clone 里跑 `tea` 会自己推断仓库；不在 clone 里跑就加 `-r qinyuanj/se-fish`。
- REST API 用 `$GITEA_URL` + `$GITEA_TOKEN`（已在本机环境变量里）。**token 不写进仓库**，脚本里只读环境变量。

## 约定

- **建 issue**：`tea issues create -r qinyuanj/se-fish -t "标题" -d "正文"`（多行正文用 heredoc）。`-L` 传标签，Gitea 的标签可传名字或 id。
- **读 issue（含评论）**：`tea issues -r qinyuanj/se-fish <index> --comments`。
- **列 issue**：`tea issues list -r qinyuanj/se-fish --state all --labels ready-for-agent`。
- **评论**：`tea comments -r qinyuanj/se-fish <index> "正文"`（等价于 `tea comments add`）。
- **贴长正文（过程产物）**：调研全文、验证台账、验收记录作为评论贴到对应 issue，不落进仓库。正文超过几 KB 时走 REST：`tea api -X POST 'repos/qinyuanj/se-fish/issues/<index>/comments' -F body=@正文.md`（命令行长度与引号都不再是问题）；回读校验用 `tea api 'repos/qinyuanj/se-fish/issues/comments/<id>' -o out.json`，`jq -r .body` 与原文比对。注意 `tea api` 的 endpoint **不要以 `/` 开头**（`/repos/...` 会被拼成 `/api/v1//repos/...` 而 404）。
- **打 / 摘标签**：`tea issues edit -r qinyuanj/se-fish <index> --add-labels "..." --remove-labels "..."`。
- **指派 / 取消指派**：`tea issues edit -r qinyuanj/se-fish <index> --add-assignees <用户名>`。
- **关闭**：`tea issues close -r qinyuanj/se-fish <index>`；要带结案说明就先评论再关闭。
- **PR**：Gitea 的 PR 与 issue 共用编号空间，`tea pulls ...`；`#42` 指哪个面要看清 skill 的语境。

## 阻塞关系（原生，优先用）

Gitea 1.27 有原生依赖关系，UI 可见：

- **加阻塞**（`<issue>` 被 `<blocker>` 阻塞）：
  `POST /api/v1/repos/qinyuanj/se-fish/issues/<issue>/dependencies`
  正文**必须**给全 `{"owner":"qinyuanj","repo":"se-fish","index":<blocker>}`——只给 `index` 会 404（`repository does not exist [id: 0, uid: 0, owner_name: , name: ]`，2026-09-21 在 1.27.3 实测）。
- **读「被谁阻塞」**：`GET .../issues/<issue>/dependencies`。
- **读「阻塞了谁」**：`GET .../issues/<issue>/blocks`。

一张 ticket 在所有 blocker 关闭后才是可动的。

## skill 说「发布到 issue tracker」时

在 `qinyuanj/se-fish` 建 Gitea issue；默认打 `ready-for-agent`，除非另有指示。

## skill 说「取出相关 ticket」时

`tea issues -r qinyuanj/se-fish <index> --comments`。

## Wayfinding 操作（`/wayfinder` 用）

**地图**是一张 issue，**子 ticket** 是它的子 issue。

- **地图**：一张打 `wayfinder:map` 标签的 issue，正文放 Notes / Decisions-so-far / Fog。
- **子 ticket**：正文顶部写 `Part of #<map>`，标签 `wayfinder:<type>`（`research` / `prototype` / `grilling` / `task`）；被认领后指派给驱动的开发者。
- **阻塞**：用上面的原生依赖关系，不用纯文本行。原生关系不可用时（或跨外网同步场景）退回正文顶部一行 `Blocked by: #<n>, #<n>`。
- **frontier 查询**：列出地图的子 issue，滤掉还有未关闭 blocker 的、以及已有 assignee 的；按地图顺序取第一个。
- **认领**：`tea issues edit -r qinyuanj/se-fish <n> --add-assignees @me`——会话的第一次写操作。
- **结案**：先评论答案，再 `close`，然后把上下文指针追加到地图的 Decisions-so-far 一节。

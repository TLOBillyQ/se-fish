# Triage 标签

这些 skill 用五个标准 triage 角色说话。本文件把角色映射到本仓库 issue tracker 里实际的标签串。

| skill 里的角色  | 本仓库的标签串     | 含义                                |
| --------------- | ------------------ | ----------------------------------- |
| `needs-triage`  | `needs-triage`     | 待维护者评估                        |
| `needs-info`    | `needs-info`       | 等报告者补充信息                    |
| `ready-for-agent` | `ready-for-agent` | 规格完备，可以交给 AFK 的 agent     |
| `ready-for-human` | `ready-for-human` | 需要人来实现                        |
| `wontfix`       | `wontfix`          | 不会处理                            |

skill 提到某个角色时（例如「打上 AFK-ready 的 triage 标签」），用右列的字符串。

现状（2026-09-21）：五个标签都已建在 `qinyuanj/se-fish`——`ready-for-agent` = 124、`needs-triage` = 125、`needs-info` = 126、`ready-for-human` = 127、`wontfix` = 128（`tea labels list -r qinyuanj/se-fish` 可复核）。REST API 建 issue 时标签传 id 最稳，传名字也行；`tea issues edit --add-labels/--remove-labels` 传名字可用。

需要人（或无法在被操作目录内运行的会话）执行的活儿挂 `ready-for-human`，例：#2 迁移工作区。

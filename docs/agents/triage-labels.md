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

标签以 GitHub `TLOBillyQ/se-fish` 为准，用 `gh label list -R TLOBillyQ/se-fish --limit 100` 查询。`gh issue create --label` 与 `gh issue edit --add-label/--remove-label` 传标签名。需要的标签不存在时，用 `gh label create <标签名> -R TLOBillyQ/se-fish --description "<含义>" --color "<六位颜色>"` 创建后再使用。

需要人（或无法在被操作目录内运行的会话）执行的活儿挂 `ready-for-human`，例如需要人工操作的工作区迁移。

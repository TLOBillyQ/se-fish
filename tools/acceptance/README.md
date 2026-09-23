# 钓鱼图的 acceptance 流水线

Gherkin 验收，跑在本机 Lua 5.4 + 内网 Gitea 的 `acceptance4lua`（纯 Lua）之上。feature 用中文写，
`features/` 下的文件必须以 `# language: zh-CN` 开头（框架的强制规则）。

## 一条命令

```sh
bash tools/acceptance/run_acceptance.sh      # parse → dry-check（advisory）→ generate → run
```

在仓库根执行（脚本自己 cd 到根）。全绿打印 `acceptance run OK` 并以 0 退出；不绿时逐条打印
`not ok - <场景>`，随后附失败步骤的原话（部署类步骤失败时带那次 deploy 的完整输出）。

不需要 luarocks，也不依赖 WSL：`lua` 取 PATH 里的（本机 5.4.6，命令名就是 `lua`，不是 `lua5.4`），
`acceptance4lua` 由首次运行自己 clone。

## 布局

- `features/engineering/deploy-mirror.feature` —— 目前唯一的车道：在 `tmp/` 的临时工作区验
  「部署把三端镜像进去」与「部署不碰非自有文件」。不启动对局；断言用的是钓鱼图的真实文件路径。
- `tools/acceptance/steps.lua` —— 步骤聚合与分发。acceptance4lua 按步骤文本精确查 handler，
  所以这里存的是 Lua pattern，把代入例子值之后的句子路由到实现；只差一个数值的同类句子共用一个 handler。
- `tools/acceptance/steps_deploy.lua` —— deploy-mirror 车道的 handler。只查仓库与临时工作区；
  所有命令走 cmd（Windows 版 Lua 的 `os.execute` 就是 cmd.exe，`rm`/`mkdir`/`find` 那套用不了），
  路径与引用交给 `tools/win_shell`。
- `tools/acceptance/bootstrap.lua` —— 把 `acceptance4lua` 放到 `package.path` 上；树不在时先
  `git clone` 到 `.toolcache/acceptance4lua`（上游是纯 Lua，clone 下来直接把 `src/` 拼进 LUA_PATH，
  不走 luarocks）。树的位置可用 `SE_FISH_LUA_TOOLS` 覆盖；固定提交 `8dd107144a7635596d75e4fccfce35121dc67570`，缓存就位后离线运行，版本不符直接报错。
- `tools/acceptance/cli/*.lua` —— `acceptance4lua.cli.*` 的宿主 wrapper；同目录的
  `gherkin-parser` / `ir-dry-checker` / `entrypoint_generator` 是 bash 入口，按路径调用即可
  （`entrypoint_generator` 把生成的 spec 绑到 `tools.acceptance.steps`）。
- `build/acceptance/`（IR、dry 报告、生成的 spec）与 `.toolcache/`：生成物，已在 `.gitignore` 里。

## 约定

- 每次运行先清 `build/acceptance/generated/` 再生成：改过 feature 名字不会留下旧 stem 继续跑。
- `ir-dry-checker` 只出报告；单独跑验收时工具错误不拦流水线，`tools/quality/run.sh` 设置 `ACCEPTANCE_STRICT_TOOLS=1`，工具错误会失败。
- 临时工作区与那次 deploy 的输出留在 `tmp/deploy-mirror-workspace`、`tmp/deploy-mirror.out`
  （都在 `.gitignore` 里），失败时直接翻；部署步骤用的伪 home 是 `tmp/deploy-mirror-home`
  （只需它在盘上不存在，不建目录）。
- 车道里没有真编辑器：工作区预置的 `eggy.json` 是伪造的绑定，部署步骤把 `USERPROFILE` 指到空的
  临时 home，让编辑器收尾按「找不到 editor-cli.exe」跳过，结果不随本机装没装 editor-cli 变化。
  带编辑器的收尾（validate → diff → push）由真机跑 `lua tools/cli.lua deploy` 覆盖，不在这条车道里。
## 示例值变异（独立入口）

```sh
bash tools/acceptance/mutate.sh
```

入口先跑原版验收作基线，再把 `deploy-mirror.feature` 复制到 `build/acceptance/mutation/`；固定版本
`acceptance4lua` 的 mutator 以 `full` 模式改变 Examples 单元格，由单进程 runner-worker 逐条执行
生成的 spec。原 feature、步骤实现和业务源码都不会被改写；上游仅可能给产物目录中的副本写入验证标记。
三个变异分别覆盖部署树路径、预置路径与保留路径，报告列出每条变异对应的场景、原值、新值和
`killed` / `survived` / `error`。结构化结果在 `build/acceptance/mutation/report.json`，基线输出在
`baseline.txt`，均被 Git 忽略。存活变异只报告、不作为退出门槛；基线失败、mutator / worker 故障、
零变异或报告写入失败均返回非零。日常快速验收仍只需运行 `run_acceptance.sh`。

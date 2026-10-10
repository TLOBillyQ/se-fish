# 质量工具

项目使用原生 Windows、PowerShell 7、Lua 5.4 与现有 LuaUnit。终端与 viewer 刷新共用 `project.json`：分析 `client/`、`common/`、`server/` 的业务 Lua，排除官方 `packages/` 与 `server/_trigger/`；CRAP 与 DRY 都使用这一范围。

## 安装与校验

在仓库根运行：

```powershell
.\tools\quality\install.ps1
.\tools\quality\project.ps1 doctor
```

本地工具来源与固定提交以 `project.json` 为准，默认来源为相邻的 `uml-viewer`、`crapper`、`mutator` 仓库。安装器生成根目录 `uml` 与 `uml.ps1`；业务仓库不手工修改这些启动入口。工具 checkout 更新与 Python 包安装是两个步骤，`doctor` 核对实际提交、未提交差异、解释器、依赖与实际导入路径。已有 Python venv 可用于安装；新环境可通过安装入口的 `-Python` 指定可执行文件。

## 日常命令

```powershell
# 完整 LuaUnit → 本轮 LCOV → DRY → 全树 CRAP
.\tools\quality\project.ps1 quality

# 仅生成完整测试的覆盖率
.\tools\quality\project.ps1 coverage

# 对选定业务文件执行差分 mutation
.\tools\quality\project.ps1 mutation common/RateLimit.lua --max-workers 12

# 仅显式全量操作重新测试该文件的全部变异
.\tools\quality\project.ps1 mutation --mutate-all common/RateLimit.lua --max-workers 12

# viewer / companion 使用同一公开入口：完整 LuaUnit → 本轮 LCOV → 全树 CRAP
.\uml.ps1 crap

# 生成架构图；已有 viewer 自动重载
.\uml.ps1 ir
```

完整测试失败时停止覆盖率发布，旧 LCOV 失效；转换失败同样停止后续指标。任何 CRAP 刷新都替换完整业务树快照，选中单模块也保持其他模块的指标。DRY 保留重复代码候选报告，不设质量门槛。

安装器登记的 `viewer-seam.patch` 使 `uml.ps1 crap` 在存在 `tools/quality/project.json` 时优先执行项目 `coverage` → `crap`，不进入通用 crapper 的测试发现；Unix `./uml crap` 经同一 PowerShell 分发器执行。该入口会忽略单类或组件目标并完整替换快照。成功后 companion 继续执行 `uml.ps1 ir` 并发送 `:display`；覆盖率、转换或 CRAP 失败时立即停止，不生成 IR、不发送成功展示通知。`uml.ps1 mutate <文件> [参数]` 同样转交项目 mutation 接缝并保留参数及退出码。手工复验可以运行 `.\uml.ps1 crap && .\uml.ps1 ir`。

运行中的 companion 使用启动时取得的规则；新规则需通过 `:quit-for-restart` → 等待旧 JVM 自然退出 → `.\uml.ps1 --restart` 协议重启后载入。分发脚本每次命令执行时读取，因此旧 companion 执行 `.\uml.ps1 crap` 也立即使用修复后的质量入口。GUI 复验代表模块为 `client.LocalReelIn`。

项目命令 `mutation` 是正式名称，`mutate` 保留为兼容别名；UML 命令仍使用 `uml.ps1 mutate`。CRAP 与 mutation 刷新均先运行完整覆盖率，耗时包含完整测试，不应按秒完成来判断成功。

mutation 的存活与未覆盖结果表示测试缺口，保留有效快照。差分流程不会因这些结果自动重跑或转为全量。基线失败与基础设施失败须按真实输出处理，不作为有效新指标。无函数定义的配置或转发模块可能没有 mutation 快照；工具当前不测试模块顶层语句。

## 可重跑验收

代表文件必须显式指定；该命令包含一次选定文件的全量 mutation：

```powershell
.\tools\quality\verify.ps1 -File common/RateLimit.lua
```

入口串行执行环境校验、完整质量流程、两次差分、选定文件显式全量、公开命令失败路径测试与 IR 生成，并核对代表源码哈希。核对第二次差分输出中的 `Mutation function:` 与 `Mutation run:`：`executed` 是本轮实际执行数，`reused` 是函数 digest 与 mutation ID 均一致而继承的历史 killed 数，`uncovered` 是覆盖率缺口，`excluded` 是行筛选排除数。加 `--verbose` 可查看每个 mutation 的 `action`、`reason`、`previous` 与 `result`；历史 survived 会重新执行，源码 digest 或 mutation ID 改变以及显式 `--mutate-all` 都不会复用。不能只依据快照修改时间判断复用。自动命令验收与真实 GUI 验收分别记录。

真实 viewer 验收步骤：

1. 使用 `.\uml.ps1` 首次启动，等待 companion 的 `:display` 被消费。确认顶层为 `client`、`common`、`server`，并查看真实窗口。
2. 打开代表模块卡片，对照 EDN 检查 CRAP、覆盖率、函数名与 mutation 数量。缺少任一指标仍显示红色；红色本身不作为工具失败。
3. 右键刷新 CRAP，核对 companion 实际执行项目入口，完整 CRAP 快照仍含其他模块，IR 与窗口自动更新。
4. 右键差分 mutation，再对同一明确选定文件执行右键全量 mutation。核对邮件队列按顺序消费、命令使用相同配置、结果与窗口更新。
5. 在窗口中设置视图状态，通过 companion 写入 `:quit-for-restart`，等待旧 JVM 自然退出，再执行 `.\uml.ps1 --restart`；核对 companion 身份、恢复的视图与后续邮件处理。session 保存实际图的绝对路径；旧 session 缺少路径时读取项目 `policy.edn` 的 `:out`，同图 `:display` 保留当前视图。

每步保留触发命令、日志、快照关联结果和窗口截图。只有 CLI 或 fixture 通过时，GUI 项仍标为未验证。保持 policy 中已有用户设置，IR 使用生成器更新。

## 产物归属

`.metrics/crap.edn`、`.metrics/mutate/*.edn` 与 `docs/uml/se-fish.edn` 按项目约定纳入版本管理。`build/`、`target/`、`.toolcache/`、`.uml-viewer/` 为本地报告、覆盖率、worker、工具检出与会话产物。验收过程证据按 issue-tracker 工作流记录，发布动作遵循已有授权。

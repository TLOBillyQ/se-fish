# 质量工具

项目使用原生 Windows、PowerShell 7、Lua 5.4 与现有 LuaUnit。终端与 viewer 刷新共用 `project.json`：分析 `client/`、`common/`、`server/` 的业务 Lua，排除官方 `packages/` 与 `server/_trigger/`；CRAP 与 DRY 都使用这一范围。

## 安装与校验

在仓库根运行：

```powershell
.\tools\quality\install.ps1
.\tools\quality\project.ps1 doctor
```

本地工具来源与固定提交以 `project.json` 为准，默认来源为相邻的 `uml-viewer`、`crapper`、`mutator` 仓库。独立检出位于其他目录时，先将配置的 `tools.*.source` 登记为从检出根到这些固定来源的相对路径；不复制已有缓存。安装器使用 viewer 上游公开的 `scripts/get-uml-viewer.ps1`，按固定 SHA 执行 `git init → git fetch → git checkout`，生成根目录 `uml` 与 `uml.ps1`；业务仓库不手工修改这些启动入口。工具 checkout 更新与 Python 包安装是两个步骤，`doctor` 核对实际提交、未提交差异、解释器、依赖与实际导入路径。已有 Python venv 可用于安装；新环境可通过安装入口的 `-Python` 指定可执行文件。

已有工具 checkout 先按当前 `project.json` 精确预检：任何未提交 diff 都必须等于仍需保留的登记补丁；历史 viewer 私有补丁、其他源码改动、暂存或未跟踪内容都会明确失败并保留原字节，安装器不执行 `git restore`、不覆盖用户未保存改动。失败后把对应 `.uml-viewer/<工具>` checkout 移到备份目录再重跑安装；`.uml-viewer` 下 session、policy、proposals、mailboxes 与项目 `.metrics/` 数据不属于工具 checkout，继续保留。`-UpgradeFrom` 已停用，历史自动撤销入口不再提供。

完整安装同时准备 `project.json` 的 `lua_tools`：LuaCov、dry4lua、luacheck 和 acceptance4lua（DRY 使用其 JSON 模块）。每项登记 URL、固定提交与运行模块；沿用 acceptance bootstrap 的现有固定版本。`doctor` 检查这些 checkout 的提交、origin、运行源码和 Lua 模块加载，不借用全局 Lua 模块或其他检出的缓存。缺失依赖可重跑安装；版本、来源或源码不符时先将提示中的损坏缓存移走，再运行安装器，安装不会覆盖未知内容。`-InstallOnly` 仅准备 viewer/crapper/mutator checkout，不构成完整质量环境。

acceptance4lua 的 Gherkin 解析、生成与验收仍使用 `tools/acceptance/` 独立入口及按需 bootstrap；质量安装不会替代该用途。`doctor` 只读取 bootstrap 公开 pins，拒绝 quality 与 acceptance 固定提交漂移，不触发 acceptance 安装。旧 `deps.sh` 不在正式安装或 quality 调用链中，不接入旧 crap4lua/mutate4lua。

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

viewer 上游固定版本通过标准 quality dispatch 执行项目入口：`uml.ps1 crap` 完整执行 `coverage` → `crap`，忽略单类或组件目标并完整替换快照；成功率/覆盖率失败立即停止。`uml.ps1 mutate <文件> [参数]` 转交项目 mutation 接缝并保留参数及退出码。手工复验可以运行 `.\uml.ps1 crap && .\uml.ps1 ir`。

运行中的 companion 使用启动时取得的规则；新规则需通过 `:quit-for-restart` → 等待旧 JVM 自然退出 → `.\uml.ps1 --restart` 协议重启后载入。分发脚本每次命令执行时读取，因此旧 companion 执行 `.\uml.ps1 crap` 也立即使用修复后的质量入口。GUI 复验代表模块为 `client.LocalReelIn`。

项目命令 `mutation` 是正式名称，`mutate` 保留为兼容别名；UML 命令仍使用 `uml.ps1 mutate`。CRAP 与 mutation 刷新均先运行完整覆盖率，耗时包含完整测试，不应按秒完成来判断成功。

mutation 从覆盖率开始核对目标源码；worker 仅修改副本。运行期间原始文件被保存或删除时停止发布，保留外部编辑和上一份有效 mutation 快照；失败清理不会写回旧源码。下游入口同样在写快照前检查源码。旧版 `target/mutator-backup/` 没有工具最后写入字节的所有权记录，发现备份时停止运行并保留源码与备份，需人工核对后处理。

mutation 的存活与未覆盖结果表示测试缺口，保留有效快照。差分流程不会因这些结果自动重跑或转为全量。基线失败与基础设施失败须按真实输出处理，不作为有效新指标。无函数定义的配置或转发模块可能没有 mutation 快照；工具当前不测试模块顶层语句。

质量请求共用仓库 `target/quality.lock` 的操作系统锁。公开 PowerShell、Python 脚本、companion 分发及安装器使用同一锁；同仓库忙时明确拒绝并返回 1，进程异常退出自动释放，另一仓库独立运行。锁文件保持稳定，不通过删除文件解锁。安装器在工具替换完成后释放锁，再调用自行持锁的 doctor；启动解释器时若遇到安装切换可失败，但不得在未取得锁时消费统计或发布指标。

`refresh-crap` 在一次持锁请求内执行完整 coverage → 全树 CRAP，供 viewer 使用。mutation 在同一请求内直接复用覆盖率流程，不启动另一个抢锁的项目请求。所有质量命令及 mutation-report/doctor 的一致性读取均受保护；IR 生成和 viewer 邮件/会话属于独立工具边界。

mutation 发布先校验完整暂存树，准备新文件，再将受影响旧路径可逆移入事务备份；替换、过期路径删除或最终验证失败时恢复发布前快照。成功后清理备份。若回滚自身失败，报出并保留 `target/mutation-publication/publish-*` 恢复材料；该目录有遗留材料时停止后续 mutation，避免覆盖证据。此保护针对质量请求与可控发布失败，不能保证任意外部进程持续禁止恢复写入时仍能自动恢复。

## 可重跑验收

空缓存安装回归使用公开入口；准备独立检出、登记兄弟工具来源后，首次执行 `install.ps1`，再从开发检出运行 `python -I tests/tooling/slow/quality_install_test.py <独立检出绝对路径>`。用例依次检查缺失/错误来源/污染诊断、真实完整 quality 和重复安装；只临时修改独立缓存，并恢复故障注入。完整 quality 日志保留在独立检出的 `build/quality/install-acceptance-quality.log`。该 suite 被 unittest discover 导入时只跳过，不解析发现参数、不设置主检出为目标；只有显式脚本入口接受另一个独立检出的绝对路径。

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

# 质量工具

项目使用原生 Windows、PowerShell 7、Lua 5.4 与原生 Busted。终端与 viewer 刷新共用 `project.json`：分析 `client/`、`common/`、`server/` 的业务 Lua，排除官方 `packages/` 与 `server/_trigger/`；CRAP 与 DRY 都使用这一范围。

## 解释器与测试命令契约

Lua 解释器与测试命令是两条独立契约（#81）。`project.json` 的 `lua.executable`（含 `lua.version` 版本断言）用于 `lua -v` 校验、LCOV/DRY 报告脚本和项目内 Lua 子命令；`commands.coverage` 与 `commands.mutation_test` 是整体不透明的测试 argv，切换后首项是 Busted 启动器（Windows 上写 `busted.bat`：Python 的 `CreateProcess` 只补 `.exe`，裸 `busted` 解析不到 LuaRocks 的 `.bat` 垫片）——质量入口不得从测试 argv 的首项推导解释器。

## Busted 固定依赖与原生入口

`project.json` 的 `busted` 段登记固定依赖（#81）：Busted 2.3.0（rock `2.3.0-1`）、Luassert `1.9.0-1`、LuaCov `0.17.0-1`，并记录 Busted/Luassert 上游来源 commit 供核验。其中 `busted.sources` 是**声明性登记**（`busted`/`luassert` 的上游 URL 与 commit），当前没有运行代码消费它——安装走 LuaRocks 的 `busted.rocks` 清单、`doctor` 只核对命令版本与 rock 安装状态；保留它是为了把「这些依赖固定在哪次上游提交」写进版本管理，供将来改用源码 checkout 安装或加校验时直接取用。安装器经 LuaRocks 按 `busted.rocks` 清单安装固定版本（已安装则跳过，可重跑）；`doctor` 核对 busted 命令版本与 rocks 安装状态，失败信息区分解释器缺失、Busted 命令缺失、版本不符与 rock 未安装。LuaCov 的运行时来源仍是 `lua_tools.luacov` 的固定 checkout（与 rock 同一上游 commit），质量覆盖率流程不消费全局 rock。

LCOV reporter 的固定实现是 `tools/quality/report_lcov.lua`：基于 `luacov.runner` / `ReporterBase` 写出 `SF:`（反斜杠归一为正斜杠）、`DA:`、`LF:`、`LH:`、`end_of_record`。若未来替换为共享 reporter，只能替换内部生成器，必须保持 `paths.lcov` 输出路径、LCOV 字段、路径归一化与 `report_lcov.lua <stats> <output>` 参数契约；CRAP/mutation 只消费该文件，不感知 reporter 实现。

原生 Busted 入口由根目录 `.busted` 定义车道：`fast`（default，日常）与 `full`（追加 `tests/native/slow` 的 slow Lua）；探针（`tests/probes`）、共享夹具（`tests/support`）与 Python 回归不进入发现范围。共享初始化 `tests/native/helper.lua` 通过 `tests/support/baseline.lua` 建立 Debug/AcceptanceSlot 基线，并按案例快照恢复共享配置，案例失败不泄漏。

## 覆盖率

```powershell
# 完整套件发现的案例清单（口径是「案例」；Python 回归不在其中）
busted --run=full --list

# 日常车道
busted --run=fast

# 完整套件覆盖率（单段，直接写仓库根 luacov.stats.out）
busted --run=full --coverage
```

完整套件用 `busted --run=full --coverage` 单段统计，LuaCov 按默认 `statsfile` 写仓库根 `luacov.stats.out`；`run_coverage` 成功后整份替换成 `paths.stats` 快照并转 LCOV，失败时不发布 LCOV 并保留上一份统计快照供诊断。`project.json` 的 `commands.coverage`/`commands.mutation_test` 因此直接指向 Busted，argv 仍整体不透明（解释器契约不变）。Busted 不带 `--coverage` 不写任何文件。

起 lua 子进程的回归统一从 `tests/support/interpreter.lua` 取解释器：Lua 把它记在 arg 的负索引，但下标随启动选项前移——`lua s.lua` 是 `arg[-1]`，`lua -lluacov s.lua` 是 `arg[-2]`，Busted 启动形状 `lua -e 语句 busted` 是 `arg[-3]`（此时 `arg[-1]` 是 `-e` 的语句原文）。写死 `arg[-1]` 会让这类回归只在 `--coverage` 下整片失败，命令行里的"解释器"变成一段 Lua 源码，cmd 报「找不到路径」。



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
# 完整 Busted → 本轮 LCOV → DRY → 全树 CRAP
.\tools\quality\project.ps1 quality

# 仅生成完整测试的覆盖率
.\tools\quality\project.ps1 coverage

# 对选定业务文件执行差分 mutation
.\tools\quality\project.ps1 mutation common/RateLimit.lua --max-workers 12

# 仅显式全量操作重新测试该文件的全部变异
.\tools\quality\project.ps1 mutation --mutate-all common/RateLimit.lua --max-workers 12

# viewer / companion 使用同一公开入口：完整 Busted → 本轮 LCOV → 全树 CRAP
.\uml.ps1 crap

# 生成架构图；已有 viewer 自动重载
.\uml.ps1 ir
```

完整测试失败时停止覆盖率发布，旧 LCOV 失效；转换失败同样停止后续指标。任何 CRAP 刷新都替换完整业务树快照，选中单模块也保持其他模块的指标。DRY 保留重复代码候选报告，不设质量门槛。

标准分发映射声明在仓库根 `uml-quality.json`（`version: 1`，`operations.crap` / `operations.mutate`），固定版本的 viewer 与 companion 每次执行命令时读取，无需 viewer 私有补丁（crapper/mutator 仍有各自未上游化的保护，补丁照常登记）。图上入口因此落到项目公开命令：`uml.ps1 crap` → `project.ps1 refresh-crap`（`forwardArgs: none`、`scope: whole-tree`，有效结果退出码 0），`uml.ps1 mutate <文件> [参数]` → `project.ps1 mutation`（`forwardArgs: append`，保留参数与退出码，0 与 3 视为有效结果）。`project.ps1 doctor` 会先核对这份声明与项目公开入口是否一致，缺失、无效 JSON 或错映射都在环境核对之前明确失败；校验不通过时图上操作失败关闭，不回退到通用 crapper/mutator 或 `deps.edn` 别名。

`uml.ps1 crap` 完整执行 `coverage` → `crap`，忽略单类或组件目标并完整替换快照；成功率/覆盖率失败立即停止。`uml.ps1 mutate <文件> [参数]` 转交项目 mutation 接缝并保留参数及退出码。手工复验可以运行 `.\uml.ps1 crap && .\uml.ps1 ir`。分发后的结果记录在 `.uml-viewer/quality-result.json`，companion 只消费刚等到的那条记录，`validResult` 为真才使用 IR 与显示。

运行中的 companion 使用启动时取得的规则；新规则需通过 `:quit-for-restart` → 等待旧 JVM 自然退出 → `.\uml.ps1 --restart` 协议重启后载入。分发脚本每次命令执行时读取，因此旧 companion 执行 `.\uml.ps1 crap` 也立即使用修复后的质量入口。GUI 复验代表模块为 `client.LocalReelIn`。

项目命令 `mutation` 是正式名称，`mutate` 保留为兼容别名；UML 命令仍使用 `uml.ps1 mutate`。CRAP 与 mutation 刷新均先运行完整覆盖率，耗时包含完整测试，不应按秒完成来判断成功。

mutation 从覆盖率开始核对目标源码；worker 仅修改副本。运行期间原始文件被保存或删除时停止发布，保留外部编辑和上一份有效 mutation 快照；失败清理不会写回旧源码。下游入口同样在写快照前检查源码。旧版 `target/mutator-backup/` 没有工具最后写入字节的所有权记录，发现备份时停止运行并保留源码与备份，需人工核对后处理。

worker 是 `target/mutation-workers/run-*/worker-*` 下的测试树副本（Windows 上没有 symlink 权限时整树复制）。它必须自足地跑起 `commands.mutation_test`：根目录 `.busted` 按 mutator 的配置文件清单快照进 worker，`tests/native/helper.lua` 等发现目标随测试目录进入 worker，`busted.bat` 由 PATH 上固定版本的 LuaRocks 垫片解析。三者任一缺失都会让基线非零退出，按基线失败处理而不是发布新快照。worker 与业务扫描都不得带上工具缓存：`sources.roots` 只列 `client`/`common`/`server`，`.toolcache`、`.uml-viewer` 同时从 worker 的复制范围里排除。`tests/tooling/slow/busted_worker_test.py` 钉住这三点，并要求 worker 的 fast 发现集合与主入口逐条一致、实际执行案例数等于该清单条数。

mutation 的存活与未覆盖结果表示测试缺口，保留有效快照。差分流程不会因这些结果自动重跑或转为全量。基线失败与基础设施失败须按真实输出处理，不作为有效新指标。无函数定义的配置或转发模块可能没有 mutation 快照；工具当前不测试模块顶层语句。

质量请求共用仓库 `target/quality.lock` 的操作系统锁。公开 PowerShell、Python 脚本、companion 分发及安装器使用同一锁；同仓库忙时明确拒绝并返回 1，进程异常退出自动释放，另一仓库独立运行。锁文件保持稳定，不通过删除文件解锁。安装器在工具替换完成后释放锁，再调用自行持锁的 doctor；启动解释器时若遇到安装切换可失败，但不得在未取得锁时消费统计或发布指标。

`refresh-crap` 在一次持锁请求内执行完整 coverage → 全树 CRAP，供 viewer 使用。mutation 在同一请求内直接复用覆盖率流程，不启动另一个抢锁的项目请求。所有质量命令及 mutation-report/doctor 的一致性读取均受保护；IR 生成和 viewer 邮件/会话属于独立工具边界。

mutation 发布先校验完整暂存树，准备新文件，再将受影响旧路径可逆移入事务备份；替换、过期路径删除或最终验证失败时恢复发布前快照。成功后清理备份。若回滚自身失败，报出并保留 `target/mutation-publication/publish-*` 恢复材料；该目录有遗留材料时停止后续 mutation，避免覆盖证据。此保护针对质量请求与可控发布失败，不能保证任意外部进程持续禁止恢复写入时仍能自动恢复。

## 可重跑验收

空缓存安装回归使用公开入口；准备独立检出、登记兄弟工具来源后，首次执行 `install.ps1`，再从开发检出运行 `python -I tests/tooling/slow/quality_install_test.py <独立检出绝对路径>`。用例依次检查缺失/错误来源/污染诊断、真实完整 quality 和重复安装；只临时修改独立缓存，并恢复故障注入。完整 quality 日志保留在独立检出的 `build/quality/install-acceptance-quality.log`。该 suite 被 unittest discover 导入时只跳过，不解析发现参数、不设置主检出为目标；只有显式脚本入口接受另一个独立检出的绝对路径，因此上面这条命令是它的手工入口，`verify.ps1 -QualityInstallRoot <绝对路径>` 是同一入口的自动执行形态。

代表文件必须显式指定；该命令包含一次选定文件的全量 mutation：
```powershell
.\tools\quality\verify.ps1 -File common/RateLimit.lua
```

安装 suite 在 discover 下恒被跳过（它只吃独立检出），因此复验入口另有一条显式执行路径：
```powershell
.\tools\quality\verify.ps1 -File common/RateLimit.lua -QualityInstallRoot <独立检出绝对路径>
```
缺省 `-QualityInstallRoot` 时该步骤降级为警告，不阻塞本次复验；给了绝对路径则执行上面的安装 suite 入口，非零退出并入本次复验。

入口串行执行环境校验、完整质量流程、两次差分、选定文件显式全量、公开命令失败路径测试、安装 suite 显式执行与 IR 生成，并核对代表源码哈希。核对第二次差分输出中的 `Mutation function:` 与 `Mutation run:`：`executed` 是本轮实际执行数，`reused` 是函数 digest 与 mutation ID 均一致而继承的历史 killed 数，`uncovered` 是覆盖率缺口，`excluded` 是行筛选排除数。加 `--verbose` 可查看每个 mutation 的 `action`、`reason`、`previous` 与 `result`；历史 survived 会重新执行，源码 digest 或 mutation ID 改变以及显式 `--mutate-all` 都不会复用。不能只依据快照修改时间判断复用。自动命令验收与真实 GUI 验收分别记录。

真实 viewer 验收步骤：

1. 使用 `.\uml.ps1` 首次启动，等待 companion 的 `:display` 被消费。确认顶层为 `client`、`common`、`server`，并查看真实窗口。
2. 打开代表模块卡片，对照 EDN 检查 CRAP、覆盖率、函数名与 mutation 数量。缺少任一指标仍显示红色；红色本身不作为工具失败。
3. 右键刷新 CRAP，核对 companion 实际执行项目入口，完整 CRAP 快照仍含其他模块，IR 与窗口自动更新。
4. 右键差分 mutation，再对同一明确选定文件执行右键全量 mutation。核对邮件队列按顺序消费、命令使用相同配置、结果与窗口更新。
5. 在窗口中设置视图状态，通过 companion 写入 `:quit-for-restart`，等待旧 JVM 自然退出，再执行 `.\uml.ps1 --restart`；核对 companion 身份、恢复的视图与后续邮件处理。session 保存实际图的绝对路径；旧 session 缺少路径时读取项目 `policy.edn` 的 `:out`，同图 `:display` 保留当前视图。

每步保留触发命令、日志、快照关联结果和窗口截图。只有 CLI 或 fixture 通过时，GUI 项仍标为未验证。保持 policy 中已有用户设置，IR 使用生成器更新。

## 产物归属

`.metrics/crap.edn`、`.metrics/mutate/*.edn` 与 `docs/uml/se-fish.edn` 按项目约定纳入版本管理。`build/`、`target/`、`.toolcache/`、`.uml-viewer/` 为本地报告、覆盖率、worker、工具检出与会话产物。验收过程证据按 issue-tracker 工作流记录，发布动作遵循已有授权。

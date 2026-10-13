# 开发工作流

修改代码、运行测试、同步宿主或操作编辑器前，以及整理过程产物时，读取本文。

## 工具链

Lua 命令使用 **Lua 5.4**，执行前用 `lua -v` 核对；验收脚本可用 `ACCEPTANCE_LUA_BIN` 指定解释器。Lua 5.5 对循环变量重新赋值会报 `attempt to assign to const variable`，遇到此错误先检查版本。

- `lua tools/cli.lua deploy`：将三端业务代码字节镜像到宿主目录，排除 `packages/`；编辑器开着本图时执行 validate → 只读 diff。有本地新增或不同文件时报告尚未同步并返回失败；为保留 packages，不执行全工作区 `code push`。
- `lua tools/cli.lua sync`：将宿主目录的 `eggy.json`、API 存根、`data/` 回灌仓库。
- `lua tools/cli.lua sync --packages`：在上述清单外追加三端官方包字节镜像，删除过期包文件，保留三端根现有 `README.md`；任一端源 packages 缺失或为空时整次同步在写入前失败。
- 技能包预设命令见 `lua tools/cli.lua ability-presets --help`；验收脚本说明见 `tools/acceptance/README.md`。
- 质量入口为 `.\tools\quality\project.ps1`，安装、覆盖率、CRAP、DRY、差分 mutation 与复验步骤见 [tools/quality/README.md](../../tools/quality/README.md)；只出报告，不设指标门槛。
- 单测放 `tests/native/`（slow 车道放 `tests/native/slow/`），共享夹具放 `tests/support/`，探针放 `tests/probes/`（手工探针，不入任何车道）。日常运行 `busted --run=fast`（等价 `default`），收尾运行 `busted --run=full`；车道由根目录 `.busted` 定义，共享初始化在 `tests/native/helper.lua`。Windows 专用案例在案例内判平台，非 Windows 时 `return pending(...)`，`--list` 行数因此跨平台不变。
  - 与「完成判据」表里 `0 pending` 的关系：那张表的 `0 pending` 是在 **Windows**（本轮目标平台）上取的数；非 Windows 下这些案例会以 pending 出现，判据相应放松为「除已知平台案例外 0 pending」。本轮 macOS **仅设计未实机**，没有实机数据。
  - **执行序只保证到文件内**：迁移保留的是**文件内**执行序（`it` 注册序 == 旧 LuaUnit 类内方法序），**不保留跨文件的全局类名字典序**。LuaUnit 的 `collectTests()` 排的是全局 `_G.Test*` **类名**，`.busted` 的 `sort-files=true` 排的是**文件路径字符串**，是两个键空间，技术上无法廉价复现；且 helper 在文件发现**之前**执行，插不进重排钩子。
    - 为什么可以接受：跨类没有共享状态，夹具逐例隔离（`tests/native/helper.lua`）；**且不复刻旧序反而修了一个真 bug**——旧序下 `damage_float_test.lua` 与 `vitals_test.lua` 都定义全局 `TestDamageNotice`，后加载整表覆盖前者，导致 `test_rounding_and_effective_health` **从未被执行**，迁移后复活（+1，属修复而非回归）。
    - 裁定原文见迁移台账 `issue-84-mapping.md:96` 与 `issue-85-mapping.md:63`（台账在仓库外，按文件名检索）。
  - `busted` 与 `busted.bat`：人手 shell 里敲、以及 `shutil.which`（会按 `PATHEXT` 找到 `.bat` 垫片）用裸 `busted` 即可；只有 Python `CreateProcess`/`shell=False` 起子进程时必须写 `busted.bat`（`CreateProcess` 只补 `.exe`，裸名会 `[WinError 2]`），`tools/quality/project.json` 的 `commands.*` 因此写 `busted.bat`，而 `busted.command` 仍写裸 `busted` 供 `shutil.which` 用。

**架构图（uml-viewer）。** 根目录 `policy.edn` 描述三端模块树，`docs/uml/se-fish.edn` 是生成的依赖图（不要手编）。

- `.\uml.ps1`：首次启动 viewer 与 companion 看图、向 agent 发起图上操作；`.\uml.ps1 ir` 在修改三端代码后重新生成图，viewer 检测文件变化自动重载。
- **companion 后端是 Herdr（0.9.3，且只有它）**：旧 tmux/psmux 路径已退役，Linux/WSL 不提供 companion。companion ownership 记录在 `.uml-viewer/companion.edn`，必须显式记为 Herdr；旧记录或缺 backend 的记录会保留并拒绝接管，不要猜着重连。能力契约与验收边界见 uml-viewer 的 `docs/herdr-backend-contract.md`。
- **重启 viewer 必须走协议**：往 `.uml-viewer/to-viewer.edn` 写 `:quit-for-restart` → 等旧 JVM 自然退出 → `.\uml.ps1 --restart`；新 JVM 按持久化记录重新 bind 原 pane，不新建 companion。**绝不 SIGKILL**，也不要绕开公开 wrapper 直接传 `--restart`。
- 图上 `crap` / `mutate`：companion 消费邮箱命令后执行项目公开入口（即 `uml-quality.json` 声明的 `project.ps1 refresh-crap` / `project.ps1 mutation`）。每次调用前删掉上一条 `.uml-viewer/quality-result.json`，运行后核对刚等到的记录里 `version`、`operation`、`projectRoot`、实际退出码与 `validResult`；只有 `validResult` 为真才继续 IR 与显示。
- 图上 `client|common|server` 为三棵树；`**/packages/**` 与 `server/_trigger/` 被 `:exclude` 排除，vendor 依赖显示为 `*.packages` 椭圆。viewer 从 `.metrics/crap.edn` 与 `.metrics/mutate/*.edn` 加载指标；缺少任一指标的类卡片为红色。Lua 指标安装、原生 Windows 适配与命令见 [tools/quality/README.md](../../tools/quality/README.md)。
- **标准 quality 分发**：根目录 `uml-quality.json`（版本管理）声明图上 `crap` / `mutate` 转交哪个项目公开命令，终端与右键走同一实现；参数、退出码、锁与失败报告一致。改项目质量入口时同步核对这份声明，`project.ps1 doctor` 会先校验它。
- `target/` 放覆盖率与 mutation worker，属于忽略的临时产物；`.metrics/` 保留质量快照并纳入版本管理。无函数定义的配置或转发模块不生成 mutation 快照；当前工具不测试模块顶层语句。
- 根目录 `uml`、`uml.ps1` 由安装器拷贝，不要编辑；固定工具组合的安装与校验使用 [tools/quality/README.md](../../tools/quality/README.md) 的项目入口。
- **本轮只在 Windows 实机验收**：安装、doctor、full／fast、coverage、CRAP、独立 Python 回归与 Herdr 恢复都只有 Windows 的实机数据。**macOS 仅设计、未实机验证，没有实机数据**；Herdr 的 macOS 端到端验收已取消，不等于通过。

**Windows worktree 起手式。** `tools/quality/project.json` 的 `tools.*.source` 写成 `../uml-viewer` 这类相对路径，从检出根的**父目录**解析；worktree 里没有主检出旁的真实工具检出，必须在 worktree 的父目录建 junction：

```powershell
foreach ($t in 'uml-viewer','crapper','mutator') {
  New-Item -ItemType Junction -Path "<worktree 父目录>\$t" -Target "C:\Users\<用户名>\Desktop\dev\github\$t"
}
```

- 目标必须是这些**真实检出**。指向 `.uml-viewer\<tool>`（安装产物而非上游检出）会让 install／doctor 预检与标准分发回归大面积报错。
- `.toolcache` 也 junction 到主检出的同名目录，否则要自己备齐 `project.json` 的 `lua_tools` 全套：`luacov`、`dry4lua`、`luacheck`、`acceptance4lua`，以及它们的 Lua 依赖 `argparse`、`datafile`、`luafilesystem`。缺 `luacheck` 时 `tests/native/slow/quality_report_test.lua` 会经 `dry4lua/ast.lua` 抛 `luacheck required`，断言先撞在 `broken.lua` 那一行——报错点离根因三层。
- `.uml-viewer` 也 junction 到主检出的同名目录，才能复用已安装的 venv 与 viewer checkout；代价是会话、邮箱与 `quality-result.json` 一并共享，不要在两处同时起 viewer。

**宿主目录专用于镜像。** 默认 `C:\Users\<用户名>\Desktop\dev\eggy\LuaSource_钓鱼怎么这么危险啊喂！`，可用 `EGGY_WORKSPACE` 覆盖。

**编辑器工程 ≠ 仓库检出。** `eggy.json` 回灌不等于 `code init` 绑定；手动执行 code-* 时用 `--workspace` 指向已绑定的宿主目录，否则会报 `CODE_BINDING_INVALID`。`deploy` 已带此参数。Git Bash 验证命令：

```bash
"$USERPROFILE/.eggitor/cli/editor-cli.exe" code validate --strict --json --workspace "<宿主目录>"
```

## 测试纪律

- **试玩优先**：新增验证尽量只用编辑器 E2E，复杂功能以试玩证明可用；操作见 `eggy-lua` 的「试玩验收」。
- **先列失败方式**：确需单独测试某个系统时，先列出所有可能失败的方式，再写代码；代码写完后不补写单测。
- **局部开发、全量收尾**：开发期间用 `busted --run=fast` 验证；业务功能仍按需试玩，收尾执行下面的全部检查。
- **可复现取证**：每次试玩保留可重跑的触发步骤（`input` 命令、探针文件）与对应证据（`log grep` 命中行、截图路径）。

## 完成判据

代码改动按顺序执行，全部通过才算完成：

| 检查 | 通过条件 |
|---|---|
| `busted --run=fast`（日常） | fast 车道全部用例通过，末行匹配 `N successes / 0 failures / 0 errors / 0 pending : T seconds`，退出码 0 |
| `busted --run=full`（收尾） | 含 slow 车道，全部用例通过，末行匹配 `N successes / 0 failures / 0 errors / 0 pending : T seconds`，退出码 0 |
| `.\tools\quality\project.ps1 quality` | 完整 Busted 套件通过，生成本轮 LCOV、全树 CRAP 与 DRY 报告 |
| `bash tools/acceptance/run_acceptance.sh`（有 feature 时） | `N passed, 0 failed`，末行 `acceptance run OK`；无 feature 时提示跳过且返回 0 |
| 每个改过的 `.lua` 执行 `lua -e "assert(loadfile('<file>'))"` | 无输出、退出码 0 |
| `lua tools/cli.lua deploy` 后执行上面的 `code validate` | `ok=true`、`data.valid=true`、`data.is_se_map=true`，`data.issues` 与 `meta.warnings` 均为空 |
| validate 通过后全套试玩 | 每条验收现象都有取证产物；`log trace` 本轮窗口有效且无错误 |

## 产物归属

执行过程产物（调研全文、验证台账、验收记录、开发计划）贴进对应 issue 的评论；`docs/` 只留长期参考（术语、技术难点、vendor 说明、ADR）。`eggy-dev-plan` 默认的 `docs/plan/` 输出在本仓库改为 issue 评论。


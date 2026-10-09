# 开发工作流

修改代码、运行测试、同步宿主或操作编辑器前，以及整理过程产物时，读取本文。

## 工具链

Lua 命令使用 **Lua 5.4**，执行前用 `lua -v` 核对；验收脚本可用 `ACCEPTANCE_LUA_BIN` 指定解释器。Lua 5.5 对循环变量重新赋值会报 `attempt to assign to const variable`，遇到此错误先检查版本。

- `lua tools/cli.lua deploy`：将三端业务代码字节镜像到宿主目录，排除 `packages/`；编辑器开着本图时执行 validate → 只读 diff。有本地新增或不同文件时报告尚未同步并返回失败；为保留 packages，不执行全工作区 `code push`。
- `lua tools/cli.lua sync`：将宿主目录的 `eggy.json`、API 存根、`data/` 回灌仓库。
- `lua tools/cli.lua sync --packages`：在上述清单外追加三端官方包字节镜像，删除过期包文件，保留三端根现有 `README.md`；任一端源 packages 缺失或为空时整次同步在写入前失败。
- 技能包预设命令见 `lua tools/cli.lua ability-presets --help`；验收脚本说明见 `tools/acceptance/README.md`。
- 质量与变异脚本位于 `tools/quality/`，只出报告，不设门槛。
- 单测按对象放入 `tests/gameplay/` 或 `tests/tooling/`；真实 CLI 子进程用例放入 `tests/tooling/slow/`。日常运行 `lua tests/run.lua fast`；分类运行 `lua tests/run.lua gameplay` 或 `lua tests/run.lua tooling`；完整运行 `lua tests/run.lua`（等价于 `full`）。

**架构图（uml-viewer）。** 根目录 `policy.edn` 描述三端模块树，`docs/uml/se-fish.edn` 是生成的依赖图（不要手编）。

- `.\uml.cmd ir`：修改三端代码后重新生成图；viewer 检测文件变化自动重载。
- `.\uml.cmd`：启动 viewer 与 companion 看图、向 agent 发起图上操作。重启 viewer 由 companion 处理，不要直接杀进程。
- 图上 `client|common|server` 为三棵树；`**/packages/**` 与 `server/_trigger/` 被 `:exclude` 排除，vendor 依赖显示为 `*.packages` 椭圆。类卡片全红表示缺 CRAP/mutation 数据；本次接入未配置 Lua 指标计算，属预期。
- 根目录 `uml`、`uml.ps1`、`uml.cmd` 由安装器拷贝，不要编辑；`.uml-viewer/` 缺失或入口过期时在仓库根运行 `get-uml-viewer`（来自 uml-viewer 仓库 `scripts/`）。

**宿主目录专用于镜像。** 默认 `C:\Users\<用户名>\Desktop\dev\eggy\LuaSource_钓鱼怎么这么危险啊喂！`，可用 `EGGY_WORKSPACE` 覆盖。

**编辑器工程 ≠ 仓库检出。** `eggy.json` 回灌不等于 `code init` 绑定；手动执行 code-* 时用 `--workspace` 指向已绑定的宿主目录，否则会报 `CODE_BINDING_INVALID`。`deploy` 已带此参数。Git Bash 验证命令：

```bash
"$USERPROFILE/.eggitor/cli/editor-cli.exe" code validate --strict --json --workspace "<宿主目录>"
```

## 测试纪律

- **试玩优先**：新增验证尽量只用编辑器 E2E，复杂功能以试玩证明可用；操作见 `eggy-lua` 的「试玩验收」。
- **先列失败方式**：确需单独测试某个系统时，先列出所有可能失败的方式，再写代码；代码写完后不补写单测。
- **局部开发、全量收尾**：开发期间用 `lua tests/run.lua fast` 或分类入口验证；业务功能仍按需试玩，收尾执行下面的全部检查。
- **可复现取证**：每次试玩保留可重跑的触发步骤（`input` 命令、探针文件）与对应证据（`log grep` 命中行、截图路径）。

## 完成判据

代码改动按顺序执行，全部通过才算完成：

| 检查 | 通过条件 |
|---|---|
| `lua tests/run.lua fast`（日常） | gameplay 全部用例与不启动真实 CLI 的 tooling 用例，统计行 `0 failures`，末行 `OK` |
| `lua tests/run.lua`（收尾，等价于 `full`） | 所有保留的单测（含回同步传输），统计行 `0 failures`，末行 `OK` |
| `bash tools/quality/run.sh` | 完整单测通过，生成覆盖率与静态质量报告 |
| `bash tools/acceptance/run_acceptance.sh`（有 feature 时） | `N passed, 0 failed`，末行 `acceptance run OK`；无 feature 时提示跳过且返回 0 |
| 每个改过的 `.lua` 执行 `lua -e "assert(loadfile('<file>'))"` | 无输出、退出码 0 |
| `lua tools/cli.lua deploy` 后执行上面的 `code validate` | `ok=true`、`data.valid=true`、`data.is_se_map=true`，`data.issues` 与 `meta.warnings` 均为空 |
| validate 通过后全套试玩 | 每条验收现象都有取证产物；`log trace` 本轮窗口有效且无错误 |

## 产物归属

执行过程产物（调研全文、验证台账、验收记录、开发计划）贴进对应 issue 的评论；`docs/` 只留长期参考（术语、技术难点、vendor 说明、ADR）。`eggy-dev-plan` 默认的 `docs/plan/` 输出在本仓库改为 issue 评论。


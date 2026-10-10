# 质量工具

`run.sh` / `mutate.sh` 是原有 `crap4lua`、`dry4lua`、`mutate4lua` 流程。uml-viewer 使用 Python `crapper` / `mutator`，两套工具独立运行。本项目使用原生 Windows，不使用 WSL。

## uml-viewer 依赖

先按 `docs/agents/workflow.md` 安装 uml-viewer，其安装器会检出工具到 `.uml-viewer/`，但不会安装 Python 依赖。已验证 Lua 5.4.6、Python 3.12，工具版本为：

| 工具 | 仓库 | 提交 |
| --- | --- | --- |
| crapper | https://github.com/TLOBillyQ/crapper | `afcd1475ffe62c09e8ee5e4805f3a689bde4a649` |
| mutator | https://github.com/TLOBillyQ/mutator | `1348ea5c30ce1e82a872789bc2baa574c0340d10` |

在仓库根使用 PowerShell 安装（已有 venv 时不必重建）：

```powershell
py -3 -m venv .uml-viewer/crapper/.venv
& .uml-viewer/crapper/.venv/Scripts/python.exe -m pip install -e .uml-viewer/crapper
py -3 -m venv .uml-viewer/mutator/.venv
& .uml-viewer/mutator/.venv/Scripts/python.exe -m pip install -e .uml-viewer/mutator
```

Windows 兼容入口为 `tools/quality/run_mutator_windows.py`，运行前加载同目录 `windows_adapter.py`：用复制代替 overlay 符号链接，用 `taskkill` 清理超时进程树，并在删除文件前清除只读位。适配器从 `.uml-viewer/crapper/src` 加载兄弟工具。上游仍会打印 `Native Windows is not supported` 提示，提示本身不会退出；以测试结果和退出码为准。

## 覆盖率与指标

LuaCov 源码位于 `.toolcache/luacov/src`，依赖安装见 `deps.sh`。以下命令在仓库根运行：

```powershell
lua -v
$env:LUA_PATH = '.toolcache/luacov/src/?.lua;.toolcache/luacov/src/?/init.lua;./?.lua;./?/init.lua;;'
New-Item -ItemType Directory -Force build/quality, target/coverage/lua | Out-Null
Remove-Item luacov.stats.out -ErrorAction Ignore
lua -lluacov tests/run.lua full
Move-Item luacov.stats.out build/quality/luacov.stats.out -Force
lua tools/quality/report_lcov.lua build/quality/luacov.stats.out target/coverage/lua/lcov.info
$sources = @(git ls-files -- client common server | Where-Object { $_ -match '\.lua$' -and $_ -notmatch '/packages/|^server/_trigger/' })
.\uml.cmd crap --root . --use-existing-coverage @sources
```

先确保测试成功，再转换覆盖率或运行指标工具。每次 crapper 会替换整份 `.metrics/crap.edn`，始终计算全树。转换器排除官方 `packages/` 和 `server/_trigger/`；输出必须命名为 `lcov.info`，置于 `target/coverage/` 下才能自动发现。

对改动文件执行差分 mutation，例如：

```powershell
& .uml-viewer/mutator/.venv/Scripts/python.exe tools/quality/run_mutator_windows.py --root . --use-existing-coverage --test-command 'lua tests/run.lua fast' --max-workers 4 common/RateLimit.lua
.\uml.cmd ir
```

退出码 `0` 表示全部选中变异被杀死，`2` 表示基线测试失败，`3` 表示存在存活变异。存活和未覆盖结果保留为测试缺口，不能因此重跑文件或添加 `--mutate-all`。内存不足时降低 `--max-workers`；文件中途被终止时，从尚未保存快照的文件恢复。

当前 Lua mutator 只统计函数体。没有本地函数定义的配置或 API 转发模块不会生成独立快照，顶层常量与语句也不纳入变异测试。上游会反复重写、打印其他模块的既有快照，这不表示对那些模块重新执行测试。

## 产物归属

`.metrics/crap.edn` 与 `.metrics/mutate/*.edn` 是 viewer 的指标输入，保留并纳入版本管理，便于打开图时读取已有结果。`build/`、`target/`、`.toolcache/` 和 `.uml-viewer/` 为本地报告、覆盖率、worker、依赖与会话文件，不提交。中断后先确认没有 mutator 进程，再清除 `target/mutation-workers/`；保留覆盖率可以继续差分运行。不要删除正在运行的 viewer 邮箱或依赖检出。

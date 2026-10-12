"""项目公开质量接缝：LuaUnit、完整覆盖率与固定工具配置。"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

os.environ.setdefault("PYTHONDONTWRITEBYTECODE", "1")

PROJECT_ROOT = Path(__file__).resolve().parents[2]


def load_config(root=None, config=None):
    root = Path(root or PROJECT_ROOT).resolve()
    return json.loads(Path(config or root / "tools/quality/project.json").read_text(encoding="utf-8-sig"))


def source_files(root, config):
    """列出部署树内业务 Lua，包括尚未提交的新模块。"""
    root = Path(root)
    result = []
    for directory in config["sources"]["roots"]:
        for path in (root / directory).rglob("*.lua"):
            relative = path.relative_to(root).as_posix()
            parts = path.relative_to(root).parts
            excluded = config["sources"]["exclude"]
            if any(rule in parts or relative.startswith(rule.rstrip("/") + "/") for rule in excluded):
                continue
            result.append(relative)
    return sorted(result)


def lua_environment(root, config):
    env = os.environ.copy()
    source = (Path(root) / config["paths"]["luacov"]).resolve().as_posix()
    env["LUA_PATH"] = f"{source}/?.lua;{source}/?/init.lua;./?.lua;./?/init.lua;;"
    return env


def lua_executable(config):
    """Lua 解释器只来自 lua.executable；测试命令 argv 整体不透明，首项不做解释器。"""
    return config.get("lua", {}).get("executable", "lua")


def verify_lua(config):
    executable = lua_executable(config)
    expected = config.get("lua", {}).get("version", "Lua 5.4.")
    if shutil.which(executable) is None:
        raise RuntimeError(f"缺少 Lua 解释器：{executable} 不在 PATH；质量入口要求 {expected}x")
    result = subprocess.run([executable, "-v"], capture_output=True, text=True)
    version = result.stdout + result.stderr
    if result.returncode or expected not in version:
        raise RuntimeError(f"质量入口要求 {expected}x，实际为：{version.strip()}")


def run_coverage(root, config):
    """仅将通过完整测试的新统计发布为可发现 LCOV。"""
    root = Path(root).resolve()
    command = config["commands"]["coverage"]
    lcov = root / config["paths"]["lcov"]
    stats = root / config["paths"]["stats"]
    temporary = lcov.with_suffix(".pending")
    for path in (lcov, temporary, stats, root / "luacov.stats.out", root / "luacov.report.out"):
        path.unlink(missing_ok=True)
    verify_lua(config)
    lcov.parent.mkdir(parents=True, exist_ok=True)
    stats.parent.mkdir(parents=True, exist_ok=True)
    env = lua_environment(root, config)
    result = subprocess.run(command, cwd=root, env=env)
    if result.returncode:
        print(f"完整测试失败（退出码 {result.returncode}）；未生成本轮 LCOV。", file=sys.stderr)
        return result.returncode
    generated = root / "luacov.stats.out"
    if not generated.is_file() or generated.stat().st_size == 0:
        raise RuntimeError("完整测试未生成 LuaCov 统计，停止指标刷新。")
    generated.replace(stats)
    result = subprocess.run([lua_executable(config), str(PROJECT_ROOT / "tools/quality/report_lcov.lua"),
                             str(stats), str(temporary)], cwd=root, env=env)
    if result.returncode:
        temporary.unlink(missing_ok=True)
        return result.returncode
    text = temporary.read_text(encoding="utf-8")
    if "SF:" not in text or "end_of_record" not in text:
        temporary.unlink(missing_ok=True)
        raise RuntimeError("LCOV 转换未生成有效记录，停止指标刷新。")
    temporary.replace(lcov)
    print(f"本轮完整覆盖率：{lcov}")
    return 0


def doctor(root, config):
    root = Path(root).resolve()
    verify_lua(config)
    executable = lua_executable(config)
    # 读取 bootstrap 的公开 pins，不触发 ensure/install，保留 acceptance 独立入口。
    pins = subprocess.run([
        executable, "-e",
        'local b=require("tools.acceptance.bootstrap"); '
        'for _,n in ipairs({"dry4lua","acceptance4lua"}) do print(n.."="..b.pins[n]) end',
    ], cwd=root, capture_output=True, text=True)
    if pins.returncode:
        raise RuntimeError(f"无法读取 acceptance bootstrap 固定提交：{pins.stderr.strip()}")
    for line in pins.stdout.splitlines():
        name, commit = line.split("=", 1)
        if config["lua_tools"][name]["commit"] != commit:
            raise RuntimeError(f"{name} quality 与 acceptance bootstrap 固定提交不一致："
                               f"{config['lua_tools'][name]['commit']} / {commit}")
    for name, tool in config["lua_tools"].items():
        directory = root / ".toolcache" / name
        repair = "请移走损坏缓存后运行 tools/quality/install.ps1"
        if not (directory / ".git").exists():
            raise RuntimeError(f"{name} 缺少运行依赖 checkout：{directory}；{repair}")
        actual = subprocess.check_output(["git", "-C", str(directory), "rev-parse", "HEAD"], text=True).strip()
        if actual != tool["commit"]:
            raise RuntimeError(f"{name} 提交不符：{actual}，预期 {tool['commit']}；{repair}")
        origin = subprocess.check_output(["git", "-C", str(directory), "remote", "get-url", "origin"], text=True).strip()
        if origin != tool["url"]:
            raise RuntimeError(f"{name} 来源不符：{origin}，预期 {tool['url']}；{repair}")
        dirty = subprocess.check_output(["git", "-C", str(directory), "status", "--porcelain", "--", "src"], text=True).strip()
        if dirty:
            raise RuntimeError(f"{name} 运行源码已修改或有未登记模块：{dirty}；{repair}")
        source = directory / "src"
        env = os.environ.copy()
        sources = [source] + [root / ".toolcache" / other / "src" for other in config["lua_tools"] if other != name]
        env["LUA_PATH"] = ";".join(pattern for path in sources for pattern in
                                   (f"{path.as_posix()}/?.lua", f"{path.as_posix()}/?/init.lua"))
        env["LUA_CPATH"] = ""
        for module in tool["modules"]:
            snippet = (f"local p=assert(package.searchpath({module!r}, package.path)); "
                       f"print(p); assert(require({module!r}))")
            result = subprocess.run([executable, "-e", snippet],
                                    cwd=root, env=env, capture_output=True, text=True)
            if result.returncode:
                raise RuntimeError(f"{name} 无法加载运行模块 {module}：{result.stderr.strip()}；{repair}")
            print(f"{name} {actual} {result.stdout.strip()}")
    doctor_busted(root, config)
    for name, tool in config["tools"].items():
        directory = root / ".uml-viewer" / tool["directory"]
        if not (directory / ".git").exists():
            raise RuntimeError(f"{name} 缺少 git checkout：{directory}")
        actual = subprocess.check_output(["git", "-C", str(directory), "rev-parse", "HEAD"], text=True).strip()
        if actual != tool["commit"]:
            raise RuntimeError(f"{name} 提交不符：{actual}，预期 {tool['commit']}")
        dirty = subprocess.check_output(["git", "-C", str(directory), "status", "--short"], text=True).strip()
        print(f"{name} {actual}" + (f"\n未提交差异：\n{dirty}" if dirty else "（干净）"))
        for patch in tool.get("patches", []):
            patch_path = root / patch
            result = subprocess.run(["git", "-C", str(directory), "apply", "--reverse", "--check", str(patch_path)],
                                    capture_output=True)
            if result.returncode:
                raise RuntimeError(f"{name} 缺少已登记补丁 {patch}，请运行 tools/quality/install.ps1")
        if name == "viewer":
            continue
        python = directory / ".venv/Scripts/python.exe"
        snippet = (f"import sys,{name}; print(sys.executable); print(sys.version); print({name}.__file__); "
                   f"assert {name}.__file__.replace('\\\\','/').lower().startswith({str(directory / 'src').replace(chr(92), '/').lower()!r})")
        subprocess.run([str(python), "-c", snippet], check=True)
        subprocess.run([str(python), "-m", "pip", "check"], check=True)
    return 0


def doctor_busted(root, config):
    """核对 Busted 固定依赖：命令可用、版本相符、pinned rocks 已安装；可重跑。

    失败信息区分解释器缺失（verify_lua）、Busted 命令缺失、版本不符与 rock 未安装。
    LuaCov 的运行时来源仍是 lua_tools.luacov 的固定 checkout（上面的 lua_tools 检查），
    这里的 luacov rock 只为 busted --coverage 等直接用法保持同一固定版本。
    """
    spec = config.get("busted")
    if not spec:
        raise RuntimeError("project.json 缺少 busted 固定依赖配置")
    repair = "请运行 tools/quality/install.ps1 安装固定依赖"
    command = spec["command"]
    path = shutil.which(command)
    if path is None:
        raise RuntimeError(f"缺少 Busted 命令：{command} 不在 PATH；{repair}")
    result = subprocess.run([path, "--version"], capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(f"Busted 无法运行：{result.stderr.strip() or result.stdout.strip()}；{repair}")
    actual = result.stdout.strip()
    if actual != spec["version"]:
        raise RuntimeError(f"Busted 版本不符：{actual}，预期 {spec['version']}；{repair}")
    luarocks = shutil.which("luarocks")
    if luarocks is None:
        raise RuntimeError(f"缺少 LuaRocks 命令，无法核对 Busted 固定依赖；{repair}")
    for rock in spec["rocks"]:
        name, version = rock["name"], rock["version"]
        result = subprocess.run([luarocks, "list", name, "--porcelain"], capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError(f"无法查询 {name} 安装状态：{result.stderr.strip()}；{repair}")
        rows = [line.split("\t") for line in result.stdout.splitlines() if line.strip()]
        if not any(len(fields) >= 3 and fields[0] == name and fields[1] == version and fields[2] == "installed"
                   for fields in rows):
            raise RuntimeError(f"{name} 固定版本 {version} 未安装；{repair}")
        print(f"{name} {version}（rock）")
    print(f"busted {actual}（{path}）")


def run_quality(root, config):
    """完整质量流程：本轮覆盖率 → DRY → 全树 CRAP。"""
    import crap
    code = run_coverage(root, config)
    if code:
        return code
    code = crap.run_dry(root, config)
    if code:
        return code
    return crap.run_crap(root, config)


def run_mutation(root, config, args):
    import mutation
    try:
        config_path = Path(args.config) if args.config else root / "tools/quality/project.json"
        return mutation.run(root, config, config_path, args.files, mutate_all=args.mutate_all,
                            changed=args.changed, max_workers=args.max_workers,
                            lines=set(args.lines) if args.lines else None, verbose=args.verbose)
    except ValueError as error:
        print(f"quality: {error}", file=sys.stderr)
        return 1


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=PROJECT_ROOT)
    parser.add_argument("--config", type=Path)
    parser.add_argument("command", choices=["coverage", "test", "doctor", "run", "quality",
                                            "crap", "refresh-crap", "dry", "mutation", "mutate", "mutation-report"])
    parser.add_argument("files", nargs="*", help="mutation 目标业务 Lua（相对路径）")
    parser.add_argument("--mutate-all", action="store_true", help="显式全量 mutation（必须给文件）")
    parser.add_argument("--changed", action="store_true", help="对 git 变更的业务 Lua 差分")
    parser.add_argument("--max-workers", type=int)
    parser.add_argument("--lines", type=int, nargs="*")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args(argv)
    root = args.root.resolve()
    from locking import repository_lock
    with repository_lock(root):
        return dispatch(root, args)


def dispatch(root, args):
    config = load_config(root, args.config)
    if args.command == "coverage":
        return run_coverage(root, config)
    if args.command == "refresh-crap":
        code = run_coverage(root, config)
        if code:
            return code
        import crap
        return crap.run_crap(root, config)
    if args.command == "doctor":
        return doctor(root, config)
    if args.command == "test":
        command = config["commands"]["mutation_test"]
        verify_lua(config)
        return subprocess.run(command, cwd=root).returncode
    if args.command in ("run", "quality"):
        return run_quality(root, config)
    import crap
    if args.command == "crap":
        return crap.run_crap(root, config)
    if args.command == "dry":
        return crap.run_dry(root, config)
    if args.command == "mutation-report":
        import mutation
        return mutation.report(root, config)
    if args.command in ("mutation", "mutate"):
        return run_mutation(root, config, args)
    raise RuntimeError(f"未知质量命令：{args.command}")


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, OSError, subprocess.CalledProcessError) as error:
        print(f"quality: {error}", file=sys.stderr)
        sys.exit(1)

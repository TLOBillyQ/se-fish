"""项目公开质量接缝：LuaUnit、完整覆盖率与固定工具配置。"""
from __future__ import annotations

import argparse
import json
import os
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


def verify_lua(command):
    result = subprocess.run([command[0], "-v"], capture_output=True, text=True)
    version = result.stdout + result.stderr
    if result.returncode or "Lua 5.4." not in version:
        raise RuntimeError(f"质量入口要求 Lua 5.4，实际为：{version.strip()}")


def run_coverage(root, config):
    """仅将通过完整测试的新统计发布为可发现 LCOV。"""
    root = Path(root).resolve()
    command = config["commands"]["coverage"]
    lcov = root / config["paths"]["lcov"]
    stats = root / config["paths"]["stats"]
    temporary = lcov.with_suffix(".pending")
    for path in (lcov, temporary, stats, root / "luacov.stats.out", root / "luacov.report.out"):
        path.unlink(missing_ok=True)
    verify_lua(command)
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
    result = subprocess.run([command[0], str(PROJECT_ROOT / "tools/quality/report_lcov.lua"),
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
    verify_lua(config["commands"]["coverage"])
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
                                            "crap", "dry", "mutation", "mutate", "mutation-report"])
    parser.add_argument("files", nargs="*", help="mutation 目标业务 Lua（相对路径）")
    parser.add_argument("--mutate-all", action="store_true", help="显式全量 mutation（必须给文件）")
    parser.add_argument("--changed", action="store_true", help="对 git 变更的业务 Lua 差分")
    parser.add_argument("--max-workers", type=int)
    parser.add_argument("--lines", type=int, nargs="*")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args(argv)
    root = args.root.resolve()
    config = load_config(root, args.config)
    if args.command == "coverage":
        return run_coverage(root, config)
    if args.command == "doctor":
        return doctor(root, config)
    if args.command == "test":
        command = config["commands"]["mutation_test"]
        verify_lua(command)
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

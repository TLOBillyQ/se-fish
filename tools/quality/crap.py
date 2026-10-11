"""全树 CRAP 快照与 DRY 报告；覆盖率只读取调用方指定的本轮 LCOV。"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from dataclasses import asdict
from pathlib import Path

from project import PROJECT_ROOT, load_config, source_files

# 由固定 venv 解释器提供 crapper；doctor 负责验证实际导入来源，
# 不在运行路径强制注入本地源码目录，以免遮蔽环境问题。
from crapper.analyze import analyze_files
from crapper.coverage import CoverageBundle, parse_lcov
from crapper.metrics import render_edn
from crapper.report import format_report


def run_crap(root, config, files=None, lcov_path=None):
    root = Path(root).resolve()
    # 即使请求携带单模块，也重新从统一配置发现完整业务树。
    files = source_files(root, config)
    if not files:
        raise RuntimeError("没有可分析的业务 Lua 源码")
    _validate_sources(root, files)
    coverage = Path(lcov_path or root / config["paths"]["lcov"])
    if not coverage.is_file():
        raise RuntimeError(f"缺少本轮 LCOV：{coverage}")
    text = coverage.read_text(encoding="utf-8-sig")
    if "end_of_record" not in text:
        raise RuntimeError(f"本轮 LCOV 不完整：{coverage}")
    bundle = CoverageBundle(lcov=parse_lcov(text))
    entries = analyze_files([root / path for path in files], root, bundle)
    if not entries or not any(entry.coverage is not None for entry in entries):
        raise RuntimeError("本轮 LCOV 未匹配到业务 Lua 函数，停止发布 CRAP")
    snapshot = root / config["paths"]["crap"]
    snapshot.parent.mkdir(parents=True, exist_ok=True)
    temporary = snapshot.with_suffix(".pending")
    temporary.write_text(render_edn(entries), encoding="utf-8")
    temporary.replace(snapshot)
    report = root / "build/quality/crap.json"
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps({"source_count": len(files), "functions": [asdict(entry) for entry in entries]}, ensure_ascii=False, indent=2), encoding="utf-8")
    (report.parent / "crap.txt").write_text(format_report(entries), encoding="utf-8")
    print(f"CRAP 完成：{len(files)} 个业务文件，{len(entries)} 个函数，完整替换 {snapshot}；仅报告、不设门槛。")
    return 0


def _validate_sources(root, files):
    """以 Lua loadfile 预校验业务源码，避免损坏文件静默跳过 CRAP。"""
    for relative in files:
        result = subprocess.run(
            ["lua", "-e", f'assert(loadfile({str(root / relative)!r}))'],
            cwd=root,
            capture_output=True,
            text=True,
        )
        if result.returncode:
            raise RuntimeError(f"业务 Lua 源码解析失败：{relative}：{result.stderr.strip()}")


def run_dry(root, config, files=None):
    root = Path(root).resolve()
    files = source_files(root, config)
    output = root / "build/quality"
    output.mkdir(parents=True, exist_ok=True)
    manifest = output / "sources.txt"
    manifest.write_text("\n".join(files) + "\n", encoding="utf-8")
    env = os.environ.copy()
    paths = []
    for tool in ("dry4lua", "luacheck", "acceptance4lua"):
        source = (PROJECT_ROOT / ".toolcache" / tool / "src").as_posix()
        paths.extend([f"{source}/?.lua", f"{source}/?/init.lua"])
    env["LUA_PATH"] = ";".join(paths) + ";./?.lua;./?/init.lua;;"
    report = output / "dry.json"
    temporary = report.with_suffix(".pending")
    temporary.unlink(missing_ok=True)
    result = subprocess.run([config["commands"]["coverage"][0], str(PROJECT_ROOT / "tools/quality/report.lua"), str(manifest), str(temporary)], cwd=root, env=env)
    if result.returncode:
        temporary.unlink(missing_ok=True)
        return result.returncode
    temporary.replace(report)
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=PROJECT_ROOT)
    parser.add_argument("--config", type=Path)
    args = parser.parse_args(argv)
    return run_crap(args.root, load_config(args.root, args.config))


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, OSError, ValueError) as error:
        print(f"quality: {error}", file=sys.stderr)
        sys.exit(1)

"""项目 mutation：限定业务范围，并保护失败前的有效快照。"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# 固定实际导入来源；公开入口和旧兼容入口使用同一 checkout。
_TOOL_ROOT = Path(__file__).resolve().parents[2] / ".uml-viewer"
sys.path.insert(0, str(_TOOL_ROOT / "mutator/src"))
sys.path.insert(0, str(_TOOL_ROOT / "crapper/src"))


def _test_command(root: Path, command: list) -> list:
    """Worker 直接运行项目 argv，mutator 会把 cwd 映射到 overlay。"""
    return command


def _changed_lua(root: Path, config: dict) -> list[str]:
    result = subprocess.run(["git", "diff", "--name-only", "--diff-filter=d", "--", *config["sources"]["roots"]],
                            cwd=root, capture_output=True, text=True, check=True)
    changed = {line.strip() for line in result.stdout.splitlines() if line.strip()}
    result = subprocess.run(["git", "ls-files", "--others", "--exclude-standard", "--", *config["sources"]["roots"]],
                            cwd=root, capture_output=True, text=True, check=True)
    changed.update(line.strip() for line in result.stdout.splitlines() if line.strip())
    return sorted(changed)


def select_targets(root: Path, config: dict, paths: list[str], *, changed: bool, mutate_all: bool) -> list[Path]:
    if mutate_all and (not paths or changed):
        raise ValueError("显式全量 mutation 必须指定业务文件")
    if not paths:
        changed = True
    if changed:
        paths = _changed_lua(root, config)
    owned = set()
    for directory in config["sources"]["roots"]:
        for path in (root / directory).rglob("*.lua"):
            relative = path.relative_to(root).as_posix()
            parts = path.relative_to(root).parts
            excluded = config["sources"]["exclude"]
            if any(rule in parts or relative.startswith(rule.rstrip("/") + "/") for rule in excluded):
                continue
            owned.add(relative)
    selected = []
    for name in paths:
        path = (root / name).resolve()
        try:
            relative = path.relative_to(root.resolve()).as_posix()
        except ValueError:
            raise ValueError(f"mutation 目标超出项目：{name}") from None
        if relative not in owned or not path.is_file():
            if changed:
                continue
            raise ValueError(f"mutation 仅允许指定配置范围内的业务 Lua 文件：{name}")
        selected.append(path)
    return sorted(set(selected))


def _same_snapshot(source: Path, destination: Path) -> bool:
    if not destination.is_file():
        return False
    from mutator.edn import loads
    fresh = loads(source.read_text(encoding="utf-8"))
    current = loads(destination.read_text(encoding="utf-8"))
    fresh.pop("tested-at", None)
    current.pop("tested-at", None)
    return fresh == current


def _publish(root: Path, config: dict, staged: Path) -> None:
    destination_root = root / config["paths"]["mutation"]
    for source in staged.rglob("*.edn"):
        destination = destination_root / source.relative_to(staged)
        if _same_snapshot(source, destination):
            continue
        destination.parent.mkdir(parents=True, exist_ok=True)
        temporary = destination.with_name(destination.name + ".pending")
        temporary.write_bytes(source.read_bytes())
        os.replace(temporary, destination)


def _validate_tree(directory: Path, label: str) -> None:
    from mutator.edn import loads
    from mutator.functions import mutation_file
    for path in directory.rglob("*.edn"):
        try:
            data = loads(path.read_text(encoding="utf-8"))
        except ValueError as error:
            raise ValueError(f"{label} mutation 快照损坏：{path}（{error}）") from None
        if not isinstance(data, dict) or not isinstance(data.get("namespace"), str) or not isinstance(data.get("forms"), list):
            raise ValueError(f"{label} mutation 快照损坏：{path}")
        outcomes = data.get("outcomes", {})
        if not isinstance(outcomes, dict):
            raise ValueError(f"{label} mutation outcomes 损坏：{path}")
        for mutation, status in outcomes.items():
            if mutation_file(mutation) is None or status not in {"killed", "survived", ":killed", ":survived"}:
                raise ValueError(f"{label} mutation outcomes 不完整：{path}")
        for form in data["forms"]:
            counts = [form.get(key) for key in ("killed", "survived", "uncovered", "sites")]
            if (not isinstance(form.get("id"), str) or not isinstance(form.get("file"), str)
                    or not all(isinstance(value, int) and value >= 0 for value in counts)
                    or sum(counts[:3]) != counts[3]):
                raise ValueError(f"{label} mutation 快照不完整：{path}")


def _validate(root: Path, config: dict, label: str = "当前") -> None:
    _validate_tree(root / config["paths"]["mutation"], label)


def report(root: Path, config: dict) -> int:
    from mutator.edn import loads
    _validate(root, config)
    totals = {key: 0 for key in ("killed", "survived", "uncovered", "sites")}
    for path in (root / config["paths"]["mutation"]).rglob("*.edn"):
        for form in loads(path.read_text(encoding="utf-8"))["forms"]:
            for key in totals:
                totals[key] += form[key]
    print("mutation 快照：" + ", ".join(f"{key}={value}" for key, value in totals.items()))
    return 0


def run(root: Path, config: dict, config_path: Path | str, paths: list[str], *, mutate_all: bool = False,
        changed: bool = False, max_workers: int | None = None,
        lines: set[int] | None = None, verbose: bool = False) -> int:
    targets = select_targets(root, config, paths, changed=changed, mutate_all=mutate_all)
    if not targets:
        print("没有选中的业务 Lua 文件；mutation 未运行")
        return 0
    from mutator.runner import CommandRunner
    import windows_adapter
    windows_adapter.install()
    class ProjectRunner(CommandRunner):
        def run(self, command, cwd, timeout):
            result = super().run(command, cwd, timeout)
            if result.code == 127:
                raise RuntimeError(f"测试命令无法启动：{result.output}")
            return result

    command = config["commands"]["mutation_test"]
    if not isinstance(command, list) or not command:
        raise ValueError("项目测试命令必须是非空 argv")
    _validate(root, config)
    command_cwd = _test_command(root, command)
    coverage = subprocess.run([sys.executable, "-B", str(Path(__file__).parent / "project.py"),
                               "--root", str(root), "--config", str(config_path), "coverage"], cwd=root)
    if coverage.returncode:
        return 2
    original = {path: path.read_bytes() for path in targets}
    staging_parent = root / "target/mutation-staging"
    staging_parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="run-", dir=staging_parent) as directory:
        staging_root = Path(directory)
        staging_metrics = staging_root / ".metrics/mutate"
        source_metrics = root / config["paths"]["mutation"]
        if source_metrics.is_dir():
            shutil.copytree(source_metrics, staging_metrics)
        else:
            staging_metrics.mkdir(parents=True)
        from mutator import metrics as upstream_metrics
        original_edn_files = upstream_metrics._edn_files
        original_snapshot_path = upstream_metrics.snapshot_path
        original_remove_empty = upstream_metrics._remove_empty_dirs
        upstream_metrics._edn_files = lambda _root: sorted(path for path in staging_metrics.rglob("*.edn") if path.is_file())
        upstream_metrics.snapshot_path = lambda root, namespace: staging_metrics.joinpath(*namespace.replace("\\", "/").replace("::", "/").split("/")[:-1], namespace.replace("\\", "/").replace("::", "/").split("/")[-1] + ".edn")
        upstream_metrics._remove_empty_dirs = lambda directory: None
        try:
            _validate_tree(staging_metrics, "暂存")
            baseline = ProjectRunner(verbose=verbose).run(command_cwd, root, None)
            if baseline.code != 0:
                print(f"mutation 基线测试失败（退出码 {baseline.code}）\n{baseline.output}", file=sys.stderr)
                return 2
            print("完整 LuaUnit 基线通过；mutation 使用既有完整覆盖率做差分")
            from mutator.engine import mutate_file
            from mutator.coverage import covered_lines
            from mutator.report import format_decisions, format_results
            forms, written, baselines, results = [], [], {}, []
            code = 0
            for target in targets:
                result = mutate_file(target, root, runner=ProjectRunner(verbose=verbose),
                                     covered_lines=covered_lines(root, target, "lua"),
                                     ignore_coverage=False, mutate_all=mutate_all,
                                     lines=lines, test_command=command_cwd, timeout_factor=10.0,
                                     mutation_warning=50, baselines=baselines, max_workers=max_workers)
                if result.baseline_failed:
                    print(result.baseline_message, file=sys.stderr)
                    return 2
                results.append(result)
                forms.extend(result.forms)
                written.extend(result.written)
                if any(form.survived for form in result.forms):
                    code = 3
            print(format_results(forms))
            _validate_tree(staging_metrics, "暂存")
            if any(path.read_bytes() != content for path, content in original.items()):
                raise RuntimeError("mutation 改动了原始业务源码")
            if code in {0, 3}:
                _publish(root, config, staging_metrics)
                _validate(root, config, "发布")
                print(format_decisions(results, verbose=verbose), end="")
                print("mutation 有效快照已保留；存活和未覆盖表示测试缺口")
            return code
        except Exception as exc:
            print(f"mutation 基础设施失败：{exc}", file=sys.stderr)
            return 1
        finally:
            upstream_metrics._edn_files = original_edn_files
            upstream_metrics.snapshot_path = original_snapshot_path
            upstream_metrics._remove_empty_dirs = original_remove_empty
            for path, content in original.items():
                if path.read_bytes() != content:
                    path.write_bytes(content)

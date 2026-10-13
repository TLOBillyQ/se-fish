"""项目 mutation：限定业务范围，并保护失败前的有效快照。"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

# 固定实际导入来源；公开入口和旧兼容入口使用同一 checkout。
_TOOL_ROOT = Path(__file__).resolve().parents[2] / ".uml-viewer"
sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(_TOOL_ROOT / "mutator/src"))
sys.path.insert(0, str(_TOOL_ROOT / "crapper/src"))

# 正式 mutation 的默认墙钟预算与默认单 worker（#98 AC3）：默认不占满逻辑核心，
# 需要更多 worker 或更长预算时由调用方显式给出并记录依据。
DEFAULT_BUDGET_SECONDS = 3600.0
DEFAULT_MAX_WORKERS = 1
LOG_DIRECTORY = "target/mutation-logs"
_BUDGET_POLICY = "在目标边界提前退出，记录未运行范围，退出码 4"
_RECOVERY = ("超预算后用同一命令重跑，未变化的输入按 .metrics/mutate 历史复用；"
             "发布回滚材料保留在 target/mutation-publication/publish-*；"
             "运行期间源码被外部保存或删除时停止发布并保留外部编辑")


def _now() -> float:
    return time.monotonic()


def _joined(command: list) -> str:
    return " ".join(f'"{item}"' if " " in str(item) else str(item) for item in command)


def _scope_label(*, mutate_all: bool, changed: bool, paths: list[str]) -> str:
    if mutate_all:
        return "显式全量"
    if changed or not paths:
        return "git 差分"
    return "显式指定"


def _log_path() -> str:
    return f"{LOG_DIRECTORY}/mutation-{time.strftime('%Y%m%d-%H%M%S')}.log"


def _capture_command(root: Path, invocation: list[str] | None) -> str:
    """还原可复制的公开入口调用；本工具不自动写日志文件。"""
    if not invocation:
        return ""
    entry = (Path(root) / "tools/quality/project.ps1").as_posix()
    return _joined(["pwsh", "-NoProfile", "-File", entry, *invocation])


def budget_record(root: Path, *, completed: int, skipped: list[Path], elapsed: float,
                  budget_seconds: float) -> str:
    """超预算记录：明确未覆盖范围，让调用方区分「全部完成」与「提前退出」。"""
    names = "、".join(path.relative_to(root).as_posix() for path in skipped)
    return "\n".join([
        f"mutation 超预算提前退出：已完成 {completed}/{completed + len(skipped)} 个目标",
        f"  已用 {elapsed:.1f} 秒 / 预算 {budget_seconds:g} 秒",
        f"  未运行 ({len(skipped)} 个): {names}",
        "  只覆盖已完成目标，不作为全树或全范围证明；退出码 4。",
    ])


def launch_record(root: Path, config: dict, *, scope: str, targets: list[Path],
                  max_workers: int, budget_seconds: float,
                  invocation: list[str] | None = None) -> str:
    """启动前记录：可复制到日志头，覆盖基准、范围、worker、预算、日志与恢复方式。"""
    names = "、".join(path.relative_to(root).as_posix() for path in targets)
    log = _log_path()
    lines = [
        "mutation 启动前记录（复制到日志头）",
        f"基准: {_joined(config['commands']['mutation_test'])}",
        f"范围: {scope} {len(targets)} 个文件：{names}",
        f"worker: {max_workers}",
        f"时间预算: {budget_seconds:g} 秒；超预算策略: {_BUDGET_POLICY}",
        f"日志: {log}",
    ]
    capture = _capture_command(root, invocation)
    if capture:
        lines.append(f"采集: {capture} *> {log}")
    lines.append(f"恢复: {_RECOVERY}")
    lines.append("mutation 启动前记录结束")
    return "\n".join(lines)


def _test_command(root: Path, command: list) -> list:
    """Worker 直接运行项目 argv，mutator 会把 cwd 映射到 overlay。"""
    return command


def _changed_lua(root: Path, config: dict) -> list[str]:
    result = subprocess.run(["git", "diff", "--name-only", "--diff-filter=d", "--", *config["sources"]["roots"]],
                            cwd=root, capture_output=True, text=True, check=True)
    changed = {line.strip() for line in result.stdout.splitlines() if line.strip()}
    result = subprocess.run(["git", "diff", "--cached", "--name-only", "--diff-filter=d", "--", *config["sources"]["roots"]],
                            cwd=root, capture_output=True, text=True, check=True)
    changed.update(line.strip() for line in result.stdout.splitlines() if line.strip())
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
    from project import source_files
    owned = set(source_files(root, config))
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


def _publish(root: Path, config: dict, staged: Path, *, changed: set[Path], removed: set[Path]) -> None:
    destination_root = root / config["paths"]["mutation"]
    _validate_tree(staged, "暂存")
    destination_root.mkdir(parents=True, exist_ok=True)
    # 先准备全部新文件，再将旧路径可逆迁入备份；占用失败发生在发布前。
    publication = root / "target/mutation-publication"
    publication.mkdir(parents=True, exist_ok=True)
    transaction = Path(tempfile.mkdtemp(prefix="publish-", dir=publication))
    prepared, backed_up, published = [], [], []
    preserve = False
    try:
        for relative in sorted(changed):
            source = staged / relative
            destination = destination_root / relative
            if source.is_file() and not _same_snapshot(source, destination):
                fresh = transaction / "new" / relative
                fresh.parent.mkdir(parents=True, exist_ok=True)
                fresh.write_bytes(source.read_bytes())
                prepared.append(relative)
        affected = set(prepared) | removed
        for relative in sorted(affected):
            destination = destination_root / relative
            if destination.is_file():
                backup = transaction / "old" / relative
                backup.parent.mkdir(parents=True, exist_ok=True)
                os.replace(destination, backup)
                backed_up.append(relative)
        for relative in prepared:
            destination = destination_root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            os.replace(transaction / "new" / relative, destination)
            published.append(relative)
        _validate(root, config, "发布")
    except Exception as error:
        try:
            for relative in reversed(published):
                (destination_root / relative).unlink()
            for relative in reversed(backed_up):
                os.replace(transaction / "old" / relative, destination_root / relative)
        except OSError as recovery:
            preserve = True
            raise RuntimeError(f"发布失败：{error}；回滚失败：{recovery}；恢复材料保留在 {transaction}") from error
        raise
    finally:
        if not preserve:
            shutil.rmtree(transaction)


def _snapshot_path(directory: Path, namespace: str) -> Path:
    """历史输入和上游写入共用 namespace 边界。"""
    parts = namespace.replace("\\", "/").replace("::", "/").split("/")
    if any(part in {"", ".", ".."} or ":" in part for part in parts):
        raise ValueError(f"mutation namespace 路径无效：{namespace!r}")
    path = directory.joinpath(*parts[:-1], parts[-1] + ".edn")
    try:
        path.resolve().relative_to(directory.resolve())
    except ValueError:
        raise ValueError(f"mutation namespace 解析路径超出指标根：{namespace!r}") from None
    return path


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
        _snapshot_path(directory, data["namespace"])
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


def _source_change(original: dict[Path, bytes]) -> str | None:
    for path, content in original.items():
        if not path.is_file():
            return f"mutation 原始源码被删除，停止发布并保留外部编辑：{path}"
        if path.read_bytes() != content:
            return f"mutation 原始源码已变化，停止发布并保留外部编辑：{path}"
    return None


def run(root: Path, config: dict, config_path: Path | str, paths: list[str], *, mutate_all: bool = False,
        changed: bool = False, max_workers: int | None = None,
        lines: set[int] | None = None, verbose: bool = False,
        budget_seconds: float = DEFAULT_BUDGET_SECONDS,
        invocation: list[str] | None = None) -> int:
    scope = _scope_label(mutate_all=mutate_all, changed=changed, paths=paths)
    targets = select_targets(root, config, paths, changed=changed, mutate_all=mutate_all)
    original = {path: path.read_bytes() for path in targets}
    try:
        return _run(root, config, targets, original=original, mutate_all=mutate_all,
                    max_workers=max_workers, lines=lines, verbose=verbose,
                    scope=scope, budget_seconds=budget_seconds, invocation=invocation)
    finally:
        # 附带报告变化，不抛新异常，保留原测试输出、异常与退出码。
        try:
            reason = _source_change(original)
        except OSError as error:
            reason = f"mutation 原始源码无法核对，保留原失败与外部编辑：{error}"
        if reason:
            print(reason, file=sys.stderr)


def _run(root: Path, config: dict, targets: list[Path], *, original: dict[Path, bytes],
         mutate_all: bool = False, max_workers: int | None = None,
         lines: set[int] | None = None, verbose: bool = False,
         scope: str = "显式指定", budget_seconds: float = DEFAULT_BUDGET_SECONDS,
         invocation: list[str] | None = None) -> int:
    if not targets:
        print("没有选中的业务 Lua 文件；mutation 未运行")
        return 0
    if max_workers is None:
        max_workers = DEFAULT_MAX_WORKERS
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
    publication = root / "target/mutation-publication"
    if publication.is_dir() and any(publication.iterdir()):
        raise RuntimeError(f"存在未完成发布的恢复材料，停止覆盖：{publication}")
    command_cwd = _test_command(root, command)
    # 预算覆盖整条命令：覆盖率与基线属于前置步骤，边界检查发生在目标之间。
    started = _now()
    deadline = started + budget_seconds
    print(launch_record(root, config, scope=scope, targets=targets,
                        max_workers=max_workers, budget_seconds=budget_seconds,
                        invocation=invocation))
    from project import run_coverage
    if run_coverage(root, config):
        return 2
    reason = _source_change(original)
    if reason:
        raise RuntimeError(reason)
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
        # 上游历史由项目公开快照提供，历史读取/写入一致，失败不会重写无关文件。
        from mutator import metrics as upstream_metrics
        original_edn_files = upstream_metrics._edn_files
        original_snapshot_path = upstream_metrics.snapshot_path
        original_remove_empty = upstream_metrics._remove_empty_dirs
        upstream_metrics._edn_files = lambda _root: sorted(path for path in staging_metrics.rglob("*.edn") if path.is_file())
        upstream_metrics.snapshot_path = lambda root, namespace: _snapshot_path(staging_metrics, namespace)
        upstream_metrics._remove_empty_dirs = lambda directory: None
        initial_files = {path.relative_to(staging_metrics) for path in staging_metrics.rglob("*.edn")}
        try:
            _validate_tree(staging_metrics, "暂存")
            baseline = ProjectRunner(verbose=verbose).run(command_cwd, root, None)
            if baseline.code != 0:
                print(f"mutation 基线测试失败（退出码 {baseline.code}）\n{baseline.output}", file=sys.stderr)
                return 2
            print("完整 Busted 基线通过；mutation 使用既有完整覆盖率做差分")
            from mutator.engine import mutate_file
            from mutator.coverage import covered_lines
            from mutator.report import format_decisions, format_results
            forms, results = [], []
            baselines = {}
            code = 0
            skipped = []
            for index, target in enumerate(targets):
                # 断点只有工具内部知道：预算在目标边界检查，才能记录未运行范围。
                if _now() >= deadline:
                    skipped = targets[index:]
                    break
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
                if any(form.survived for form in result.forms):
                    code = 3
            if skipped:
                # 部分结果不构成全树证明：已完成范围照常发布，调用方按 4 判定未完成。
                code = 4
                print(budget_record(root, completed=len(targets) - len(skipped), skipped=skipped,
                                    elapsed=_now() - started, budget_seconds=budget_seconds))
            print(format_results(forms))
            _validate_tree(staging_metrics, "暂存")
            reason = _source_change(original)
            if reason:
                raise RuntimeError(reason)
            if code in {0, 3, 4}:
                final_files = {path.relative_to(staging_metrics) for path in staging_metrics.rglob("*.edn")}
                _publish(root, config, staging_metrics, changed=final_files, removed=initial_files - final_files)
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

"""原生 Windows 运行时适配：复制 overlay，并正确终止超时进程树。"""

from __future__ import annotations

import os
import shutil
import stat
import subprocess
import sys
import time
from pathlib import Path


def _copy_or_link(link: Path, target: Path) -> None:
    link.parent.mkdir(parents=True, exist_ok=True)
    if link.is_symlink() or link.exists():
        if link.is_dir() and not link.is_symlink():
            shutil.rmtree(link)
        else:
            link.unlink()
    resolved = target.resolve()
    if resolved.is_dir():
        # copyfile 不复制只读位，避免 .git pack 文件删不掉
        shutil.copytree(resolved, link, symlinks=False, copy_function=shutil.copyfile)
    else:
        shutil.copyfile(resolved, link)


def _copy_once(link: Path, target: Path, cache: dict[Path, Path]) -> None:
    resolved = target.resolve()
    cached = cache.get(resolved)
    if cached is None:
        cache[resolved] = link
        _copy_or_link(link, resolved)
        return
    # 当前 worker 已复制过该源文件：从缓存副本再复制一份。
    link.parent.mkdir(parents=True, exist_ok=True)
    if link.exists() or link.is_symlink():
        if link.is_dir() and not link.is_symlink():
            shutil.rmtree(link)
        else:
            link.unlink()
    if resolved.is_dir():
        shutil.copytree(cached, link, symlinks=False, copy_function=shutil.copyfile)
    else:
        shutil.copyfile(cached, link)


# mutator 的独立 venv 不安装兄弟工具；先加入同仓 crapper 的源码路径。
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / '.uml-viewer' / 'crapper' / 'src'))


def install() -> None:
    from mutator import runner, workers

    def link_or_copy(link: Path, target: Path) -> None:
        _copy_or_link(link, target)

    def run(self, command: str, cwd: Path, timeout: float | None) -> runner.CommandResult:
        if self.verbose:
            print(f"+ ({cwd}) {command}", file=sys.stderr)
        started = time.monotonic()
        environment = runner.os.environ.copy()
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        runner._prefer_worker_sources(cwd, environment)
        process = subprocess.Popen(
            command,
            cwd=cwd,
            shell=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            env=environment,
        )
        try:
            output, _err = process.communicate(timeout=timeout)
            code = process.returncode if process.returncode is not None else 1
            timed_out = False
        except subprocess.TimeoutExpired:
            subprocess.run(
                ["taskkill", "/F", "/T", "/PID", str(process.pid)],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
            output, _err = process.communicate()
            code = 124
            timed_out = True
        seconds = time.monotonic() - started
        return runner.CommandResult(code=code, timed_out=timed_out, seconds=seconds, output=output or "")

    workers.symlink = link_or_copy
    runner.CommandRunner.run = run

    def delete_tree(path: Path) -> None:
        """复制树删除：先清只读位（Windows 上 unlink 只读文件会拒绝访问）。"""
        if path.is_symlink():
            path.unlink()
            return
        if not path.exists():
            return
        if path.is_dir():
            for child in list(path.iterdir()):
                delete_tree(child)
            path.rmdir()
            return
        os.chmod(path, stat.S_IWRITE | stat.S_IREAD)
        path.unlink()

    workers.delete_tree = delete_tree
    # `mutate_file` 用 `covered_lines` 调用 `test_plan`，随后调用 `run_mutants`；
    # 替换 worker 创建函数，使每个 overlay 都使用副本，且每个源文件在每个 worker 中
    # 只复制一次，即使递归遍历导入关系时沿多条导入链访问同一文件。
    original_create_workers = workers.create_workers

    def create_workers(base: Path, root: Path, relative: str, original: bytes, count: int):
        copied: dict[Path, Path] = {}
        previous = workers.symlink
        workers.symlink = lambda link, target: _copy_once(link, target, copied)
        try:
            return original_create_workers(base, root, relative, original, count)
        finally:
            workers.symlink = previous

    workers.create_workers = create_workers

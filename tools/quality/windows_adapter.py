"""Windows worker 复制回退；保留上游 argv runner 与进程树清理。"""
from __future__ import annotations

import os
import shutil
from pathlib import Path


def _copy(link: Path, target: Path) -> None:
    link.parent.mkdir(parents=True, exist_ok=True)
    if target.is_dir():
        shutil.copytree(target.resolve(), link, copy_function=shutil.copyfile,
                        ignore=shutil.ignore_patterns(".git", "__pycache__", ".venv", ".uml-viewer", ".toolcache"))
    else:
        shutil.copyfile(target.resolve(), link)


def _copy_importer(worker: Path, root: Path, relative: str) -> None:
    from mutator import workers
    real = root
    current = worker
    for segment in relative.split("/")[:-1]:
        real = real / segment
        current = current / segment
        if current.is_symlink():
            workers._expand_directory(current, real)
        else:
            current.mkdir(parents=True, exist_ok=True)
        workers._link_children(current, real, set())
    destination = worker / relative
    if destination.is_symlink():
        destination.unlink()
    elif destination.exists():
        return
    destination.write_bytes((root / relative).read_bytes())


def _overlay(worker: Path, root: Path, relative: str, original: bytes) -> None:
    from mutator import workers
    segments = relative.split("/")
    # 路径上的目录独立建立，每一级兄弟均沿用上游链接/Windows 复制回退。
    for index in range(len(segments) - 1):
        relative_dir = Path(*segments[:index + 1])
        (worker / relative_dir).mkdir(parents=True, exist_ok=True)
        workers._link_children(worker / relative_dir, root / relative_dir, {segments[index + 1]})
    destination = worker / relative
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(original)


def install() -> None:
    from mutator import workers
    # 工具 checkout 和依赖缓存不属于 LuaUnit worker，复制它们会造成巨大开销。
    workers.SKIP_LINK = workers.SKIP_LINK | {".uml-viewer", ".toolcache"}
    # 被变异文件必须始终作为独立副本进入 worker；目录 symlink 会写回真实源码。
    workers._copy_importer = _copy_importer
    workers._overlay = _overlay
    if os.name == "nt":
        # 不要求开发者启用 Windows 开发模式或管理员 symlink 权限。
        workers.symlink = _copy

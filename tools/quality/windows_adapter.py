"""Windows worker 复制回退；保留上游 argv runner 与进程树清理。"""
from __future__ import annotations

import os
import shutil
from pathlib import Path


def _copy(link: Path, target: Path) -> None:
    link.parent.mkdir(parents=True, exist_ok=True)
    if target.is_dir():
        shutil.copytree(target.resolve(), link, copy_function=shutil.copyfile,
                        ignore=shutil.ignore_patterns(".git", "__pycache__", ".venv"))
    else:
        shutil.copyfile(target.resolve(), link)


def _copy_importer(worker: Path, root: Path, relative: str) -> None:
    current = worker
    for segment in relative.split("/")[:-1]:
        current = current / segment
        current.mkdir(parents=True, exist_ok=True)
    destination = worker / relative
    if not destination.exists():
        destination.write_bytes((root / relative).read_bytes())


def _overlay(worker: Path, root: Path, relative: str, original: bytes) -> None:
    destination = worker / relative
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(original)
    # 被变异文件保持独立副本；仅补同目录 Lua 依赖，避免展开工具或构建目录。
    for source in (root / relative).parent.iterdir():
        if source.suffix != ".lua":
            continue
        copy = destination.parent / source.name
        if source.is_file() and not copy.exists():
            _copy_importer(worker, root, (root / relative).parent.relative_to(root).joinpath(source.name).as_posix())


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

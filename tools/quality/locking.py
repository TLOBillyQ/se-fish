"""同仓库质量请求的进程级互斥；句柄关闭（包括异常退出）自动释放。"""
from contextlib import contextmanager
from pathlib import Path
import os


@contextmanager
def repository_lock(root):
    path = Path(root).resolve() / 'target/quality.lock'
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('a+b') as stream:
        stream.seek(0)
        if os.name == 'nt':
            import msvcrt
            try:
                msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
            except OSError:
                raise RuntimeError('同仓库质量任务正在运行，请稍后重试。') from None
        else:
            import fcntl
            try:
                fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise RuntimeError('同仓库质量任务正在运行，请稍后重试。') from None
        try:
            yield
        finally:
            stream.seek(0)
            if os.name == 'nt':
                msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                fcntl.flock(stream, fcntl.LOCK_UN)

"""启动 mutator 前先安装原生 Windows 运行时适配。"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import windows_adapter  # noqa: E402
import mutator.cli  # noqa: E402

windows_adapter.install()
sys.exit(mutator.cli.main())

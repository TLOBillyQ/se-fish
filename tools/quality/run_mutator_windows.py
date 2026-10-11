"""兼容旧 Windows 命令，转入项目质量入口与统一配置。"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

if __name__ == "__main__":
    entry = Path(__file__).resolve().parent / "project.py"
    sys.exit(subprocess.run([sys.executable, "-B", str(entry), "mutation", *sys.argv[1:]]).returncode)

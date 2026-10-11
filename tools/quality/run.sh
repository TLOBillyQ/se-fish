#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
# 兼容旧 Bash 入口，完整质量流程统一由项目配置分发。
exec .uml-viewer/crapper/.venv/Scripts/python.exe tools/quality/project.py run "$@"

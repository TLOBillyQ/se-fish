#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
pwsh -NoProfile -File tools/quality/project.ps1 mutation "$@"

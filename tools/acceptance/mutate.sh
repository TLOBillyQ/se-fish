#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
LUA="${ACCEPTANCE_LUA_BIN:-lua}"
if ! command -v "$LUA" >/dev/null 2>&1; then
  echo "找不到 lua 解释器：$LUA" >&2
  exit 1
fi
case "$("$LUA" -v 2>&1)" in
  *5.4*) ;;
  *) echo "变异车道需要 Lua 5.4" >&2; exit 1 ;;
esac
export ACCEPTANCE_LUA_BIN="$LUA"
work_dir="build/acceptance/mutation"
mkdir -p "$work_dir"
rm -f "$work_dir/report.json"
if ! ACCEPTANCE_STRICT_TOOLS=1 bash tools/acceptance/run_acceptance.sh > "$work_dir/baseline.txt" 2>&1; then
  echo "基线验收失败：$work_dir/baseline.txt" >&2
  exit 1
fi
cp features/engineering/deploy-mirror.feature "$work_dir/deploy-mirror.feature"
PWD=. TMPDIR="$work_dir" "$LUA" tools/acceptance/cli/mutation.lua

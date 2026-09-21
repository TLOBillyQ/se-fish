#!/usr/bin/env bash
# 钓鱼图的 acceptance 入口：parse → dry-check（advisory）→ generate → run，一条命令跑完。
# 在任意目录执行；脚本自己 cd 到仓库根。
#
# 需要 PATH 里的 lua（5.4，本机命令名就是 lua；可用 ACCEPTANCE_LUA_BIN 覆盖）；
# acceptance4lua 由 tools/acceptance/bootstrap.lua 首次运行时 clone 进 .toolcache/，
# 不走 luarocks、不依赖 WSL。步骤处理器只查仓库与 tmp/ 下的临时工作区，不启动对局；
# 见 tools/acceptance/README.md。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

LUA="${ACCEPTANCE_LUA_BIN:-lua}"
if ! command -v "$LUA" >/dev/null 2>&1; then
  echo "找不到 lua 解释器（PATH 里没有 $LUA）；用 ACCEPTANCE_LUA_BIN 指一个" >&2
  exit 1
fi
LUA_VERSION="$("$LUA" -v 2>&1 | head -1)"
case "$LUA_VERSION" in
  *5.4*) ;;
  *) echo "acceptance 需要 Lua 5.4，$LUA 报的是: $LUA_VERSION" >&2; exit 1 ;;
esac
export ACCEPTANCE_LUA_BIN="$LUA"

GEN_DIR="build/acceptance/generated"
IR_DIR="build/acceptance/ir"
DRY_DIR="build/acceptance/dry"
# 先清生成的 spec：改过名的 feature 会留下旧 stem，不清就会一直跑着过期的用例。
rm -rf "$GEN_DIR"
mkdir -p "$GEN_DIR" "$IR_DIR" "$DRY_DIR"

shopt -s nullglob
# 扫每一条车道子目录，外加 features/ 下的裸 feature；stem 带车道名，同名文件不会撞。
features=(features/*.feature features/*/*.feature)
if [ "${#features[@]}" -eq 0 ]; then
  echo "features/ 下没有 feature 文件" >&2
  exit 1
fi

LUA_PATH_FOR_SPECS="$("$LUA" -e 'package.path="./?.lua;"..package.path; io.write(require("tools.acceptance.bootstrap").lua_path())')"

fail=0
for feature in "${features[@]}"; do
  echo "== $feature"
  stem="$(echo "${feature#features/}" | sed 's|/|_|g; s|\.feature$||')"
  tools/acceptance/gherkin-parser "$feature" "$IR_DIR/$stem.json"
  tools/acceptance/ir-dry-checker "$IR_DIR/$stem.json" "$DRY_DIR/$stem.json" || true
  mkdir -p "$GEN_DIR/$stem"
  tools/acceptance/entrypoint_generator "$IR_DIR/$stem.json" "$GEN_DIR/$stem/feature_acceptance_spec.lua"
  if ! ACCEPTANCE_FEATURE_JSON="$IR_DIR/$stem.json" LUA_PATH="$LUA_PATH_FOR_SPECS" \
       "$LUA" "$GEN_DIR/$stem/feature_acceptance_spec.lua"; then
    echo "FAILED: $feature" >&2
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "acceptance run FAILED" >&2
  exit 1
fi
echo "acceptance run OK"

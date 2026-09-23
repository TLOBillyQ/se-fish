#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
bash tools/quality/deps.sh
lua tools/quality/bootstrap.lua mutate4lua
mkdir -p build/quality/mutation/project/common build/quality/mutation/project/tests/lib
cp common/RateLimit.lua common/GameCfg.lua build/quality/mutation/project/common/
cp tests/rate_limit_test.lua tests/run.lua build/quality/mutation/project/tests/
cp tests/lib/luaunit.lua build/quality/mutation/project/tests/lib/
before="$(sha256sum common/RateLimit.lua | cut -d ' ' -f1)"
ROOT="$(pwd -W | tr '\\' '/')"
export LUA_PATH="$ROOT/.toolcache/mutate4lua/src/?.lua;$ROOT/.toolcache/mutate4lua/src/?/init.lua;$ROOT/.toolcache/luacheck/src/?.lua;$ROOT/.toolcache/luacheck/src/?/init.lua;$ROOT/.toolcache/argparse/src/?.lua;$ROOT/.toolcache/luacov/src/?.lua;$ROOT/.toolcache/luacov/src/?/init.lua;$ROOT/.toolcache/datafile/?.lua;$ROOT/tests/lib/?.lua;./?.lua;./?/init.lua;;"
export LUA_CPATH="$ROOT/.toolcache/luafilesystem/?.dll;;"
export SE_FISH_ROOT="$ROOT"
export SE_FISH_BASH="$(cygpath -m "$(command -v bash)")"
cd build/quality/mutation/project
set +e
lua ../../../../tools/quality/mutate.lua common/RateLimit.lua --max-workers 1 --test-command 'lua tests/run.lua' > ../mutate.txt 2>&1
code=$?
set -e
if [ "$before" != "$(sha256sum "$ROOT/common/RateLimit.lua" | cut -d ' ' -f1)" ]; then
  echo "原始源码在变异期间发生变化" >&2
  exit 1
fi
lua ../../../../tools/quality/mutation_report.lua "$code"

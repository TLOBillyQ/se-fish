#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
bash tools/quality/deps.sh
for tool in acceptance4lua crap4lua dry4lua mutate4lua; do
  lua tools/quality/bootstrap.lua "$tool"
done
export LUA_PATH=".toolcache/crap4lua/src/?.lua;.toolcache/crap4lua/src/?/init.lua;.toolcache/dry4lua/src/?.lua;.toolcache/dry4lua/src/?/init.lua;.toolcache/luacheck/src/?.lua;.toolcache/luacheck/src/?/init.lua;.toolcache/argparse/src/?.lua;.toolcache/luacov/src/?.lua;.toolcache/luacov/src/?/init.lua;.toolcache/datafile/?.lua;tests/lib/?.lua;./?.lua;./?/init.lua;;"
export LUA_CPATH=".toolcache/luafilesystem/?.dll;;"
lua -e 'assert(require("luacheck")); assert(require("lfs")); assert(require("luacov")); assert(require("argparse")); assert(require("datafile"))'
ACCEPTANCE_STRICT_TOOLS=1 bash tools/acceptance/run_acceptance.sh
mkdir -p build/quality
rm -f luacov.stats.out luacov.report.out build/quality/crap.json build/quality/dry.json
lua -lluacov tests/run.lua
lua -e 'require("luacov.reporter").report()'
test -s luacov.report.out
mv luacov.stats.out build/quality/luacov.stats.out
mv luacov.report.out build/quality/luacov.report.out
lua tools/quality/report.lua

#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p .toolcache
while read -r name url commit; do
  if [ ! -d ".toolcache/$name/.git" ]; then
    git clone "$url" ".toolcache/$name"
    git -C ".toolcache/$name" checkout --detach "$commit"
  fi
  actual="$(git -C ".toolcache/$name" rev-parse HEAD)"
  if [ "$actual" != "$commit" ]; then
    echo "$name 缓存提交不符：$actual，预期 $commit" >&2
    exit 1
  fi
done <<'PINS'
luacheck https://github.com/lunarmodules/luacheck.git cc089e3f65acdd1ef8716cc73a3eca24a6b845e4
luacov https://github.com/lunarmodules/luacov.git b1f9eae400da976b93edb7f94cf5d05f538a0655
luafilesystem https://github.com/lunarmodules/luafilesystem.git 7c6e1b013caec0602ca4796df3b1d7253a2dd258
argparse https://github.com/mpeterv/argparse.git 412e6aca393e365f92c0315dfe50181b193f1ace
datafile https://github.com/hishamhm/datafile.git 52e43ad0606dd0cfce2133cf23974bbf9c60877d
PINS
if [ ! -f .toolcache/luafilesystem/lfs.dll ]; then
  LUA_HOME="$(dirname "$(dirname "$(command -v lua)")")"
  gcc -shared -O2 -I"$LUA_HOME/include" -o .toolcache/luafilesystem/lfs.dll \
    .toolcache/luafilesystem/src/lfs.c -L"$LUA_HOME/bin" -llua54
fi

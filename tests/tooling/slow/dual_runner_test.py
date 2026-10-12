"""双 runner 聚合入口回归（#82）：命令选择、案例清单、退出码与覆盖率合并的轻量验证。

只跑 fast 车道的真实双段执行与一次合并统计（秒级），不触碰 full/slow 的长耗时集合；
真实 mutation 不在本票范围。
"""
import json
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


"""双 runner 聚合入口回归（#82）：命令选择、案例清单、退出码与覆盖率合并的轻量验证。

只跑 fast 车道的真实双段执行与一次合并统计（秒级），不触碰 full/slow 的长耗时集合；
覆盖率发布/快照保留用桩测试命令验证，不跑真实 mutation。
"""
import json
import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

# 桩聚合入口（真 lua 跑）：--fail 时退出 3 且不写合并统计；成功时写一份可解析的合并统计。
STUB_AGGREGATOR = r'''
if arg[2] == "--fail" then
  os.exit(3)
end
local f = assert(io.open("luacov.stats.out", "w"))
f:write("2:common/Stub.lua\n7 0 \n")
f:close()
os.exit(0)
'''

# 桩 Lua 解释器：响应 -v，并扮演 report_lcov.lua 写出 LCOV。
# 本用例只核对发布/快照语义（真实合并语义由 tests/tooling/coverage_merge_test.lua 与
# tests/tooling/slow/dual_runner_test.py 的真实双段执行覆盖），因此不依赖 .toolcache/luacov。
STUB_INTERPRETER = r'''
import sys
from pathlib import Path

argv = sys.argv[1:]
if argv and argv[0] == "-v":
    print("Lua 5.4.6  stub interpreter")
    sys.exit(0)
if any("report_lcov.lua" in item for item in argv):
    Path(argv[-1]).write_text("SF:common/Stub.lua\nDA:1,7\nDA:2,0\nLF:2\nLH:1\nend_of_record\n",
                              encoding="utf-8")
sys.exit(0)
'''


def _run(*argv):
    return subprocess.run(list(argv), cwd=ROOT, capture_output=True,
                          text=True, encoding="utf-8", errors="replace")


class CoveragePublicationTest(unittest.TestCase):
    """两段覆盖率：完整成功后才一次发布，失败保留原快照。"""

    def _make_root(self, directory, fail):
        root = Path(directory)
        (root / "build/quality").mkdir(parents=True, exist_ok=True)
        (root / "target/coverage/lua").mkdir(parents=True, exist_ok=True)
        (root / "stub-aggregator.lua").write_text(STUB_AGGREGATOR, encoding="utf-8")
        interpreter = root / "stub-interpreter.py"
        interpreter.write_text(STUB_INTERPRETER, encoding="utf-8")
        fake_lua = root / "fake-lua.bat"
        fake_lua.write_text(f'@echo off\r\n"{sys.executable}" "{interpreter}" %*\r\n', encoding="ascii")
        config = root / "project.json"
        config.write_text(json.dumps({
            "lua": {"executable": str(fake_lua), "version": "Lua 5.4."},
            "commands": {
                "coverage": ["lua", "stub-aggregator.lua", "full", "--fail" if fail else "--ok"],
                "mutation_test": ["lua", "stub-aggregator.lua", "fast"],
            },
            "paths": {"lcov": "target/coverage/lua/lcov.info",
                      "stats": "build/quality/luacov.stats.out",
                      "luacov": "unused-by-stub"},
        }), encoding="utf-8")
        return root, config

    def _quality(self, root, config):
        environment = os.environ.copy()
        # 测试命令里的 `lua` 用仓库当前 PATH 的真解释器跑桩聚合入口；报告脚本走 fake-lua.bat。
        environment["PATH"] = os.environ.get("PATH", "")
        environment.pop("LUA_PATH", None)
        environment.pop("LUA_CPATH", None)
        return subprocess.run([sys.executable, "-B", str(ROOT / "tools/quality/project.py"),
                               "--root", str(root), "--config", str(config), "coverage"],
                              cwd=root, capture_output=True, text=True,
                              encoding="utf-8", errors="replace", env=environment)

    def test_failed_run_keeps_previous_stats_snapshot(self):
        with tempfile.TemporaryDirectory(prefix="se-fish-dual-") as directory:
            root, config = self._make_root(directory, fail=True)
            stats = root / "build/quality/luacov.stats.out"
            previous = "2:common/Previous.lua\n5 5 \n"
            stats.write_text(previous, encoding="utf-8")
            result = self._quality(root, config)
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue(stats.is_file(), "测试命令失败后原统计快照被清掉")
            self.assertEqual(stats.read_text(encoding="utf-8"), previous)
            self.assertFalse((root / "target/coverage/lua/lcov.info").exists(),
                             "失败不得发布 LCOV")

    def test_successful_run_publishes_stats_once(self):
        with tempfile.TemporaryDirectory(prefix="se-fish-dual-") as directory:
            root, config = self._make_root(directory, fail=False)
            stats = root / "build/quality/luacov.stats.out"
            stats.write_text("2:common/Previous.lua\n5 5 \n", encoding="utf-8")
            (root / "target/coverage/lua/lcov.info").write_text("SF:common/Old.lua\nend_of_record\n",
                                                                encoding="utf-8")
            result = self._quality(root, config)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            body = stats.read_text(encoding="utf-8")
            self.assertIn("common/Stub.lua", body, "合并统计未发布到快照位置")
            self.assertNotIn("common/Previous.lua", body, "一次发布必须整份替换旧快照")
            self.assertFalse((root / "luacov.stats.out").exists(), "合并统计不得留在仓库根")


class DualRunnerCommandSelectionTest(unittest.TestCase):
    """project.json 的两条测试 argv 都经聚合入口分进程跑两套 runner。"""

    def setUp(self):
        self.config = json.loads((ROOT / "tools/quality/project.json").read_text(encoding="utf-8"))

    def test_coverage_argv_routes_both_runners_on_full(self):
        coverage = self.config["commands"]["coverage"]
        self.assertEqual(coverage[:3], ["lua", "tests/run_migration.lua", "full"])
        self.assertIn("--coverage", coverage, "覆盖率 argv 必须让聚合入口产出并合并两段统计")

    def test_mutation_test_argv_routes_both_runners_on_fast(self):
        mutation_test = self.config["commands"]["mutation_test"]
        self.assertEqual(mutation_test[:3], ["lua", "tests/run_migration.lua", "fast"])
        self.assertNotIn("--coverage", mutation_test, "fast 轻量 argv 不产统计")


class DualRunnerListTest(unittest.TestCase):
    """两套 runner 有明确案例清单：分段、full 含 slow、fast 排除 slow、Python 独立。"""

    def _list(self, lane):
        result = _run("lua", "tests/run_migration.lua", lane, "--list")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout

    def test_both_segments_are_listed(self):
        listed = self._list("full")
        self.assertIn("[legacy] full", listed)
        self.assertIn("[native] full", listed)

    def test_full_includes_slow_and_fast_excludes_it(self):
        full = self._list("full")
        # #92：tests/tooling/slow 的 Lua 案例已全部迁到 tests/native/slow（该目录只剩本文件这类
        # Python 回归），所以 slow 边界改由原生车道承担，旧侧必须彻底为空。
        self.assertIn("tests/native/slow/", full, "full 原生清单必须含 native/slow")
        self.assertNotIn("tests/tooling/slow/", full, "旧 slow 目录已迁空，full 清单不得再有它")
        fast = self._list("fast")
        for banned in ("tests/tooling/slow/", "tests/native/slow/"):
            self.assertNotIn(banned, fast, f"fast 清单不得含 slow：{banned}")

    def test_python_regression_never_listed(self):
        listed = self._list("full")
        self.assertNotIn("_test.py", listed, "Python 回归不得进 Lua 聚合清单")

    def test_unknown_lane_exits_nonzero_with_usage(self):
        result = _run("lua", "tests/run_migration.lua", "nonsense")
        self.assertEqual(result.returncode, 1)
        self.assertIn("fast", result.stderr)
        self.assertIn("full", result.stderr)


class DualRunnerFastExecutionTest(unittest.TestCase):
    """真实分进程执行：两段都跑、任一失败整体失败、空集合不误报。"""

    def test_aggregated_fast_runs_both_segments_successfully(self):
        result = _run("lua", "tests/run_migration.lua", "fast")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        # 口径（#82 遗留）：一行里两个数各标各的名字——「文件」是发现到的案例文件数，
        # 「案例」是该 runner 统计行报出的真实案例数。旧 bug 下「案例」印的就是文件数
        # （两数恒等），所以这里必须钉住「案例 > 文件」，任何回退都会红。
        legacy = re.search(r"legacy: (\d+) 文件 / (\d+) 案例 ok code=0", result.stdout)
        native = re.search(r"native: (\d+) 文件 / (\d+) 案例 ok code=0", result.stdout)
        self.assertIsNotNone(legacy, result.stdout)
        self.assertIsNotNone(native, result.stdout)
        for runner, match in (("legacy", legacy), ("native", native)):
            files, cases = int(match.group(1)), int(match.group(2))
            self.assertGreater(cases, files, f"{runner} 的案例数不得退化成文件数")
        # 案例数必须来自 runner 自己的统计行，不能是另算的一套口径。
        self.assertIn(f"Ran {legacy.group(2)} tests", result.stdout)
        self.assertIn(f"{native.group(2)} successes /", result.stdout)

    def test_merged_coverage_stats_sum_both_segments_without_wiping(self):
        for relative in ("luacov.stats.out", "build/quality/luacov-legacy.out",
                         "build/quality/luacov-native.out"):
            (ROOT / relative).unlink(missing_ok=True)
        result = _run("lua", "tests/run_migration.lua", "fast", "--coverage")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        merged = ROOT / "luacov.stats.out"
        legacy = ROOT / "build/quality/luacov-legacy.out"
        native = ROOT / "build/quality/luacov-native.out"
        for path in (merged, legacy, native):
            self.assertTrue(path.is_file() and path.stat().st_size > 0, f"缺少统计：{path}")
        self.assertIn("merge: ok", result.stdout)

        def hits(path, name):
            # luacov.stats 格式：<max>:<文件名>\n<逐行命中>
            lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
            for index, line in enumerate(lines):
                head, sep, filename = line.partition(":")
                if sep and head.isdigit() and filename.strip() == name:
                    return [int(x) for x in lines[index + 1].split()]
            return None

        # 两段都覆盖的共享模块：合并命中必须等于两段之和，任何一侧被清空都会在这里失败。
        # luacov 在 Windows 下用反斜杠键名（common\GameCfg.lua），两段一致才能按行相加。
        name = None
        for line in legacy.read_text(encoding="utf-8", errors="replace").splitlines():
            head, sep, filename = line.partition(":")
            if sep and head.isdigit() and filename.replace("\\", "/") == "common/GameCfg.lua":
                name = filename
                break
        self.assertIsNotNone(name, "旧段统计应包含 common/GameCfg.lua")
        self.assertIsNotNone(hits(native, name), "原生段统计应包含同一键名，否则两段不会相加而是各存一份")
        legacy_hits = hits(legacy, name)
        native_hits = hits(native, name)
        merged_hits = hits(merged, name)
        self.assertTrue(legacy_hits, "旧段统计没有该文件行数据")
        self.assertTrue(native_hits, "原生段统计没有该文件行数据")
        self.assertTrue(merged_hits, "合并统计没有该文件行数据")
        self.assertEqual(len(merged_hits), max(len(legacy_hits), len(native_hits)))
        nonzero = 0
        for index in range(len(merged_hits)):
            expected = (legacy_hits[index] if index < len(legacy_hits) else 0) + \
                       (native_hits[index] if index < len(native_hits) else 0)
            self.assertEqual(merged_hits[index], expected,
                             f"第 {index + 1} 行合并命中不符：{merged_hits[index]} != {expected}")
            if expected > 0:
                nonzero += 1
        self.assertGreater(nonzero, 0, "两段命中全为 0，合并断言没有实际约束力")


if __name__ == "__main__":
    unittest.main(verbosity=2)

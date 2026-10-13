"""Busted 车道契约（#81；#93 全量切换后是唯一的 Lua 测试入口）：
fast 排除 slow、full 包含 slow；探针、夹具与 Python 回归不进入发现范围。
LuaUnit 基线（#82 验收，commit 3bfd870）：fast 1321 / full 1342；旧 runner 已由 #93（0e435b0）删除，
当前分支不可复跑，要复现须 `git checkout 3bfd870`。
"""
import re
import shutil
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

DUMP_SNIPPET = (
    'local cfg = dofile(".busted") '
    'for k, v in pairs(cfg._all) do '
    'if type(v) ~= "table" then print("all:" .. tostring(k) .. "=" .. tostring(v)) end '
    'end '
    'for _, task in ipairs({"default", "fast", "full"}) do '
    'for _, r in ipairs(((cfg[task] or {}).ROOT) or {}) do print("root:" .. task .. ":" .. r) end '
    'end'
)


class BustedLaneConfigTest(unittest.TestCase):
    """.busted 配置形状：车道 ROOT、pattern、recursive、helper 与排序策略。"""

    def _dump(self):
        result = subprocess.run(["lua", "-e", DUMP_SNIPPET], cwd=ROOT,
                                capture_output=True, text=True, encoding="utf-8", errors="replace")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        settings, roots = {}, {}
        for line in result.stdout.splitlines():
            if line.startswith("all:"):
                key, _, value = line[4:].partition("=")
                settings[key] = value
            elif line.startswith("root:"):
                _, task, path = line.split(":", 2)
                roots.setdefault(task, []).append(path)
        return settings, roots

    def test_lane_baseline_settings(self):
        settings, _ = self._dump()
        self.assertEqual(settings.get("pattern"), "_test")
        self.assertEqual(settings.get("recursive"), "false",
                         "recursive 必须显式为 false，否则 fast 会沿目录递归捕获 tests/native/slow")
        self.assertEqual(settings.get("helper"), "tests/native/helper.lua")
        self.assertEqual(settings.get("sort-files"), "true")

    def test_lane_roots_are_exactly_the_native_dirs(self):
        """ROOT 白名单是「谁会被发现」的唯一机制，因此钉精确集合而不是排除法。

        排除法（「不得含 tests/gameplay 等旧目录」）在旧目录删除后退化成恒真断言；
        精确集合让「fast 不含 slow」「default 等价 fast」直接、不可绕过。
        """
        _, roots = self._dump()
        self.assertEqual(sorted(roots.get("default", [])), ["tests/native"],
                         f"default 的 ROOT 集合被改动：{roots.get('default')}")
        self.assertEqual(sorted(roots.get("fast", [])), ["tests/native"],
                         f"fast 的 ROOT 集合被改动：{roots.get('fast')}")
        self.assertEqual(sorted(roots.get("full", [])), ["tests/native", "tests/native/slow"],
                         f"full 的 ROOT 集合被改动：{roots.get('full')}")

    def test_probes_and_support_never_in_roots(self):
        _, roots = self._dump()
        for task, paths in roots.items():
            for path in paths:
                for banned in ("tests/probes", "tests/support"):
                    self.assertFalse(path == banned or path.startswith(banned + "/"),
                                     f"{task} 不得发现探针/夹具：{path}")


class BustedDiscoveryTest(unittest.TestCase):
    """发现行为：--list 证明 fast 不含 slow 案例、full 含 slow 案例，探针与 Python 不被加载。"""

    def _list(self, lane):
        busted = shutil.which("busted")
        if busted is None:
            self.skipTest("缺少 busted 命令；安装与版本由 doctor 校验")
        result = subprocess.run([busted, "--run=" + lane, "--list"], cwd=ROOT,
                                capture_output=True, text=True, encoding="utf-8", errors="replace")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout

    def test_fast_list_has_native_cases_but_not_slow_sentinel(self):
        listed = self._list("fast")
        self.assertIn("native shared baseline", listed)
        self.assertNotIn("native slow sentinel", listed)

    def test_full_list_includes_slow_sentinel(self):
        listed = self._list("full")
        self.assertIn("native slow sentinel", listed)
        self.assertIn("native shared baseline", listed)

    def test_probes_and_python_never_listed(self):
        listed = self._list("full")
        self.assertNotIn("tests/probes", listed)
        self.assertNotIn("tests/support", listed)
        self.assertNotIn("_test.py", listed)

    def test_fast_case_count_exceeds_file_count(self):
        """案例数口径（接住 #92 在 run_migration.lua 里钉过、随入口删除丢掉的那条）。

        车道报出的案例数必须来自 runner 自己的统计行，且严格大于案例文件数——
        任何「把文件数当案例数」的回退都会在这里红。
        """
        busted = shutil.which("busted")
        if busted is None:
            self.skipTest("缺少 busted 命令；安装与版本由 doctor 校验")
        result = subprocess.run([busted, "--run=fast"], cwd=ROOT,
                                capture_output=True, text=True, encoding="utf-8", errors="replace")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        # Busted 没有总数行：整行按四项取，词形随数量单复数变（pending 恒为 pending）。
        matches = re.findall(r"(\d+) successes? / (\d+) failures? / (\d+) errors? / (\d+) pending",
                             result.stdout)
        self.assertTrue(matches, "找不到 Busted 统计行：\n" + result.stdout[-2000:])
        cases = sum(int(value) for value in matches[-1])
        files = sorted((ROOT / "tests/native").glob("*_test.lua"))
        self.assertGreater(cases, len(files), f"fast 案例数 {cases} 不得退化成文件数 {len(files)}")


if __name__ == "__main__":
    unittest.main()

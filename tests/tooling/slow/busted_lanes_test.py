"""Busted 车道契约（#81）：fast 排除 slow、full 包含 slow；探针与 Python 不进入发现范围。"""
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
                         "recursive 必须显式为 false，否则 fast 会沿目录递归捕获 tests/tooling/slow")
        self.assertEqual(settings.get("helper"), "tests/native/helper.lua")
        self.assertEqual(settings.get("sort-files"), "true")

    def test_fast_excludes_slow_and_full_includes_it(self):
        _, roots = self._dump()
        fast, full = roots.get("fast", []), roots.get("full", [])
        # 双 runner 互斥发现（#82）：Busted ROOT 只含原生目录，旧 LuaUnit 目录交给 tests/run.lua，
        # 否则 Busted 会 loadfile 整个 LuaUnit 套件、注册 0 案例且退出码为 0（跨 runner 加载）。
        for expected in ("tests/native",):
            self.assertIn(expected, fast)
        for banned in ("tests/gameplay", "tests/tooling", "tests/tooling/slow"):
            self.assertNotIn(banned, fast, f"fast 的 Busted ROOT 不得含旧测试目录：{banned}")
            self.assertNotIn(banned, full, f"full 的 Busted ROOT 不得含旧测试目录：{banned}")
        self.assertFalse(any("slow" in path.split("/") for path in fast),
                         f"fast 不得包含 slow 目录：{fast}")
        for expected in list(fast) + ["tests/native/slow"]:
            self.assertIn(expected, full)

    def test_probes_support_and_lib_never_in_roots(self):
        _, roots = self._dump()
        for task, paths in roots.items():
            for path in paths:
                self.assertNotIn(path, ("tests/probes", "tests/support", "tests/lib"),
                                 f"{task} 不得发现探针/夹具/LuaUnit：{path}")


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


if __name__ == "__main__":
    unittest.main()

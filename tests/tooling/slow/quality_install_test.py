"""公开安装与质量接缝验收；仅使用独立检出及其缓存，不读取主工作区缓存。
运行：python -I tests/tooling/slow/quality_install_test.py <独立检出绝对路径>
独立检出先登记 project.json 的兄弟工具来源，并运行 install.ps1。
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import unittest

# discover 只导入并跳过；只有显式脚本入口才设置独立检出。
ROOT = None


def run(script, *args):
    env = os.environ.copy()
    for key in ("LUA_PATH", "LUA_CPATH", "SE_FISH_LUA_TOOLS", "PYTHONPATH"):
        env.pop(key, None)
    return subprocess.run(["pwsh", "-NoProfile", "-File", str(ROOT / "tools/quality" / script), *args],
                          cwd=ROOT, env=env, capture_output=True, text=True,
                          encoding="utf-8", errors="replace")


class QualityInstallTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if ROOT is None:
            raise unittest.SkipTest("安装验收需要显式独立检出入口")

    def test_doctor_names_missing_dependency_and_repair(self):
        cache = ROOT / ".toolcache/dry4lua"
        saved = cache.with_name("dry4lua-saved")
        cache.rename(saved)
        try:
            result = run("project.ps1", "doctor")
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("dry4lua", result.stdout + result.stderr)
            self.assertIn("tools/quality/install.ps1", result.stdout + result.stderr)
        finally:
            saved.rename(cache)

    def test_doctor_rejects_wrong_dependency_origin(self):
        cache = ROOT / ".toolcache/dry4lua"
        original = subprocess.check_output(["git", "-C", str(cache), "remote", "get-url", "origin"], text=True).strip()
        subprocess.run(["git", "-C", str(cache), "remote", "set-url", "origin", "https://invalid.example/dry4lua.git"], check=True)
        try:
            result = run("project.ps1", "doctor")
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("dry4lua", result.stdout + result.stderr)
            self.assertIn("来源", result.stdout + result.stderr)
            self.assertIn("tools/quality/install.ps1", result.stdout + result.stderr)
        finally:
            subprocess.run(["git", "-C", str(cache), "remote", "set-url", "origin", original], check=True)

    def test_doctor_rejects_modified_dependency_source(self):
        source = ROOT / ".toolcache/acceptance4lua/src/acceptance4lua/json.lua"
        original = source.read_bytes()
        source.write_bytes(original + b"\n-- altered\n")
        try:
            result = run("project.ps1", "doctor")
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("acceptance4lua", result.stdout + result.stderr)
            self.assertIn("tools/quality/install.ps1", result.stdout + result.stderr)
        finally:
            source.write_bytes(original)

    def test_repeat_install_preserves_usable_runtime(self):
        result = run("install.ps1")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        result = run("project.ps1", "doctor")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for name in ("dry4lua", "acceptance4lua", "luacheck", "luacov"):
            self.assertIn(name, result.stdout)

    def test_quality_publishes_full_tree_reports_from_installed_cache(self):
        result = run("project.ps1", "quality")
        (ROOT / "build/quality/install-acceptance-quality.log").write_text(result.stdout + result.stderr, encoding="utf-8")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("0 failures", result.stdout)
        lcov = (ROOT / "target/coverage/lua/lcov.info").read_text(encoding="utf-8")
        self.assertIn("end_of_record", lcov)
        dry = json.loads((ROOT / "build/quality/dry.json").read_text(encoding="utf-8"))
        crap = json.loads((ROOT / "build/quality/crap.json").read_text(encoding="utf-8"))
        self.assertGreater(dry["source_count"], 0)
        self.assertGreater(len(dry["candidates"]), 0)
        self.assertEqual(dry["source_count"], crap["source_count"])
        self.assertGreater(len(crap["functions"]), 0)
        for prefix in ("client.", "common.", "server."):
            self.assertIn(prefix, (ROOT / ".metrics/crap.edn").read_text(encoding="utf-8"))


if __name__ == "__main__":
    if len(sys.argv) < 2 or not Path(sys.argv[1]).is_absolute():
        raise SystemExit("需要显式独立检出绝对路径")
    ROOT = Path(sys.argv.pop(1)).resolve()
    if ROOT == Path(__file__).resolve().parents[3] or not (ROOT / "tools/quality/project.json").is_file():
        raise SystemExit("安装验收必须使用另一个独立检出")
    unittest.main()

"""公开 unittest discover 不得启动显式安装验收或消费发现参数。"""
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


class QualityInstallDiscoveryTest(unittest.TestCase):
    def test_doctor_reports_bootstrap_pin_drift_before_cache_checks(self):
        with tempfile.TemporaryDirectory(prefix="quality-pin-") as directory:
            sandbox = Path(directory)
            shutil.copytree(ROOT / "tools/acceptance", sandbox / "tools/acceptance")
            shutil.copy(ROOT / "tools/win_shell.lua", sandbox / "tools/win_shell.lua")
            settings = json.loads((ROOT / "tools/quality/project.json").read_text(encoding="utf-8"))
            settings["lua_tools"]["dry4lua"]["commit"] = "0" * 40
            config = sandbox / "config.json"
            config.write_text(json.dumps(settings), encoding="utf-8")
            result = subprocess.run([
                "pwsh", "-NoProfile", "-File", str(ROOT / "tools/quality/project.ps1"),
                "--root", str(sandbox), "--config", str(config), "doctor",
            ], cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 1, output)
            self.assertIn("dry4lua", output)
            self.assertIn("bootstrap", output)
            self.assertIn("固定提交不一致", output)
            self.assertFalse((sandbox / ".toolcache").exists())

    def test_discovery_skips_installation_without_an_explicit_checkout(self):
        with tempfile.TemporaryDirectory(prefix="quality-discovery-") as directory:
            sandbox = Path(directory)
            # 发现仅加载安装 suite；cwd 中的缓存哨兵必须保持原样。
            cache = sandbox / ".toolcache/dry4lua"
            cache.mkdir(parents=True)
            sentinel = cache / "sentinel"
            sentinel.write_bytes(b"untouched\n")
            result = subprocess.run([
                sys.executable, "-I", "-B", "-m", "unittest", "discover",
                "-s", str(ROOT / "tests/tooling/slow"), "-p", "quality_install_test.py",
            ], cwd=sandbox, capture_output=True, text=True, encoding="utf-8", errors="replace")
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn("skipped=1", output)
            self.assertIn("Ran 0 tests", output)
            self.assertEqual(sentinel.read_bytes(), b"untouched\n")
            self.assertEqual(list(sandbox.iterdir()), [sandbox / ".toolcache"])


if __name__ == "__main__":
    unittest.main()

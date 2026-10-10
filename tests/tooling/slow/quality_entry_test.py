"""从公开 PowerShell 入口验证覆盖率失败不会消费旧报告。"""
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


class QualityEntryTest(unittest.TestCase):
    def test_installer_uses_local_pinned_commits_on_first_and_repeat_install(self):
        config = json.loads((ROOT / "tools/quality/project.json").read_text(encoding="utf-8"))
        env = os.environ.copy()
        for name, tool in config["tools"].items():
            prefix = "UML_VIEWER" if name == "viewer" else name.upper()
            env[prefix + "_REPO_URL"] = str((ROOT / tool["source"]).resolve())
            env[prefix + "_REF"] = tool["commit"]
        installer = ROOT / 'tools/quality/install.ps1'
        with tempfile.TemporaryDirectory(prefix="se-fish-install-") as directory:
            root = Path(directory)
            for _ in range(2):
                result = subprocess.run(["pwsh", "-NoProfile", "-File", str(installer), "-Root", str(root), "-InstallOnly"],
                                        cwd=root, env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                for tool in config["tools"].values():
                    checkout = root / ".uml-viewer" / tool["directory"]
                    actual = subprocess.check_output(["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True).strip()
                    self.assertEqual(actual, tool["commit"])
            self.assertTrue((root / "uml.ps1").is_file())

    def test_viewer_checkout_matches_registered_patch(self):
        result = subprocess.run(["pwsh", "-NoProfile", "-File", str(ROOT / "tools/quality/project.ps1"), "doctor"],
                                cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_failed_full_suite_invalidates_old_coverage(self):
        with tempfile.TemporaryDirectory(prefix="se-fish-quality-") as directory:
            environment = os.environ.copy()
            environment.pop("LUA_PATH", None)
            environment.pop("LUA_CPATH", None)
            root = Path(directory)
            lcov = root / "target/coverage/lua/lcov.info"
            lcov.parent.mkdir(parents=True)
            lcov.write_text("SF:common/Old.lua\nDA:1,1\nend_of_record\n")
            config = root / "project.json"
            config.write_text(json.dumps({
                "commands": {"coverage": ["lua", "-e", "error('完整测试基线失败')"]},
                "paths": {"lcov": "target/coverage/lua/lcov.info",
                          "stats": "build/quality/luacov.stats.out",
                          "luacov": str(ROOT / ".toolcache/luacov/src")},
            }), encoding="utf-8")
            result = subprocess.run([
                "pwsh", "-NoProfile", "-File", str(ROOT / "tools/quality/project.ps1"),
                "--root", str(root), "--config", str(config), "coverage",
            ], capture_output=True, text=True, encoding="utf-8", errors="replace", env=environment)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("完整测试基线失败", result.stdout + result.stderr)
            self.assertFalse(lcov.exists(), "失败后旧 LCOV 仍可被自动发现")


if __name__ == "__main__":
    unittest.main()

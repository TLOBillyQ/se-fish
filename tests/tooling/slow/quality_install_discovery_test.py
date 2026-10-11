"""公开 unittest discover 不得启动显式安装验收或消费发现参数。"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


OLD_REVISION = "4cc471417c6f54f0b24b031d8e3a86300322905b"


class QualityInstallDiscoveryTest(unittest.TestCase):
    def _old_installation(self, sandbox):
        driver = sandbox / "driver"
        shutil.copytree(ROOT / "tools/quality", driver / "tools/quality")
        subprocess.run(["git", "init", "-q", str(driver)], check=True)
        subprocess.run(["git", "-C", str(driver), "fetch", "-q", str(ROOT), OLD_REVISION], check=True)
        old = json.loads(subprocess.check_output([
            "git", "-C", str(ROOT), "show", f"{OLD_REVISION}:tools/quality/project.json"], text=True))
        config = json.loads((ROOT / "tools/quality/project.json").read_text(encoding="utf-8"))
        target = sandbox / "installation"
        target.mkdir()
        for name, tool in old["tools"].items():
            source = ROOT / ".uml-viewer" / tool["directory"]
            config["tools"][name]["source"] = os.path.relpath(source, driver)
            directory = target / ".uml-viewer" / tool["directory"]
            directory.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(["git", "clone", "-q", "--no-checkout", str(source), str(directory)], check=True)
            subprocess.run(["git", "-C", str(directory), "checkout", "-q", tool["commit"]], check=True)
            for patch in tool.get("patches", []):
                content = subprocess.check_output(["git", "-C", str(ROOT), "show", f"{OLD_REVISION}:{patch}"])
                subprocess.run(["git", "-C", str(directory), "apply", "-"], input=content, check=True)
        (driver / "tools/quality/project.json").write_text(json.dumps(config), encoding="utf-8")
        return driver, target, config

    def test_explicit_upgrade_replaces_only_registered_old_patches(self):
        with tempfile.TemporaryDirectory(prefix="quality-upgrade-") as directory:
            driver, target, config = self._old_installation(Path(directory))
            result = subprocess.run([
                "pwsh", "-NoProfile", "-File", str(driver / "tools/quality/install.ps1"),
                "-Root", str(target), "-InstallOnly", "-UpgradeFrom", OLD_REVISION,
            ], capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=90)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            for tool in config["tools"].values():
                checkout = target / ".uml-viewer" / tool["directory"]
                for patch in tool.get("patches", []):
                    check = subprocess.run(["git", "-C", str(checkout), "apply", "--reverse", "--check",
                                            str(driver / patch)], capture_output=True)
                    self.assertEqual(check.returncode, 0, check.stderr.decode(errors="replace"))

    def test_explicit_upgrade_rejects_unknown_state_before_changing_any_tool(self):
        for fault in ("tracked", "index", "untracked"):
            with self.subTest(fault=fault), tempfile.TemporaryDirectory(prefix="quality-upgrade-") as directory:
                driver, target, config = self._old_installation(Path(directory))
                # 最后一个工具故障，证明前两个工具不会先被撤销。
                mutator = target / ".uml-viewer/mutator"
                if fault == "untracked":
                    (mutator / "unknown.txt").write_bytes(b"unknown\n")
                else:
                    source = mutator / "src/mutator/engine.py"
                    source.write_bytes(source.read_bytes() + b"\n# unknown\n")
                    if fault == "index":
                        subprocess.run(["git", "-C", str(mutator), "add", "src/mutator/engine.py"], check=True)
                before = {p.relative_to(target): p.read_bytes() for p in target.rglob("*")
                          if p.is_file() and ".git" not in p.relative_to(target).parts}
                indices = {name: subprocess.check_output(["git", "-C", str(target / ".uml-viewer" / tool["directory"]),
                                                          "diff", "--cached"]) for name, tool in config["tools"].items()}
                result = subprocess.run([
                    "pwsh", "-NoProfile", "-File", str(driver / "tools/quality/install.ps1"),
                    "-Root", str(target), "-InstallOnly", "-UpgradeFrom", OLD_REVISION,
                ], capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=90)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn("未登记", result.stdout + result.stderr)
                self.assertEqual({p.relative_to(target): p.read_bytes() for p in target.rglob("*")
                                  if p.is_file() and ".git" not in p.relative_to(target).parts
                                  and "target" not in p.relative_to(target).parts}, before)
                for name, tool in config["tools"].items():
                    self.assertEqual(subprocess.check_output(["git", "-C", str(target / ".uml-viewer" / tool["directory"]),
                                                              "diff", "--cached"]), indices[name])

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

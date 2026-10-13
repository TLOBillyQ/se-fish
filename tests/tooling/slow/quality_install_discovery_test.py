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

# 直接问 loader「discover 收进了哪些模块」：verify.ps1 只看退出码，删掉或漏掉一个回归文件
# 只会让 `Ran N tests` 静默下降，因此这里钉「目录全集 == 收集全集」（#93 补的防漏断言）。
DISCOVER_PROBE = (
    "import unittest\n"
    "loader = unittest.TestLoader()\n"
    "suite = loader.discover({directory!r}, pattern='*_test.py')\n"
    "def walk(node):\n"
    "    for child in node:\n"
    "        if isinstance(child, unittest.TestSuite):\n"
    "            walk(child)\n"
    "        else:\n"
    "            print(type(child).__module__)\n"
    "walk(suite)\n"
)



def standard_installation(sandbox):
    driver = sandbox / "driver"
    shutil.copytree(ROOT / "tools/quality", driver / "tools/quality")
    config = json.loads((ROOT / "tools/quality/project.json").read_text(encoding="utf-8"))
    common = Path(subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "--git-common-dir"], text=True).strip())
    if not common.is_absolute():
        common = ROOT / common
    siblings = common.resolve().parent.parent
    for name, tool in config["tools"].items():
        tool["source"] = os.path.relpath(siblings / ("uml-viewer" if name == "viewer" else name), driver)
    config["tools"]["viewer"]["commit"] = "79c8d563c42f9c8912e2810fcf71b7c24a72a88d"
    config["tools"]["viewer"]["patches"] = []
    (driver / "tools/quality/project.json").write_text(json.dumps(config), encoding="utf-8")
    target = sandbox / "installation"
    target.mkdir()
    return driver, target, config


def install(driver, target):
    return subprocess.run(["pwsh", "-NoProfile", "-File", str(driver / "tools/quality/install.ps1"),
                           "-Root", str(target), "-InstallOnly"], capture_output=True, text=True,
                          encoding="utf-8", errors="replace", timeout=90)


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

    def test_standard_installer_supports_empty_cache_and_repeat_install(self):
        with tempfile.TemporaryDirectory(prefix="quality-standard-") as directory:
            driver, target, config = standard_installation(Path(directory))
            for attempt in range(2):
                result = install(driver, target)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                viewer = target / ".uml-viewer/uml-viewer"
                self.assertEqual(subprocess.check_output(["git", "-C", str(viewer), "rev-parse", "HEAD"], text=True).strip(),
                                 config["tools"]["viewer"]["commit"])
                self.assertEqual(subprocess.check_output(["git", "-C", str(viewer), "status", "--porcelain"], text=True), "")
                self.assertTrue((target / "uml.ps1").is_file())

    def test_install_rejects_edits_inside_registered_patch_files_before_any_update(self):
        with tempfile.TemporaryDirectory(prefix="quality-dirty-") as directory:
            driver, target, config = standard_installation(Path(directory))
            result = install(driver, target)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            source = target / ".uml-viewer/mutator/src/mutator/engine.py"
            original = source.read_bytes() + b"\n# user unsaved change\n"
            source.write_bytes(original)
            result = install(driver, target)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn("保留现场", result.stdout + result.stderr)
            self.assertEqual(source.read_bytes(), original)

    def test_upgrade_request_fails_closed_without_touching_registered_tool(self):
        with tempfile.TemporaryDirectory(prefix="quality-upgrade-stop-") as directory:
            driver, target, config = standard_installation(Path(directory))
            result = install(driver, target)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            source = target / ".uml-viewer/uml-viewer/scripts/get-uml-viewer.ps1"
            before = source.read_bytes()
            result = subprocess.run([
                "pwsh", "-NoProfile", "-File", str(driver / "tools/quality/install.ps1"),
                "-Root", str(target), "-InstallOnly", "-UpgradeFrom", OLD_REVISION,
            ], capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=90)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn("-UpgradeFrom 已停用", result.stdout + result.stderr)
            self.assertIn("保留现场", result.stdout + result.stderr)
            self.assertEqual(source.read_bytes(), before)

    def test_doctor_reports_bootstrap_pin_drift_before_cache_checks(self):
        with tempfile.TemporaryDirectory(prefix="quality-pin-") as directory:
            sandbox = Path(directory)
            shutil.copytree(ROOT / "tools/acceptance", sandbox / "tools/acceptance")
            shutil.copy(ROOT / "tools/win_shell.lua", sandbox / "tools/win_shell.lua")
            # doctor 先核对标准分发映射（#95），隔离沙箱按仓库根布局提供同一份声明，
            # 本用例的核对对象仍是 bootstrap 固定提交漂移。
            shutil.copy(ROOT / "uml-quality.json", sandbox / "uml-quality.json")
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

    def test_discovery_collects_every_regression_file(self):
        """verify.ps1 的 Python 闸门只看退出码：删文件或漏收集只会让 `Ran N tests` 静默下降。

        这里直接问 loader 收进了哪些模块，钉「目录中的 *_test.py 全集 == discover 收集全集」，
        新加的文件没被 pattern 收进、或文件被误删导致覆盖面下降，都在这里红。
        """
        directory = ROOT / "tests/tooling/slow"
        result = subprocess.run([
            sys.executable, "-I", "-B", "-c", DISCOVER_PROBE.format(directory=str(directory)),
        ], cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        collected = {line.strip() for line in result.stdout.splitlines() if line.strip()}
        expected = {path.stem for path in directory.glob("*_test.py")}
        self.assertEqual(collected, expected,
                         f"discover 未收全回归文件：漏 {sorted(expected - collected)}，"
                         f"多 {sorted(collected - expected)}")

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

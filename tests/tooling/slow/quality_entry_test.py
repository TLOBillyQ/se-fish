"""从公开 PowerShell 入口验证覆盖率失败不会消费旧报告。"""
import importlib
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

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


# 桩脚本：按 mode 扮演 Lua 解释器（interp）或测试命令（test），每次调用记录 argv。
# 解释器分支响应 -v 并模拟 report_lcov.lua 写出 LCOV；测试分支模拟通过完整测试并产出统计。
STUB_SCRIPT = r'''
import json
import sys
from pathlib import Path

log = Path(sys.argv[1])
mode = sys.argv[2]
rest = sys.argv[3:]
with log.open("a", encoding="utf-8") as handle:
    handle.write(json.dumps({"mode": mode, "argv": rest}) + "\n")
if rest and rest[0] == "-v":
    print("Lua 5.4.6  stub interpreter")
    sys.exit(0)
if mode == "test":
    Path("luacov.stats.out").write_text("stub stats\n", encoding="utf-8")
    sys.exit(0)
if any("report_lcov.lua" in item for item in rest):
    Path(rest[-1]).write_text("SF:common/Stub.lua\nDA:1,1\nLF:1\nLH:1\nend_of_record\n", encoding="utf-8")
sys.exit(0)
'''


class QualityInterpreterTest(unittest.TestCase):
    """测试命令 argv 整体不透明：版本检查与报告脚本只能走 lua.executable。"""

    def _make_stub_quality_root(self, directory):
        root = Path(directory)
        log = root / "invocations.jsonl"
        stub = root / "stub.py"
        stub.write_text(STUB_SCRIPT, encoding="utf-8")

        def launcher(name, mode):
            path = root / name
            path.write_text(f'@echo off\r\n"{sys.executable}" "{stub}" "{log}" {mode} %*\r\n',
                            encoding="ascii")
            return path

        fake_lua = launcher("fake-lua.bat", "interp")
        test_cmd = launcher("test-cmd.bat", "test")
        config = root / "project.json"
        config.write_text(json.dumps({
            "lua": {"executable": str(fake_lua), "version": "Lua 5.4."},
            "commands": {
                "coverage": [str(test_cmd), "--lane", "full"],
                "mutation_test": [str(test_cmd), "--lane", "fast"],
            },
            "paths": {"lcov": "target/coverage/lua/lcov.info",
                      "stats": "build/quality/luacov.stats.out",
                      "luacov": "unused-by-stub"},
        }), encoding="utf-8")
        return root, config, log

    def _run_quality(self, root, config, *arguments):
        return subprocess.run([
            "pwsh", "-NoProfile", "-File", str(ROOT / "tools/quality/project.ps1"),
            "--root", str(root), "--config", str(config), *arguments,
        ], capture_output=True, text=True, encoding="utf-8", errors="replace")

    def _invocations(self, log, mode):
        return [json.loads(line)["argv"] for line in log.read_text(encoding="utf-8").splitlines()
                if json.loads(line)["mode"] == mode]

    def test_coverage_uses_interpreter_not_test_command_for_version_and_report(self):
        with tempfile.TemporaryDirectory(prefix="se-fish-interp-") as directory:
            root, config, log = self._make_stub_quality_root(directory)
            result = self._run_quality(root, config, "coverage")
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue((root / "target/coverage/lua/lcov.info").is_file())
            interpreter = self._invocations(log, "interp")
            test_command = self._invocations(log, "test")
            self.assertIn(["-v"], interpreter, "版本检查必须使用 Lua 解释器")
            self.assertTrue(any(any("report_lcov.lua" in item for item in argv) for argv in interpreter),
                            f"报告脚本必须使用 Lua 解释器：{interpreter}")
            self.assertEqual(test_command, [["--lane", "full"]],
                             "测试命令只应收到原始 argv，不应被当作解释器调用 -v 或报告脚本")

    def test_mutation_test_command_is_run_as_opaque_argv(self):
        with tempfile.TemporaryDirectory(prefix="se-fish-interp-") as directory:
            root, config, log = self._make_stub_quality_root(directory)
            result = self._run_quality(root, config, "test")
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            interpreter = self._invocations(log, "interp")
            test_command = self._invocations(log, "test")
            self.assertIn(["-v"], interpreter)
            self.assertEqual(test_command, [["--lane", "fast"]],
                             "mutation_test 首项不应被当作 Lua 解释器做版本检查")


class BustedPinnedConfigTest(unittest.TestCase):
    """project.json 登记 Busted 固定依赖：版本校验、doctor 与安装共用同一份 pins。"""

    def test_project_config_pins_busted_dependencies(self):
        config = json.loads((ROOT / "tools/quality/project.json").read_text(encoding="utf-8"))
        self.assertEqual(config["lua"]["executable"], "lua")
        self.assertIn("Lua 5.4.", config["lua"]["version"])
        busted = config["busted"]
        self.assertEqual(busted["command"], "busted")
        self.assertEqual(busted["version"], "2.3.0")
        rocks = {rock["name"]: rock["version"] for rock in busted["rocks"]}
        self.assertEqual(rocks["busted"], "2.3.0-1")
        self.assertEqual(rocks["luassert"], "1.9.0-1")
        self.assertEqual(rocks["luacov"], "0.17.0-1")
        self.assertEqual(busted["sources"]["busted"]["url"], "https://github.com/lunarmodules/busted.git")
        self.assertEqual(busted["sources"]["busted"]["commit"], "56e6d68204d1456afa77f1346bf4e050df65b629")
        self.assertEqual(busted["sources"]["luassert"]["url"], "https://github.com/lunarmodules/luassert.git")
        self.assertEqual(busted["sources"]["luassert"]["commit"], "8d8dc8a54cc468048a128a867f6449a6c3fdd11a")
        # LuaCov 0.17.0-1 由 lua_tools.luacov 的固定提交承载（同一上游 commit）。
        self.assertEqual(config["lua_tools"]["luacov"]["commit"], "b1f9eae400da976b93edb7f94cf5d05f538a0655")


class DoctorBustedTest(unittest.TestCase):
    """doctor 的 Busted 固定依赖校验：失败信息区分解释器缺失、Busted 缺失与版本不符。"""

    @classmethod
    def setUpClass(cls):
        sys.path.insert(0, str(ROOT / "tools/quality"))

    def setUp(self):
        import project
        self.project = importlib.reload(project)
        self.config = {
            "lua": {"executable": "lua", "version": "Lua 5.4."},
            "busted": {
                "command": "busted",
                "version": "2.3.0",
                "rocks": [{"name": "luassert", "version": "1.9.0-1"},
                          {"name": "luacov", "version": "0.17.0-1"},
                          {"name": "busted", "version": "2.3.0-1"}],
            },
        }

    def _completed(self, stdout="", returncode=0):
        return subprocess.CompletedProcess(args=[], returncode=returncode, stdout=stdout, stderr="")

    def _porcelain(self, name, version):
        return self._completed(f"{name}\t{version}\tinstalled\tC:/rocks\n")

    def test_missing_busted_config_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "busted"):
            self.project.doctor_busted(ROOT, {"lua": self.config["lua"]})

    def test_missing_busted_command_is_distinct_from_interpreter_failure(self):
        with mock.patch.object(self.project.shutil, "which", return_value=None):
            with self.assertRaisesRegex(RuntimeError, "Busted"):
                self.project.doctor_busted(ROOT, self.config)

    def test_busted_version_mismatch(self):
        def fake_run(argv, **kwargs):
            if argv[1:] == ["--version"]:
                return self._completed("2.2.0\n")
            raise AssertionError(f"意外调用：{argv}")

        with mock.patch.object(self.project.shutil, "which", return_value="/mock/busted"), \
                mock.patch.object(self.project.subprocess, "run", side_effect=fake_run):
            with self.assertRaisesRegex(RuntimeError, "2\\.2\\.0"):
                self.project.doctor_busted(ROOT, self.config)

    def test_missing_pinned_rock_is_reported_by_name(self):
        def fake_run(argv, **kwargs):
            if argv[1:] == ["--version"]:
                return self._completed("2.3.0\n")
            if argv[1] == "list":
                return self._completed("")
            raise AssertionError(f"意外调用：{argv}")

        with mock.patch.object(self.project.shutil, "which", side_effect=["/mock/busted", "/mock/luarocks"]), \
                mock.patch.object(self.project.subprocess, "run", side_effect=fake_run):
            with self.assertRaisesRegex(RuntimeError, r"luassert.*1\.9\.0-1"):
                self.project.doctor_busted(ROOT, self.config)

    def test_pinned_environment_passes(self):
        versions = {"luassert": "1.9.0-1", "luacov": "0.17.0-1", "busted": "2.3.0-1"}

        def fake_run(argv, **kwargs):
            if argv[1:] == ["--version"]:
                return self._completed("2.3.0\n")
            if argv[1] == "list":
                return self._porcelain(argv[2], versions[argv[2]])
            raise AssertionError(f"意外调用：{argv}")

        with mock.patch.object(self.project.shutil, "which", side_effect=["/mock/busted", "/mock/luarocks"]), \
                mock.patch.object(self.project.subprocess, "run", side_effect=fake_run):
            self.assertIsNone(self.project.doctor_busted(ROOT, self.config))


if __name__ == "__main__":
    unittest.main()

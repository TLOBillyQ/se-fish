"""从公开质量入口验证 mutation 范围与失败快照保护。"""
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


class QualityMutationTest(unittest.TestCase):
    def test_full_mutation_requires_an_explicit_target(self):
        result = subprocess.run([
            "pwsh", "-NoProfile", "-File", str(ROOT / "tools/quality/project.ps1"),
            "mutation", "--mutate-all",
        ], cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
        self.assertEqual(result.returncode, 1)
        self.assertIn("显式", result.stdout + result.stderr)

    def test_vendor_target_is_rejected_before_tests(self):
        result = subprocess.run([
            "pwsh", "-NoProfile", "-File", str(ROOT / "tools/quality/project.ps1"),
            "mutation", "server/packages/ability_system/init.lua",
        ], cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
        self.assertEqual(result.returncode, 1)
        self.assertIn("配置范围", result.stdout + result.stderr)

    def test_baseline_failure_keeps_valid_snapshot(self):
        with tempfile.TemporaryDirectory(prefix="se-fish-mutation-") as directory:
            root = Path(directory)
            source = root / "common/Example.lua"
            source.parent.mkdir()
            source.write_text("local M = {}\nfunction M.value(x) return x + 1 end\nreturn M\n")
            snapshot = root / ".metrics/mutate/common.Example.edn"
            snapshot.parent.mkdir(parents=True)
            old = b'{:namespace "common.Example" :forms []}\n'
            snapshot.write_bytes(old)
            config = root / "config.json"
            settings = json.loads((ROOT / "tools/quality/project.json").read_text(encoding="utf-8"))
            settings["commands"]["coverage"] = ["lua", "-e", "error('真实测试基线失败')"]
            settings["commands"]["mutation_test"] = ["lua", "-e", "error('真实测试基线失败')"]
            settings["paths"]["luacov"] = str(ROOT / ".toolcache/luacov/src")
            config.write_text(json.dumps(settings), encoding="utf-8")
            result = subprocess.run([
                "pwsh", "-NoProfile", "-File", str(ROOT / "tools/quality/project.ps1"),
                "--root", str(root), "--config", str(config), "mutation", "common/Example.lua",
            ], cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("真实测试基线失败", result.stdout + result.stderr)
            self.assertEqual(snapshot.read_bytes(), old)

    def test_corrupt_snapshot_is_reported_and_never_republished(self):
        with tempfile.TemporaryDirectory(prefix="se-fish-mutation-") as directory:
            root = Path(directory)
            source = root / "common/Example.lua"
            source.parent.mkdir()
            source.write_text("local M = {}\nfunction M.value(x) return x + 1 end\nreturn M\n")
            snapshot = root / ".metrics/mutate/bad.edn"
            snapshot.parent.mkdir(parents=True)
            snapshot.write_bytes(b'{:namespace "bad" :forms [')
            config = root / "config.json"
            settings = json.loads((ROOT / "tools/quality/project.json").read_text(encoding="utf-8"))
            settings["paths"]["luacov"] = str(ROOT / ".toolcache/luacov/src")
            config.write_text(json.dumps(settings), encoding="utf-8")
            result = subprocess.run([
                "pwsh", "-NoProfile", "-File", str(ROOT / "tools/quality/project.ps1"),
                "--root", str(root), "--config", str(config), "mutation", "common/Example.lua",
            ], cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
            self.assertEqual(result.returncode, 1)
            self.assertIn("损坏", result.stdout + result.stderr)
            self.assertEqual(snapshot.read_bytes(), b'{:namespace "bad" :forms [')

    def test_scoped_publish_only_replaces_target_snapshot(self):
        with tempfile.TemporaryDirectory(prefix="se-fish-mutation-") as directory:
            root = Path(directory)
            source = root / "common/Example.lua"
            source.parent.mkdir()
            source.write_text("local M = {}\nfunction M.enabled(flag) return flag and true or false end\nreturn M\n")
            metrics = root / ".metrics/mutate"
            metrics.mkdir(parents=True)
            (metrics / "common.Example.edn").write_text(
                '{:namespace "common.Example" :forms [] :outcomes {}}\n', encoding="utf-8")
            other = metrics / "common.Other.edn"
            untouched = b'{:namespace "common.Other" :forms [] :outcomes {}}\n'
            other.write_bytes(untouched)
            (root / "coverage_fixture.lua").write_text(
                "local f=assert(io.open('luacov.stats.out','w'))\n"
                "f:write('3:common\\\\Example.lua\\n1 1 1 \\n')\n"
                "f:close()\n", encoding="utf-8")
            (root / "mutation_fixture.lua").write_text("os.exit(0)\n", encoding="utf-8")
            config = root / "config.json"
            settings = json.loads((ROOT / "tools/quality/project.json").read_text(encoding="utf-8"))
            settings["commands"]["coverage"] = ["lua", "coverage_fixture.lua"]
            settings["commands"]["mutation_test"] = ["lua", "mutation_fixture.lua"]
            settings["paths"]["luacov"] = str(ROOT / ".toolcache/luacov/src")
            config.write_text(json.dumps(settings), encoding="utf-8")
            result = subprocess.run([
                "pwsh", "-NoProfile", "-File", str(ROOT / "tools/quality/project.ps1"),
                "--root", str(root), "--config", str(config),
                "mutation", "common/Example.lua", "--mutate-all", "--max-workers", "1",
            ], cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
            self.assertIn(result.returncode, (0, 3), result.stdout + result.stderr)
            self.assertEqual(other.read_bytes(), untouched)
            self.assertIn(':file "common/Example.lua"',
                          (metrics / "common.Example.edn").read_text(encoding="utf-8"))

    def test_scoped_publish_removes_deleted_target_snapshot_only(self):
        with tempfile.TemporaryDirectory(prefix="se-fish-mutation-") as directory:
            root = Path(directory)
            source = root / "common/Example.lua"
            source.parent.mkdir()
            source.write_text("local M = {}\nreturn M\n", encoding="utf-8")
            metrics = root / ".metrics/mutate"
            metrics.mkdir(parents=True)
            (metrics / "common.Example.edn").write_text(
                '{:namespace "common.Example" :forms [] :outcomes {}}\n', encoding="utf-8")
            other = metrics / "common.Other.edn"
            untouched = b'{:namespace "common.Other" :forms [] :outcomes {}}\n'
            other.write_bytes(untouched)
            (root / "coverage_fixture.lua").write_text(
                "local f=assert(io.open('luacov.stats.out','w'))\n"
                "f:write('3:common\\\\Example.lua\\n1 1 1 \\n')\n"
                "f:close()\n", encoding="utf-8")
            (root / "mutation_fixture.lua").write_text("os.exit(0)\n", encoding="utf-8")
            config = root / "config.json"
            settings = json.loads((ROOT / "tools/quality/project.json").read_text(encoding="utf-8"))
            settings["commands"]["coverage"] = ["lua", "coverage_fixture.lua"]
            settings["commands"]["mutation_test"] = ["lua", "mutation_fixture.lua"]
            settings["paths"]["luacov"] = str(ROOT / ".toolcache/luacov/src")
            config.write_text(json.dumps(settings), encoding="utf-8")
            result = subprocess.run([
                "pwsh", "-NoProfile", "-File", str(ROOT / "tools/quality/project.ps1"),
                "--root", str(root), "--config", str(config),
                "mutation", "common/Example.lua", "--mutate-all", "--max-workers", "1",
            ], cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
            self.assertIn(result.returncode, (0, 3), result.stdout + result.stderr)
            self.assertFalse((metrics / "common.Example.edn").exists(), result.stdout + result.stderr)
            self.assertEqual(other.read_bytes(), untouched)

    def test_worker_keeps_sibling_dependency_for_luaunit(self):
        with tempfile.TemporaryDirectory(prefix="se-fish-worker-") as directory:
            root = Path(directory)
            common = root / "common"
            common.mkdir()
            (common / "Dependency.lua").write_text(
                "local M = {}\nfunction M.value(x) return x end\nreturn M\n", encoding="utf-8")
            source = common / "Example.lua"
            source.write_text("local M = {}\nfunction M.strict(x) return x + 1 end\nreturn M\n",
                              encoding="utf-8")
            test = root / "test.lua"
            test.write_text('require("common.Dependency")\n'
                            'local M=require("common.Example")\nassert(M.strict(1)==2)\n',
                            encoding="utf-8")
            settings = json.loads((ROOT / "tools/quality/project.json").read_text(encoding="utf-8"))
            settings["commands"] = {"coverage": ["lua", "-lluacov", "test.lua"],
                                    "mutation_test": ["lua", "test.lua"]}
            settings["paths"]["luacov"] = str(ROOT / ".toolcache/luacov/src")
            config = root / "config.json"
            config.write_text(json.dumps(settings), encoding="utf-8")
            result = subprocess.run([
                "pwsh", "-NoProfile", "-File", str(ROOT / "tools/quality/project.ps1"),
                "--root", str(root), "--config", str(config),
                "mutation", "common/Example.lua", "--max-workers", "1", "--verbose",
            ], cwd=ROOT, timeout=90, capture_output=True, text=True,
                          encoding="utf-8", errors="replace")
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn("result=killed", output)


if __name__ == "__main__":
    unittest.main()

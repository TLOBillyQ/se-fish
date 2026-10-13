"""公开 mutation 入口的墙钟预算、启动前记录与默认资源占用。"""
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PYTHON = ROOT / ".uml-viewer/crapper/.venv/Scripts/python.exe"
SOURCE = "local M={}\nfunction M.value(x) return x + 1 end\nreturn M\n"
# 夹具的 coverage 子命令真的往继承来的 stdout 写字：真实覆盖率的 busted 子进程
# 正是这样绕过 Python 缓冲直写日志，缺了它「记录在日志头」这条断言就抓不到缺陷。
COVERAGE_STDOUT = "fixture-coverage-stdout"


class MutationBudgetTest(unittest.TestCase):
    def fixture(self, root, names, *, delay=0.0):
        for name in names:
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(SOURCE, encoding="utf-8")
        lines = len(SOURCE.splitlines())
        stats = "".join(f"{lines}:{name}\n" + "1 " * lines + "\n" for name in names)
        (root / "coverage.lua").write_text(
            f"print({json.dumps(COVERAGE_STDOUT)})\n"
            "local f=assert(io.open('luacov.stats.out','w'))\n"
            f"f:write({json.dumps(stats)})\n"
            "f:close()\n", encoding="utf-8")
        (root / "test.py").write_text(
            "import time\n" + (f"time.sleep({delay})\n" if delay else ""), encoding="utf-8")
        settings = json.loads((ROOT / "tools/quality/project.json").read_text(encoding="utf-8"))
        settings["commands"] = {"coverage": ["lua", "coverage.lua"],
                                "mutation_test": [str(PYTHON), "-B", str(root / "test.py")]}
        settings["paths"]["luacov"] = str(ROOT / ".toolcache/luacov/src")
        (root / "config.json").write_text(json.dumps(settings), encoding="utf-8")

    def invoke(self, root, *arguments, timeout=150):
        return subprocess.run([
            "pwsh", "-NoProfile", "-File", str(ROOT / "tools/quality/project.ps1"),
            "--root", str(root), "--config", str(root / "config.json"), "mutation", *arguments,
        ], cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace",
            timeout=timeout)

    def test_launch_record_precedes_work_with_scope_workers_and_budget(self):
        with tempfile.TemporaryDirectory(prefix="se-fish-budget-") as directory:
            root = Path(directory)
            self.fixture(root, ("common/Alpha.lua",))
            result = self.invoke(root, "common/Alpha.lua", "--max-workers", "1",
                                 "--budget-seconds", "300")
            output = result.stdout + result.stderr
            self.assertIn(result.returncode, (0, 3), output)
            record = output[:output.index("完整 Busted 基线通过")]
            self.assertIn("mutation 启动前记录", record)
            self.assertIn("common/Alpha.lua", record)
            self.assertIn("时间预算: 300 秒", record)
            self.assertIn("worker: 1", record)
            self.assertIn(str(PYTHON), record)

    def test_launch_record_names_the_log_location_and_the_recovery_path(self):
        with tempfile.TemporaryDirectory(prefix="se-fish-budget-") as directory:
            root = Path(directory)
            self.fixture(root, ("common/Alpha.lua",))
            result = self.invoke(root, "common/Alpha.lua", "--max-workers", "1")
            output = result.stdout + result.stderr
            self.assertIn(result.returncode, (0, 3), output)
            record = output[:output.index("完整 Busted 基线通过")]
            self.assertRegex(record, r"日志: target/mutation-logs/mutation-\d{8}-\d{6}\.log")
            self.assertIn("tools/quality/project.ps1", record)
            self.assertIn("恢复: ", record)
            self.assertIn(".metrics/mutate", record)

    def test_launch_record_stays_at_the_head_of_a_real_redirect(self):
        with tempfile.TemporaryDirectory(prefix="se-fish-budget-") as directory:
            root = Path(directory)
            self.fixture(root, ("common/Alpha.lua",))
            result = self.invoke(root, "common/Alpha.lua", "--max-workers", "1")
            output = result.stdout + result.stderr
            self.assertIn(result.returncode, (0, 3), output)
            # 重定向到日志时子进程绕过 Python 缓冲直写；记录整段仍须在它之前。
            self.assertLess(output.index("mutation 启动前记录结束"),
                            output.index(COVERAGE_STDOUT), output)

    def test_exhausted_budget_skips_every_target_and_reports_the_unrun_scope(self):
        with tempfile.TemporaryDirectory(prefix="se-fish-budget-") as directory:
            root = Path(directory)
            self.fixture(root, ("common/Alpha.lua", "common/Beta.lua"))
            result = self.invoke(root, "common/Alpha.lua", "common/Beta.lua",
                                 "--max-workers", "1", "--budget-seconds", "0")
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 4, output)
            self.assertIn("mutation 超预算提前退出", output)
            self.assertIn("已完成 0/2", output)
            self.assertIn("未运行 (2 个): common/Alpha.lua、common/Beta.lua", output)
            self.assertFalse((root / ".metrics/mutate/common.Alpha.edn").exists())
            self.assertFalse((root / ".metrics/mutate/common.Beta.edn").exists())

    def test_over_budget_publishes_completed_targets_and_records_the_rest(self):
        with tempfile.TemporaryDirectory(prefix="se-fish-budget-") as directory:
            root = Path(directory)
            self.fixture(root, ("common/Alpha.lua", "common/Beta.lua"), delay=3.0)
            result = self.invoke(root, "common/Alpha.lua", "common/Beta.lua",
                                 "--max-workers", "1", "--budget-seconds", "6")
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 4, output)
            self.assertIn("已完成 1/2", output)
            self.assertIn("未运行 (1 个): common/Beta.lua", output)
            self.assertIn(':file "common/Alpha.lua"',
                          (root / ".metrics/mutate/common.Alpha.edn").read_text(encoding="utf-8"))
            self.assertFalse((root / ".metrics/mutate/common.Beta.edn").exists())

    def test_defaults_are_one_worker_and_sixty_minutes(self):
        with tempfile.TemporaryDirectory(prefix="se-fish-budget-") as directory:
            root = Path(directory)
            self.fixture(root, ("common/Alpha.lua",))
            result = self.invoke(root, "common/Alpha.lua")
            output = result.stdout + result.stderr
            self.assertIn(result.returncode, (0, 3), output)
            record = output[:output.index("完整 Busted 基线通过")]
            self.assertIn("worker: 1", record)
            self.assertIn("时间预算: 3600 秒", record)

    def test_worker_count_follows_the_explicit_argument(self):
        with tempfile.TemporaryDirectory(prefix="se-fish-budget-") as directory:
            root = Path(directory)
            self.fixture(root, ("common/Alpha.lua",))
            result = self.invoke(root, "common/Alpha.lua", "--max-workers", "3")
            output = result.stdout + result.stderr
            self.assertIn(result.returncode, (0, 3), output)
            record = output[:output.index("完整 Busted 基线通过")]
            self.assertIn("worker: 3", record)

    def test_cli_defaults_match_the_mutation_module(self):
        script = ("import sys\n"
                  f"sys.path.insert(0, {str(ROOT / 'tools/quality')!r})\n"
                  "import mutation, project\n"
                  "print(mutation.DEFAULT_MAX_WORKERS, mutation.DEFAULT_BUDGET_SECONDS, "
                  "project.MUTATION_MAX_WORKERS)\n")
        result = subprocess.run([str(PYTHON), "-B", "-c", script], cwd=ROOT,
                                capture_output=True, text=True, encoding="utf-8")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        workers, budget, declared = result.stdout.split()
        self.assertEqual(declared, workers)
        self.assertEqual(float(budget), 3600.0)

    def test_budget_exit_code_is_not_a_valid_dispatch_result(self):
        declared = json.loads((ROOT / "uml-quality.json").read_text(encoding="utf-8-sig"))
        self.assertEqual(declared["operations"]["mutate"]["validResultExitCodes"], [0, 3])


if __name__ == "__main__":
    unittest.main()

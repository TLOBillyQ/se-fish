"""worker 契约：Busted mutation 链路在项目固定配置下可用（#96）。

seam 是公开质量入口与项目配置之间的那条缝：mutation 用 `commands.mutation_test`
在 worker overlay 里跑测试，overlay 必须能解析根目录 `.busted`、`tests/native/helper.lua`
与固定 Busted 依赖，且发现集合与主入口一致。工具缓存（`.toolcache`/`.uml-viewer`）
既不进业务扫描，也不进 worker。
"""
import json
import shutil
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CONFIG = ROOT / "tools/quality/project.json"

# 与 tools/quality/mutation.py 相同的固定导入来源：worker 由 vendored mutator 提供，
# Windows 复制回退由项目侧 windows_adapter 安装。
sys.path.insert(0, str(ROOT / "tools/quality"))
sys.path.insert(0, str(ROOT / ".uml-viewer/mutator/src"))
sys.path.insert(0, str(ROOT / ".uml-viewer/crapper/src"))

import windows_adapter  # noqa: E402
from mutator import workers  # noqa: E402
from project import source_files  # noqa: E402

TARGET = "common/RateLimit.lua"
SUMMARY = "successes / 0 failures / 0 errors / 0 pending"


def settings():
    return json.loads(CONFIG.read_text(encoding="utf-8-sig"))


def run(argv, cwd, timeout=600):
    return subprocess.run(argv, cwd=cwd, capture_output=True, text=True,
                          encoding="utf-8", errors="replace", timeout=timeout)


def listed(argv, cwd):
    result = run([*argv, "--list"], cwd)
    if result.returncode:
        raise AssertionError(result.stdout + result.stderr)
    return sorted(line.strip() for line in result.stdout.splitlines() if line.strip())


class BustedWorkerTest(unittest.TestCase):
    def setUp(self):
        windows_adapter.install()
        self.config = settings()
        self.command = self.config["commands"]["mutation_test"]
        self.addCleanup(self._remove_workers)
        self.base = None
        self.worker = None

    def _remove_workers(self):
        if self.base is not None:
            workers.delete_tree(self.base)
        self.base = None
        self.worker = None

    def _create_worker(self):
        source = ROOT / TARGET
        self.base = workers.new_run_dir(ROOT)
        self.worker = workers.create_workers(self.base, ROOT, TARGET, source.read_bytes(), 1)[0]
        return self.worker

    def test_mutation_argv_uses_the_windows_busted_launcher(self):
        # Windows 的 CreateProcess 只补 .exe，裸 `busted` 会 [WinError 2]。
        launcher = self.command[0]
        self.assertEqual(Path(launcher).suffix, ".bat",
                         f"mutation 测试 argv 必须以 Busted 的 .bat 启动器开头：{launcher}")
        self.assertTrue(shutil.which(launcher), f"启动器不在 PATH：{launcher}")
        self.assertIn("--run=fast", self.command, "mutation 基线必须跑 fast 车道")

    def test_worker_runs_the_project_fast_lane_matching_the_main_entry(self):
        worker = self._create_worker()
        self.assertTrue((worker / ".busted").is_file())
        self.assertFalse((worker / ".busted").is_symlink(),
                         "worker 必须拿到自己的 .busted 快照，不能指向真实源码")
        self.assertTrue((worker / "tests/native/helper.lua").is_file(),
                        "worker 必须能解析 .busted 声明的共享 helper")

        main = listed(self.command, ROOT)
        self.assertTrue(main, "主入口 fast 车道不应为空")
        discovered = listed(self.command, worker)
        if discovered != main:
            known = set(discovered)
            self.fail(f"worker overlay 的 fast 发现集合与主入口不一致：主入口 {len(main)} 条 / "
                      f"worker {len(discovered)} 条；仅主入口有 {[x for x in main if x not in known][:5]}；"
                      f"仅 worker 有 {[x for x in discovered if x not in set(main)][:5]}")

        result = run(self.command, worker)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        tail = [line for line in result.stdout.splitlines() if line.strip()][-1]
        self.assertRegex(tail, r"^\d+ " + SUMMARY + r" : [\d.]+ seconds$")
        self.assertEqual(int(tail.split()[0]), len(main),
                         "worker 实际执行的案例数必须等于主入口 fast 清单条数")

        self.assertFalse((worker / TARGET).is_symlink(),
                         "worker 的变异目标必须是独立副本；目录 symlink 会写回真实源码")
        before = (ROOT / TARGET).read_bytes()
        (worker / TARGET).write_bytes(b"return {}\n")
        self.assertEqual((ROOT / TARGET).read_bytes(), before,
                         "写入 worker 副本不得穿透到主树源码")

    def test_worker_and_business_scan_never_include_tool_caches(self):
        worker = self._create_worker()
        for cache in (".toolcache", ".uml-viewer"):
            self.assertFalse((worker / cache).exists(), f"{cache} 不得进入 worker")
            self.assertTrue(list((ROOT / cache).rglob("*.lua")),
                            f"{cache} 里应有 Lua，否则这条断言无判别力")

        files = source_files(ROOT, self.config)
        self.assertTrue(files)
        outside = [name for name in files if not name.startswith(("client/", "common/", "server/"))]
        self.assertEqual(outside, [], "业务扫描不得离开三端源码树")
        caches = [name for name in files if name.startswith((".toolcache/", ".uml-viewer/"))]
        self.assertEqual(caches, [], "工具缓存的 Lua 不得进入业务扫描")


if __name__ == "__main__":
    unittest.main()

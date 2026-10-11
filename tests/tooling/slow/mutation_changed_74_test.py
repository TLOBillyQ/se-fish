"""#74：通过公开 project.ps1 验证 Git 改动业务文件选择。"""
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


class MutationChangedTest(unittest.TestCase):
    # 失败方式：暂存修改/新增漏选，混合状态重复，删除误选，范围排除失效，显式入口被状态干扰。
    def _git(self, root, *args):
        return subprocess.run(["git", *args], cwd=root, check=True,
                              capture_output=True, text=True)

    def _fixture(self, root):
        self._git(root, "init", "-q")
        self._git(root, "config", "user.name", "测试")
        self._git(root, "config", "user.email", "fixture@example.invalid")
        for name in ("Staged", "Unstaged", "Both", "Deleted", "Clean"):
            self._change(root, f"common/{name}.lua")
        (root / "test.lua").write_text(
            'for _,file in ipairs(arg) do assert(dofile(file).value(1)==3) end\n', encoding="utf-8")
        settings = json.loads((ROOT / "tools/quality/project.json").read_text(encoding="utf-8"))
        settings["paths"]["luacov"] = str(ROOT / ".toolcache/luacov/src")
        (root / "config.json").write_text(json.dumps(settings), encoding="utf-8")
        self._git(root, "add", ".")
        self._git(root, "commit", "-qm", "测试基线")

    def _change(self, root, name, staged=False):
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("local M={}\nfunction M.value(x) return x + 2 end\nreturn M\n", encoding="utf-8")
        # 已有文件追加注释，制造真实 Git 变化而不改变测试值。
        if staged:
            with path.open("a", encoding="utf-8") as stream:
                stream.write("-- 已暂存变化\n")
            self._git(root, "add", name)

    def _assert_selected(self, root, expected, *args):
        settings = json.loads((root / "config.json").read_text(encoding="utf-8"))
        settings["commands"] = {
            "coverage": ["lua", "-lluacov", "test.lua", *expected],
            "mutation_test": ["lua", "test.lua", *expected],
        }
        (root / "config.json").write_text(json.dumps(settings), encoding="utf-8")
        result = subprocess.run([
            "pwsh", "-NoProfile", "-File", str(ROOT / "tools/quality/project.ps1"),
            "--root", str(root), "--config", str(root / "config.json"), "mutation",
            *args, "--max-workers", "1", "--verbose",
        ], cwd=ROOT, timeout=90, capture_output=True, text=True, encoding="utf-8", errors="replace")
        output = result.stdout + result.stderr
        self.assertIn(result.returncode, (0, 3), output)
        selected = [line.split("/M.value ")[0].removeprefix("Mutation function: ")
                    for line in output.splitlines() if line.startswith("Mutation function: ")]
        self.assertEqual(selected, [name[:-4].replace("/", ".") for name in expected], output)
        self.assertNotIn("没有选中的业务 Lua 文件", output)

    def test_default_mutation_selects_staged_modification(self):
        with tempfile.TemporaryDirectory(prefix="se-fish-changed-") as directory:
            root = Path(directory)
            self._fixture(root)
            self._change(root, "common/Staged.lua", staged=True)
            self._assert_selected(root, ["common/Staged.lua"])

    def test_changed_mutation_selects_staged_addition(self):
        with tempfile.TemporaryDirectory(prefix="se-fish-changed-") as directory:
            root = Path(directory)
            self._fixture(root)
            self._change(root, "client/Added.lua", staged=True)
            self._assert_selected(root, ["client/Added.lua"], "--changed")

    def test_mixed_changes_are_unique_and_exclude_deleted_and_nonbusiness(self):
        with tempfile.TemporaryDirectory(prefix="se-fish-changed-") as directory:
            root = Path(directory)
            self._fixture(root)
            self._change(root, "common/Staged.lua", staged=True)
            self._change(root, "client/Added.lua", staged=True)
            with (root / "common/Unstaged.lua").open("a", encoding="utf-8") as stream:
                stream.write("-- 未暂存变化\n")
            self._change(root, "server/New.lua")
            self._change(root, "common/Both.lua", staged=True)
            with (root / "common/Both.lua").open("a", encoding="utf-8") as stream:
                stream.write("-- 未暂存注释\n")
            self._git(root, "rm", "common/Deleted.lua")
            (root / "common/Clean.lua").unlink()
            for name in ("server/packages/Official.lua", "server/_trigger/Trigger.lua",
                         "common/readme.txt", "tests/Outside.lua"):
                self._change(root, name, staged=True)
            self._change(root, "client/packages/Untracked.lua")
            expected = ["client/Added.lua", "common/Both.lua", "common/Staged.lua",
                        "common/Unstaged.lua", "server/New.lua"]
            for args in ((), ("--changed",)):
                with self.subTest(args=args):
                    self._assert_selected(root, expected, *args)

    def test_explicit_file_and_full_mutation_ignore_other_git_changes(self):
        with tempfile.TemporaryDirectory(prefix="se-fish-changed-") as directory:
            root = Path(directory)
            self._fixture(root)
            self._change(root, "common/Staged.lua", staged=True)
            for args in (("common/Clean.lua",), ("--mutate-all", "common/Clean.lua")):
                with self.subTest(args=args):
                    self._assert_selected(root, ["common/Clean.lua"], *args)


if __name__ == "__main__":
    unittest.main()

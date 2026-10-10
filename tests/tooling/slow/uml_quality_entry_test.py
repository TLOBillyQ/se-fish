"""公开 UML 子进程分发：真实覆盖率与全树 CRAP，失败不得发布。"""
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PYTHON = ROOT / '.uml-viewer/crapper/.venv/Scripts/python.exe'


class UmlQualityEntryTest(unittest.TestCase):
    def fixture(self, root, command):
        scripts = root / '.uml-viewer/uml-viewer/scripts'
        scripts.mkdir(parents=True)
        shutil.copy(ROOT / 'uml.ps1', root / 'uml.ps1')
        shutil.copy(ROOT / '.uml-viewer/uml-viewer/scripts/uml-command.ps1', scripts)
        quality = root / 'tools/quality'
        quality.mkdir(parents=True)
        config = {
            'sources': {'roots': ['common'], 'exclude': ['packages']},
            'commands': {'coverage': command},
            'paths': {'luacov': str(ROOT / '.toolcache/luacov/src'),
                      'stats': 'build/quality/luacov.stats.out',
                      'lcov': 'target/coverage/lua/lcov.info', 'crap': '.metrics/crap.edn'},
        }
        (quality / 'project.json').write_text(json.dumps(config), encoding='utf-8')
        # 隔离项目的入口记录 argv，再交给真实项目实现；不启动通用工具或 GUI。
        def quote(path):
            return str(path).replace("'", "''")
        (quality / 'project.ps1').write_text(
            "$args | ConvertTo-Json -Compress | Add-Content -LiteralPath 'calls.jsonl'\n"
            f"& '{quote(PYTHON)}' -B '{quote(ROOT / 'tools/quality/project.py')}' --root '{quote(root)}' @args\n"
            'exit $LASTEXITCODE\n', encoding='utf-8')
        (root / 'common/packages').mkdir(parents=True)
        for name in ('First', 'Second'):
            (root / f'common/{name}.lua').write_text('local M = {}\nfunction M.value() return 1 end\nreturn M\n')
        (root / 'common/packages/Vendor.lua').write_text('error("不应扫描 vendor")\n')
        (root / 'tests.lua').write_text('assert(require("common.First").value() == 1)\nassert(require("common.Second").value() == 1)\n')
        snapshot = root / '.metrics/crap.edn'
        snapshot.parent.mkdir()
        snapshot.write_text('旧快照', encoding='utf-8')
        lcov = root / 'target/coverage/lua/lcov.info'
        lcov.parent.mkdir(parents=True)
        lcov.write_text('SF:common/First.lua\nDA:2,999\nend_of_record\n')
        return snapshot, lcov

    def invoke(self, root, *args):
        env = os.environ.copy()
        env.pop('LUA_PATH', None)
        env.pop('LUA_CPATH', None)
        return subprocess.run(['pwsh', '-NoProfile', '-File', str(root / 'uml.ps1'), *args],
                              cwd=root, env=env, capture_output=True, text=True, encoding='utf-8', errors='replace')

    def calls(self, root):
        path = root / 'calls.jsonl'
        return [json.loads(line) for line in path.read_text(encoding='utf-8-sig').splitlines()] if path.exists() else []

    def test_crap_refreshes_coverage_then_whole_tree_even_with_target(self):
        with tempfile.TemporaryDirectory(prefix='se-fish-uml-') as directory:
            root = Path(directory)
            snapshot, lcov = self.fixture(root, ['lua', '-lluacov', 'tests.lua'])
            result = self.invoke(root, 'crap', 'common/First.lua')
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(self.calls(root), ['coverage', 'crap'])
            text = snapshot.read_text(encoding='utf-8')
            self.assertIn('common.First', text)
            self.assertIn('common.Second', text)
            self.assertNotIn('Vendor', text)
            self.assertNotIn('999', lcov.read_text())
            self.assertNotIn('busted', (result.stdout + result.stderr).lower())

    def test_coverage_failure_preserves_snapshot_and_stops_dispatch(self):
        with tempfile.TemporaryDirectory(prefix='se-fish-uml-') as directory:
            root = Path(directory)
            snapshot, lcov = self.fixture(root, ['lua', '-e', 'error("覆盖率基线失败")'])
            result = self.invoke(root, 'crap')
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(self.calls(root), ['coverage'])
            self.assertIn('覆盖率基线失败', result.stdout + result.stderr)
            self.assertEqual(snapshot.read_text(encoding='utf-8'), '旧快照')
            self.assertFalse(lcov.exists())

    def test_missing_stats_stops_before_crap(self):
        with tempfile.TemporaryDirectory(prefix='se-fish-uml-') as directory:
            root = Path(directory)
            snapshot, lcov = self.fixture(root, ['lua', '-e', 'print("没有覆盖率统计")'])
            result = self.invoke(root, 'crap')
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(self.calls(root), ['coverage'])
            self.assertEqual(snapshot.read_text(encoding='utf-8'), '旧快照')
            self.assertFalse(lcov.exists())

    def test_conversion_failure_preserves_snapshot(self):
        with tempfile.TemporaryDirectory(prefix='se-fish-uml-') as directory:
            root = Path(directory)
            snapshot, lcov = self.fixture(root, ['lua', '-e',
                'local f=assert(io.open("luacov.stats.out", "w")); f:write("损坏统计"); f:close()'])
            result = self.invoke(root, 'crap')
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(self.calls(root), ['coverage'])
            self.assertEqual(snapshot.read_text(encoding='utf-8'), '旧快照')
            self.assertFalse(lcov.exists())

    def test_project_config_precedes_deps_alias(self):
        with tempfile.TemporaryDirectory(prefix='se-fish-uml-') as directory:
            root = Path(directory)
            self.fixture(root, ['lua', '-e', 'error("项目配置优先")'])
            (root / 'deps.edn').write_text('{:aliases {:crap {:main-opts ["通用别名"]}}}')
            result = self.invoke(root, 'crap')
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(self.calls(root), ['coverage'])
            self.assertIn('项目配置优先', result.stdout + result.stderr)

    def test_mutation_forwards_arguments_to_project_entry(self):
        with tempfile.TemporaryDirectory(prefix='se-fish-uml-') as directory:
            root = Path(directory)
            self.fixture(root, ['lua', '-lluacov', 'tests.lua'])
            (root / 'tools/quality/project.ps1').write_text(
                '$args | ConvertTo-Json -Compress | Set-Content calls.jsonl\nexit 3\n', encoding='utf-8')
            result = self.invoke(root, 'mutate', 'common/First.lua', '--mutate-all')
            self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
            self.assertEqual(self.calls(root), [['mutate', 'common/First.lua', '--mutate-all']])


if __name__ == '__main__':
    unittest.main()

"""公开 mutation 在 Windows 发布占用失败时保留完整旧快照。"""
import ctypes
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
# 验收可显式选择只读的已安装工具来源，所有执行产物仍在 fixture。
import os
TOOLS = Path(os.environ.get('QUALITY_TEST_TOOLS_ROOT', str(ROOT)))


class MutationPublishTest(unittest.TestCase):
    def fixture(self, root):
        quality = root / 'tools/quality'
        quality.mkdir(parents=True)
        for path in (ROOT / 'tools/quality').glob('*.py'):
            shutil.copy(path, quality)
        shutil.copy(ROOT / 'tools/quality/report_lcov.lua', quality)
        entry = (ROOT / 'tools/quality/project.ps1').read_text(encoding='utf-8')
        interpreter = str(TOOLS / '.uml-viewer/crapper/.venv/Scripts/python.exe').replace("'", "''")
        entry = entry.replace("$python = Join-Path $root '.uml-viewer/crapper/.venv/Scripts/python.exe'", f"$python = '{interpreter}'")
        (quality / 'project.ps1').write_text(entry, encoding='utf-8')
        for tool in ('mutator', 'crapper'):
            shutil.copytree(TOOLS / f'.uml-viewer/{tool}/src', root / f'.uml-viewer/{tool}/src')
        config = json.loads((ROOT / 'tools/quality/project.json').read_text(encoding='utf-8'))
        config['commands'] = {'coverage': ['lua', '-lluacov', 'test.lua'], 'mutation_test': ['lua', 'test.lua']}
        config['paths']['luacov'] = str(TOOLS / '.toolcache/luacov/src')
        (quality / 'project.json').write_text(json.dumps(config), encoding='utf-8')
        (root / 'common').mkdir()
        for name in ('A', 'B'):
            (root / f'common/{name}.lua').write_text('local M={}\nfunction M.value(x) return x + 1 end\nreturn M\n')
        (root / 'test.lua').write_text('assert(require("common.A").value(1)==2)\nassert(require("common.B").value(1)==2)\n')
        metrics = root / '.metrics/mutate'
        metrics.mkdir(parents=True)
        for name in ('A', 'B'):
            (metrics / f'common.{name}.edn').write_text('{:namespace "common.' + name + '" :forms [] :outcomes {}}\n')
        return metrics

    def test_success_removes_stale_snapshot_and_keeps_differential_and_full_results(self):
        with tempfile.TemporaryDirectory(prefix='se-fish-success-76-') as directory:
            root = Path(directory)
            metrics = self.fixture(root)
            (metrics / 'common.B.edn').rename(metrics / 'legacy.edn')
            # 加入 file-bearing 旧记录，触发旧 per-file 快照清理。
            (metrics / 'legacy.edn').write_text('{:namespace "common.B" :forms [{:id "defn/M.value" '
                ':file "common/B.lua" :hash "old" :killed 1 :survived 0 :uncovered 0 :sites 1}] :outcomes {}}\n')
            command = ['pwsh', '-NoProfile', '-File', str(root / 'tools/quality/project.ps1'),
                       'mutation', 'common/A.lua', 'common/B.lua', '--max-workers', '1']
            for index, extra in enumerate(([], [], ['--mutate-all'])):
                result = subprocess.run(command + extra, cwd=root, timeout=90, capture_output=True,
                                        text=True, encoding='utf-8', errors='replace')
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertFalse((metrics / 'legacy.edn').exists())
                self.assertEqual(set(p.name for p in metrics.iterdir()), {'common.A.edn', 'common.B.edn'})
                self.assertEqual(list((root / 'target/mutation-publication').iterdir()), [])
                if extra:
                    self.assertIn('reused=0', result.stdout)
                elif index == 1:
                    self.assertIn('reused=4', result.stdout)
                    self.assertIn('executed=0', result.stdout)
            (root / 'test.lua').write_text('assert(type(require("common.A").value(1))=="number")\n'
                                          'assert(type(require("common.B").value(1))=="number")\n')
            result = subprocess.run(command + ['--mutate-all'], cwd=root, timeout=90, capture_output=True,
                                    text=True, encoding='utf-8', errors='replace')
            self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
            self.assertIn('survived', (metrics / 'common.A.edn').read_text())

    def test_windows_delete_failure_preserves_whole_previous_tree(self):
        self.check_locked_publication(delete=True)

    def test_windows_replace_failure_preserves_whole_previous_tree(self):
        self.check_locked_publication(delete=False)

    def check_locked_publication(self, delete):
        with tempfile.TemporaryDirectory(prefix='se-fish-publish-76-') as directory:
            root = Path(directory)
            metrics = self.fixture(root)
            if delete:
                # 旧 per-file 快照被 namespace 正式快照取代时，上游会清除旧路径。
                (metrics / 'common.B.edn').unlink()
                (metrics / 'legacy.edn').write_text('{:namespace "common.B" :forms [{:id "defn/M.value" '
                    ':file "common/B.lua" :hash "old" :killed 1 :survived 0 :uncovered 0 :sites 1}] :outcomes {}}\n')
            before = {p.name: p.read_bytes() for p in metrics.iterdir()}
            kernel = ctypes.WinDLL('kernel32', use_last_error=True)
            create = kernel.CreateFileW
            create.argtypes = [ctypes.c_wchar_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_void_p,
                               ctypes.c_uint32, ctypes.c_uint32, ctypes.c_void_p]
            create.restype = ctypes.c_void_p
            kernel.CloseHandle.argtypes = [ctypes.c_void_p]
            handle = create(str(metrics / ('legacy.edn' if delete else 'common.B.edn')), 0x80000000, 3, None, 3, 0, None)
            self.assertNotIn(handle, (None, ctypes.c_void_p(-1).value))
            try:
                result = subprocess.run(['pwsh', '-NoProfile', '-File', str(root / 'tools/quality/project.ps1'),
                    'mutation', 'common/A.lua', 'common/B.lua', '--max-workers', '1'], cwd=root,
                    timeout=90, capture_output=True, text=True, encoding='utf-8', errors='replace')
            finally:
                kernel.CloseHandle(handle)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn('基础设施失败', result.stdout + result.stderr)
            self.assertEqual({p.name: p.read_bytes() for p in metrics.iterdir()}, before)


if __name__ == '__main__':
    unittest.main()

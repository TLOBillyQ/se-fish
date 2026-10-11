"""公开质量入口：同仓库互斥与异常退出释放。"""
import json
import os
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


class QualityLockTest(unittest.TestCase):
    def fixture(self, root):
        quality = root / 'tools/quality'
        quality.mkdir(parents=True)
        for path in (ROOT / 'tools/quality').glob('*.py'):
            shutil.copy(path, quality)
        shutil.copy(ROOT / 'tools/quality/project.ps1', quality)
        # 创建隔离解释器环境；项目分发与实现保持真实，不写共享工具缓存。
        environment = root / '.uml-viewer/crapper/.venv'
        subprocess.run([os.sys.executable, '-m', 'venv', '--without-pip', str(environment)], check=True)
        (root / 'test.lua').write_text(
            "local f=assert(io.open('ready','w')); f:write('已启动'); f:close()\n"
            "while not io.open('release','r') do end\n", encoding='utf-8')
        (quality / 'project.json').write_text(json.dumps({
            'commands': {'coverage': ['lua'], 'mutation_test': ['lua', 'test.lua']},
            'paths': {}, 'tools': {},
        }), encoding='utf-8')

    def command(self, root):
        return ['pwsh', '-NoProfile', '-File', str(root / 'tools/quality/project.ps1'), 'test']

    def test_atomic_refresh_failure_keeps_snapshot(self):
        with tempfile.TemporaryDirectory(prefix='se-fish-refresh-76-') as directory:
            root = Path(directory)
            self.fixture(root)
            config_path = root / 'tools/quality/project.json'
            config = json.loads(config_path.read_text())
            config['commands']['coverage'] = ['lua', '-e', 'error("本轮覆盖率失败")']
            config['paths'].update({'stats': 'build/stats', 'lcov': 'target/lcov.info', 'luacov': 'unused'})
            config_path.write_text(json.dumps(config), encoding='utf-8')
            snapshot = root / '.metrics/crap.edn'
            snapshot.parent.mkdir()
            snapshot.write_bytes(b'old-valid-snapshot')
            result = subprocess.run(self.command(root)[:-1] + ['refresh-crap'], cwd=root,
                                    capture_output=True, text=True, encoding='utf-8', errors='replace')
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn('本轮覆盖率失败', result.stdout + result.stderr)
            self.assertEqual(snapshot.read_bytes(), b'old-valid-snapshot')

    def test_same_repository_rejects_overlap_and_releases_after_process_exit(self):
        with tempfile.TemporaryDirectory(prefix='se-fish-lock-76-') as directory:
            root = Path(directory)
            self.fixture(root)
            first = subprocess.Popen(self.command(root), cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                deadline = time.monotonic() + 15
                while not (root / 'ready').exists() and first.poll() is None:
                    if time.monotonic() > deadline:
                        self.fail('首请求未启动')
                    time.sleep(0.02)
                self.assertTrue((root / 'ready').exists(), first.communicate() if first.poll() is not None else '')
                second = subprocess.Popen(self.command(root), cwd=root, stdout=subprocess.PIPE,
                                          stderr=subprocess.PIPE, text=True, encoding='utf-8', errors='replace')
                try:
                    stdout, stderr = second.communicate(timeout=5)
                except subprocess.TimeoutExpired:
                    subprocess.run(['taskkill', '/PID', str(second.pid), '/T', '/F'], capture_output=True)
                    second.communicate(timeout=10)
                    self.fail('同仓库请求未明确拒绝，进入重叠测试')
                self.assertEqual(second.returncode, 1, stdout + stderr)
                self.assertIn('正在运行', stdout + stderr)
            finally:
                # Windows 结束公开入口的整个进程树，覆盖 Python 持锁进程强杀。
                subprocess.run(['taskkill', '/PID', str(first.pid), '/T', '/F'], capture_output=True)
                first.communicate(timeout=10)
                (root / 'release').touch()
            third = subprocess.run(self.command(root), cwd=root, capture_output=True,
                                   text=True, encoding='utf-8', errors='replace', timeout=15)
            self.assertEqual(third.returncode, 0, third.stdout + third.stderr)


if __name__ == '__main__':
    unittest.main()

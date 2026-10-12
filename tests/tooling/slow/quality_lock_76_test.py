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

    def test_installer_first_and_repeat_install_accept_atomic_viewer_patch(self):
        tools = Path(os.environ.get('QUALITY_TEST_TOOLS_ROOT', str(ROOT)))
        with tempfile.TemporaryDirectory(prefix='se-fish-install-76-') as directory:
            sandbox = Path(directory)
            project = sandbox / 'source'
            shutil.copytree(ROOT / 'tools/quality', project / 'tools/quality')
            config_path = project / 'tools/quality/project.json'
            config = json.loads(config_path.read_text())
            for tool in config['tools'].values():
                tool['source'] = os.path.relpath((tools / tool['source']).resolve(), project)
            config_path.write_text(json.dumps(config), encoding='utf-8')
            destination = sandbox / 'installed'
            destination.mkdir()
            for _ in range(2):
                result = subprocess.run(['pwsh', '-NoProfile', '-File', str(project / 'tools/quality/install.ps1'),
                                         '-Root', str(destination), '-InstallOnly'], cwd=destination,
                                        capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=90)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            command = destination / '.uml-viewer/uml-viewer/scripts/uml-command.ps1'
            runtime = command.read_text(encoding='utf-8')
            # 标准分发：安装的 viewer runtime 无补丁即读取仓库根 uml-quality.json，
            # 项目命令映射由声明式配置提供，不再有 refresh-crap 私补丁痕迹。
            self.assertIn('Read-UmlQualityConfig', runtime)
            self.assertNotIn('refresh-crap', runtime)
            self.assertEqual('', subprocess.check_output(['git', '-C', str(destination / '.uml-viewer/uml-viewer'),
                                                          'status', '--porcelain'], text=True).strip())

    def test_powershell_lock_blocks_public_python_entry(self):
        with tempfile.TemporaryDirectory(prefix='se-fish-install-lock-76-') as directory:
            root = Path(directory)
            self.fixture(root)
            (root / 'target').mkdir()
            (root / 'release').touch()
            script = root / 'owner.ps1'
            script.write_text("$s=[IO.File]::Open('target/quality.lock',[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::ReadWrite)\n"
                              "$s.Lock(0,1)\ntry { & ./tools/quality/project.ps1 test; exit $LASTEXITCODE } finally { $s.Dispose() }\n", encoding='utf-8')
            result = subprocess.run(['pwsh', '-NoProfile', '-File', str(script)], cwd=root,
                                    capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=10)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn('正在运行', result.stdout + result.stderr)

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
                for action in ('coverage', 'quality', 'refresh-crap', 'crap', 'dry', 'mutation', 'mutation-report', 'doctor'):
                    blocked = subprocess.run(self.command(root)[:-1] + [action], cwd=root,
                                             capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=5)
                    self.assertEqual(blocked.returncode, 1, blocked.stdout + blocked.stderr)
                    self.assertIn('正在运行', blocked.stdout + blocked.stderr)
                direct = subprocess.run([os.sys.executable, '-B', str(root / 'tools/quality/project.py'), 'test'],
                                        cwd=root, capture_output=True, text=True, encoding='utf-8', timeout=5)
                self.assertEqual(direct.returncode, 1, direct.stdout + direct.stderr)
                self.assertIn('正在运行', direct.stdout + direct.stderr)
                installed = subprocess.run(['pwsh', '-NoProfile', '-File', str(ROOT / 'tools/quality/install.ps1'),
                                            '-Root', str(root), '-InstallOnly'], cwd=root, capture_output=True,
                                            text=True, encoding='utf-8', errors='replace', timeout=10)
                self.assertEqual(installed.returncode, 1, installed.stdout + installed.stderr)
                self.assertIn('正在运行', installed.stdout + installed.stderr)
                # 另一项目的公开请求不会因当前项目持锁被拒绝。
                other = root / 'other'
                self.fixture(other)
                (other / 'release').touch()
                independent = subprocess.run(self.command(other), cwd=other, capture_output=True, timeout=10)
                self.assertEqual(independent.returncode, 0, independent.stderr)
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

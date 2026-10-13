"""verify.ps1 的安装 suite 显式执行步骤：discover 恒跳过 QualityInstallTest，必须有自动路径补上。

`tests/tooling/slow/quality_install_test.py` 的模块入口只吃显式独立检出——discover 导入时
`ROOT is None`，`setUpClass` 抛 `SkipTest`，所以「被跳过」本身不是执行证据。这里钉住公开复验
入口 `tools/quality/verify.ps1` 在 discover 之外确有一条自动路径，并钉住缺省独立检出时不阻塞。

轻量回归：质量入口用桩（记录 argv 后成功退出），不运行真实 doctor/quality/mutation，也不构造
第二份独立检出。
"""
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
TOOLS = Path(os.environ.get('QUALITY_TEST_TOOLS_ROOT', str(ROOT)))

# 质量入口桩：doctor/quality/mutation 逐条记录 argv 后成功退出。
PROJECT_STUB = '$args | ConvertTo-Json -Compress | Add-Content calls.jsonl\nexit 0\n'

# 显式入口桩：与 quality_install_test.py 的 __main__ 契约相同——只接受绝对路径的独立检出，
# 并且只在真正被执行（而不是被 discover 导入）时留下记录。
INSTALL_ENTRY_STUB = '''"""显式入口桩：只有 __main__ 被执行时才记录，discover 导入不留痕。"""
import json
import sys
from pathlib import Path

ROOT = None

if __name__ == "__main__":
    if len(sys.argv) < 2 or not Path(sys.argv[1]).is_absolute():
        raise SystemExit("需要显式独立检出绝对路径")
    ROOT = Path(sys.argv.pop(1)).resolve()
    Path("install-entry.json").write_text(json.dumps({"root": str(ROOT)}), encoding="utf-8")
'''

PLACEHOLDER = '''import unittest


class PlaceholderTest(unittest.TestCase):
    def test_placeholder(self):
        self.assertTrue(True)
'''


def link(path, target):
    """junction 复用真实工具环境（安装好的 venv），不新建环境。"""
    path.parent.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(['cmd', '/c', 'mklink', '/J', str(path), str(target)],
                            capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr


def build_fixture(root):
    """隔离复验环境：真实 verify.ps1 + 质量入口桩 + 真实 venv（junction）。"""
    shutil.copytree(ROOT / 'tools/quality', root / 'tools/quality')
    (root / 'tools/quality/project.ps1').write_text(PROJECT_STUB, encoding='utf-8')
    (root / 'uml.ps1').write_text('exit 0\n', encoding='utf-8')
    (root / 'common').mkdir()
    (root / 'common/RateLimit.lua').write_text('local M = {}\nreturn M\n', encoding='utf-8')
    slow = root / 'tests/tooling/slow'
    slow.mkdir(parents=True)
    (slow / 'placeholder_test.py').write_text(PLACEHOLDER, encoding='utf-8')
    (slow / 'quality_install_test.py').write_text(INSTALL_ENTRY_STUB, encoding='utf-8')
    link(root / '.uml-viewer/crapper/.venv', TOOLS / '.uml-viewer/crapper/.venv')
    return slow


class VerifyInstallStepTest(unittest.TestCase):
    """公开复验入口对安装 suite 的两种形态：缺省降级为警告，给了独立检出就显式执行。"""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='se-fish-verify-')
        self.root = Path(self.tmp.name)
        self.slow = build_fixture(self.root)
        self.checkout = self.root / 'independent-checkout'
        self.checkout.mkdir()

    def tearDown(self):
        self.tmp.cleanup()

    def verify(self, *arguments):
        env = os.environ.copy()
        for key in ('LUA_PATH', 'LUA_CPATH', 'SE_FISH_LUA_TOOLS', 'PYTHONPATH'):
            env.pop(key, None)
        return subprocess.run(['pwsh', '-NoProfile', '-File', str(self.root / 'tools/quality/verify.ps1'),
                               '-File', 'common/RateLimit.lua', *arguments],
                              cwd=self.root, env=env, capture_output=True, text=True,
                              encoding='utf-8', errors='replace', timeout=180)

    def entry_record(self):
        path = self.root / 'install-entry.json'
        return json.loads(path.read_text(encoding='utf-8')) if path.exists() else None

    def test_discover_still_runs_and_install_suite_warns_without_a_checkout(self):
        result = self.verify()
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn('Ran 1 test', output, 'discover 步骤必须照旧执行')
        self.assertIsNone(self.entry_record(), '没有独立检出时不得执行安装 suite')
        self.assertIn('QualityInstallRoot', output, '缺省必须提示参数名，而不是静默通过')
        self.assertIn('README', output, '缺省必须指向 README 的人工步骤')

    def test_explicit_checkout_runs_the_install_suite_entry(self):
        result = self.verify('-QualityInstallRoot', str(self.checkout))
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertNotIn('未提供', output, '给了独立检出就不该再降级为警告')
        record = self.entry_record()
        self.assertIsNotNone(record, '显式独立检出必须真的执行安装 suite 入口，而不是只打印提示')
        self.assertEqual(record['root'], str(self.checkout.resolve()))

    def test_install_suite_failure_reaches_the_overall_exit(self):
        (self.slow / 'quality_install_test.py').write_text(
            'if __name__ == "__main__":\n    raise SystemExit(2)\n', encoding='utf-8')
        result = self.verify('-QualityInstallRoot', str(self.checkout))
        output = result.stdout + result.stderr
        self.assertNotEqual(result.returncode, 0, '安装 suite 的非零退出必须并入整体退出码')
        self.assertIn('安装 suite（独立检出）未通过', output, '失败必须由复验入口报出，而不是只留在子进程')


if __name__ == '__main__':
    unittest.main()

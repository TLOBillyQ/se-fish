"""标准 quality 分发：固定标准 viewer 经仓库根 uml-quality.json 调用项目公开入口。

验收口径：图上右键与终端使用同一个项目质量实现；参数、退出码、锁与错误报告一致；
完整 coverage 成功后才发布 LCOV，失败保留上一份快照。轻量回归：测试命令用桩，
不运行真实 mutation，也不依赖测试迁移完成。
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
TOOLS = Path(os.environ.get('QUALITY_TEST_TOOLS_ROOT', str(ROOT)))

# 桩完整测试：成功时产出可合并的统计，等价聚合入口的发布前提。
PASSING_STATS = ('local f=assert(io.open("luacov.stats.out","w"));'
                 'f:write("2:common/First.lua\\n1 1 \\n2:common/Second.lua\\n1 1 \\n");f:close()')
FAILING = 'error("完整测试基线失败")'
FAILING_MESSAGE = '完整测试基线失败'


def link(path, target):
    """junction 复用工具来源检出，不新建环境，也不写共享缓存。"""
    path.parent.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(['cmd', '/c', 'mklink', '/J', str(path), str(target)],
                            capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr


def coverage_argv(body):
    return ['lua', '-e', body]


def set_coverage_command(root, body):
    """只换隔离项目的 coverage 内联脚本，其余配置保持 build_fixture 的产物。"""
    config_path = root / 'tools/quality/project.json'
    config = json.loads(config_path.read_text(encoding='utf-8'))
    config['commands']['coverage'] = coverage_argv(body)
    config_path.write_text(json.dumps(config), encoding='utf-8')


def build_fixture(root, command):
    """隔离项目：固定标准 viewer + 真实项目质量实现 + 声明式分发配置。"""
    viewer = json.loads((ROOT / 'tools/quality/project.json').read_text(encoding='utf-8'))['tools']['viewer']
    assert not viewer.get('patches'), '标准分发前提：固定 viewer 不依赖私有补丁'
    checkout = root / '.uml-viewer/uml-viewer'
    source = (TOOLS / viewer['source']).resolve()
    subprocess.run(['git', 'clone', '--no-checkout', str(source), str(checkout)],
                   check=True, capture_output=True, encoding='utf-8', errors='replace')
    subprocess.run(['git', '-C', str(checkout), 'checkout', viewer['commit']],
                   check=True, capture_output=True, encoding='utf-8', errors='replace')
    for name in ('uml', 'uml.ps1', 'uml-quality.json'):
        shutil.copy(ROOT / name, root / name)
    shutil.copytree(ROOT / 'tools/quality', root / 'tools/quality')
    config = {
        'sources': {'roots': ['common'], 'exclude': ['packages']},
        'lua': {'executable': 'lua', 'version': 'Lua 5.4.'},
        'commands': {'coverage': command, 'mutation_test': command},
        'paths': {'luacov': (TOOLS / '.toolcache/luacov/src').as_posix(),
                  'stats': 'build/quality/luacov.stats.out',
                  'lcov': 'target/coverage/lua/lcov.info',
                  'crap': '.metrics/crap.edn',
                  'mutation': '.metrics/mutate'},
        'lua_tools': json.loads((ROOT / 'tools/quality/project.json').read_text(encoding='utf-8'))['lua_tools'],
    }
    (root / 'tools/quality/project.json').write_text(json.dumps(config), encoding='utf-8')
    # 复用工具来源检出的 venv 与 Lua 工具缓存（junction），不新建环境，也不写共享缓存。
    link(root / '.uml-viewer/crapper/.venv', TOOLS / '.uml-viewer/crapper/.venv')
    link(root / '.toolcache', TOOLS / '.toolcache')
    (root / 'common/packages').mkdir(parents=True)
    for name in ('First', 'Second'):
        (root / f'common/{name}.lua').write_text('local M = {}\nfunction M.value() return 1 end\nreturn M\n')
    (root / 'common/packages/Vendor.lua').write_text('error("不应扫描 vendor")\n')
    snapshot = root / '.metrics/crap.edn'
    snapshot.parent.mkdir(parents=True)
    snapshot.write_text('旧快照', encoding='utf-8')
    lcov = root / 'target/coverage/lua/lcov.info'
    lcov.parent.mkdir(parents=True)
    lcov.write_text('SF:common/First.lua\nDA:2,999\nend_of_record\n', encoding='utf-8')
    return snapshot, lcov


def invoke_graph(root, *args):
    """图上公开入口：与终端 project.ps1 平行的另一个入口。"""
    env = os.environ.copy()
    env.pop('LUA_PATH', None)
    env.pop('LUA_CPATH', None)
    return subprocess.run(['pwsh', '-NoProfile', '-File', str(root / 'uml.ps1'), *args],
                          cwd=root, env=env, capture_output=True, text=True,
                          encoding='utf-8', errors='replace')


def invoke_terminal(root, *args):
    env = os.environ.copy()
    env.pop('LUA_PATH', None)
    env.pop('LUA_CPATH', None)
    return subprocess.run(['pwsh', '-NoProfile', '-File', str(root / 'tools/quality/project.ps1'), *args],
                          cwd=root, env=env, capture_output=True, text=True,
                          encoding='utf-8', errors='replace')


def result_record(root):
    path = root / '.uml-viewer/quality-result.json'
    return json.loads(path.read_text(encoding='utf-8-sig')) if path.exists() else None


def declared():
    """仓库根声明式分发配置；DeclaredMappingTest 与 DoctorDispatchCheckTest 共用同一读取口径。"""
    return json.loads((ROOT / 'uml-quality.json').read_text(encoding='utf-8'))


class StandardDispatchTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='se-fish-dispatch-')
        self.root = Path(self.tmp.name)
        self.snapshot, self.lcov = build_fixture(self.root, coverage_argv(PASSING_STATS))

    def tearDown(self):
        self.tmp.cleanup()

    def test_graph_crap_runs_declared_project_refresh_then_whole_tree(self):
        result = invoke_graph(self.root, 'crap', 'common/First.lua')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        text = self.snapshot.read_text(encoding='utf-8')
        self.assertIn('common.First', text)
        self.assertIn('common.Second', text, '全树快照必须保留其他模块的指标')
        self.assertNotIn('Vendor', text)
        self.assertNotIn('999', self.lcov.read_text(encoding='utf-8'), '必须使用本轮覆盖率')
        record = result_record(self.root)
        self.assertEqual({'configured': True, 'tool': 'configured', 'operation': 'crap',
                          'crapScope': 'whole-tree', 'exitCode': 0, 'validResult': True},
                         {key: record[key] for key in ('configured', 'tool', 'operation',
                                                        'crapScope', 'exitCode', 'validResult')},
                         '图上调用必须来自声明式分发，而不是通用工具路由')

    def test_graph_crap_failure_preserves_snapshot_and_invalidates_lcov(self):
        set_coverage_command(self.root, FAILING)
        result = invoke_graph(self.root, 'crap')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(FAILING_MESSAGE, result.stdout + result.stderr)
        self.assertEqual(self.snapshot.read_text(encoding='utf-8'), '旧快照')
        self.assertFalse(self.lcov.exists(), 'coverage 失败后旧 LCOV 不得继续被发现')
        self.assertFalse(result_record(self.root)['validResult'])

    def test_graph_mutate_forwards_arguments_and_exit_code(self):
        (self.root / 'tools/quality/project.ps1').write_text(
            '$args | ConvertTo-Json -Compress | Set-Content calls.jsonl\nexit 3\n', encoding='utf-8')
        result = invoke_graph(self.root, 'mutate', 'common/First.lua', '--mutate-all')
        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
        calls = json.loads((self.root / 'calls.jsonl').read_text(encoding='utf-8'))
        self.assertEqual(['mutation', 'common/First.lua', '--mutate-all'], calls)
        self.assertTrue(result_record(self.root)['validResult'], '存活结果按声明契约视为有效')

    def test_missing_stats_stops_before_crap(self):
        set_coverage_command(self.root, 'print("没有覆盖率统计")')
        result = invoke_graph(self.root, 'crap')
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.snapshot.read_text(encoding='utf-8'), '旧快照')
        self.assertFalse(self.lcov.exists())
        self.assertIn('LuaCov 统计', result.stdout + result.stderr)

    def test_corrupt_stats_conversion_stops_before_crap(self):
        set_coverage_command(self.root, 'local f=assert(io.open("luacov.stats.out","w")); f:write("损坏统计"); f:close()')
        result = invoke_graph(self.root, 'crap')
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.snapshot.read_text(encoding='utf-8'), '旧快照')
        self.assertFalse(self.lcov.exists())

    def test_declared_configuration_precedes_generic_tool_route(self):
        """声明式分发优先：即使仓库有 deps.edn，也不会落到通用 crapper。"""
        (self.root / 'deps.edn').write_text('{:aliases {:crap {:main-opts ["通用别名"]}}}', encoding='utf-8')
        set_coverage_command(self.root, FAILING)
        result = invoke_graph(self.root, 'crap')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(FAILING_MESSAGE, result.stdout + result.stderr,
                      '项目声明的配置必须执行，而不是回退到通用工具或 Clojure 别名')
        self.assertEqual('configured', result_record(self.root)['tool'])

    def test_invalid_declaration_fails_closed_without_running_another_tool(self):
        (self.root / 'uml-quality.json').write_text('{broken', encoding='utf-8')
        result = invoke_graph(self.root, 'crap')
        self.assertEqual(1, result.returncode, result.stdout + result.stderr)
        self.assertIn('uml-quality.json', result.stdout + result.stderr)
        self.assertIsNone(result_record(self.root), '配置无效时不得发布质量结果')
        partial = {'version': 1, 'operations': {'crap': json.loads((ROOT / 'uml-quality.json').read_text())['operations']['crap']}}
        (self.root / 'uml-quality.json').write_text(json.dumps(partial), encoding='utf-8')
        result = invoke_graph(self.root, 'crap')
        self.assertEqual(1, result.returncode, result.stdout + result.stderr)
        self.assertIn('uml-quality.json', result.stdout + result.stderr)
        self.assertNotIn(FAILING_MESSAGE, result.stdout + result.stderr, '校验失败不得启动任何质量命令')


    def test_terminal_quality_keeps_dry_and_report_paths(self):
        """标准分发不吞掉既有 DRY：quality 仍是覆盖率 → DRY → 全树 CRAP。"""
        with tempfile.TemporaryDirectory(prefix='se-fish-quality-') as directory:
            root = Path(directory)
            build_fixture(root, coverage_argv(PASSING_STATS))
            result = invoke_terminal(root, 'quality')
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            dry = json.loads((root / 'build/quality/dry.json').read_text(encoding='utf-8'))
            crap = json.loads((root / 'build/quality/crap.json').read_text(encoding='utf-8'))
            self.assertEqual(dry['source_count'], crap['source_count'],
                             'DRY 与 CRAP 必须共用同一业务范围')
            self.assertTrue((root / 'build/quality/crap.txt').is_file())
            self.assertIn('DRY 分析完成', output)
            self.assertIn('CRAP 完成', output)

    def test_declared_crap_refresh_does_not_reach_for_generic_tools(self):
        """图上 crap 走项目实现：报告写入项目声明的路径，而不是通用工具的默认位置。"""
        with tempfile.TemporaryDirectory(prefix='se-fish-dispatch-') as directory:
            root = Path(directory)
            snapshot, lcov = build_fixture(root, coverage_argv(PASSING_STATS))
            result = invoke_graph(root, 'crap')
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('common.First', snapshot.read_text(encoding='utf-8'))
            self.assertTrue((root / 'build/quality/crap.json').is_file(),
                            'CRAP 报告路径由项目配置决定')


class DeclaredMappingTest(unittest.TestCase):
    """声明式配置本身：仓库根 uml-quality.json 映射到项目公开入口，并被固定校验器接受。"""

    declared = staticmethod(declared)

    def test_manifest_maps_to_public_project_entry(self):
        config = self.declared()
        self.assertEqual(1, config['version'])
        operations = config['operations']
        self.assertEqual(['crap', 'mutate'], sorted(operations))
        for name in ('crap', 'mutate'):
            self.assertEqual(['./tools/quality/project.ps1'], operations[name]['argv'][:1])
        self.assertEqual('none', operations['crap']['forwardArgs'])
        self.assertEqual(['refresh-crap'], operations['crap']['argv'][1:])
        self.assertEqual('whole-tree', operations['crap']['scope'])
        self.assertEqual([0], operations['crap']['validResultExitCodes'])
        self.assertEqual(['mutation'], operations['mutate']['argv'][1:])
        self.assertEqual('append', operations['mutate']['forwardArgs'])
        self.assertEqual([0, 3], operations['mutate']['validResultExitCodes'])

    def test_fixed_viewer_validator_accepts_declared_manifest(self):
        viewer = json.loads((ROOT / 'tools/quality/project.json').read_text(encoding='utf-8'))['tools']['viewer']
        script = (TOOLS / viewer['source'] / 'scripts/uml-quality-config.ps1').resolve()
        result = subprocess.run(['pwsh', '-NoProfile', '-Command',
                                 f'. {str(script)!r}; $c = Read-UmlQualityConfig {str(ROOT)!r}; '
                                 "$c.operations.crap.scope; $c.operations.mutate.argv[1]"],
                                capture_output=True, text=True, encoding='utf-8', errors='replace')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(['whole-tree', 'mutation'],
                         [line.strip() for line in result.stdout.splitlines() if line.strip()])

    def test_terminal_and_graph_share_one_implementation(self):
        """终端 project.ps1 与图上 uml.ps1 都落到同一分发实现（refresh-crap / mutation）。"""
        project_entry = (ROOT / 'tools/quality/project.py').read_text(encoding='utf-8')
        self.assertIn('refresh-crap', project_entry)
        self.assertIn('"mutation"', project_entry)
        manifest = self.declared()
        self.assertNotIn('standardTools', manifest, '项目不用通用 crapper/mutator 路由')
        self.assertFalse((ROOT / 'deps.edn').exists(), '没有 Clojure 别名路由可回退')


class TerminalGraphParityTest(unittest.TestCase):
    """终端与图上调用同一公开入口：参数、退出码、锁与错误报告一致。"""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='se-fish-parity-')
        self.root = Path(self.tmp.name)
        self.snapshot, self.lcov = build_fixture(self.root, coverage_argv(PASSING_STATS))

    def tearDown(self):
        self.tmp.cleanup()

    def test_graph_and_terminal_return_the_same_code_for_the_same_failure(self):
        set_coverage_command(self.root, FAILING)
        terminal = invoke_terminal(self.root, 'coverage')
        self.assertNotEqual(terminal.returncode, 0)
        self.assertIn(FAILING_MESSAGE, terminal.stdout + terminal.stderr)
        graph = invoke_graph(self.root, 'crap')
        self.assertNotEqual(graph.returncode, 0)
        self.assertEqual(terminal.returncode, graph.returncode, '同一失败在两个入口返回同一退出码')
        self.assertIn(FAILING_MESSAGE, graph.stdout + graph.stderr)
        self.assertEqual(self.snapshot.read_text(encoding='utf-8'), '旧快照')
        # 同一失败文本来自同一项目实现，而不是各自的包装信息。
        marker = FAILING_MESSAGE
        self.assertEqual((terminal.stdout + terminal.stderr).count(marker),
                         (graph.stdout + graph.stderr).count(marker))

    def test_target_and_routing_arguments_cannot_narrow_the_declared_scope(self):
        """图上单类右键与越界路由旗标都不能缩小快照：与终端全树刷新得到同一份业务树。"""
        with self.subTest(arguments='目标'), tempfile.TemporaryDirectory(prefix='se-fish-parity-') as directory:
            root = Path(directory)
            snapshot, _ = build_fixture(root, coverage_argv(PASSING_STATS))
            result = invoke_graph(root, 'crap', 'common/First.lua')
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            graph_text = snapshot.read_text(encoding='utf-8')
            self.assertIn('common.Second', graph_text, '单类右键不得缩小全树快照')
            terminal_ref = Path(directory) / 'terminal'
            build_fixture(terminal_ref, coverage_argv(PASSING_STATS))
            terminal = invoke_terminal(terminal_ref, 'refresh-crap')
            self.assertEqual(terminal.returncode, 0, terminal.stdout + terminal.stderr)
            self.assertEqual(graph_text.splitlines(),
                             (terminal_ref / '.metrics/crap.edn').read_text(encoding='utf-8').splitlines(),
                             '图上带目标的刷新与终端全树刷新必须得到同一快照')
        with self.subTest(arguments='路由旗标'), tempfile.TemporaryDirectory(prefix='se-fish-parity-') as directory:
            root = Path(directory)
            snapshot, _ = build_fixture(root, coverage_argv(PASSING_STATS))
            result = invoke_graph(root, 'crap', '--exclude', 'common/Second.lua', 'common/First.lua')
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            text = snapshot.read_text(encoding='utf-8')
            self.assertIn('common.Second', text, '调用方旗标不得缩小全树快照')
            self.assertNotIn('Vendor', text)

    def test_graph_request_is_refused_by_the_same_repository_lock(self):
        holder = self.root / 'holder.ps1'
        holder.write_text("$s=[IO.File]::Open('target/quality.lock',[IO.FileMode]::OpenOrCreate,"
                          "[IO.FileAccess]::ReadWrite,[IO.FileShare]::ReadWrite)\n"
                          "$s.Lock(0,1)\n'已持锁' | Set-Content held.txt\n"
                          "Start-Sleep -Seconds 20\n", encoding='utf-8')
        process = subprocess.Popen(['pwsh', '-NoProfile', '-File', str(holder)], cwd=self.root)
        try:
            deadline = time.monotonic() + 15
            while not (self.root / 'held.txt').exists():
                if time.monotonic() > deadline or process.poll() is not None:
                    self.fail('持锁进程未启动')
                time.sleep(0.05)
            for arguments in (['crap'], ['mutate', 'common/First.lua']):
                result = invoke_graph(self.root, *arguments)
                self.assertEqual(1, result.returncode, result.stdout + result.stderr)
                self.assertIn('正在运行', result.stdout + result.stderr)
                record = result_record(self.root)
                self.assertIsNotNone(record)
                self.assertFalse(record['validResult'], '被锁拒绝不是有效质量结果')
                self.assertEqual(1, record['exitCode'])
            terminal = invoke_terminal(self.root, 'refresh-crap')
            self.assertEqual(1, terminal.returncode, terminal.stdout + terminal.stderr)
            self.assertEqual((terminal.stdout + terminal.stderr).strip(),
                             (invoke_graph(self.root, 'crap').stdout + invoke_graph(self.root, 'crap').stderr).strip(),
                             '图上与终端的锁失败报告必须一致')
        finally:
            process.kill()
            process.wait(timeout=10)


class DoctorDispatchCheckTest(unittest.TestCase):
    """doctor 核对声明式分发：图上入口的前提缺失时明确失败，而不是等到右键才发现。

    公开接缝是 `project.ps1 doctor`；分发校验在其它环境核对之前执行，
    因此隔离项目只需 uml-quality.json 与 project.json 就能观察失败信息。
    """

    declared = staticmethod(declared)

    def isolated_root(self, directory):
        root = Path(directory)
        quality = root / 'tools/quality'
        quality.mkdir(parents=True)
        (quality / 'project.json').write_text(json.dumps({
            'sources': {'roots': ['common'], 'exclude': ['packages']},
            # 故意指向不存在的解释器：分发核对必须先于环境核对，配置问题才不会被环境噪音掩盖。
            'lua': {'executable': 'missing-lua-for-isolation', 'version': 'Lua 5.4.'},
            'commands': {'coverage': coverage_argv(PASSING_STATS), 'mutation_test': coverage_argv(PASSING_STATS)},
            'paths': {'luacov': 'unused', 'stats': 'build/stats', 'lcov': 'target/lcov.info',
                      'crap': '.metrics/crap.edn', 'mutation': '.metrics/mutate'},
            'lua_tools': {}, 'tools': {}, 'busted': {},
        }), encoding='utf-8')
        return root

    def run_doctor(self, root, payload):
        path = root / 'uml-quality.json'
        if payload is None:
            path.unlink(missing_ok=True)
        else:
            path.write_text(payload if isinstance(payload, str) else json.dumps(payload), encoding='utf-8')
        env = os.environ.copy()
        env.pop('LUA_PATH', None)
        env.pop('LUA_CPATH', None)
        return subprocess.run([sys.executable, '-B', str(ROOT / 'tools/quality/project.py'),
                               '--root', str(root), '--config', str(root / 'tools/quality/project.json'),
                               'doctor'],
                              cwd=root, env=env, capture_output=True, text=True,
                              encoding='utf-8', errors='replace')

    def test_missing_manifest_fails_doctor(self):
        with tempfile.TemporaryDirectory(prefix='se-fish-doctor-') as directory:
            result = self.run_doctor(self.isolated_root(directory), None)
            self.assertEqual(1, result.returncode, result.stdout + result.stderr)
            self.assertIn('uml-quality.json', result.stdout + result.stderr)

    def test_invalid_manifest_fails_doctor(self):
        for payload in ('{broken',
                        {'version': 1, 'operations': {'crap': self.declared()['operations']['crap']}}):
            with self.subTest(payload=str(payload)[:20]), tempfile.TemporaryDirectory(prefix='se-fish-doctor-') as directory:
                result = self.run_doctor(self.isolated_root(directory), payload)
                self.assertEqual(1, result.returncode, result.stdout + result.stderr)
                self.assertIn('uml-quality.json', result.stdout + result.stderr)

    def test_manifest_mapping_must_match_project_public_entry(self):
        declared = self.declared()
        cases = [
            lambda ops: ops['crap'].__setitem__('argv', ['crapper', '--full-tree']),
            lambda ops: ops['crap'].__setitem__('forwardArgs', 'append'),
            lambda ops: ops['mutate'].__setitem__('forwardArgs', 'none'),
            lambda ops: ops['mutate'].__setitem__('validResultExitCodes', [0]),
        ]
        for index, patch in enumerate(cases):
            with self.subTest(case=index), tempfile.TemporaryDirectory(prefix='se-fish-doctor-') as directory:
                root = self.isolated_root(directory)
                operations = json.loads(json.dumps(declared['operations']))
                patch(operations)
                result = self.run_doctor(root, {'version': 1, 'operations': operations})
                self.assertEqual(1, result.returncode, result.stdout + result.stderr)
                self.assertIn('uml-quality.json', result.stdout + result.stderr)

    def test_repository_manifest_is_accepted(self):
        """仓库根配置通过 doctor 的分发核对：校验规则与实际声明不漂移。"""
        with tempfile.TemporaryDirectory(prefix='se-fish-doctor-') as directory:
            root = self.isolated_root(directory)
            result = self.run_doctor(root, self.declared())
            self.assertIn('标准分发映射相符', result.stdout, result.stdout + result.stderr)
            self.assertNotIn('分发配置', result.stderr, result.stdout + result.stderr)
            self.assertIn('缺少 Lua 解释器', result.stderr, '分发核对已通过，失败应来自隔离环境的解释器缺失')


if __name__ == '__main__':
    unittest.main()

"""以公开项目 CLI 和真实 Lua 执行核对差分记录，不读取内部结构或 mtime。"""
import json
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
COUNTS = r'executed=(\d+) reused=(\d+) uncovered=(\d+) excluded=(\d+)'


class MutationReuseTest(unittest.TestCase):
    # 失败方式：继承误报执行、survived 不重测、digest/位置变化仍复用、
    # 全量仍复用、未覆盖/过滤误报复用、普通输出缺函数计数、失败发布新快照。
    def test_differential_reasons_and_counts_are_public(self):
        version = subprocess.run(['lua', '-v'], capture_output=True, text=True)
        self.assertEqual(version.returncode, 0, version.stdout + version.stderr)
        self.assertIn('Lua 5.4', version.stdout + version.stderr)
        with tempfile.TemporaryDirectory(prefix='se-fish-reuse-') as directory:
            root = Path(directory)
            (root / 'common').mkdir()
            source = root / 'common/Example.lua'
            original = ('local M = {}\n'
                        'function M.strict(x) return x + 1 end\n'
                        'function M.loose(x) return x + 1 end\n'
                        'function M.unused(x)\n  return x + 1\nend\nreturn M\n')
            source.write_text(original, encoding='utf-8')
            test = root / 'test.lua'
            test.write_text('local M=require("common.Example")\n'
                            'assert(M.strict(1)==2)\nassert(type(M.loose(1))=="number")\n',
                            encoding='utf-8')
            settings = json.loads((ROOT / 'tools/quality/project.json').read_text(encoding='utf-8'))
            settings['commands'] = {'coverage': ['lua', '-lluacov', 'test.lua'],
                                    'mutation_test': ['lua', 'test.lua']}
            settings['paths']['luacov'] = str(ROOT / '.toolcache/luacov/src')
            config = root / 'config.json'
            config.write_text(json.dumps(settings), encoding='utf-8')

            def invoke(*extra):
                return subprocess.run(['pwsh', '-NoProfile', '-File', str(ROOT / 'tools/quality/project.ps1'),
                    '--root', str(root), '--config', str(config), 'mutation', 'common/Example.lua',
                    '--max-workers', '2', *extra], cwd=ROOT, timeout=90,
                    capture_output=True, text=True, encoding='utf-8', errors='replace')

            def run(*extra):
                before = source.read_bytes()
                result = invoke(*extra)
                output = result.stdout + result.stderr
                self.assertIn(result.returncode, (0, 3), output)
                self.assertEqual(source.read_bytes(), before)
                total = re.search(r'^Mutation run: ' + COUNTS + r'$', output, re.MULTILINE)
                self.assertIsNotNone(total, output)
                counts = tuple(map(int, total.groups()))
                functions = {}
                for name, *values in re.findall(r'^Mutation function: common.Example/M\.(\S+) ' + COUNTS + r'$',
                                                output, re.MULTILINE):
                    functions[name] = tuple(map(int, values))
                self.assertEqual(set(functions), {'strict', 'loose', 'unused'}, output)
                self.assertEqual(tuple(sum(values[i] for values in functions.values()) for i in range(4)), counts)
                return output, counts, functions

            def details(output, name):
                return [line for line in output.splitlines()
                        if re.match(r'common/Example.lua:\d+ common.Example/M\.' + name + r' ', line)]

            first, counts, functions = run('--verbose')
            self.assertGreater(counts[0], 0)
            self.assertEqual(counts[1], 0)
            self.assertGreater(counts[2], 0)
            for name, outcome in [('strict', 'killed'), ('loose', 'survived')]:
                records = details(first, name)
                self.assertEqual(len(records), functions[name][0])
                self.assertTrue(records)
                self.assertTrue(all('action=executed reason=no-history previous=none result=' + outcome
                                    in line for line in records), first)
            self.assertTrue(all('action=uncovered reason=uncovered previous=none result=uncovered'
                                in line for line in details(first, 'unused')), first)

            ordinary, ordinary_counts, ordinary_functions = run()
            self.assertNotIn('action=', ordinary)
            self.assertEqual(ordinary_functions['strict'], (0, functions['strict'][0], 0, 0))
            self.assertEqual(ordinary_functions['loose'], functions['loose'])
            second, counts, functions = run('--verbose')
            self.assertEqual(counts, ordinary_counts)
            self.assertGreater(counts[0], 0, second)
            self.assertGreater(counts[1], 0, second)
            self.assertTrue(all('action=reused reason=unchanged-killed previous=killed result=killed'
                                in line for line in details(second, 'strict')), second)
            self.assertTrue(all('action=executed reason=previous-survived previous=survived result=survived'
                                in line for line in details(second, 'loose')), second)

            source.write_text(original.replace('M.strict(x) return x + 1', 'M.strict(x) return x + 2'),
                              encoding='utf-8')
            test.write_text('local M=require("common.Example")\nassert(M.strict(1)==3)\n'
                            'assert(type(M.loose(1))=="number")\n', encoding='utf-8')
            changed, _, functions = run('--verbose')
            self.assertEqual(functions['strict'][1], 0)
            self.assertTrue(all('action=executed reason=digest-changed' in line
                                for line in details(changed, 'strict')), changed)
            source.write_text('-- 位置变化，函数文本不变\n' + source.read_text(encoding='utf-8'), encoding='utf-8')
            moved, counts, _ = run('--verbose')
            self.assertEqual(counts[1], 0)
            for name in ('strict', 'loose'):
                self.assertTrue(all('action=executed reason=id-changed previous=none' in line
                                    for line in details(moved, name)), moved)
            all_output, counts, _ = run('--verbose', '--mutate-all')
            self.assertEqual(counts[1], 0)
            for name in ('strict', 'loose'):
                self.assertTrue(all('action=executed reason=explicit-all' in line
                                    for line in details(all_output, name)), all_output)
            self.assertGreater(counts[2], 0)
            filtered, counts, _ = run('--verbose', '--lines', '999')
            self.assertEqual(counts[0:2], (0, 0))
            self.assertGreater(counts[3], 0)
            for name in ('strict', 'loose'):
                self.assertTrue(all('action=excluded reason=line-filter' in line
                                    for line in details(filtered, name)), filtered)
            self.assertIn('action=uncovered reason=uncovered', filtered)

            # 快照是公开产物；只比对完整字节，失败时不得发布成功记录。
            metrics = root / settings['paths']['mutation']
            snapshots = {path.relative_to(metrics): path.read_bytes() for path in metrics.rglob('*.edn')}
            self.assertTrue(snapshots)
            settings['commands']['mutation_test'] = ['lua', '-e', 'error("fixture baseline failed")']
            config.write_text(json.dumps(settings), encoding='utf-8')
            failed = invoke('--verbose')
            failure_output = failed.stdout + failed.stderr
            self.assertEqual(failed.returncode, 2, failure_output)
            self.assertIn('fixture baseline failed', failure_output)
            self.assertNotIn('Mutation run:', failure_output)
            self.assertEqual({path.relative_to(metrics): path.read_bytes() for path in metrics.rglob('*.edn')}, snapshots)


if __name__ == '__main__':
    unittest.main()

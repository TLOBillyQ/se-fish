"""公开 CRAP 子进程接缝的迁移失败护栏。"""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[3] / "tools/quality/crap.py"
CRAPPER_PYTHON = Path(__file__).resolve().parents[3] / ".uml-viewer/crapper/.venv/Scripts/python.exe"


class CrapFailureTests(unittest.TestCase):
    def test_missing_current_coverage_preserves_previous_snapshot(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "common").mkdir()
            (root / "common/Example.lua").write_text("local M = {}\nfunction M.run() return 1 end\nreturn M\n", encoding="utf-8")
            (root / ".metrics").mkdir()
            snapshot = root / ".metrics/crap.edn"
            snapshot.write_text("previous successful snapshot", encoding="utf-8")
            config = root / "project.json"
            config.write_text(json.dumps({"sources": {"roots": ["common"], "exclude": ["packages", "server/_trigger"]}, "paths": {"lcov": "target/coverage/lua/lcov.info", "crap": ".metrics/crap.edn"}}), encoding="utf-8")
            result = subprocess.run([str(CRAPPER_PYTHON), str(SCRIPT), "--root", str(root), "--config", str(config)], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("LCOV", result.stderr)
            self.assertEqual(snapshot.read_text(encoding="utf-8"), "previous successful snapshot")


if __name__ == "__main__":
    unittest.main()

"""CLI behavior checks using temporary projects and offline release responses."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

GZIM = str(Path(sys.argv.pop(1)).resolve())


class CliTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="gzim cli ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def run_cli(self, *args, env=None):
        return subprocess.run([GZIM, *args], cwd=self.root, env=env,
                              capture_output=True, text=True, timeout=8)

    def test_inline_execution_and_failures(self):
        result = self.run_cli("eval", 'yap(args[0])', "hello world")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "hello world\n")
        for args in [("eval",), ("eval", "let x be"), ("eval", "yap(1 / 0)")]:
            self.assertNotEqual(self.run_cli(*args).returncode, 0)

    def test_directory_check_continues_and_skips_generated_trees(self):
        for name, source in [("good.gzim", 'yap("not executed")'),
                             ("nested/bad.gzim", "let x be"),
                             ("build/ignored.gzim", "invalid source"),
                             (".gzim/ignored.gzim", "invalid source")]:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(source)
        result = self.run_cli("check", ".")
        self.assertEqual(result.returncode, 1)
        self.assertIn("2 checked, 1 failed", result.stdout)
        self.assertIn("bad.gzim", result.stderr)
        self.assertNotIn("not executed", result.stdout)
        (self.root / "nested/bad.gzim").write_text("yap(1)")
        self.assertEqual(self.run_cli("check", ".").returncode, 0)

    def test_empty_or_missing_check_target(self):
        self.assertNotEqual(self.run_cli("check", ".").returncode, 0)
        self.assertNotEqual(self.run_cli("check", "missing").returncode, 0)

    def test_doctor_identifies_executable(self):
        result = self.run_cli("doctor")
        self.assertEqual(result.returncode, 0)
        self.assertIn(GZIM, result.stdout)

    @unittest.skipIf(os.name == "nt", "POSIX fake curl fixture")
    def test_update_comparison_and_invalid_responses(self):
        curl = self.root / "curl"
        curl.write_text('#!/bin/sh\nprintf "%s" "$FAKE_RELEASE"\n')
        curl.chmod(0o755)
        env = dict(os.environ, PATH=str(self.root), GZIM_NO_UPDATE_CHECK="0")
        current = self.run_cli("--version", "--offline").stdout
        for tag, expected in [("v2.0.6", False), ("v2.0.5", False), ("v2.0.4", False), ("v2.0.3", False),
                              ("v2.0.10", True), ("v2.1.0", True),
                              ("v10.0.0", True), ("v2.1.0-rc.1", False)]:
            env["FAKE_RELEASE"] = json.dumps({"tag_name": tag})
            result = self.run_cli("--version", env=env)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.stdout, current)
            self.assertEqual("Update available:" in result.stderr, expected, result.stderr)
            if expected:
                self.assertIn("install.", result.stderr)
                self.assertIn("GZIM_INSTALL_ROOT", result.stderr)
        for response in ["invalid json", "[]", '{"tag_name": "v9.0.0", "prerelease": true}',
                         '{"tag_name": "v9.0.0", "draft": true}']:
            env["FAKE_RELEASE"] = response
            result = self.run_cli("--version", env=env)
            self.assertEqual(result.stdout, current)
            self.assertEqual(result.returncode, 0)
            self.assertNotIn("Update available:", result.stderr)
        env["FAKE_RELEASE"] = '{"tag_name": "v9.0.0"}'
        self.assertEqual(self.run_cli("--version", "--offline", env=env).stderr, "")
        env["GZIM_NO_UPDATE_CHECK"] = "1"
        self.assertEqual(self.run_cli("--version", env=env).stderr, "")
        env["GZIM_NO_UPDATE_CHECK"] = "0"
        curl.write_text('#!/bin/sh\nexit 28\n')
        started = time.monotonic()
        result = self.run_cli("--version", env=env)
        self.assertLess(time.monotonic() - started, 4)
        self.assertEqual(result.returncode, 0)
        self.assertIn("unavailable", result.stderr)
        curl.unlink()
        self.assertEqual(self.run_cli("--version", env=env).returncode, 0)


if __name__ == "__main__":
    unittest.main()

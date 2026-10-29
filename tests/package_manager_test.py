"""Dependency revisions, strict locking, and rollback with offline Git repositories."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

GZIM = str(Path(sys.argv.pop(1)).resolve())


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='gzim packages ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.project = self.root / 'project'
        self.project.mkdir()
        self.cli('init')

    def cli(self, *args, success=True):
        result = subprocess.run([GZIM, *args], cwd=self.project, capture_output=True, text=True, timeout=15)
        if success:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0)
        return result

    def git(self, root, *args):
        return subprocess.run(['git', '-C', str(root), *args], check=True, capture_output=True, text=True).stdout.strip()

    def upstream(self, name):
        root = self.root / name
        root.mkdir()
        self.git(root, 'init', '-b', 'main')
        self.commit(root, 1)
        return root

    def commit(self, root, value):
        (root / 'main.gzim').write_text(f'let value be {value}\n')
        self.git(root, 'add', 'main.gzim')
        self.git(root, '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '-m', str(value))
        return self.git(root, 'rev-parse', 'HEAD')

    def revision(self, name):
        return self.git(self.project / '.gzim/packages' / name, 'rev-parse', 'HEAD')

    def test_branch_lock_and_explicit_update(self):
        upstream = self.upstream('upstream')
        self.cli('add', 'cool', upstream.as_uri() + '#main')
        first = self.revision('cool')
        second = self.commit(upstream, 2)
        lock_before = (self.project / 'gzim.lock').read_bytes()
        self.cli('install', '--locked')
        self.assertEqual(self.revision('cool'), first)
        self.assertEqual((self.project / 'gzim.lock').read_bytes(), lock_before)
        self.cli('install')
        self.assertEqual(self.revision('cool'), first)
        self.cli('update', 'cool')
        self.assertEqual(self.revision('cool'), second)
        self.assertEqual(json.loads((self.project / 'gzim.lock').read_text())['packages']['cool']['revision'], second)

    def test_update_one_preserves_other_pins_and_update_all_refreshes(self):
        a, b = self.upstream('a'), self.upstream('b')
        self.cli('add', 'a', a.as_uri() + '#main')
        self.cli('add', 'b', b.as_uri() + '#main')
        original_b = self.revision('b')
        new_a, new_b = self.commit(a, 2), self.commit(b, 2)
        self.cli('update', 'a')
        self.assertEqual(self.revision('a'), new_a)
        self.assertEqual(self.revision('b'), original_b)
        self.cli('update')
        self.assertEqual(self.revision('b'), new_b)

    def test_locked_requires_matching_manifest_before_installing(self):
        self.cli('install', '--locked', success=False)
        source = self.upstream('upstream')
        self.cli('add', 'cool', source.as_uri())
        before = self.revision('cool')
        lock = self.project / 'gzim.lock'
        lock_before = lock.read_bytes()
        manifest = self.project / 'gzim.toml'
        manifest.write_text(manifest.read_text().replace(source.as_uri(), source.as_uri() + '#main'))
        self.cli('install', '--locked', success=False)
        self.assertEqual(self.revision('cool'), before)
        self.assertEqual(lock.read_bytes(), lock_before)

    def test_failed_batch_update_preserves_all_installed_packages(self):
        a, b = self.upstream('a'), self.upstream('b')
        self.cli('add', 'a', a.as_uri() + '#main')
        self.cli('add', 'b', b.as_uri() + '#main')
        original_a, original_b = self.revision('a'), self.revision('b')
        lock_before = (self.project / 'gzim.lock').read_bytes()
        manifest_before = (self.project / 'gzim.toml').read_bytes()
        self.commit(a, 2)
        self.git(b, 'branch', '-m', 'missing-main')
        self.cli('update', success=False)
        self.assertEqual(self.revision('a'), original_a)
        self.assertEqual(self.revision('b'), original_b)
        self.assertEqual((self.project / 'gzim.lock').read_bytes(), lock_before)
        self.assertEqual((self.project / 'gzim.toml').read_bytes(), manifest_before)
        self.assertEqual(list((self.project / '.gzim').glob('.install-*')), [])

    def test_package_named_backup_is_valid(self):
        source = self.upstream('upstream')
        self.cli('add', 'backup', source.as_uri())
        self.cli('install', '--locked')
        self.assertEqual(self.revision('backup'), self.git(source, 'rev-parse', 'HEAD'))


if __name__ == '__main__':
    unittest.main()

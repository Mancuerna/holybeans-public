import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from tool.ci.publish_selected import check_run
from tool.ci.release_artifact import checked_tag, verify_bundle, verify_manifest
from tool.ci.scope import requires_flutter


class CiScopeTests(unittest.TestCase):
    def test_only_documentation_skips_flutter(self):
        self.assertFalse(requires_flutter(['README.md', 'docs/RELEASING.md']))
        self.assertTrue(requires_flutter(['docs/generator.py']))
        self.assertTrue(requires_flutter(['README.md', 'lib/main.dart']))
        self.assertTrue(requires_flutter(['.github/workflows/ci.yml']))
        self.assertTrue(requires_flutter(['unknown-file']))
        self.assertTrue(requires_flutter([]))

    def test_git_scope_covers_renames_and_documentation(self):
        script = Path(__file__).parents[1] / 'ci/scope.py'
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args):
                return subprocess.check_output(['git', '-C', str(root), *args], text=True).strip()
            git('init', '-q')
            git('config', 'user.name', 'Test')
            git('config', 'user.email', 'test@example.invalid')
            (root / 'lib').mkdir()
            (root / 'docs').mkdir()
            (root / 'lib/main.dart').write_text('source\n')
            (root / 'README.md').write_text('readme\n')
            git('add', '.')
            git('commit', '-qm', 'Initial fixture')
            base = git('rev-parse', 'HEAD')
            (root / 'README.md').write_text('Updated readme\n')
            git('add', '.')
            git('commit', '-qm', 'Documentation')
            output = root / '.output'
            env = {**os.environ, 'BASE_SHA': base, 'FULL_VALIDATION': 'false',
                   'GITHUB_OUTPUT': str(output)}
            subprocess.run([sys.executable, str(script),], cwd=root, env=env,
                           check=True, capture_output=True)
            self.assertEqual(output.read_text(), 'flutter=false\n')
            output.unlink()
            # A source renamed into docs must still trigger code validation.
            git('mv', 'lib/main.dart', 'docs/old.md')
            git('commit', '-qm', 'Move source')
            subprocess.run([sys.executable, str(script)], cwd=root, env=env,
                           check=True, capture_output=True)
            self.assertEqual(output.read_text(), 'flutter=true\n')


class ReleaseArtifactTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bundle = self.root / 'holybeans-1.1.20-158.aab'
        self.bundle.write_bytes(b'test bundle')
        self.notes = self.root / 'play-notes.md'
        self.notes.write_text('<es-ES>Corrección.</es-ES>\n<en-GB>Fix.</en-GB>')
        self.sha = hashlib.sha256(self.bundle.read_bytes()).hexdigest()
        self.manifest = {'tag': 'v1.1.20', 'commit': 'a' * 40,
                         'package': 'com.caffeinateddev.holybeans', 'version': '1.1.20',
                         'version_code': 158, 'bundle': self.bundle.name, 'sha256': self.sha,
                         'notes_sha256': hashlib.sha256(self.notes.read_bytes()).hexdigest()}

    def verify(self):
        return verify_manifest(self.manifest, self.root, 'v1.1.20', 'a' * 40, self.sha)

    def test_same_prebuilt_bundle_is_accepted(self):
        self.assertEqual(self.verify(), self.bundle)

    def test_modified_bundle_is_rejected(self):
        self.bundle.write_bytes(b'changed')
        with self.assertRaises(ValueError):
            self.verify()

    def test_modified_notes_are_rejected(self):
        self.notes.write_text('changed')
        with self.assertRaises(ValueError):
            self.verify()

    def test_wrong_source_package_version_and_traversal_are_rejected(self):
        for key, value in [('commit', 'b' * 40), ('tag', 'v1.1.21'), ('package', 'other'),
                           ('version', '1.1.21'), ('version_code', 157),
                           ('version_code', True), ('bundle', '../other.aab')]:
            with self.subTest(key=key):
                original = self.manifest[key]
                self.manifest[key] = value
                with self.assertRaises(ValueError):
                    self.verify()
                self.manifest[key] = original

    def test_tag_cannot_be_a_branch_or_shell_expression(self):
        for tag in ['main', '--help', 'v1.2', 'v1.2.3;echo', 'v1.2.3/../main']:
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                checked_tag(tag)


class BuildEvidenceTests(unittest.TestCase):
    def test_requires_successful_release_workflow_for_exact_code(self):
        metadata = {'build_run_id': '123', 'commit': 'a' * 40}
        run = {'conclusion': 'success', 'event': 'release',
               'head_sha': 'a' * 40, 'path': '.github/workflows/release-build.yml'}
        with patch.dict('os.environ', {'GITHUB_REPOSITORY': 'example/app'}):
            for event in ('release', 'workflow_dispatch'):
                with self.subTest(event=event):
                    with patch('subprocess.check_output', return_value=json.dumps({**run, 'event': event})):
                        check_run(metadata)
            for field, value in [('conclusion', 'failure'), ('conclusion', None),
                                 ('head_sha', 'b' * 40), ('event', 'pull_request'),
                                 ('event', 'push'), ('event', None),
                                 ('path', '.github/workflows/ci.yml')]:
                with self.subTest(field=field, value=value):
                    invalid = {**run, field: value}
                    with patch('subprocess.check_output', return_value=json.dumps(invalid)):
                        with self.assertRaises(ValueError):
                            check_run(metadata)

    def test_bundle_requires_package_version_signature_and_certificate(self):
        xml = ('<manifest xmlns:android="http://schemas.android.com/apk/res/android" '
               'package="com.caffeinateddev.holybeans" android:versionName="1.1.20" '
               'android:versionCode="158"/>')
        cert = 'SHA256: ' + ':'.join(['AA'] * 32)
        def verify(outputs):
            with patch('subprocess.check_output', side_effect=outputs):
                verify_bundle(Path('app.aab'), Path('bundletool.jar'), '1.1.20', 158, 'aa' * 32)
        verify([xml, 'jar verified.', cert])
        for outputs in [[xml.replace('holybeans', 'other'), 'jar verified.', cert],
                        [xml.replace('158', '157'), 'jar verified.', cert],
                        [xml, 'jar is unsigned.', cert],
                        [xml, 'jar verified.', cert.replace('AA', 'BB')]]:
            with self.subTest(outputs=outputs), self.assertRaises(ValueError):
                verify(outputs)


if __name__ == '__main__':
    unittest.main()

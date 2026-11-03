from contextlib import contextmanager
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from tool.ci.validation import complete_jobs, find_validation, fingerprint, main, reusable_run, validate_metadata
from tool.publish_play import PublishError


@contextmanager
def working_directory(path):
    previous = Path.cwd()
    os.chdir(path)
    try:
        yield
    finally:
        os.chdir(previous)


class ValidationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.git('init', '-q')
        self.git('config', 'user.name', 'Test')
        self.git('config', 'user.email', 'test@example.invalid')
        self.write('pubspec.yaml', 'name: app\nversion: 1.2.1+159\ndependencies: {}\n')
        self.write('.release-please-manifest.json', '{".": "1.2.1"}\n')
        self.write('docs/releases/1.2.1.md', '<es-ES>Mejora.</es-ES>\n<en-GB>Improvement.</en-GB>\n')
        self.write('lib/main.dart', 'source\n')
        self.write('pubspec.lock', 'locked dependencies\n')
        self.write('.github/workflows/ci.yml', 'workflow\n')
        self.write('tool/ci/validation.py', 'validation logic\n')
        self.commit = self.save()

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.root), *args], text=True).strip()

    def write(self, path, text):
        file = self.root / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(text)

    def save(self):
        self.git('add', '.')
        self.git('commit', '-qm', 'Fixture')
        return self.git('rev-parse', 'HEAD')

    def source(self, ref='HEAD'):
        with working_directory(self.root):
            return fingerprint(ref)

    def run_record(self, **changes):
        return {'id': 10, 'run_attempt': 1, 'status': 'completed', 'conclusion': 'success',
                'path': '.github/workflows/ci.yml', 'event': 'pull_request',
                'head_repository': {'full_name': 'example/app'}, 'head_sha': self.commit,
                'created_at': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'), **changes}

    def test_release_metadata_and_documentation_preserve_tested_source(self):
        before = self.source()
        self.write('pubspec.yaml', 'name: app\nversion: 1.2.2+160\ndependencies: {}\n')
        self.write('.release-please-manifest.json', '{".": "1.2.2"}\n')
        self.write('docs/releases/1.2.2.md', '<es-ES>Otra mejora.</es-ES>\n<en-GB>Another improvement.</en-GB>')
        self.write('CHANGELOG.md', 'Release notes\n')
        self.write('README.md', 'Documentation\n')
        self.save()
        validate_metadata(self.root)
        self.assertEqual(before, self.source())

    def test_source_dependencies_workflow_and_validation_changes_invalidate_evidence(self):
        before = self.source()
        for path in ('lib/main.dart', 'pubspec.lock', 'pubspec.yaml',
                     '.github/workflows/ci.yml', 'tool/ci/validation.py',
                     'android/app/proguard-rules.pro', 'docs/generator.py'):
            with self.subTest(path=path):
                self.git('reset', '--hard', self.commit)
                file = self.root / path
                self.write(path, (file.read_text() if file.exists() else '') + '# changed\n')
                self.save()
                self.assertNotEqual(before, self.source())

    def test_removed_files_and_executable_mode_invalidate_evidence(self):
        before = self.source()
        (self.root / 'lib/main.dart').chmod(0o755)
        self.save()
        self.assertNotEqual(before, self.source())
        self.git('reset', '--hard', self.commit)
        (self.root / 'lib/main.dart').unlink()
        self.save()
        self.assertNotEqual(before, self.source())

    def test_invalid_or_mismatched_release_metadata_is_rejected(self):
        for path, text in [('pubspec.yaml', 'version: 1.2.1+159\nversion: 1.2.2+160\n'),
                           ('pubspec.yaml', 'version: 1.2.1+157\n'),
                           ('.release-please-manifest.json', '{".": "1.2.0"}'),
                           ('docs/releases/1.2.1.md', 'No translated notes')]:
            with self.subTest(path=path):
                self.git('reset', '--hard', self.commit)
                self.write(path, text)
                with self.assertRaises((ValueError, PublishError)):
                    validate_metadata(self.root)

    def test_reuse_rejects_failed_stale_fork_wrong_workflow_and_current_runs(self):
        cutoff = '2026-01-01T00:00:00Z'
        good = self.run_record(created_at='2026-02-01T00:00:00Z')
        self.assertTrue(reusable_run(good, 'example/app', '99', cutoff))
        for change in ({'id': 99}, {'status': 'in_progress'}, {'conclusion': 'failure'},
                       {'conclusion': 'skipped'}, {'path': '.github/workflows/other.yml'},
                       {'event': 'pull_request_target'}, {'head_sha': '--invalid'},
                       {'head_repository': None},
                       {'created_at': '2025-12-31T00:00:00Z'},
                       {'head_repository': {'full_name': 'fork/app'}}):
            with self.subTest(change=change):
                self.assertFalse(reusable_run({**good, **change}, 'example/app', '99', cutoff))

    def test_release_metadata_cannot_reuse_build_number_or_downgrade_version(self):
        for name, code, allowed in [('1.2.2', 160, True), ('1.2.2', 159, False),
                                    ('1.2.0', 160, False), ('1.2.1', 159, True)]:
            with self.subTest(name=name, code=code), working_directory(self.root):
                self.write('pubspec.yaml', f'version: {name}+{code}\n')
                self.write('.release-please-manifest.json', json.dumps({'.': name}))
                self.write(f'docs/releases/{name}.md', '<es-ES>Mejora.</es-ES>\n<en-GB>Improvement.</en-GB>')
                if allowed:
                    validate_metadata(self.root, self.commit)
                else:
                    with self.assertRaises(ValueError):
                        validate_metadata(self.root, self.commit)

    def test_only_complete_passing_jobs_are_evidence(self):
        jobs = [{'name': name, 'status': 'completed', 'conclusion': 'success'}
                for name in ('scope', 'flutter', 'android', 'CI result')]
        self.assertTrue(complete_jobs(jobs))
        for name in ('flutter', 'android'):
            for conclusion in ('skipped', 'failure', 'cancelled'):
                with self.subTest(name=name, conclusion=conclusion):
                    changed = [{**j, 'conclusion': conclusion} if j['name'] == name else j for j in jobs]
                    self.assertFalse(complete_jobs(changed))

    def test_matching_head_reuses_full_run_but_not_successful_lightweight_run(self):
        full = self.run_record()
        lightweight = self.run_record(id=11)
        jobs = [{'name': name, 'status': 'completed', 'conclusion': 'success'}
                for name in ('flutter', 'android')]
        def fetch(path):
            if '/workflows/' in path:
                return {'workflow_runs': [lightweight, full]}
            return {'jobs': [] if '/runs/11/' in path else jobs}
        with working_directory(self.root):
            self.assertEqual(find_validation('example/app', '99', fingerprint(), fetch)['id'], 10)
            self.write('lib/main.dart', 'different source\n')
            self.save()
            self.assertIsNone(find_validation('example/app', '99', fingerprint(), fetch))

    def test_unavailable_api_and_force_full_run_tests(self):
        for force in ('true', 'false'):
            with self.subTest(force=force), working_directory(self.root):
                output = self.root / 'output'
                output.write_text('')
                env = {'GITHUB_OUTPUT': str(output), 'GITHUB_REPOSITORY': 'example/app',
                       'GITHUB_RUN_ID': '99', 'GITHUB_STEP_SUMMARY': '', 'FORCE_FULL': force}
                with patch.dict(os.environ, env), patch('tool.ci.validation.find_validation', side_effect=OSError) as find:
                    main()
                self.assertEqual(output.read_text(), 'full=true\n')
                self.assertEqual(find.call_count, 0 if force == 'true' else 1)


if __name__ == '__main__':
    unittest.main()

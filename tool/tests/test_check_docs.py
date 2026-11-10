from pathlib import Path
import tempfile
import unittest

from tool.ci.check_docs import check


class CheckDocsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.database = 'lib/data/database/app_database.dart'
        self.backup = 'lib/data/services/journal_backup.dart'
        self.write(self.database, 'static const currentSchema = 38;\n')
        self.write(self.backup, 'static const version = 36;\n')
        self.data = ('The current database schema is **38** and\n'
                     'the current backup format is **36**.\n')
        self.write('docs/DATA.md', self.data)

    def write(self, path, text):
        file = self.root / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(text)

    def test_current_versions_and_valid_links_pass(self):
        self.write('README.md', '[Data](docs/DATA.md#compatibility)\n'
                   '[Website](https://example.com) [Email](mailto:a@example.com)')
        self.assertEqual(check(self.root), [])

    def test_stale_documented_versions_fail(self):
        for current, stale in [('38', '37'), ('36', '35')]:
            with self.subTest(current=current):
                self.write('docs/DATA.md', self.data.replace(current, stale))
                errors = check(self.root)
                self.assertEqual(len(errors), 1)
                self.assertIn('docs/DATA.md', errors[0])
                self.assertIn(current, errors[0])
                self.assertIn(stale, errors[0])

    def test_source_version_changes_require_documentation_update(self):
        for path, declaration in [
            (self.database, 'static const currentSchema = 39;\n'),
            (self.backup, 'static const version = 37;\n'),
        ]:
            with self.subTest(path=path):
                previous = (self.root / path).read_text()
                self.write(path, declaration)
                self.assertEqual(len(check(self.root)), 1)
                self.write(path, previous)

    def test_missing_documented_version_is_not_silently_accepted(self):
        for phrase in ['database schema', 'backup format']:
            with self.subTest(phrase=phrase):
                self.write('docs/DATA.md', self.data.replace(phrase, 'unknown'))
                errors = check(self.root)
                self.assertEqual(len(errors), 1)
                self.assertIn(phrase, errors[0])

    def test_missing_source_constant_is_reported(self):
        self.write(self.database, '// No schema declaration.\n')
        errors = check(self.root)
        self.assertEqual(len(errors), 1)
        self.assertIn('currentSchema', errors[0])

    def test_missing_compatibility_files_are_reported(self):
        for path in ['docs/DATA.md', self.database, self.backup]:
            with self.subTest(path=path):
                previous = (self.root / path).read_text()
                (self.root / path).unlink()
                errors = check(self.root)
                self.assertTrue(any(path in error for error in errors))
                self.write(path, previous)

    def test_missing_relative_links_still_fail(self):
        self.write('README.md', '[Missing](docs/MISSING.md)')
        self.assertEqual(check(self.root), ['README.md: missing docs/MISSING.md'])


if __name__ == '__main__':
    unittest.main()

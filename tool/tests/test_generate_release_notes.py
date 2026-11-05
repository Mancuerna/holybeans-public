from pathlib import Path
import tempfile
import unittest

from tool.generate_release_notes import OUTPUT, dart_string, generate
from tool.publish_play import PublishError


class GenerateReleaseNotesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'docs/releases').mkdir(parents=True)
        (self.root / 'pubspec.yaml').write_text('version: 1.4.1+162\n')
        self.notes = self.root / 'docs/releases/1.4.1.md'
        self.notes.write_text('<es-ES>Mejora actual.</es-ES>\n<en-GB>Current fix.</en-GB>')

    def test_selects_only_current_version_and_ignores_build_number(self):
        (self.root / 'docs/releases/1.4.0.md').write_text(
            '<es-ES>Cambio antiguo.</es-ES>\n<en-GB>Old change.</en-GB>')
        generate(self.root)
        source = (self.root / OUTPUT).read_text()
        self.assertIn("currentReleaseVersion = '1.4.1'", source)
        self.assertIn("'es': 'Mejora actual.'", source)
        self.assertIn("'en': 'Current fix.'", source)
        self.assertNotIn('antiguo', source)
        self.assertNotIn('Old change', source)
        (self.root / 'pubspec.yaml').write_text('version: 1.4.1+163\n')
        generate(self.root)
        self.assertEqual((self.root / OUTPUT).read_text(), source)

    def test_new_version_replaces_previous_generated_content(self):
        generate(self.root)
        (self.root / 'pubspec.yaml').write_text('version: 1.5.0+163\n')
        (self.root / 'docs/releases/1.5.0.md').write_text(
            '<es-ES>Novedad.</es-ES>\n<en-GB>New feature.</en-GB>')
        generate(self.root)
        source = (self.root / OUTPUT).read_text()
        self.assertIn("currentReleaseVersion = '1.5.0'", source)
        self.assertIn('New feature.', source)
        self.assertNotIn('Current fix.', source)

    def test_missing_version_or_translations_fail_generation(self):
        self.notes.unlink()
        with self.assertRaises(FileNotFoundError):
            generate(self.root)
        for body in [
            '<es-ES>Mejora.</es-ES>',
            '<en-GB>Fix.</en-GB>',
            '<es-ES> </es-ES><en-GB>Fix.</en-GB>',
            '<es-ES>Mejora.</es-ES><en-GB> </en-GB>',
            '<es-ES>' + 'x' * 501 + '</es-ES><en-GB>Fix.</en-GB>',
        ]:
            with self.subTest(body=body):
                self.notes.write_text(body)
                with self.assertRaises(PublishError):
                    generate(self.root)
        self.assertFalse((self.root / OUTPUT).exists())

    def test_dart_literals_escape_quotes_interpolation_and_line_breaks(self):
        self.assertEqual(dart_string("It's $5"), "'It\\'s \\$5'")
        self.assertEqual(dart_string('${value}'), "'\\${value}'")
        self.assertEqual(dart_string('a\\b\nc\rd\t'), "'a\\\\b\\nc\\rd\\t'")
        self.assertEqual(dart_string('Café ☕'), "'Café ☕'")


if __name__ == '__main__':
    unittest.main()

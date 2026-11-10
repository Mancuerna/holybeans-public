"""Check relative Markdown links and documented data versions locally."""
from pathlib import Path
import re


def check_data_versions(root):
    documentation = root / 'docs/DATA.md'
    if not documentation.is_file():
        return ['docs/DATA.md: missing compatibility documentation']
    text = documentation.read_text()
    errors = []
    for path, constant, label in [
        ('lib/data/database/app_database.dart', 'currentSchema', 'database schema'),
        ('lib/data/services/journal_backup.dart', 'version', 'backup format'),
    ]:
        source = root / path
        if not source.is_file():
            errors.append(f'{path}: missing version source')
            continue
        declarations = re.findall(
            rf'^\s*static const {constant}\s*=\s*(\d+)\s*;',
            source.read_text(), re.MULTILINE)
        if len(declarations) != 1:
            errors.append(f'{path}: expected one numeric {constant} declaration')
            continue
        documented = re.findall(
            rf'current\s+{label}\s+is\s+\*\*(\d+)\*\*', text)
        if len(documented) != 1:
            errors.append(f'docs/DATA.md: expected one current {label} version')
        elif documented[0] != declarations[0]:
            errors.append(f'docs/DATA.md: {label} is {documented[0]}, '
                          f'expected {declarations[0]} from {path}')
    return errors


def check(root):
    errors = check_data_versions(root)
    for source in [*root.glob('*.md'), *root.glob('docs/**/*.md')]:
        text = source.read_text()
        for link in re.findall(r'\]\(([^)]+)\)', text):
            link = link.split('#', 1)[0]
            if not link or '://' in link or link.startswith('mailto:'):
                continue
            if not (source.parent / link).exists():
                errors.append(f'{source.relative_to(root)}: missing {link}')
    return errors


if __name__ == '__main__':
    errors = check(Path.cwd())
    if errors:
        raise SystemExit('\n'.join(errors))
    print('Relative documentation links and data versions verified.')

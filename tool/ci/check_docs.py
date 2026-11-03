"""Check relative Markdown links without accessing the network."""
from pathlib import Path
import re


def check(root):
    errors = []
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
    print('Relative documentation links verified.')

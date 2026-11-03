"""Conservative CI selection: only known documentation paths skip Flutter."""
import os
from pathlib import PurePosixPath
import subprocess


def requires_flutter(paths):
    def documentation(path):
        return (path in {'README.md', 'README.es.md', 'CONTRIBUTING.md', 'CHANGELOG.md'}
                or (path.startswith('docs/') and PurePosixPath(path).suffix in {'.md', '.png', '.jpg', '.svg'})
                or path.startswith('.github/ISSUE_TEMPLATE/'))
    return not paths or any(not documentation(path) for path in paths)


def main():
    full = os.environ.get('FULL_VALIDATION') == 'true'
    base = os.environ.get('BASE_SHA', '')
    if not full and base and set(base) != {'0'}:
        result = subprocess.run(['git', 'diff', '--no-renames', '--name-only', '-z', base, 'HEAD'], capture_output=True)
        full = result.returncode != 0 or requires_flutter(
            [p for p in result.stdout.decode().split('\0') if p])
        if result.returncode == 0:
            subprocess.run(['git', 'diff', '--check', base, 'HEAD'], check=True)
        else:
            subprocess.run(['git', 'show', '--format=', '--check', 'HEAD'], check=True)
    else:
        full = True
        subprocess.run(['git', 'show', '--format=', '--check', 'HEAD'], check=True)
    with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
        output.write(f'flutter={str(full).lower()}\n')
    print('Full code validation selected.' if full else 'Documentation-only checks selected; Flutter tests not run.')


if __name__ == '__main__':
    main()

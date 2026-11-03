"""Publish downloaded, verified inputs with the publisher from the default branch."""
import argparse
import json
import os
from pathlib import Path
import subprocess

from tool.publish_play import PlayPublisher, build_plan, print_plan


def check_run(metadata):
    run_id = metadata['build_run_id']
    if not isinstance(run_id, str) or not run_id.isdigit():
        raise ValueError('Invalid release build run ID.')
    repository = os.environ['GITHUB_REPOSITORY']
    run = json.loads(subprocess.check_output(
        ['gh', 'api', f'repos/{repository}/actions/runs/{run_id}'], text=True))
    if (run.get('conclusion') != 'success' or run.get('event') not in {'release', 'workflow_dispatch'}
            or run.get('head_sha') != metadata['commit']
            or run.get('path') != '.github/workflows/release-build.yml'):
        raise ValueError('A successful release-build run for this commit is required.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check-run', action='store_true')
    parser.add_argument('--publish', action='store_true')
    parser.add_argument('--credentials', type=Path)
    args = parser.parse_args()
    root = Path('release-inputs')
    metadata = json.loads((root / 'release.json').read_text())
    if args.check_run:
        check_run(metadata)
        return
    plan = build_plan(root, root / metadata['bundle'], root / 'play-notes.md', os.environ['TRACK'])
    if (plan.version_name != metadata['version'] or plan.version_code != metadata['version_code']
            or plan.sha256 != metadata['sha256']):
        raise ValueError('The selected pubspec does not match the verified artifact.')
    print_plan(plan)
    if args.publish:
        if args.credentials is None:
            parser.error('--credentials is required with --publish')
        PlayPublisher(log=print).publish(plan, args.credentials)
    else:
        print('Dry run only. No Play requests made.')


if __name__ == '__main__':
    main()

"""Reuse recent complete CI only when the checked source has the same contents."""
from datetime import datetime, timedelta, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

from tool.ci.scope import documentation
from tool.publish_play import parse_release_notes

VERSION = re.compile(rb'^version: ([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)$', re.MULTILINE)
SHA = re.compile(r'[0-9a-f]{40}')
WORKFLOW = '.github/workflows/ci.yml'
FULL_JOBS = {'flutter', 'android', 'release'}


def git(*args):
    return subprocess.check_output(['git', *args], stderr=subprocess.PIPE, timeout=60)


def version(data):
    matches = list(VERSION.finditer(data))
    if len(matches) != 1:
        raise ValueError('Expected exactly one stable version+build line in pubspec.yaml.')
    match = matches[0]
    return match[1].decode(), int(match[2])


def validate_metadata(root, base=None):
    name, code = version((root / 'pubspec.yaml').read_bytes())
    if code <= 157:
        raise ValueError('Release build numbers must continue after 157.')
    if json.loads((root / '.release-please-manifest.json').read_text()) != {'.': name}:
        raise ValueError('Release manifest and pubspec version must agree.')
    parse_release_notes(root / 'docs/releases' / f'{name}.md')
    if base and set(base) != {'0'}:
        if not SHA.fullmatch(base):
            raise ValueError('Invalid base commit.')
        old_name, old_code = version(git('show', f'{base}:pubspec.yaml'))
        if (name, code) != (old_name, old_code):
            numbers = lambda value: tuple(map(int, value.split('.')))
            if numbers(name) < numbers(old_name) or code <= old_code:
                raise ValueError('Version changes must advance the build number without downgrading the version.')


def fingerprint(ref='HEAD'):
    """Hash Git blobs and modes, excluding docs and separately checked release metadata."""
    digest = hashlib.sha256(b'holybeans-ci-source-v1\0')
    entries = git('ls-tree', '-r', '-z', ref).split(b'\0')
    for entry in entries:
        if not entry:
            continue
        metadata, path_bytes = entry.split(b'\t', 1)
        path = path_bytes.decode()
        if documentation(path) or path == '.release-please-manifest.json':
            continue
        mode, kind, oid = metadata.split()
        if path == 'pubspec.yaml':
            data = git('show', f'{ref}:pubspec.yaml')
            name, _ = version(data)
            normalized = VERSION.sub(f'version: {name}+<checked separately>'.encode(), data)
            oid = hashlib.sha256(normalized).hexdigest().encode()
        digest.update(b'\0'.join((mode, kind, oid, path_bytes)) + b'\0')
    return digest.hexdigest()


def api(path):
    return json.loads(subprocess.check_output(
        ['gh', 'api', path], stderr=subprocess.PIPE, text=True, timeout=60))


def reusable_run(run, repository, current_run, cutoff):
    return (str(run.get('id')) != current_run
            and run.get('status') == 'completed' and run.get('conclusion') == 'success'
            and run.get('path') == WORKFLOW
            and run.get('event') in {'push', 'pull_request', 'workflow_dispatch'}
            and (run.get('head_repository') or {}).get('full_name') == repository
            and run.get('created_at', '') >= cutoff
            and SHA.fullmatch(run.get('head_sha', '')) is not None)


def complete_jobs(jobs):
    # A successful lightweight/reused run is never evidence for another reuse.
    passed = {job['name'] for job in jobs
              if job.get('status') == 'completed' and job.get('conclusion') == 'success'}
    return FULL_JOBS <= passed


def find_validation(repository, current_run, source, fetch=api):
    cutoff = (datetime.now(timezone.utc) - timedelta(days=7)).strftime('%Y-%m-%dT%H:%M:%SZ')
    runs = fetch(f'repos/{repository}/actions/workflows/ci.yml/runs?status=success&per_page=100')['workflow_runs']
    seen = set()
    examined = 0
    for run in runs:
        if not reusable_run(run, repository, current_run, cutoff):
            continue
        commit = run['head_sha']
        if commit in seen:
            continue
        # Bound API/Git work; a miss always falls back to complete tests.
        examined += 1
        if examined > 20:
            break
        try:
            try:
                git('cat-file', '-e', f'{commit}^{{commit}}')
            except subprocess.CalledProcessError:
                git('fetch', '--no-tags', 'origin', commit)
            if fingerprint(commit) != source:
                seen.add(commit)
                continue
            jobs = fetch(f'repos/{repository}/actions/runs/{run["id"]}/attempts/{run["run_attempt"]}/jobs?per_page=100')['jobs']
            if complete_jobs(jobs):
                return run
        except (subprocess.SubprocessError, OSError, ValueError, KeyError):
            continue
    return None


def main():
    validate_metadata(Path.cwd())
    source = fingerprint()
    run = None
    reason = 'Complete tests required: no matching successful full CI found.'
    if os.environ.get('FORCE_FULL') != 'true':
        try:
            run = find_validation(os.environ['GITHUB_REPOSITORY'], os.environ['GITHUB_RUN_ID'], source)
        except (subprocess.SubprocessError, OSError, ValueError, KeyError):
            reason = 'CI evidence unavailable; running the complete tests.'
    else:
        reason = 'Complete tests explicitly requested.'
    if run:
        reason = f'Reusing complete CI run {run["id"]} for source fingerprint {source}.'
    with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
        output.write(f'full={str(run is None).lower()}\n')
    print(reason)
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as summary:
            summary.write(reason + '\n')
            if run:
                repository = os.environ['GITHUB_REPOSITORY']
                summary.write(f'Validated commit: `{run["head_sha"]}`. '
                              f'[Evidence](https://github.com/{repository}/actions/runs/{run["id"]}).\n')


if __name__ == '__main__':
    main()

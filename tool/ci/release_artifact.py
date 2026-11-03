"""Bind a release bundle to its tag, source revision, notes and upload certificate."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET

from tool.publish_play import PACKAGE, parse_release_notes, pubspec_version


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def checked_tag(tag):
    if not re.fullmatch(r'v[0-9]+\.[0-9]+\.[0-9]+', tag):
        raise ValueError('Expected a stable release tag such as v1.1.20.')
    return tag


def verify_manifest(manifest, directory, tag, commit, expected_sha256):
    checked_tag(tag)
    if not re.fullmatch(r'[0-9a-f]{64}', expected_sha256):
        raise ValueError('An explicit lowercase SHA-256 from the build is required.')
    if (manifest.get('tag') != tag or manifest.get('commit') != commit
            or manifest.get('package') != PACKAGE or manifest.get('version') != tag[1:]):
        raise ValueError('Release identity does not match the requested tag and commit.')
    code = manifest.get('version_code')
    if type(code) is not int or code <= 157:
        raise ValueError('The new release must continue the existing Play version codes.')
    expected = f'holybeans-{tag[1:]}-{code}.aab'
    if manifest.get('bundle') != expected:
        raise ValueError('Invalid bundle filename.')
    bundle = directory / expected
    if digest(bundle) != expected_sha256 or manifest.get('sha256') != expected_sha256:
        raise ValueError('Bundle checksum mismatch.')
    notes = directory / 'play-notes.md'
    if digest(notes) != manifest.get('notes_sha256'):
        raise ValueError('Release notes checksum mismatch.')
    parse_release_notes(notes)
    return bundle


def verify_bundle(bundle, bundletool, version, code, certificate):
    if not re.fullmatch(r'[0-9A-Fa-f:]{64,95}', certificate):
        raise ValueError('Configure the expected upload certificate SHA-256.')
    cert = certificate.replace(':', '').lower()
    if len(cert) != 64:
        raise ValueError('Invalid certificate fingerprint.')
    manifest = subprocess.check_output(
        ['java', '-jar', str(bundletool), 'dump', 'manifest', '--bundle', str(bundle)], text=True)
    root = ET.fromstring(manifest)
    android = '{http://schemas.android.com/apk/res/android}'
    if (root.get('package') != PACKAGE or root.get(android + 'versionName') != version
            or root.get(android + 'versionCode') != str(code)):
        raise ValueError('AAB package or version mismatch.')
    output = subprocess.check_output(
        ['jarsigner', '-J-Duser.language=en', '-verify', str(bundle)], text=True)
    if 'jar verified.' not in output:
        raise ValueError('AAB signature verification failed.')
    output = subprocess.check_output(
        ['keytool', '-J-Duser.language=en', '-printcert', '-jarfile', str(bundle)], text=True)
    actual = re.findall(r'SHA256:\s*([A-Fa-f0-9:]+)', output)
    if len(actual) != 1 or actual[0].replace(':', '').lower() != cert:
        raise ValueError('Unexpected upload signing certificate.')


def stage(args):
    tag = checked_tag(args.tag)
    version, code = pubspec_version(Path.cwd())
    if tag != f'v{version}' or code <= 157:
        raise ValueError('Tag/version mismatch or reused initial version code.')
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
    if commit != args.commit:
        raise ValueError('Checkout is not the release commit.')
    notes = Path('docs/releases') / f'{version}.md'
    parse_release_notes(notes)
    verify_bundle(args.bundle, args.bundletool, version, code, args.certificate)
    args.directory.mkdir(parents=True, exist_ok=False)
    name = f'holybeans-{version}-{code}.aab'
    shutil.copyfile(args.bundle, args.directory / name)
    shutil.copyfile(notes, args.directory / 'play-notes.md')
    data = {'tag': tag, 'commit': commit, 'package': PACKAGE, 'version': version,
            'version_code': code, 'bundle': name, 'sha256': digest(args.bundle),
            'notes_sha256': digest(notes), 'build_run_id': args.run_id}
    (args.directory / 'release.json').write_text(json.dumps(data, indent=2) + '\n')
    print(json.dumps(data, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    build = sub.add_parser('stage')
    build.add_argument('--bundle', required=True, type=Path)
    build.add_argument('--bundletool', required=True, type=Path)
    build.add_argument('--certificate', required=True)
    build.add_argument('--run-id', required=True)
    verify = sub.add_parser('verify')
    verify.add_argument('--sha256', required=True)
    for cmd in (build, verify):
        cmd.add_argument('--tag', required=True)
        cmd.add_argument('--commit', required=True)
        cmd.add_argument('--directory', required=True, type=Path)
    args = parser.parse_args()
    if args.command == 'stage':
        stage(args)
    else:
        data = json.loads((args.directory / 'release.json').read_text())
        bundle = verify_manifest(data, args.directory, args.tag, args.commit, args.sha256)
        print(f'Verified {bundle.name}: {args.sha256}')


if __name__ == '__main__':
    main()

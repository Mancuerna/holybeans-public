"""Exercise the Android signing guard without building or using an upload key.

Run after Flutter dependency resolution with JDK 21 and an Android SDK available:
    python3 -m tool.ci.check_android_signing
"""
import os
from pathlib import Path
import subprocess


VARIABLES = (
    'HOLYBEANS_KEYSTORE',
    'HOLYBEANS_KEYSTORE_PASSWORD',
    'HOLYBEANS_KEY_ALIAS',
    'HOLYBEANS_KEY_PASSWORD',
)
ERROR = 'Release signing requires'


def check(root):
    environment = dict(os.environ)
    for name in (*VARIABLES, 'ORG_GRADLE_PROJECT_allowDebugSigning'):
        environment.pop(name, None)
    # Dry runs never open this deliberately nonexistent keystore.
    complete = dict(zip(VARIABLES, (
        str(root / 'build/signing-test-unused.jks'),
        'test-password', 'test-alias', 'test-password',
    )))
    cases = [
        ('missing signing', ':app:bundleRelease', {}, [], False),
        ('debug without signing', ':app:assembleDebug', {}, [], True),
        ('profile without signing', ':app:assembleProfile', {}, [], True),
        ('explicit debug signing', ':app:bundleRelease', {},
         ['-PallowDebugSigning=true'], True),
        ('environment opt-in', ':app:bundleRelease',
         {'ORG_GRADLE_PROJECT_allowDebugSigning': 'true'}, [], True),
        ('false is not an opt-in', ':app:bundleRelease', {},
         ['-PallowDebugSigning=false'], False),
        ('complete signing', ':app:bundleRelease', complete, [], True),
        ('abbreviated release', ':app:bundleRel', {}, [], False),
        ('aggregate includes release', ':app:assemble', {}, [], False),
    ]
    for name in VARIABLES:
        cases.append((f'missing {name}', ':app:bundleRelease',
                      {key: value for key, value in complete.items()
                       if key != name}, [], False))
        cases.append((f'blank {name}', ':app:bundleRelease',
                      {**complete, name: '  '}, [], False))
    for label, task, values, arguments, allowed in cases:
        result = subprocess.run(
            ['./gradlew', task, '--dry-run', '--console=plain', *arguments],
            cwd=root / 'android', env={**environment, **values},
            capture_output=True, text=True, timeout=300,
        )
        output = result.stdout + result.stderr
        passed = result.returncode == 0 if allowed else (
            result.returncode != 0 and ERROR in output)
        if not passed:
            raise SystemExit(f'FAIL: {label}\n{output}')
        print(f'PASS: {label}', flush=True)


if __name__ == '__main__':
    check(Path(__file__).resolve().parents[2])

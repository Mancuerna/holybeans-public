# Release automation

## What runs when

| Event | Result |
| --- | --- |
| Code PR, or push to `main` | Lightweight checks and complete Flutter/Android tests, or verified reuse of a recent full CI for identical source |
| Documentation-only change | Lightweight checks; the required `CI result` reports that Flutter/Android were skipped |
| Push to `main` with release automation enabled | Release Please updates one pending release PR |
| Merge the reviewed release PR | Release Please creates a tag/release; the release workflow verifies CI evidence (or runs full tests) and builds its signed AAB |
| Manual `Publish selected release to Play` run | Checks an existing bundle; uploads it only if `publish` is explicitly enabled |

Ordinary commits do not create a release or publish to Play. Branch CI cancels
superseded runs; release and Play jobs are serialized without cancellation.
Actions and bundletool are pinned to immutable revisions or checksums.

## Avoiding duplicate validation

Database code regeneration, Flutter formatting, analysis and the full Flutter
suite run in one job. Android unit tests and a release bundle build run in
parallel. The release check uses explicit debug signing, obfuscation and R8; it
receives no upload key and does not publish its bundle. Every invocation still
checks release metadata, documentation, helper tests and whitespace before the
required `CI result` passes.

CI hashes tracked file contents and modes, including application code, tests,
dependencies, build settings, workflows and the reuse helper itself. Versioned
notes in `docs/releases/` and the version name in `pubspec.yaml` are compilation
inputs: changing either requires complete validation of the new inputs. This
also covers selecting notes for a version whose file already existed.

Only the documentation allowlist (excluding release notes), the release manifest
and the build-number portion of `pubspec.yaml` are excluded. Version syntax,
build number, manifest agreement and bilingual release notes are checked on
every run. All other pubspec content participates in the hash.

A complete, successful run of `ci.yml` from this repository in the last seven
days can supply evidence for the same source hash. Its `flutter`, `slow`, `android` and
`release` jobs must have actually succeeded. Skipped/reused runs cannot supply
evidence, and runs from forks, other workflows, or failed attempts are rejected.
The helper compares Git contents from the candidate's exact `head_sha`; it does
not trust a branch name or an uploaded cache marker. CI explicitly checks out
that head, so **strict up-to-date branch protection must remain enabled** before
merging a PR. A new base must be incorporated and checked before merge.

This lets the squash merge on `main` and the release tag reuse complete
validation of the same release inputs. A release PR that changes the version
name or notes needs validation of those new inputs. The scope job summary links
to the original run and records its commit and source hash. If evidence cannot
be found or read, full tests run. A manual CI dispatch with `full=true` forces full tests.
No previously built app is reused: each new release still builds and verifies
its own signed AAB, version, package and certificate.

## One-time repository setup

1. Require pull requests and the `CI result` status from GitHub Actions on
   `main`, including administrators. Require an up-to-date branch; block force
   pushes and deletion. No second reviewer is mandatory for a sole maintainer.
   Protect `v*` tags against updates/deletion with no bypass. Tag creation
   requires repository write access, held by maintainers and the release job.
   GitHub does not allow its built-in Actions integration as a bypass actor
   for a separate tag-creation restriction in this repository.
2. In Actions settings, enable **Allow GitHub Actions to create and approve pull
   requests**. Keep default workflow permissions read-only; the release proposal
   job requests the write permissions it needs. It uses `GITHUB_TOKEN`, with no
   personal token or additional GitHub App. GitHub creates a `pull_request` CI
   run for a release PR opened or updated with this token, initially requiring
   maintainer approval. Approve that run in the PR/Actions UI after reviewing the
   change. Do not dispatch a second branch CI: it duplicates work and does not
   replace the required PR check. The proposal job still explicitly dispatches
   the bundle workflow on the newly created tag, because release events from
   this token do not start it automatically.
3. Create environment `release-signing`, allowing reviewed `v*` release tags.
   Add secrets `ANDROID_UPLOAD_KEYSTORE_BASE64`,
   `ANDROID_UPLOAD_KEYSTORE_PASSWORD`, `ANDROID_UPLOAD_KEY_ALIAS`, and
   `ANDROID_UPLOAD_KEY_PASSWORD`. Add environment variable
   `ANDROID_UPLOAD_CERT_SHA256` from the existing Play upload certificate.
4. Create environments `play-internal` and `play-production`, restricted to
   `main`. Configure required reviewer approval for production. Add
   `PLAY_SERVICE_ACCOUNT_JSON` in each environment with the appropriate
   Google Play Console permissions. Never put this JSON in the repository.
5. Set `RELEASE_AUTOMATION_ENABLED=true` only after these settings are reviewed.
   CI itself does not require this switch or any secrets.

Release Please cannot bypass branch protection. It proposes release metadata;
the maintainer chooses when to merge after CI passes. Release signing does not
receive Play credentials, and PR tests receive neither key. The proposal can
also be run manually from `main`; it does not merge its own PR.

Use English Conventional Commit messages and PR titles as described in
[CONTRIBUTING.md](../CONTRIBUTING.md#commit-messages). When squash merging, review
the final message that reaches `main`; that is what Release Please reads.

## Local release builds and signing checks

Release tasks require nonblank `HOLYBEANS_KEYSTORE`,
`HOLYBEANS_KEYSTORE_PASSWORD`, `HOLYBEANS_KEY_ALIAS` and `HOLYBEANS_KEY_PASSWORD`.
There are no fallback passwords or aliases. For a local test only, use
`ORG_GRADLE_PROJECT_allowDebugSigning=true flutter build appbundle --release`
(or `-PallowDebugSigning=true` with Gradle directly). Never enable this exception
in the signing job. Complete upload-key credentials take precedence.

After resolving Flutter dependencies, `python3 -m tool.ci.check_android_signing`
checks the real Gradle task graph using dry runs and synthetic credentials;
it does not build an app or read an upload key. CI runs this matrix before the
Android unit tests. It covers missing and blank variables, debug/profile builds,
explicit opt-in, and release tasks requested by abbreviation or an aggregate.

The signing job disables Flutter cache restoration and validates the committed
wrapper JAR with a pinned Gradle action before running it. The wrapper verifies
the distribution against its pinned SHA-256 checksum. The sources are the
[official distribution checksum](https://services.gradle.org/distributions/gradle-9.3.1-all.zip.sha256)
and [Gradle wrapper validation](https://github.com/gradle/actions/blob/v6.4.1/docs/wrapper-validation.md).

## Prepare a release

Release Please starts from **1.1.19**, with `pubspec.yaml` at **1.1.19+157**.
Its Dart updater increments the numeric build suffix. Keep the proposed code
higher than **every code already uploaded to Play**, including other tracks.
Never reset the sequence because a repository or workflow is new. The initial
public commit is the bootstrap boundary: the first proposal considers only
later commits. Configuration and documentation commits alone do not require
an application release.

Before merging the release PR:

- Review the version and changelog, and complete any device/real-data migration
  checks required by the changes. Keep the private evidence outside GitHub.
- Add `docs/releases/<version>.md` with concise, reviewed notes in this format
  (each language at most 500 characters):

  ```text
  <es-ES>
  - Primera mejora para quienes usan la app.
  - Otra mejora o corrección.
  </es-ES>
  <en-GB>
  - First improvement for people using the app.
  - Another improvement or fix.
  </en-GB>
  ```

Keep each improvement on its own line prefixed with `- ` so the app can show
separate, spaced bullet points.
These notes are also the in-app “What’s new” content. CI and release builds run
`python3 -m tool.generate_release_notes` to select the exact `pubspec.yaml` version
and generate both translations. Missing, empty or oversized translations stop
the build; earlier versions are never appended. Run the same command before
local builds or tests after changing the version or notes. Acknowledgement uses
the version name, so rebuilding the same version does not show the dialog again.

After merge, the release workflow verifies matching complete CI evidence (or
runs the full suite if none is available), then builds one signed AAB. It checks
the bundle's application ID, version,
signature and expected certificate using bundletool, jarsigner and keytool.
The release receives the AAB, `release.json`, and `play-notes.md`. Symbols are
retained as a separate Actions artifact for 30 days; maintainers must archive
symbols needed for long-term debugging before expiration.

A failed build can leave a GitHub release without a bundle. Such a release
cannot be sent by the manual publisher. Review the failure before retrying;
asset uploads do not silently overwrite an existing bundle. To retry, run
`Release bundle` manually selecting the existing version **tag**, not `main`.
Validation and compilation use that tag's commit; the Play publisher accepts
only a successful bundle run for the same commit. Manual builds on branches
are skipped. No retry creates a new tag or sends anything to Play.

## Send a selected release to Play

Run `Publish selected release to Play` **from `main`**. Enter its tag and the
AAB SHA-256 from the successful `Release bundle` summary. Choose `internal` or
`production`. The default `publish=false` performs a dry run with no Play API
requests. Enable it deliberately to submit the same verified bundle.

The workflow verifies the tag's ancestry, bundle and notes hashes, selected
pubspec version, and a successful release-build run for that exact commit.
It executes publisher code from the reviewed default branch, never from an
arbitrary input tag, and does not rebuild the app. A manual input never becomes
an unquoted shell command.

Submission does not mean Google has approved or made the release available.
The publisher refuses to cancel an existing review and does not automatically
retry an uncertain commit; inspect Play Console before a manual retry.

## References

- [GitHub token and workflow events](https://docs.github.com/en/actions/concepts/security/github_token)
- [Release Please action](https://github.com/googleapis/release-please-action)
- [Dart version updater](https://github.com/googleapis/release-please/blob/main/src/updaters/dart/pubspec-yaml.ts)
- [GitHub deployment environments](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments)
- [Google Play Developer API](https://developers.google.com/android-publisher/getting_started)

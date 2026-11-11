# Contributing

Use the pinned Flutter version in the README and keep `pubspec.lock` committed.
A commit does not publish to Google Play.

## Submitting a change

1. Start a focused branch from the latest `main` and preserve unrelated work.
2. Implement the change, add regression tests for changed behaviour and run the
   applicable checks in [Validation](#validation). Update documentation and both
   translations when needed.
3. Review the diff for accidental files and personal data, then commit with an
   English Conventional Commit message and open a pull request against `main`.
4. Describe the problem, the resulting behaviour and the validation performed.
   Include reproduction steps or screenshots when they help review the change.
5. Address review feedback, keep the branch up to date and wait for `CI result`
   to pass on the latest commit. Maintainers merge approved changes through the
   pull request with the repository's branch protections in place.

Release pull requests and Google Play publication follow the separate release
procedure below.

## Commit messages

All commit messages (subject, body and explanatory footers) and pull-request
titles must be **in English**. Follow
[Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/):

```text
<type>(<optional scope>): <short description>
```

Use lowercase types, a short imperative description, and an optional scope that
names the affected feature. Keep each commit focused on one coherent change.

```text
feat(labels): add a label preview
fix(backup): preserve photos during restore
test(database): cover migration from schema 33
docs: clarify Android build instructions
ci: skip Flutter checks for documentation changes
```

Use `feat` for new features, `fix` for bug fixes, and `docs`, `test`, `refactor`,
`perf`, `build`, `ci` or `chore` as appropriate. Release Please uses `feat` to
propose a minor release and `fix` to propose a patch release. Mark an intentional
breaking change with `!` or a `BREAKING CHANGE:` footer and explain its impact.
An additive database migration is not automatically a breaking change and never
removes the requirement to preserve existing journals.

Prefer squash merging a PR into one reviewed Conventional Commit when its
intermediate commits are work in progress. Check the final squash message;
the English wording is a review requirement, not something a syntax regex can
reliably enforce. App translations remain in English and Spanish.

## Structure

- `lib/domain/`: pure logic with unit tests. Inputs are plain records or scalar
  values; map database rows in `lib/data/`. Pass the current time explicitly so
  calculations and import plans are reproducible. Architecture tests forbid
  data, platform I/O and presentation dependencies in this layer.
- `lib/data/`: Drift database, repositories, services and preferences.
  Repository aggregates own their queries and take `AppDatabase` explicitly;
  `JournalRepository` delegates to them while retaining its caller API.
- `lib/ui/`: UI grouped by feature. `JournalShell` implements `JournalActions`.
- `lib/l10n/`: English and Spanish ARB sources; generated translations are ignored.
- `test/`: unit, widget and persistence tests.
- `drift_schemas/`: historical schemas needed to verify migration paths.
- `patrol_test/`: Android integration flows using an isolated app package.

Keep files focused (roughly below 800 lines). User-visible text belongs in both
ARB files, except release notes, which use the versioned source below. Keep
comments, fixtures and issue reports free of personal data.

Maintain release notes only in `docs/releases/<version>.md`, matching the version
in `pubspec.yaml`, with `es-ES` and `en-GB` sections (at most 500 characters each).
Write each improvement on its own line prefixed with `- `; the app displays
these as spaced bullet points with aligned continuation lines.
Run `python3 -m tool.generate_release_notes` before local builds or tests and
after changing the version or its notes. CI and release builds run it automatically.
The generated Dart file is ignored; do not edit it or duplicate notes in ARB files.
The app shows only that version’s notes and remembers the last version seen,
independently of APK build numbers. Existing numeric acknowledgement preferences
migrate by showing the current notes once. `CHANGELOG.md` remains the full history.

## Validation

Format only the Dart files you changed and run the tests for affected behaviours.
Run `flutter analyze --no-pub` before submitting. CI runs the complete Flutter
suite and Android unit tests in parallel for unvalidated code changes. Identical
source can reuse a recent complete CI as described in [RELEASING.md](docs/RELEASING.md);
documentation-only changes run lightweight checks. Keep PR branches up to date
with `main`: CI tests the exact branch head and strict branch protection is required.

Run `flutter test --no-pub test/schema_verifier_test.dart` for schema changes.
Keep migrations from schema 19 and backup compatibility from version 5.
Never replace a migration with deletion or recreation of the user's journal.
Real-data migration checks are performed privately by maintainers; an absent
fixture is a reported skip, not a successful conservation test.

Tests tagged `slow` use real-time waits or substantial file I/O. The default
`flutter test --no-pub` command includes them. Use `flutter test --no-pub --tags slow`
to run that group alone, or `--exclude-tags slow` for a quicker local iteration;
run the complete suite before submitting a change. CI runs both groups in separate
required jobs with `TZ=Europe/Madrid`, including daylight-saving checks.

The Drive export benchmark is separate:
`flutter test --no-pub benchmark/drive_sync_export_benchmark_test.dart`.
Run it when changing that export's performance or contract.

Android permission, lifecycle, system picker and platform-channel changes need
an appropriate Patrol flow. Use a test device and the isolated Patrol package:
install a compatible `patrol_cli`, run `patrol doctor`, then
`patrol test --target patrol_test/<flow>_test.dart`.
Do not run hardware-writing tests unattended.

## Hardware boundaries

Machine integrations use documented read-only GET requests. Scale protocols may
identify, subscribe, keep a connection alive, tare and control their timer.
DiFluid R2 may be asked to measure using its existing test count. BOOKOO pressure
sensors may start and stop transmission. Printer commands must follow an explicit
user printing action. No firmware changes, calibration, shutdown or unrelated
settings; never automatically retry a print with an uncertain outcome.

## Releases

See [RELEASING.md](docs/RELEASING.md). Keep fixes and release metadata reviewable;
never put credentials or real backups into workflow inputs, logs or artifacts.

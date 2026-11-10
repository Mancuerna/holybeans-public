# Data and compatibility

HolyBeans stores its journal in SQLite through Drift. Photos are stored as files
and included in exported ZIP backups. The current database schema is **38** and
the current backup format is **36**. Historical database migrations from schema
19 and backup readers from version 5 must remain compatible.

`lib/data/database/` defines tables and migrations. `drift_schemas/` contains
schema snapshots, not personal journals. `test/schema_verifier_test.dart`
verifies historical migration paths. Repository transactions preserve the
relationships between coffees, brews, inventory and related records.

`lib/data/services/journal_backup/` and `journal_backup.dart` handle backup
collections, validation and restoration. Restoring a backup replaces the local
journal after confirmation; importing BeanConqueror is a separate flow that adds
records and avoids duplicate imports.

Drive holds independent backups with manual restoration. It does not merge
journals or provide live synchronization between devices.

Tests with external real backups are optional locally and explicitly skipped
when their environment variables are absent. Maintainers validate affected
migrations privately with real data before distribution. Never commit those
fixtures or upload their contents as CI artifacts.

See [sources](SOURCES.md) for calculation references and third-party resources.

# Data and compatibility

HolyBeans stores its journal in SQLite through Drift. Photos are stored as files
and included in exported ZIP backups. The current database schema is **41** and
the current backup format is **39**. Historical database migrations from schema
19 and backup readers from version 5 must remain compatible.

`lib/data/database/` defines tables and migrations. `drift_schemas/` contains
schema snapshots, not personal journals. `test/schema_verifier_test.dart`
verifies historical migration paths. Repository transactions preserve the
relationships between coffees, brews, inventory and related records.

`lib/data/services/journal_backup/` and `journal_backup.dart` handle backup
collections, validation and restoration. Restoring a backup replaces the local
journal after confirmation; importing BeanConqueror is a separate flow that adds
records and avoids duplicate imports.

Bag-end blends have their own coffee and lot. Each source stock adjustment
records the destination lot and a snapshot of the source roast date. The
adjustment delta is the contribution in grams. Transferring stock and creating
the blend happen in one transaction. The optional source archive follows it.

To move your journal **and photos** to another phone, export a manual ZIP backup
on the original phone, transfer the ZIP, and restore it on the new phone.

Since version 1.20.0, a new Drive backup uploads the journal and its photo
references. On restore, HolyBeans reconnects photos that are still available
locally. On a new phone those references alone cannot recover the image files.
Drive backups are restored manually and replace the local journal.

Tests with external real backups are optional locally and explicitly skipped
when their environment variables are absent. Maintainers validate affected
migrations privately with real data before distribution. Never commit those
fixtures or upload their contents as CI artifacts.

See [sources](SOURCES.md) for calculation references and third-party resources.

Extraction profiles are stored in `extraction_profiles` with versioned JSON, favorites and last-use time. Schema 39 adds this table and an optional `brews.extraction_profile_json` snapshot. Backup 37 includes the library and snapshots; older backups restore an empty library. A profile can contain cup flow in g/s, pressure in bar, or both, on the extraction clock including preinfusion. Deleting or editing a library profile never changes an existing brew snapshot. The standalone `holybeans-extraction-profile` format is version 1; imports also accept the designer demo versions 2 and 3. Missing measurement segments are retained, and incomplete flow curves do not imply a calculated yield.

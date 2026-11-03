/// How many copies taken before an upgrade are kept.
const preMigrationCopiesKept = 3;

const _sqliteMagic = 'SQLite format 3\u0000';

/// The schema version an SQLite file records (its `user_version`), read
/// from the first 100 bytes of the file; null when they are not an SQLite
/// header.
int? sqliteUserVersion(List<int> header) {
  if (header.length < 100) return null;
  for (var i = 0; i < _sqliteMagic.length; i++) {
    if (header[i] != _sqliteMagic.codeUnitAt(i)) return null;
  }
  // Offset 60, four bytes, big-endian.
  return header[60] << 24 | header[61] << 16 | header[62] << 8 | header[63];
}

/// Whether a database file at [fileSchema] is about to be upgraded to
/// [currentSchema], so it is worth keeping as it is. A new file (schema 0
/// or no file) has nothing to keep, and a newer one is not opened at all.
bool needsPreMigrationCopy({
  required int? fileSchema,
  required int currentSchema,
}) => fileSchema != null && fileSchema > 0 && fileSchema < currentSchema;

/// The database file as it was before the app upgraded it from [schema],
/// saved at [savedAt] as `holybeans-schema22-20261005T130226Z.sqlite`.
class PreMigrationCopy {
  const PreMigrationCopy({
    required this.fileName,
    required this.schema,
    required this.savedAt,
  });

  final String fileName;
  final int schema;
  final DateTime savedAt;

  static final _name = RegExp(
    r'^holybeans-schema(\d+)-(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z\.sqlite$',
  );

  static String nameFor(int schema, DateTime savedAt) {
    final utc = savedAt.toUtc();
    String two(int value) => value.toString().padLeft(2, '0');
    return 'holybeans-schema$schema-'
        '${utc.year.toString().padLeft(4, '0')}${two(utc.month)}'
        '${two(utc.day)}T${two(utc.hour)}${two(utc.minute)}'
        '${two(utc.second)}Z.sqlite';
  }

  static PreMigrationCopy? parse(String fileName) {
    final match = _name.firstMatch(fileName);
    if (match == null) return null;
    int part(int group) => int.parse(match.group(group)!);
    final savedAt = DateTime.utc(
      part(2),
      part(3),
      part(4),
      part(5),
      part(6),
      part(7),
    );
    // A date that rolled over (month 13, hour 25) is not one we wrote.
    if (nameFor(part(1), savedAt) != fileName) return null;
    return PreMigrationCopy(
      fileName: fileName,
      schema: part(1),
      savedAt: savedAt,
    );
  }
}

/// The copies among [fileNames], newest first; SQLite's side files and
/// anything else are left out.
List<PreMigrationCopy> preMigrationCopies(Iterable<String> fileNames) =>
    [for (final name in fileNames) ?PreMigrationCopy.parse(name)]
      ..sort((a, b) => b.savedAt.compareTo(a.savedAt));

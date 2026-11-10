import 'dart:io';

import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/domain/pre_migration.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// The journal file as it was before an update changed its schema, kept in
/// the app's private storage. If an upgrade ever went wrong, the journal
/// can come back from here, brought up to date by a later version.
class PreMigrationCopies {
  PreMigrationCopies(this.directory);

  final Directory directory;

  /// SQLite's side files that may hold part of a journal.
  static const _sideFiles = ['-wal', '-journal'];

  static Future<PreMigrationCopies> open() async {
    final support = await getApplicationSupportDirectory();
    return PreMigrationCopies(
      Directory(path.join(support.path, 'pre-migration')),
    );
  }

  /// The copies, newest first.
  Future<List<PreMigrationCopy>> list() async {
    if (!directory.existsSync()) return const [];
    return preMigrationCopies([
      await for (final entry in directory.list())
        if (entry is File) path.basename(entry.path),
    ]);
  }

  File file(PreMigrationCopy copy) =>
      File(path.join(directory.path, copy.fileName));

  Future<List<File>> recoveryFiles(PreMigrationCopy copy) async {
    final journal = file(copy);
    if (!journal.existsSync()) {
      throw FileSystemException('Missing saved journal', journal.path);
    }
    final files = [journal];
    for (final suffix in _sideFiles) {
      final side = File(path.join(directory.path, '${copy.fileName}$suffix'));
      if (side.existsSync()) files.add(side);
    }
    return files;
  }

  /// Copies [journal] before it is opened when its schema is older than
  /// [currentSchema], then keeps only the newest [preMigrationCopiesKept].
  /// Run it before the database opens. It never stops the journal from
  /// opening: on any error it gives up and returns null.
  Future<PreMigrationCopy?> keepIfUpgrading(
    File journal, {
    required int currentSchema,
    DateTime? now,
  }) async {
    try {
      if (!journal.existsSync()) return null;
      final header = await journal
          .openRead(0, 100)
          .fold<List<int>>([], (bytes, chunk) => bytes..addAll(chunk));
      final schema = sqliteUserVersion(header);
      if (!needsPreMigrationCopy(
        fileSchema: schema,
        currentSchema: currentSchema,
      )) {
        return null;
      }
      final copy = PreMigrationCopy.parse(
        PreMigrationCopy.nameFor(schema!, now ?? DateTime.now()),
      )!;
      await directory.create(recursive: true);
      final target = file(copy);
      await _copyWithSideFiles(journal, target);
      for (final stale in (await list()).skip(preMigrationCopiesKept)) {
        await _deleteWithSideFiles(file(stale));
      }
      return copy;
    } on Object catch (error, stack) {
      reportError(error, stack);
      return null;
    }
  }

  /// The journal in [copy] as backup JSON: a temporary copy is opened by
  /// this version of the app, which brings it up to date, and exported.
  Future<String> exportJson(PreMigrationCopy copy) async {
    final temporary = await Directory.systemTemp.createTemp('holybeans-');
    try {
      final journal = File(path.join(temporary.path, 'journal.sqlite'));
      await _copyWithSideFiles(file(copy), journal);
      final database = AppDatabase.at(journal);
      try {
        return await JournalBackup(database).exportJson();
      } finally {
        await database.close();
      }
    } finally {
      await temporary.delete(recursive: true);
    }
  }

  /// Copies [source] and its side files beside [target], each written
  /// aside and renamed so that a copy is complete or absent.
  static Future<void> _copyWithSideFiles(File source, File target) async {
    for (final suffix in ['', ..._sideFiles]) {
      final from = File('${source.path}$suffix');
      if (!from.existsSync()) continue;
      final aside = await from.copy('${target.path}$suffix.tmp');
      await aside.rename('${target.path}$suffix');
    }
  }

  static Future<void> _deleteWithSideFiles(File copy) async {
    for (final suffix in ['', ..._sideFiles]) {
      final file = File('${copy.path}$suffix');
      if (file.existsSync()) await file.delete();
    }
  }
}

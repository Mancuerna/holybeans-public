import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/services/pre_migration_copies.dart';
import 'package:holybeans/domain/pre_migration.dart';
import 'package:path/path.dart' as path;

void main() {
  test(
    'recovery shares original journal and side files without opening SQLite',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'recovery-files-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = PreMigrationCopies(directory);
      final name = PreMigrationCopy.nameFor(37, DateTime.utc(2026, 10));
      final copy = PreMigrationCopy.parse(name)!;
      for (final suffix in ['', '-wal', '-journal']) {
        await File(path.join(directory.path, '$name$suffix'))
            .writeAsString('original$suffix');
      }
      final files = await store.recoveryFiles(copy);
      expect(files.map((file) => path.basename(file.path)), [
        name,
        '$name-wal',
        '$name-journal',
      ]);
      expect(await Future.wait(files.map((file) => file.readAsString())), [
        'original',
        'original-wal',
        'original-journal',
      ]);
      expect((await store.list()).single.fileName, name);
      await store.file(copy).delete();
      await expectLater(
        store.recoveryFiles(copy),
        throwsA(isA<FileSystemException>()),
      );
      expect(await files[1].readAsString(), 'original-wal');
    },
  );
}

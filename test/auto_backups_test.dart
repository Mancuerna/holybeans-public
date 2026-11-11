import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/backup_settings.dart';
import 'package:holybeans/data/preferences/backup_state.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/auto_backups.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/domain/auto_backup.dart';

import 'helpers/test_database.dart';

void main() {
  late Directory directory;
  late AppDatabase database;
  late JournalBackup backup;
  late AutoBackups store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('holybeans-auto-');
    database = memoryDatabase();
    backup = JournalBackup(database);
    store = AutoBackups(Directory('${directory.path}/auto-backups'));
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  test('an empty journal is never copied', () async {
    final snapshot = await JournalSnapshot.take(backup);
    expect(snapshot.empty, isTrue);
    expect(
      await store.saveIfNeeded(snapshot, now: DateTime.utc(2026, 10, 4)),
      isNull,
    );
    expect(await store.list(), isEmpty);
  });

  test('copies follow changes once a day and keep the newest seven', () async {
    final repository = JournalRepository(database);
    var now = DateTime.utc(2026, 10, 1, 9);
    await repository.createCoffee(name: 'First', roaster: 'R');
    await BackupSettings(database).markBackedUp(now);
    final first = await store.saveIfNeeded(
      await JournalSnapshot.take(backup),
      now: now,
    );
    expect(first, isNotNull);

    // A new backup date alone is not a change.
    await BackupSettings(database)
        .markBackedUp(now.add(const Duration(hours: 5)));
    now = now.add(const Duration(days: 1));
    expect(
      await store.saveIfNeeded(await JournalSnapshot.take(backup), now: now),
      isNull,
    );

    // A change within the day waits, unless forced before a restore.
    await repository.createCoffee(name: 'Second', roaster: 'R');
    final changed = await JournalSnapshot.take(backup);
    expect(changed.fingerprint, isNot(first!.fingerprint));
    expect(await store.list(), hasLength(1));
    final soon = await store.saveIfNeeded(
      changed,
      now: now.add(const Duration(hours: 1)),
      force: true,
    );
    expect(soon, isNotNull);
    expect(
      await store.saveIfNeeded(
        await JournalSnapshot.take(backup),
        now: now.add(const Duration(hours: 2)),
      ),
      isNull,
    );

    for (var day = 0; day < 9; day++) {
      now = now.add(const Duration(days: 1));
      await repository.createCoffee(name: 'Coffee $day', roaster: 'R');
      await store.saveIfNeeded(await JournalSnapshot.take(backup), now: now);
    }
    // Files that are not automatic copies are never touched.
    await File('${store.directory.path}/notes.txt').writeAsString('mine');
    final entries = await store.list();
    expect(entries, hasLength(autoBackupsKept));
    expect(entries.first.savedAt, now);
    expect(File('${store.directory.path}/notes.txt').existsSync(), isTrue);
    expect(
      store.directory.listSync().where((file) => file.path.endsWith('.tmp')),
      isEmpty,
    );

    // The newest copy restores the journal it was taken from.
    final (source, photos) = JournalBackup.readArchive(
      await store.read(entries.first),
    );
    expect(photos, isEmpty);
    expect(JournalBackup.inspectJson(source).coffees, 11);
  });

  test('device backup state survives and tolerates damage', () async {
    final storeFile = BackupStateStore(File('${directory.path}/state.json'));
    expect((await storeFile.load()).folderUri, isNull);
    final saved = const BackupState()
        .withJournal('a' * 16, empty: false)
        .withFolder('content://tree/1', 'Copias')
        .withFolderCopy(DateTime(2026, 10, 4, 9), 'b' * 16)
        .withDismissed('2026-10-04');
    await storeFile.save(saved);
    final loaded = await storeFile.load();
    expect(loaded.toJson(), saved.toJson());
    expect(loaded.journalFingerprint, 'b' * 16);
    expect(loaded.withoutFolder().folderSavedAtMs, isNull);
    expect(loaded.withoutFolder().journalFingerprint, 'b' * 16);

    await storeFile.file.writeAsString('{not json');
    expect((await storeFile.load()).toJson(), const BackupState().toJson());
    await storeFile.file.writeAsString('{"folderUri": 3, "journalEmpty": "x"}');
    final odd = await storeFile.load();
    expect(odd.folderUri, isNull);
    expect(odd.journalEmpty, isTrue);
  });
}

@Tags(['slow'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/auto_backups.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/data/services/journal_restore.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:path/path.dart' as path;

import 'helpers/test_database.dart';

class _FailPhotos extends PhotoStore {
  _FailPhotos(super.directory, this.failure);
  final String failure;
  @override
  Future<void> stageReplacement(
    Directory staged,
    Map<String, Uint8List> files,
  ) async {
    await super.stageReplacement(staged, files);
    if (failure == 'stage') throw const FileSystemException('Staging failed');
  }

  @override
  Future<void> promoteReplacement(Directory staged) async {
    if (failure == 'promote') {
      throw const FileSystemException('Promotion failed');
    }
    await super.promoteReplacement(staged);
    if (failure == 'after-promote') {
      throw const FileSystemException('Promotion interrupted');
    }
  }
}

class _ObserveStaging extends PhotoStore {
  _ObserveStaging(super.directory);
  bool staged = false;
  @override
  Future<void> stageReplacement(
    Directory staged,
    Map<String, Uint8List> files,
  ) async {
    this.staged = true;
    await super.stageReplacement(staged, files);
  }
}

class _HoldStaging extends PhotoStore {
  _HoldStaging(super.directory);
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> stageReplacement(
    Directory staged,
    Map<String, Uint8List> files,
  ) async {
    await super.stageReplacement(staged, files);
    entered.complete();
    await release.future;
  }
}

class _FailDatabase extends JournalBackup {
  _FailDatabase(super.database);
  bool fail = true;
  @override
  Future<BackupSummary> restorePrepared(PreparedBackup prepared) async {
    if (fail) {
      fail = false;
      throw StateError('Database restore failed');
    }
    return super.restorePrepared(prepared);
  }
}

void main() {
  late Directory temp;
  late AppDatabase db;
  late AppDatabase sourceDb;
  late JournalRepository repository;
  late PhotoStore store;
  late String oldSource;
  late String newSource;
  late String coffee;
  const oldPhoto = '33333333-3333-3333-3333-333333333333.jpg';
  const newPhoto = '44444444-4444-4444-4444-444444444444.jpg';
  final oldBytes = Uint8List.fromList([1, 2, 3]);
  final newBytes = Uint8List.fromList([4, 5, 6]);
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('holybeans-restore-');
    db = memoryDatabase();
    sourceDb = memoryDatabase();
    repository = JournalRepository(db);
    store = PhotoStore(Directory(path.join(temp.path, 'photos')));
    await store.directory.create();
    coffee = await repository.createCoffee(
      name: 'Original',
      roaster: 'R',
      initialGrams: 100,
    );
    await repository.setCoffeePhotos(coffee, [oldPhoto]);
    await store.file(oldPhoto).writeAsBytes(oldBytes);
    oldSource = await JournalBackup(db).exportJson();
    final sourceRepo = JournalRepository(sourceDb);
    final newCoffee = await sourceRepo.createCoffee(
      name: 'Restored',
      roaster: 'R',
    );
    await sourceRepo.setCoffeePhotos(newCoffee, [newPhoto]);
    newSource = await JournalBackup(sourceDb).exportJson();
  });
  tearDown(() async {
    await db.close();
    await sourceDb.close();
    await temp.delete(recursive: true);
  });

  Future<void> expectOriginal({bool newPhotoKept = false}) async {
    expect((await repository.allCoffees()).single.id, coffee);
    expect((await repository.coffeeLots(coffee)).single.remainingGrams, 100);
    expect(await repository.coffeePhotos(coffee), [oldPhoto]);
    expect(await store.file(oldPhoto).readAsBytes(), oldBytes);
    expect(store.file(newPhoto).existsSync(), newPhotoKept);
  }

  for (final invalid in ['wrong type', 'missing field', 'invalid relation']) {
    test('$invalid is rejected before staging the journal or photos', () async {
      final decoded = jsonDecode(newSource) as Map<String, dynamic>;
      final data = decoded['data'] as Map<String, dynamic>;
      final row = (data['coffees'] as List).single as Map<String, dynamic>;
      switch (invalid) {
        case 'wrong type':
          row['name'] = 123;
        case 'missing field':
          row.remove('name');
        case 'invalid relation':
          (data['coffeePhotos'] as List).first['coffeeId'] = 'missing';
      }
      final photos = _ObserveStaging(store.directory);
      await expectLater(
        JournalRestore(
          JournalBackup(db),
          photos,
        ).replace(jsonEncode(decoded), {newPhoto: newBytes}),
        throwsFormatException,
      );
      expect(photos.staged, isFalse);
      await expectOriginal();
      expect(
        Directory('${store.directory.path}.restore').existsSync(),
        isFalse,
      );
    });
  }

  for (final failure in ['stage', 'promote', 'after-promote']) {
    test('$failure failure retains the original diary and photos', () async {
      final photos = _FailPhotos(store.directory, failure);
      await expectLater(
        JournalBackup(db).restoreArchive(
          JournalBackup.encodeArchive(newSource, {newPhoto: newBytes}),
          photos,
        ),
        throwsA(isA<FileSystemException>()),
      );
      await expectOriginal();
      expect(
        Directory('${store.directory.path}.restore').existsSync(),
        isFalse,
      );
    });
  }

  test(
    'database restore failure reverses promotion of replacement photos',
    () async {
      await expectLater(
        JournalRestore(
          _FailDatabase(db),
          store,
        ).replace(newSource, {newPhoto: newBytes}),
        throwsStateError,
      );
      await expectOriginal();
    },
  );

  test(
    'successful archive restoration keeps matching database and photo bytes',
    () async {
      await JournalBackup(db).restoreArchive(
        JournalBackup.encodeArchive(newSource, {newPhoto: newBytes}),
        store,
      );
      final restored = (await repository.allCoffees()).single;
      expect(restored.name, 'Restored');
      expect(await repository.coffeePhotos(restored.id), [newPhoto]);
      expect(await store.file(newPhoto).readAsBytes(), newBytes);
      // Photos the backup does not bring stay on the phone, unreferenced.
      expect(await store.file(oldPhoto).readAsBytes(), oldBytes);
      expect(
        Directory('${store.directory.path}.restore').existsSync(),
        isFalse,
      );
    },
  );

  // Persist the exact filesystem states produced by a process interruption.
  // Reopen SQLite as the next application launch does, without running catch.
  Future<void> interrupt({
    required bool promoted,
    required bool sqlCommitted,
    required bool committed,
    bool oldRenamed = true,
  }) async {
    final pending = Directory(path.join(temp.path, 'photos.restore'));
    pending.createSync();
    File(path.join(pending.path, 'journal.json'))
        .writeAsStringSync(oldSource, flush: true);
    final staged = Directory(path.join(pending.path, 'staged'));
    await store.stageReplacement(staged, {newPhoto: newBytes});
    File(path.join(pending.path, 'ready')).writeAsStringSync('1', flush: true);
    if (oldRenamed) {
      await store.directory.rename(path.join(pending.path, 'previous'));
    }
    if (promoted) await store.promoteReplacement(staged);
    if (sqlCommitted) {
      await JournalBackup(db)
          .restoreJson(newSource, availablePhotos: {newPhoto});
    }
    if (committed) {
      File(path.join(pending.path, 'committed'))
          .writeAsStringSync('1', flush: true);
    }
    // Round trip into a file-backed SQLite database, then reopen its handle.
    final persisted = await JournalBackup(db).exportJson();
    await db.close();
    final file = File(path.join(temp.path, 'journal.sqlite'));
    db = AppDatabase.forTesting(NativeDatabase(file));
    await JournalBackup(db)
        .restoreJson(persisted, availablePhotos: {oldPhoto, newPhoto});
    await db.close();
    db = AppDatabase.forTesting(NativeDatabase(file));
    repository = JournalRepository(db);
    // PhotoStore.open creates the folder if a rename left it absent.
    store.directory.createSync(recursive: true);
    await JournalRestore(JournalBackup(db), store).recover();
    await JournalRestore(JournalBackup(db), store).recover();
  }

  test(
    'reopen after staging rolls back without replacing current photos',
    () async {
      await interrupt(
        promoted: false,
        sqlCommitted: false,
        committed: false,
        oldRenamed: false,
      );
      await expectOriginal();
    },
    timeout: _recoveryTimeout,
  );
  test('reopen between the two folder renames recovers originals', () async {
    await interrupt(promoted: false, sqlCommitted: false, committed: false);
    await expectOriginal();
  }, timeout: _recoveryTimeout);
  test(
    'reopen after promotion and before SQLite commit recovers originals',
    () async {
      await interrupt(promoted: true, sqlCommitted: false, committed: false);
      await expectOriginal();
    },
    timeout: _recoveryTimeout,
  );
  test(
    'reopen after SQLite commit but before durable marker recovers originals',
    () async {
      await interrupt(promoted: true, sqlCommitted: true, committed: false);
      await expectOriginal();
    },
    timeout: _recoveryTimeout,
  );
  test(
    'reopen after durable commit keeps the restored diary and photos',
    () async {
      await interrupt(promoted: true, sqlCommitted: true, committed: true);
      expect((await repository.allCoffees()).single.name, 'Restored');
      expect(await store.file(newPhoto).readAsBytes(), newBytes);
      expect(await store.file(oldPhoto).readAsBytes(), oldBytes);
      expect(
        Directory('${store.directory.path}.restore').existsSync(),
        isFalse,
      );
    },
    timeout: _recoveryTimeout,
  );
  test('a concurrent full export waits for restore and captures matching photo bytes', () async {
    final held = _HoldStaging(store.directory);
    final restore = JournalRestore(
      JournalBackup(db),
      held,
    ).replace(newSource, {newPhoto: newBytes});
    await held.entered.future;
    var exported = false;
    final export =
        JournalSnapshot.takeWithPhotos(
          JournalBackup(db),
          PhotoStore(store.directory),
        ).then((snapshot) {
          exported = true;
          return snapshot;
        });
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(exported, isFalse);
    held.release.complete();
    await restore;
    final (snapshot, files) = await export;
    expect(snapshot.source, contains('Restored'));
    expect(snapshot.source, isNot(contains('Original')));
    expect(files, {newPhoto: newBytes});
  });

  test('plain JSON restore keeps the photos already on the phone', () async {
    await JournalBackup(db).restoreWithPhotos(newSource, const {}, store);
    final restored = (await repository.allCoffees()).single;
    expect(restored.name, 'Restored');
    // Its own photo is not on the phone, so that reference is dropped.
    expect(await repository.coffeePhotos(restored.id), isEmpty);
    expect(await store.file(oldPhoto).readAsBytes(), oldBytes);
  });

  test('plain JSON restore links again the photos it names', () async {
    await JournalBackup(db).restoreWithPhotos(oldSource, const {}, store);
    final restored = (await repository.allCoffees()).single;
    expect(await repository.coffeePhotos(restored.id), [oldPhoto]);
    expect(await store.file(oldPhoto).readAsBytes(), oldBytes);
  });

  test('undoing a restore with the copy kept before it brings back every '
      'photo', () async {
    // The copy kept before restoring holds no photos, like automatic ones.
    final before = oldSource;
    await JournalBackup(db).restoreArchive(
      JournalBackup.encodeArchive(newSource, {newPhoto: newBytes}),
      store,
    );
    await JournalBackup(db).restoreWithPhotos(before, const {}, store);
    await expectOriginal(newPhotoKept: true);
  });
}

// Durable file writes and SQLite reopen can exceed 30 s during the full
// parallel migration suite; let recovery finish before teardown starts.
const _recoveryTimeout = Timeout(Duration(minutes: 2));

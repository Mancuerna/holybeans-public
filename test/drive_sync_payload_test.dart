import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/language_setting.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/drive_sync_journal.dart';
import 'package:holybeans/data/services/drive_sync_payload.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/data/services/journal_restore.dart';
import 'package:holybeans/data/services/journal_write_gate.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/domain/drive_sync.dart';
import 'package:path/path.dart' as path;

import 'helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late Directory directory;
  late PhotoStore photos;
  late DriveSyncPayloadStore payloads;
  late JournalBackup backup;
  late JournalRepository repository;
  late DriveJournalAdapter adapter;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('drive-payload-');
    database = memoryDatabase();
    photos = PhotoStore(Directory(path.join(directory.path, 'photos')));
    payloads = DriveSyncPayloadStore(
      Directory(path.join(directory.path, 'queue')),
    );
    backup = JournalBackup(database);
    repository = JournalRepository(database);
    adapter = DriveJournalAdapter(
      backup: backup,
      photos: photos,
      payloads: payloads,
      editing: () => false,
      canApply: () => true,
    );
  });
  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  test(
    'manual restore is rejected before moving photos when the diary is stale',
    () async {
      final source = await backup.exportJson();
      final name = await photos.add(Uint8List.fromList([1, 2, 3]));
      database.writeGate.writable = false;
      await expectLater(
        JournalRestore(backup, photos).replace(source, {}),
        throwsA(isA<JournalReadOnlyException>()),
      );
      expect(await photos.file(name).readAsBytes(), [1, 2, 3]);
      expect(
        Directory(path.join(directory.path, 'photos.restore')).existsSync(),
        isFalse,
      );
    },
  );

  test(
    'export time and local preferences do not change the logical digest',
    () async {
      final first = await adapter.capture();
      await LanguageSetting(database).save(const Locale('es'));
      final second = await adapter.capture();
      expect(second.hash, first.hash);
      final decoded = jsonDecode(second.source) as Map<String, dynamic>;
      expect(decoded.containsKey('exportedAt'), isFalse);
      expect(
        (decoded['data'] as Map<String, dynamic>).containsKey('preferences'),
        isFalse,
      );
      await repository.createCoffee(
        name: 'New local coffee',
        roaster: 'Roaster',
      );
      expect((await adapter.capture()).hash, isNot(first.hash));
    },
  );

  test(
    'restoration keeps current device preferences and restores journal',
    () async {
      await repository.createCoffee(
        name: 'Snapshot coffee',
        roaster: 'Roaster',
        initialGrams: 500,
      );
      final hash = await adapter.stage('snapshot');
      await repository.createCoffee(name: 'Later coffee', roaster: 'Roaster');
      await LanguageSetting(database).save(const Locale('es'));
      await adapter.apply(
        DriveSnapshot(
          id: 'snapshot',
          deviceId: 'other',
          contentHash: hash,
          createdAt: DateTime.utc(2026),
        ),
      );
      expect(await adapter.currentHash(), hash);
      expect((await LanguageSetting(database).load())?.languageCode, 'es');
      expect(
        (await database.select(database.coffees).get()).single.name,
        'Snapshot coffee',
      );
    },
  );

  test('application blocks interaction only during replacement and releases on error', () async {
    final hash = await adapter.stage('apply-state');
    final events = <bool>[];
    adapter = DriveJournalAdapter(
      backup: backup,
      photos: photos,
      payloads: payloads,
      editing: () => false,
      canApply: () => true,
      onApplying: events.add,
    );
    final snapshot = DriveSnapshot(
      id: 'apply-state',
      deviceId: 'other',
      contentHash: hash,
      createdAt: DateTime.utc(2026),
    );
    await adapter.capture();
    expect(events, isEmpty);
    await adapter.apply(snapshot);
    expect(events, [true, false]);
    events.clear();
    await photos.directory.delete(recursive: true);
    await File(photos.directory.path).writeAsString('Blocked photo directory');
    await expectLater(
      adapter.apply(snapshot),
      throwsA(isA<FileSystemException>()),
    );
    expect(events, [true, false]);
    expect(await adapter.currentHash(), hash);
  });

  test(
    'missing referenced photos abort capture instead of publishing data loss',
    () async {
      final coffee = await repository.createCoffee(
        name: 'Photo coffee',
        roaster: 'Roaster',
      );
      final name = await photos.add(Uint8List.fromList([1, 2, 3]));
      await repository.setCoffeePhotos(coffee, [name]);
      final withPhoto = await adapter.capture();
      await adapter.stage('with-photo');
      expect((await payloads.read('with-photo')).photos[name], [1, 2, 3]);
      await photos.file(name).writeAsBytes([4, 5, 6]);
      expect((await adapter.capture()).hash, isNot(withPhoto.hash));
      await photos.delete(name);
      await expectLater(adapter.capture(), throwsFormatException);
    },
  );

  test(
    'staging is immutable and corruption is detected on reopening',
    () async {
      final initial = await adapter.capture();
      await payloads.write('immutable', initial);
      await payloads.write('immutable', initial);
      await repository.createCoffee(name: 'Changed', roaster: 'Roaster');
      await expectLater(
        payloads.write('immutable', await adapter.capture()),
        throwsFormatException,
      );
      expect((await payloads.read('immutable')).hash, initial.hash);
      final manifest = File(
        path.join(payloads.directory.path, 'immutable', 'manifest.json'),
      );
      final value =
          jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
      value['hash'] = '0' * 64;
      await manifest.writeAsString(jsonEncode(value));
      await expectLater(payloads.read('immutable'), throwsFormatException);
      await expectLater(payloads.read('../outside'), throwsFormatException);
    },
  );
}

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/drive_backups.dart';
import 'package:holybeans/data/services/drive_sync_remote.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/domain/drive_sync.dart';
import 'package:path/path.dart' as path;

import 'helpers/drive_fake_server.dart';
import 'helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/drive-retention');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;
  late AppDatabase database;
  late DriveFakeServer server;
  late DriveBackups service;
  late String coffee;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('drive-retention-');
    database = memoryDatabase();
    server = DriveFakeServer();
    messenger.setMockMethodCallHandler(channel, server.handle);
    service = DriveBackups(
      backup: JournalBackup(database),
      photos: PhotoStore(Directory(path.join(directory.path, 'photos'))),
      directory: Directory(path.join(directory.path, 'drive')),
      deviceId: 'fixture',
      account: 'a' * 64,
      client: const DriveNativeClient(channel: channel),
    );
    coffee = await JournalRepository(database)
        .createCoffee(name: 'Initial', roaster: 'Test');
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await database.close();
    await directory.delete(recursive: true);
  });

  Set<String> payloadIds() => service.payloads.directory.existsSync()
      ? service.payloads.directory
            .listSync()
            .map((entry) => path.basename(entry.path))
            .toSet()
      : {};
  List<File> safetyFiles() =>
      Directory(path.join(service.directory.path, 'safety'))
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.zip'))
          .toList();

  test(
    'downloaded payload is removed after reading its verified contents',
    () async {
      await service.save();
      final copy = (await service.list()).single;
      final payload = await service.read(copy);
      expect(JournalBackup.inspectJson(payload.source).coffees, 1);
      expect(payload.hash, copy.snapshot.contentHash);
      expect(payloadIds(), isEmpty);
    },
  );

  test(
    'unreadable upload state keeps files without blocking a valid download',
    () async {
      await service.save();
      final copy = (await service.list()).single;
      await service.stateFile.write({'version': 999});
      final payload = await service.read(copy);
      expect(payload.hash, copy.snapshot.contentHash);
      expect(payloadIds(), {copy.snapshot.id});
    },
  );

  for (final other in [false, true]) {
    test(
      'reading ${other ? 'another' : 'the pending'} copy preserves upload retry',
      () async {
        DriveBackupCopy? earlier;
        if (other) {
          await service.save();
          earlier = (await service.list()).single;
          await JournalRepository(database)
              .createCoffee(name: 'Later', roaster: 'Test');
        }
        server.loseNextUpload = true;
        await expectLater(service.save(), throwsA(isA<PlatformException>()));
        final state = (await service.stateFile.read())! as Map;
        final pending = DriveSnapshot.fromJson(state['pending']);
        final selected = earlier ?? (await service.list()).single;
        final payload = await service.read(selected);
        expect(payload.hash, selected.snapshot.contentHash);
        expect(payloadIds(), {pending.id});
        await service.save();
        expect(payloadIds(), isEmpty);
        expect(server.files.length, other ? 2 : 1);
      },
    );
  }

  test(
    'eight safety copies retain the current copy and four previous copies',
    () async {
      final names = <String>[];
      for (var index = 0; index < 8; index++) {
        final before = index == 0
            ? <String>{}
            : safetyFiles().map((f) => f.path).toSet();
        await JournalRepository(database)
            .createCoffee(name: 'Entry $index', roaster: 'Test');
        await service.safetyCopy();
        final current = safetyFiles().singleWhere(
          (file) => !before.contains(file.path),
        );
        names.add(current.path);
        // Older files appear newer than the next copy if the clock moves back.
        await current.setLastModified(DateTime.utc(2100, 1, index + 1));
      }
      final files = safetyFiles();
      stdout.writeln('DRIVE_SAFETY_RETENTION copies=${files.length}');
      expect(files.map((file) => file.path).toSet(), names.skip(3).toSet());
      final (source, _) = JournalBackup.readArchive(
        await File(names.last).readAsBytes(),
      );
      expect(JournalBackup.inspectJson(source).coffees, 9);
      final unrelated = File(
        path.join(service.directory.path, 'safety', 'manual.zip'),
      );
      await unrelated.writeAsString('Keep this file');
      await service.safetyCopy();
      expect(await unrelated.readAsString(), 'Keep this file');
      expect(
        safetyFiles().where((file) => file.path != unrelated.path),
        hasLength(5),
      );
      expect(
        unrelated.parent.listSync().where(
          (entry) => entry.path.endsWith('.tmp'),
        ),
        isEmpty,
      );
    },
  );

  test(
    'failure to capture a new safety copy preserves every existing copy',
    () async {
      for (var index = 0; index < 5; index++) {
        await service.safetyCopy();
      }
      final before = {
        for (final file in safetyFiles()) file.path: await file.readAsBytes(),
      };
      final photo = await service.photos.add(Uint8List.fromList([1, 2, 3]));
      await JournalRepository(database).setCoffeePhotos(coffee, [photo]);
      await service.photos.delete(photo);
      await expectLater(
        service.safetyCopy(),
        throwsA(isA<FileSystemException>()),
      );
      expect({
        for (final file in safetyFiles()) file.path: await file.readAsBytes(),
      }, before);
    },
  );
}

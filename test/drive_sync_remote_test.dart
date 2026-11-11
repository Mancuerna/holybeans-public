import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/atomic_json_file.dart';
import 'package:holybeans/data/services/drive_sync_journal.dart';
import 'package:holybeans/data/services/drive_sync_payload.dart';
import 'package:holybeans/data/services/drive_sync_remote.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/domain/drive_sync.dart';
import 'package:path/path.dart' as path;

import 'helpers/counted_json_file.dart';
import 'helpers/drive_fake_server.dart';
import 'helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/drive');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late DriveFakeServer server;
  late Directory directory;
  late AppDatabase database;
  late DriveSyncPayloadStore queue;
  late DriveRemoteAdapter remote;
  late DriveJournalAdapter journal;
  setUp(() async {
    server = DriveFakeServer();
    messenger.setMockMethodCallHandler(channel, server.handle);
    directory = await Directory.systemTemp.createTemp('drive-remote-');
    database = memoryDatabase();
    final photos = PhotoStore(Directory(path.join(directory.path, 'photos')));
    queue = DriveSyncPayloadStore(
      Directory(path.join(directory.path, 'queue')),
    );
    journal = DriveJournalAdapter(
      backup: JournalBackup(database),
      photos: photos,
      payloads: queue,
      editing: () => false,
      canApply: () => true,
    );
    remote = DriveRemoteAdapter(
      accountKey: 'a' * 64,
      client: const DriveNativeClient(channel: channel),
      payloads: queue,
      photoQueue: CountedJsonFile(
        File(path.join(directory.path, 'photos.json')),
      ),
    );
    final repository = JournalRepository(database);
    final coffee = await repository.createCoffee(
      name: 'Synthetic',
      roaster: 'Test',
    );
    final photo = await photos.add(Uint8List.fromList([1, 2, 3, 4]));
    await repository.setCoffeePhotos(coffee, [photo]);
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await database.close();
    await directory.delete(recursive: true);
  });

  Future<DriveSnapshot> staged({String? base}) async {
    final id = await remote.reserveId();
    final hash = await journal.stage(id);
    return DriveSnapshot(
      id: id,
      deviceId: 'phone',
      contentHash: hash,
      baseId: base,
      createdAt: DateTime.utc(2026),
    );
  }

  test(
    'publishes verified journal and photos, lists metadata, reuses photos',
    () async {
      final first = await staged();
      await remote.publish(first);
      expect(server.files.length, 2);
      final reads = server.mediaReads;
      expect((await remote.inventory()).singleHead!.id, first.id);
      expect(server.mediaReads, reads);
      final next = await staged(base: first.id);
      await remote.publish(next);
      expect(server.files.length, 3);
      expect(
        server.files.values
            .where((f) => f.properties['kind'] == 'photo')
            .length,
        1,
      );
      final destination = DriveSyncPayloadStore(
        Directory(path.join(directory.path, 'destination')),
      );
      final reader = DriveRemoteAdapter(
        accountKey: 'a' * 64,
        client: const DriveNativeClient(channel: channel),
        payloads: destination,
        photoQueue: AtomicJsonFile(
          File(path.join(directory.path, 'other.json')),
        ),
      );
      await reader.download(next);
      expect((await destination.read(next.id)).hash, next.contentHash);
      expect((await destination.read(next.id)).photos.values.single, [
        1,
        2,
        3,
        4,
      ]);
    },
  );

  test(
    'lost upload response resumes with the same photo and snapshot IDs',
    () async {
      final snapshot = await staged();
      server.loseNextUpload = true;
      await expectLater(
        remote.publish(snapshot),
        throwsA(isA<PlatformException>()),
      );
      expect(server.files.length, 1);
      await remote.publish(snapshot);
      expect(server.files.length, 2);
      await remote.publish(snapshot);
      expect(server.files.length, 2);
      expect(server.nextId, 2);
    },
  );

  test(
    'photo corruption prevents promotion of the downloaded snapshot',
    () async {
      final snapshot = await staged();
      await remote.publish(snapshot);
      final photo = server.files.values.singleWhere(
        (f) => f.properties['kind'] == 'photo',
      );
      photo.bytes = Uint8List.fromList([9]);
      await expectLater(remote.download(snapshot), throwsFormatException);
    },
  );

  test('incomplete metadata listing fails closed', () async {
    server.incomplete = true;
    await expectLater(remote.inventory(), throwsFormatException);
  });

  test(
    'all photo reservations survive a lost upload with one queue write',
    () async {
      final photos = journal.photos;
      final coffee = await JournalRepository(database)
          .createCoffee(name: 'Second', roaster: 'Test');
      await JournalRepository(database).setCoffeePhotos(coffee, [
        await photos.add(Uint8List.fromList([5, 6, 7, 8])),
      ]);
      final snapshot = await staged();
      server.loseNextUpload = true;
      await expectLater(
        remote.publish(snapshot),
        throwsA(isA<PlatformException>()),
      );
      await remote.publish(snapshot);
      expect(server.nextId, 3);
      expect(server.files, hasLength(3));
      expect((remote.photoQueue as CountedJsonFile).writes, 1);
    },
  );

  for (final mode in ['sha256', 'md5', 'missing']) {
    test(
      'unchanged photos use $mode verification without rewriting queue',
      () async {
        server.omitSha256 = mode != 'sha256';
        server.omitChecksums = mode == 'missing';
        final first = await staged();
        await remote.publish(first);
        final reads = server.photoMediaReads;
        final next = await staged(base: first.id);
        await remote.publish(next);
        expect(server.photoMediaReads - reads, mode == 'missing' ? 1 : 0);
        final photoQueue = remote.photoQueue as CountedJsonFile;
        expect(photoQueue.reads, 2);
        expect(photoQueue.writes, 1);
        expect(server.files, hasLength(3));
      },
    );
  }

  test(
    'a fresh queue reuses verified photos without downloading them',
    () async {
      await remote.publish(await staged());
      await remote.photoQueue.delete();
      final reads = server.photoMediaReads;
      await remote.publish(await staged());
      expect(server.photoMediaReads, reads);
      expect(server.files, hasLength(3));
    },
  );

  for (final mode in ['sha256', 'md5', 'missing']) {
    test('$mode mismatch never overwrites an immutable photo', () async {
      server.omitSha256 = mode != 'sha256';
      server.omitChecksums = mode == 'missing';
      final first = await staged();
      await remote.publish(first);
      final photo = server.files.values.singleWhere(
        (f) => f.properties['kind'] == 'photo',
      );
      photo.bytes = Uint8List.fromList([1, 2, 3, 9]);
      await expectLater(
        remote.publish(await staged(base: first.id)),
        throwsFormatException,
      );
      expect(photo.bytes, [1, 2, 3, 9]);
      expect(server.files, hasLength(2));
    });
  }

  test('a damaged upload is rejected before publishing the journal', () async {
    server.corruptUploads = true;
    await expectLater(remote.publish(await staged()), throwsFormatException);
    expect(server.files, hasLength(1));
    expect(server.files.values.single.properties['kind'], 'photo');
  });
}

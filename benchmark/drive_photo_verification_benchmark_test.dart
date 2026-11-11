import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/drive_sync_payload.dart';
import 'package:holybeans/data/services/drive_sync_remote.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/domain/drive_sync.dart';
import 'package:path/path.dart' as path;

import '../test/helpers/counted_json_file.dart';
import '../test/helpers/drive_fake_server.dart';
import '../test/helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('benchmark/drive-photos');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final count in [2, 10, 40]) {
    test('verification traffic with $count unchanged photos', () async {
      final directory = await Directory.systemTemp.createTemp('drive-photos-');
      final database = memoryDatabase();
      addTearDown(() async {
        messenger.setMockMethodCallHandler(channel, null);
        await database.close();
        await directory.delete(recursive: true);
      });
      final server = DriveFakeServer();
      messenger.setMockMethodCallHandler(channel, server.handle);
      final photoQueue = CountedJsonFile(
        File(path.join(directory.path, 'queue.json')),
      );
      final remote = DriveRemoteAdapter(
        accountKey: 'a' * 64,
        client: const DriveNativeClient(channel: channel),
        payloads: DriveSyncPayloadStore(
          Directory(path.join(directory.path, 'payloads')),
        ),
        photoQueue: photoQueue,
      );
      final repository = JournalRepository(database);
      final coffee = await repository.createCoffee(
        name: 'Synthetic',
        roaster: 'Test',
      );
      final store = PhotoStore(Directory(path.join(directory.path, 'photos')));
      final photos = <String, Uint8List>{};
      for (var i = 0; i < count; i++) {
        final bytes = Uint8List(64 * 1024)..[0] = i;
        final name = await store.add(bytes);
        photos[name] = bytes;
        final owner = i == 0
            ? coffee
            : await repository.createCoffee(
                name: 'Synthetic $i',
                roaster: 'Test',
              );
        await repository.setCoffeePhotos(owner, [name]);
      }
      Future<DriveSnapshot> publish() async {
        final payload = await DriveSyncPayload.prepare(
          await JournalBackup(database).exportJson(),
          photos,
        );
        final snapshot = DriveSnapshot(
          id: await remote.reserveId(),
          deviceId: 'fixture',
          contentHash: payload.hash,
        );
        await remote.payloads.write(snapshot.id, payload);
        await remote.publish(snapshot);
        return snapshot;
      }

      await publish();
      final firstWrites = photoQueue.writes;
      final firstReads = photoQueue.reads;
      final beforeReads = server.photoMediaReads;
      final beforeBytes = server.photoMediaBytes;
      await repository.createBrew(
        coffeeId: coffee,
        methodName: 'V60',
        doseGrams: 18,
      );
      final next = await publish();
      final result = {
        'photos': count,
        'initialQueueReads': firstReads,
        'initialQueueWrites': firstWrites,
        'repeatQueueReads': photoQueue.reads - firstReads,
        'repeatQueueWrites': photoQueue.writes - firstWrites,
        'repeatPhotoMediaReads': server.photoMediaReads - beforeReads,
        'repeatPhotoMediaBytes': server.photoMediaBytes - beforeBytes,
      };
      await remote.payloads.remove(next.id);
      await remote.download(next);
      expect((await remote.payloads.read(next.id)).photos, photos);
      expect((await remote.payloads.read(next.id)).hash, next.contentHash);
      stdout.writeln('DRIVE_PHOTO_VERIFICATION ${jsonEncode(result)}');
    });
  }
}

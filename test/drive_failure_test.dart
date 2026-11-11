import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/services/drive_failure.dart';
import 'package:holybeans/data/services/drive_storage.dart';
import 'package:holybeans/data/services/drive_sync_contracts.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/ui/sync/drive_sync_model.dart';
import 'package:path/path.dart' as path;

import 'helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'invalid Drive config remains recoverable and explains the failure',
    () async {
      final directory = await Directory.systemTemp.createTemp('drive-error-');
      final database = memoryDatabase();
      final photos = PhotoStore(Directory(path.join(directory.path, 'photos')));
      final storage = DriveStorage.forPhotos(photos);
      await storage.config.write({'version': 99, 'enabled': true});
      final model = await DriveSyncModel.open(JournalBackup(database), photos);
      try {
        expect(model.enabled, isFalse);
        expect(model.status, DriveSyncStatus.unavailable);
        expect(model.lastError?.kind, DriveFailureKind.invalidData);
        expect(model.lastError?.cause, isA<FormatException>());
        expect(database.writeGate.writable, isTrue);
        expect(await storage.config.read(), {'version': 99, 'enabled': true});
      } finally {
        model.dispose();
        await database.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'a later successful operation clears the previous typed failure',
    () async {
      final directory = await Directory.systemTemp.createTemp('drive-retry-');
      final database = memoryDatabase();
      const channel = MethodChannel('holybeans/drive-sync');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: 'network');
      });
      final model = await DriveSyncModel.open(
        JournalBackup(database),
        PhotoStore(Directory(path.join(directory.path, 'photos'))),
      );
      try {
        await model.enable();
        expect(model.status, DriveSyncStatus.unavailable);
        expect(model.lastError?.kind, DriveFailureKind.platform);
        expect((model.lastError?.cause as PlatformException).code, 'network');
        messenger.setMockMethodCallHandler(channel, (_) async => null);
        await model.disable();
        expect(model.lastError, isNull);
        expect(model.enabled, isFalse);
        expect(database.writeGate.writable, isTrue);
      } finally {
        model.dispose();
        messenger.setMockMethodCallHandler(channel, null);
        await database.close();
        await directory.delete(recursive: true);
      }
    },
  );
}

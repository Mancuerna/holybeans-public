import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/drive_sync_remote.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/ui/sync/drive_sync_model.dart';
import 'package:path/path.dart' as path;

import 'helpers/drive_fake_server.dart';
import 'helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const share = MethodChannel('dev.fluttercommunity.plus/share');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final fails in [false, true]) {
    test(
      'export removes its temporary ZIP after share ${fails ? 'failure' : 'success'}',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'drive-export-cleanup-',
        );
        final database = memoryDatabase();
        final server = DriveFakeServer();
        messenger.setMockMethodCallHandler(
          const DriveNativeClient().channel,
          server.handle,
        );
        final model = await DriveSyncModel.open(
          JournalBackup(database),
          PhotoStore(Directory(path.join(directory.path, 'photos'))),
        );
        addTearDown(() async {
          model.dispose();
          messenger.setMockMethodCallHandler(share, null);
          messenger.setMockMethodCallHandler(
            const DriveNativeClient().channel,
            null,
          );
          await database.close();
          await directory.delete(recursive: true);
        });
        await JournalRepository(database)
            .createCoffee(name: 'Synthetic', roaster: 'Test');
        await model.enable();
        await model.refreshCopies();
        String? sharedPath;
        messenger.setMockMethodCallHandler(share, (call) async {
          final arguments = call.arguments as Map;
          sharedPath = (arguments['paths'] as List).single as String;
          final (source, _) = JournalBackup.readArchive(
            await File(sharedPath!).readAsBytes(),
          );
          expect(JournalBackup.inspectJson(source).coffees, 1);
          if (fails) throw PlatformException(code: 'share-failed');
          return 'dev.fluttercommunity.plus/share/unavailable';
        });
        await model.exportCopy(model.copies.single);
        expect(sharedPath, isNotNull);
        expect(File(sharedPath!).existsSync(), isFalse);
        expect(model.busy, isFalse);
      },
    );
  }
}

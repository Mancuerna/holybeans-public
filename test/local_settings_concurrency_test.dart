import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/preferences/backup_state.dart';
import 'package:holybeans/data/services/paired_device.dart';
import 'package:holybeans/data/services/paired_device_file.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('holybeans-settings-');
  });
  tearDown(() => directory.delete(recursive: true));

  test('overlapping backup state saves keep the last complete state', () async {
    final file = File(path.join(directory.path, 'backup.json'));
    final stores = [BackupStateStore(file), BackupStateStore(file)];
    await Future.wait([
      for (var i = 0; i < 20; i++)
        stores[i % 2].save(
          BackupState(folderUri: 'folder-$i', folderName: 'Copies $i'),
        ),
    ]);
    final saved = await BackupStateStore(file).load();
    expect(saved.folderUri, 'folder-19');
    expect(saved.folderName, 'Copies 19');
  });

  test(
    'forgetting during a pending pairing save cannot resurrect it',
    () async {
      final file = File(path.join(directory.path, 'sensor.json'));
      final first = PairedDeviceFile(file);
      final second = PairedDeviceFile(file);
      await Future.wait([
        first.save(const FoundDevice(id: 'old', name: 'Old sensor')),
        second.save(null),
      ]);
      expect(await first.load(), isNull);
    },
  );

  test(
    'a failed state save preserves the old file and permits retry',
    () async {
      final file = File(path.join(directory.path, 'backup.json'));
      final store = BackupStateStore(file);
      await store.save(const BackupState(folderUri: 'original'));
      final obstacle = Directory('${file.path}.tmp');
      await obstacle.create();
      await expectLater(
        store.save(const BackupState(folderUri: 'failed')),
        throwsA(isA<FileSystemException>()),
      );
      expect((await store.load()).folderUri, 'original');
      await obstacle.delete();
      await store.save(const BackupState(folderUri: 'retry'));
      expect((await store.load()).folderUri, 'retry');
    },
  );
}

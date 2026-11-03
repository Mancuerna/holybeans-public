import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/backup_state.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/auto_backups.dart';
import 'package:holybeans/data/services/backup_folder.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/ui/backup/backup_center.dart';

class _Folder implements BackupFolder {
  final entered = Completer<void>();
  final releaseSave = Completer<void>();
  final destinations = <String>[];
  final released = <String>[];
  final copies = <Uint8List>[];
  bool failFirst = false;
  @override
  Future<PickedFolder?> pick() async =>
      const PickedFolder(uri: 'new', name: 'New');
  @override
  Future<bool> isAvailable(String uri) async => true;
  @override
  Future<void> release(String uri) async {
    released.add(uri);
  }

  @override
  Future<void> save(String uri, Uint8List bytes, DateTime day) async {
    destinations.add(uri);
    if (destinations.length == 1) {
      entered.complete();
      await releaseSave.future;
      if (failFirst) throw StateError('Unavailable');
    }
    copies.add(bytes);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late AppDatabase db;
  late _Folder folder;
  late BackupCenter center;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('backup-concurrency-');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await JournalRepository(db).createCoffee(name: 'Kept', roaster: 'R');
    folder = _Folder();
    center = BackupCenter(
      database: db,
      photos: null,
      services: BackupServices(
        autoBackups: AutoBackups(Directory('${dir.path}/auto')),
        state: BackupStateStore(File('${dir.path}/state.json')),
        folder: folder,
      ),
    );
    center.state = const BackupState(folderUri: 'old', folderName: 'Old');
  });
  tearDown(() async {
    center.dispose();
    await db.close();
    await dir.delete(recursive: true);
  });

  test('concurrent saves finish before a queued folder change', () async {
    final a = center.saveToFolder();
    await folder.entered.future;
    final b = center.saveToFolder();
    final change = center.chooseFolder();
    await pumpEventQueue();
    expect(folder.destinations, ['old']);
    expect(folder.released, isEmpty);
    folder.releaseSave.complete();
    await Future.wait([a, b, change]);
    expect(folder.destinations, ['old', 'old', 'new']);
    expect(folder.released, ['old']);
    expect(center.state.folderUri, 'new');
    expect(center.state.folderSavedAt, isNotNull);
    for (final bytes in folder.copies) {
      expect(JournalBackup.inspectArchive(bytes).coffees, 1);
    }
  });

  test('a failed save releases queue and forgetting cannot race it', () async {
    folder.failFirst = true;
    final a = center.saveToFolder();
    final failure = expectLater(a, throwsStateError);
    await folder.entered.future;
    final forget = center.forgetFolder();
    await pumpEventQueue();
    expect(folder.released, isEmpty);
    folder.releaseSave.complete();
    await failure;
    await forget;
    expect(center.state.folderUri, isNull);
    expect(center.state.folderSavedAt, isNull);
    expect(await center.chooseFolder(), isTrue);
    expect(folder.destinations, ['old', 'new']);
  });
}

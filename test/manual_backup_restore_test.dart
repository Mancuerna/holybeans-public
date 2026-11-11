import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/ui/backup/backup_actions.dart';
import 'package:holybeans/ui/backup/backup_center.dart';
import 'package:path/path.dart' as path;

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  for (final confirm in [false, true]) {
    testWidgets('manual ZIP preview waits for confirmation: $confirm', (
      tester,
    ) async {
      final database = memoryDatabase();
      final source = memoryDatabase();
      final repository = JournalRepository(database);
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('manual-restore-'),
      ))!;
      final photos = PhotoStore(Directory(path.join(directory.path, 'photos')));
      final center = BackupCenter(database: database, photos: photos);
      addTearDown(
        () => tester.runAsync(() async {
          center.dispose();
          await database.close();
          await source.close();
          await directory.delete(recursive: true);
        }),
      );
      const importedPhoto = '11111111-1111-1111-1111-111111111111.jpg';
      final photoBytes = Uint8List.fromList([1, 2, 3]);
      late String originalPhoto;
      late _SelectedBackup file;
      await tester.runAsync(() async {
        final original = await repository.createCoffee(
          name: 'Keep',
          roaster: 'R',
        );
        originalPhoto = await photos.add(Uint8List.fromList([9]));
        await repository.setCoffeePhotos(original, [originalPhoto]);
        final incoming = JournalRepository(source);
        final coffee = await incoming.createCoffee(
          name: 'Imported',
          roaster: 'R',
        );
        await incoming.setCoffeePhotos(coffee, [importedPhoto]);
        file = _SelectedBackup(
          JournalBackup.encodeArchive(
            await JournalBackup(source).exportJson(),
            {importedPhoto: photoBytes},
          ),
        );
      });
      final messages = <String>[];
      final actions = BackupActions(
        center: center,
        repository: repository,
        photos: photos,
        message: messages.add,
      );
      final observer = _PreviewObserver();
      late Future<void> operation;
      await tester.pumpWidget(
        localizedApp(
          locale: const Locale('en'),
          navigatorObservers: [observer],
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  operation = actions.importBackup(
                    context,
                    pickFile: () async => file,
                  );
                },
                child: const Text('Import'),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Import'));
        await observer.shown.future.timeout(const Duration(seconds: 15));
      });
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        (await tester.runAsync(repository.allCoffees))!.single.name,
        'Keep',
      );
      expect(await tester.runAsync(photos.names), {originalPhoto});
      expect(messages, isEmpty);

      await tester.runAsync(() async {
        await tester.tap(
          confirm
              ? find.widgetWithText(FilledButton, 'Restore')
              : find.widgetWithText(TextButton, 'Cancel'),
        );
        await operation.timeout(const Duration(seconds: 15));
      });
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        (await tester.runAsync(repository.allCoffees))!.single.name,
        confirm ? 'Imported' : 'Keep',
      );
      expect(await tester.runAsync(photos.names), {
        originalPhoto,
        if (confirm) importedPhoto,
      });
      if (confirm) {
        expect(
          await tester.runAsync(() => photos.file(importedPhoto).readAsBytes()),
          photoBytes,
        );
      }
      expect(messages, hasLength(confirm ? 1 : 0));
      expect(file.reads, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

class _SelectedBackup extends XFile {
  _SelectedBackup(this.bytes) : super('synthetic.zip');
  final Uint8List bytes;
  int reads = 0;

  @override
  Future<int> length() async => bytes.length;

  @override
  Future<Uint8List> readAsBytes() async {
    reads++;
    return bytes;
  }
}

class _PreviewObserver extends NavigatorObserver {
  final shown = Completer<void>.sync();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute && !shown.isCompleted) shown.complete();
  }
}

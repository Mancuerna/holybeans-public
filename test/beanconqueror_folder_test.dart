import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/beanconqueror_archive.dart';
import 'package:holybeans/data/services/beanconqueror_sources.dart';
import 'package:holybeans/data/services/export_folder.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/settings/beanconqueror_import_page.dart';

import 'helpers/beanconqueror_fixture.dart';
import 'helpers/fake_export_folder.dart';

/// The folder "Full export to directory" leaves: the export's ZIP, its
/// curves in `brews` and a photo beside them.
Map<String, List<int>> exportFolder() => {
  'Beanconqueror.zip': zip(),
  'brews/brew-v60_flow_profile.json': utf8.encode(jsonEncode(v60FlowProfile())),
  'photo_abc.jpg': [0xFF, 0xD8, 0xFF],
};

void main() {
  test(
    'the folder gives its export and reads curves a few at a time',
    () async {
      final folder = FakeExportFolder({
        ...exportFolder(),
        for (var i = 0; i < 30; i++)
          'brews/extra-$i.json': utf8.encode(jsonEncode(v60FlowProfile())),
      });
      final files = await folder.list('content://export');
      final export = await FolderExtraFiles.exportOf(folder, files);
      expect(BeanconquerorArchive.read(export!).brews, hasLength(3));

      final extra = FolderExtraFiles(folder, files);
      expect(extra.names, isNot(contains('Beanconqueror.zip')));
      expect(extra.names, contains('photo_abc.jpg'));
      folder.reads.clear();
      final progress = <(int, int)>[];
      final curves = await extra.curves({
        'brew-v60_flow_profile.json',
        for (var i = 0; i < 30; i++) 'extra-$i.json',
        'missing.json',
      }, onProgress: (done, total) => progress.add((done, total)));
      expect(curves, hasLength(31));
      expect(folder.reads, hasLength(31), reason: 'each file read once');
      expect(progress, [(25, 31), (31, 31)]);
      expect((await extra.files({'photo_abc.jpg'}))['photo_abc.jpg'], [
        0xFF,
        0xD8,
        0xFF,
      ]);
    },
  );

  test('an unpacked export is read from its JSON files, and a folder '
      'without one gives none', () async {
    final unpacked = ZipDecoder().decodeBytes(zip());
    final folder = FakeExportFolder({
      for (final file in unpacked.files)
        'Export/${file.name}': file.readBytes()!,
    });
    final export = await FolderExtraFiles.exportOf(
      folder,
      await folder.list('content://export'),
    );
    expect(BeanconquerorArchive.read(export!).brews, hasLength(3));

    final empty = FakeExportFolder({'notes.txt': utf8.encode('hello')});
    expect(
      await FolderExtraFiles.exportOf(empty, await empty.list('x')),
      isNull,
    );
  });

  testWidgets('picking the export folder brings its curves and photos', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final photos = Directory.systemTemp.createTempSync('bq_folder_photos');
    addTearDown(() => photos.deleteSync(recursive: true));
    final repository = JournalRepository(database);
    final folder = FakeExportFolder(exportFolder());
    BqImportSummary? summary;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => summary = await importFromBeanconqueror(
              context,
              repository: repository,
              photos: PhotoStore(photos),
              folder: folder,
            ),
            child: const Text('Import'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bq-source-folder')));
    // Reading and planning run in other isolates.
    await tester.runAsync(() async {
      for (
        var i = 0;
        i < 100 && find.text('Curves: 1 of 1').evaluate().isEmpty;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
    expect(find.text('Curves: 1 of 1'), findsOneWidget);
    expect(find.text('Photos: 1 of 1'), findsOneWidget);
    expect(
      find.text('The export brings every curve and photo needed.'),
      findsOneWidget,
    );

    final importButton = find.byKey(const ValueKey('bq-import'));
    await tester.scrollUntilVisible(importButton, 200);
    await tester.runAsync(() async {
      await tester.tap(importButton);
      for (var i = 0; i < 200 && summary == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
    expect(summary!.curves, 1);
    expect(summary!.photos, 1);
    expect(summary!.brews, 2);
  });

  testWidgets('a folder without an export says so', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => importFromBeanconqueror(
                context,
                repository: JournalRepository(database),
                folder: FakeExportFolder({
                  'notes.txt': [1],
                }),
              ),
              child: const Text('Import'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bq-source-folder')));
    await tester.pumpAndSettle();
    expect(find.textContaining('no Beanconqueror.zip'), findsOneWidget);
    expect(find.text('Reading the export…'), findsNothing);
  });

  testWidgets('a dialog says the export is being read until it is', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final folder = _HeldFolder(exportFolder());
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => importFromBeanconqueror(
              context,
              repository: JournalRepository(database),
              folder: folder,
            ),
            child: const Text('Import'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bq-source-folder')));
    await tester.pump();
    await tester.pump();
    expect(find.text('Reading the export…'), findsOneWidget);
    // Back does not leave it while the export is read.
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Reading the export…'), findsOneWidget);

    folder.listed.complete();
    await tester.runAsync(() async {
      for (
        var i = 0;
        i < 100 && find.text('Import from BeanConqueror').evaluate().isEmpty;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
    expect(find.text('Import from BeanConqueror'), findsOneWidget);
    expect(find.text('Reading the export…'), findsNothing);
  });
}

/// A folder whose listing waits for [listed], like a large one on a phone.
class _HeldFolder extends FakeExportFolder {
  _HeldFolder(super.files);

  final listed = Completer<void>();

  @override
  Future<List<FolderFile>> list(String uri) async {
    await listed.future;
    return super.list(uri);
  }
}

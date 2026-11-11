import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/beanconqueror_archive.dart';
import 'package:holybeans/data/services/beanconqueror_sources.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/domain/beanconqueror/bq_import_plan.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/ui/settings/beanconqueror_import_page.dart';

import 'helpers/beanconqueror_fixture.dart';
import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  testWidgets('the import page shows what comes in, takes the photos and '
      'imports', (tester) async {
    final database = memoryDatabase();
    addTearDown(database.close);
    final folder = Directory.systemTemp.createTempSync('bq_photos');
    addTearDown(() => folder.deleteSync(recursive: true));
    final repository = JournalRepository(database);
    final plan = await tester.runAsync(
      () async => planBeanconquerorImport(
        BeanconquerorArchive.read(zip()),
        await repository.beanconquerorJournal(),
      ),
    );
    BqImportSummary? summary;
    await tester.pumpWidget(
      localizedApp(
        locale: const Locale('en'),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => summary = await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BeanconquerorImportPage(
                  plan: plan!,
                  repository: repository,
                  photos: PhotoStore(folder),
                  pickFiles: () async => [
                    XFile.fromData(
                      Uint8List.fromList([0xFF, 0xD8, 0xFF]),
                      path: '/picked/photo_abc.jpg',
                    ),
                    XFile.fromData(Uint8List(3), path: '/picked/unrelated.jpg'),
                    XFile.fromData(
                      Uint8List.fromList(
                        utf8.encode(jsonEncode(v60FlowProfile())),
                      ),
                      path: '/picked/brews/brew-v60_flow_profile.json',
                    ),
                  ],
                ),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('2 beans'), findsOneWidget);
    expect(find.text('2 brews'), findsOneWidget);
    expect(find.text('2 methods'), findsOneWidget);
    expect(find.text('1 grinder'), findsOneWidget);
    expect(find.textContaining('1 bag goes into the freezer'), findsOneWidget);
    expect(find.textContaining('1 finished bean comes in'), findsOneWidget);
    expect(find.textContaining('1 brew without its bean'), findsOneWidget);
    expect(find.text('Photos: 0 of 1'), findsOneWidget);
    expect(find.text('Curves: 0 of 1'), findsOneWidget);

    final pick = find.byKey(const ValueKey('bq-pick-files'));
    await tester.scrollUntilVisible(pick, 200);
    await tester.tap(pick);
    await tester.pump();
    expect(find.text('Photos: 1 of 1'), findsOneWidget);
    expect(find.text('Curves: 1 of 1'), findsOneWidget);

    final importButton = find.byKey(const ValueKey('bq-import'));
    await tester.scrollUntilVisible(importButton, 200);
    await tester.runAsync(() async {
      await tester.tap(importButton);
      // The import copies photos and writes in real time; wait for it.
      for (var i = 0; i < 100 && summary == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
    expect(summary!.brews, 2);
    expect(summary!.photos, 1);
    expect(summary!.curves, 1);
    final stored = await database.select(database.coffeePhotos).getSingle();
    expect(File('${folder.path}/${stored.fileName}').existsSync(), isTrue);
  });

  testWidgets('a ZIP of the export folder needs no picking', (tester) async {
    final database = memoryDatabase();
    addTearDown(database.close);
    final folder = Directory.systemTemp.createTempSync('bq_photos');
    addTearDown(() => folder.deleteSync(recursive: true));
    final repository = JournalRepository(database);
    final bytes = folderZip();
    final plan = await tester.runAsync(
      () async => planBeanconquerorImport(
        BeanconquerorArchive.read(bytes),
        await repository.beanconquerorJournal(),
      ),
    );
    BqImportSummary? summary;
    await tester.pumpWidget(
      localizedApp(
        locale: const Locale('en'),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => summary = await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BeanconquerorImportPage(
                  plan: plan!,
                  repository: repository,
                  photos: PhotoStore(folder),
                  extra: ZipExtraFiles(
                    bytes,
                    BeanconquerorArchive.extraFileNames(bytes),
                  ),
                  pickFiles: () async => fail('nothing to pick'),
                ),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Photos: 1 of 1'), findsOneWidget);
    expect(find.text('Curves: 1 of 1'), findsOneWidget);
    expect(
      find.text('The export brings every curve and photo needed.'),
      findsOneWidget,
    );

    final importButton = find.byKey(const ValueKey('bq-import'));
    await tester.scrollUntilVisible(importButton, 200);
    await tester.runAsync(() async {
      await tester.tap(importButton);
      // Curves and photos are read in another isolate; wait for it.
      for (var i = 0; i < 200 && summary == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
    expect(summary!.curves, 1);
    expect(summary!.photos, 1);
  });

  testWidgets('the import says what it is busy with while it has no count', (
    tester,
  ) async {
    final database = memoryDatabase();
    addTearDown(database.close);
    final repository = JournalRepository(database);
    final plan = await tester.runAsync(
      () async => planBeanconquerorImport(
        BeanconquerorArchive.read(zip()),
        await repository.beanconquerorJournal(),
      ),
    );
    final bundle = _HeldCurves();
    BqImportSummary? summary;
    await tester.pumpWidget(
      localizedApp(
        locale: const Locale('en'),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => summary = await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BeanconquerorImportPage(
                  plan: plan!,
                  repository: repository,
                  extra: bundle,
                  pickFiles: () async => fail('nothing to pick'),
                ),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final importButton = find.byKey(const ValueKey('bq-import'));
    await tester.scrollUntilVisible(importButton, 200);
    await tester.tap(importButton);
    await tester.pump();
    expect(find.text('Reading curves…'), findsOneWidget);
    LinearProgressIndicator bar() =>
        tester.widget(find.byType(LinearProgressIndicator));
    expect(bar().value, isNull, reason: 'no count to show yet');

    expect(
      ModalRoute.of(tester.element(find.byType(BeanconquerorImportPage)))!
          .popDisposition,
      RoutePopDisposition.doNotPop,
    );
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(BeanconquerorImportPage), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(BeanconquerorImportPage), findsOneWidget);

    bundle.read.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('Saving to your journal…'), findsOneWidget);
    expect(bar().value, isNull);

    await tester.runAsync(() async {
      for (var i = 0; i < 200 && summary == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
    expect(summary!.brews, 2);
  });

  testWidgets('failed photo cleanup still leaves the import retryable', (
    tester,
  ) async {
    final database = memoryDatabase();
    addTearDown(database.close);
    final folder = Directory.systemTemp.createTempSync('bq_cleanup');
    addTearDown(() => folder.deleteSync(recursive: true));
    final photos = _RejectDeletePhotos(folder);
    final repository = JournalRepository(database);
    final plan = await tester.runAsync(
      () async => planBeanconquerorImport(
        BeanconquerorArchive.read(zip()),
        await repository.beanconquerorJournal(),
      ),
    );
    await tester.pumpWidget(
      localizedApp(
        locale: const Locale('en'),
        home: BeanconquerorImportPage(
          plan: plan!,
          repository: repository,
          photos: photos,
          extra: _BrokenCurves(),
          pickFiles: () async => [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('bq-import'));
    await tester.scrollUntilVisible(button, 200);
    await tester.runAsync(() async {
      await tester.tap(button);
      for (var i = 0; i < 100 && !photos.deleteAttempted; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pump();
    expect(photos.deleteAttempted, isTrue);
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
      find.text('The import failed; your journal is unchanged.'),
      findsOneWidget,
    );
    expect(await repository.allCoffees(), isEmpty);
    expect(tester.takeException(), isNull);
  });
}

class _RejectDeletePhotos extends PhotoStore {
  _RejectDeletePhotos(super.directory);
  bool deleteAttempted = false;
  @override
  Future<String> add(Uint8List bytes) async =>
      '11111111-1111-4111-8111-111111111111.jpg';
  @override
  Future<void> delete(String? name) async {
    deleteAttempted = true;
    throw const FileSystemException('Cannot delete copied photo');
  }
}

class _BrokenCurves implements BqExtraFiles {
  @override
  Set<String> get names => {'photo_abc.jpg', 'brew-v60_flow_profile.json'};
  @override
  Future<Map<String, Uint8List>> files(Set<String> wanted) async => {
    'photo_abc.jpg': Uint8List.fromList([0xFF, 0xD8, 0xFF]),
  };
  @override
  Future<Map<String, ShotCurve>> curves(
    Set<String> wanted, {
    BqProgress? onProgress,
  }) async => throw const FormatException('Broken curve');
}

/// The export's curves, read only once [read] completes; none come back.
class _HeldCurves implements BqExtraFiles {
  final read = Completer<void>();

  @override
  Set<String> get names => {'brew-v60_flow_profile.json'};

  @override
  Future<Map<String, ShotCurve>> curves(
    Set<String> wanted, {
    BqProgress? onProgress,
  }) async {
    await read.future;
    return const {};
  }

  @override
  Future<Map<String, Uint8List>> files(Set<String> wanted) async => const {};
}

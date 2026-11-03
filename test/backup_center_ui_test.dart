@Tags(['slow'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/backup_state.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/auto_backups.dart';
import 'package:holybeans/data/services/backup_folder.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/data/services/pre_migration_copies.dart';
import 'package:holybeans/domain/auto_backup.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/backup/backup_center.dart';

import 'helpers/legacy_schema.dart';

class FakeBackupFolder implements BackupFolder {
  bool available = true;
  PickedFolder? toPick = const PickedFolder(
    uri: 'content://tree/backups',
    name: 'Backups',
  );
  final files = <String, Uint8List>{};
  final released = <String>[];

  @override
  Future<PickedFolder?> pick() async => toPick;

  @override
  Future<bool> isAvailable(String uri) async => available;

  @override
  Future<void> release(String uri) async => released.add(uri);

  @override
  Future<void> save(String uri, Uint8List bytes, DateTime day) async {
    if (!available) throw StateError('Folder gone');
    files[folderBackupName(day)] = bytes;
  }
}

/// Lets real file and isolate work finish between frames.
/// Up to 30 s: exporting and zipping take far longer when the whole suite
/// runs at once.
Future<void> waitFor(WidgetTester tester, Future<bool> Function() done) async {
  final clock = Stopwatch()..start();
  while (clock.elapsed < const Duration(seconds: 30)) {
    if (await tester.runAsync(done) ?? false) {
      await tester.pump();
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  fail('Timed out waiting for backup work');
}

/// Waits until [finder] shows something, letting real work run meanwhile.
Future<void> waitForWidget(WidgetTester tester, Finder finder) =>
    waitFor(tester, () async => finder.evaluate().isNotEmpty);

/// Leaves the app or comes back, through the states Flutter expects.
void leaveApp(WidgetTester tester) {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

void returnToApp(WidgetTester tester) {
  for (final state in [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

void main() {
  late Directory directory;
  late AppDatabase database;
  late FakeBackupFolder folder;
  late BackupServices services;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('holybeans-center-');
    database = AppDatabase.forTesting(NativeDatabase.memory());
    folder = FakeBackupFolder();
    services = BackupServices(
      autoBackups: AutoBackups(Directory('${directory.path}/auto')),
      state: BackupStateStore(File('${directory.path}/state.json')),
      folder: folder,
    );
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  Future<void> start(WidgetTester tester) async {
    await tester.pumpWidget(
      HolyBeansApp(
        database: database,
        initialLocale: const Locale('en'),
        backupServices: services,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> stop(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
  }

  testWidgets('leaving the app keeps a copy that can be restored', (
    tester,
  ) async {
    final repository = JournalRepository(database);
    await tester.runAsync(
      () => repository.createCoffee(name: 'Kept', roaster: 'R'),
    );
    await start(tester);

    leaveApp(tester);
    await waitFor(
      tester,
      () async => (await services.autoBackups.list()).isNotEmpty,
    );
    returnToApp(tester);
    await tester.runAsync(
      () => repository.createCoffee(name: 'Later', roaster: 'R'),
    );

    await openSettings(tester);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('auto-backups')),
      300,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('auto-backups')));
    await tester.pumpAndSettle();
    await waitForWidget(tester, find.textContaining('Latest:'));
    await tester.tap(find.byKey(const ValueKey('auto-backups')));
    await tester.pumpAndSettle();
    expect(find.text('Most recent'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('auto-backup-0')));
    await waitForWidget(tester, find.byType(AlertDialog));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 beans'), findsOneWidget);
    expect(find.textContaining('keeps your current journal'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
    await waitForWidget(tester, find.text('Backup restored'));
    expect((await tester.runAsync(repository.allCoffees))!.single.name, 'Kept');

    // The replaced journal, with both coffees, became a copy too.
    final entries = (await tester.runAsync(services.autoBackups.list))!;
    expect(entries, hasLength(2));
    final (source, _) = JournalBackup.readArchive(
      (await tester.runAsync(() => services.autoBackups.read(entries.first)))!,
    );
    expect(JournalBackup.inspectJson(source).coffees, 2);
    expect(find.text('Backup restored'), findsOneWidget);
    await stop(tester);
  });

  testWidgets('the journal kept before an update can come back', (
    tester,
  ) async {
    final copies = PreMigrationCopies(Directory('${directory.path}/pre'));
    services = BackupServices(
      autoBackups: services.autoBackups,
      state: services.state,
      folder: folder,
      preMigration: copies,
    );
    // A schema 22 journal, as the previous version left it, is copied
    // before this version opens it.
    await tester.runAsync(() async {
      final journal = File('${directory.path}/old.sqlite');
      final old = AppDatabase.at(journal);
      await JournalRepository(old)
          .createCoffee(name: 'Before update', roaster: 'R');
      await reconstructLegacySchema(old, 22);
      await old.close();
      await copies.keepIfUpgrading(
        journal,
        currentSchema: AppDatabase.currentSchema,
      );
    });
    final repository = JournalRepository(database);
    await tester.runAsync(
      () => repository.createCoffee(name: 'Now', roaster: 'R'),
    );
    await start(tester);

    await openSettings(tester);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('auto-backups')),
      300,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('auto-backups')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('auto-backups')));
    await tester.pumpAndSettle();
    const kept = ValueKey('pre-migration-0');
    // The list is read from the phone's storage.
    await waitForWidget(tester, find.byKey(kept, skipOffstage: false));
    await tester.ensureVisible(find.byKey(kept));
    await tester.pumpAndSettle();
    expect(find.text('Before updating the app'), findsOneWidget);
    await tester.tap(find.byKey(kept));
    await waitForWidget(tester, find.byType(AlertDialog));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 beans'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
    await waitForWidget(tester, find.text('Backup restored'));
    expect(
      (await tester.runAsync(repository.allCoffees))!.single.name,
      'Before update',
    );
    // The journal it replaced became an automatic copy.
    expect(await tester.runAsync(services.autoBackups.list), hasLength(1));
    await stop(tester);
  });

  testWidgets('choosing a folder saves a full copy there', (tester) async {
    await tester.runAsync(
      () => JournalRepository(database).createCoffee(name: 'A', roaster: 'R'),
    );
    await start(tester);
    await openSettings(tester);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('backup-folder')),
      300,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('backup-folder')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Choose a folder on your phone'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('backup-folder')));
    await waitForWidget(tester, find.text('Copy saved in Backups'));
    await tester.pumpAndSettle();
    final name = folderBackupName(DateTime.now());
    expect(folder.files.keys, [name]);
    expect(JournalBackup.inspectArchive(folder.files[name]!).coffees, 1);
    expect(find.text('Copy saved in Backups'), findsOneWidget);
    expect(find.textContaining('Backups. Last copy:'), findsOneWidget);
    final state = (await tester.runAsync(services.state.load))!;
    expect(state.folderFingerprint, state.journalFingerprint);
    expect(state.folderUri, 'content://tree/backups');

    // Options: stop using the folder keeps its copies but releases access.
    await tester.tap(find.byKey(const ValueKey('backup-folder')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('backup-folder-forget')));
    await waitFor(tester, () async => folder.released.isNotEmpty);
    await waitForWidget(
      tester,
      find.textContaining('Choose a folder on your phone'),
    );
    expect(folder.files, hasLength(1));
    expect(
      find.textContaining('Choose a folder on your phone'),
      findsOneWidget,
    );
    await stop(tester);
  });

  testWidgets('Home offers the day\'s copy once the journal changed', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final repository = JournalRepository(database);
      await repository.createCoffee(name: 'Old', roaster: 'R');
      // An old journal would also be due for the monthly reminder.
      await database.customStatement('UPDATE coffees SET created_at_ms = 0');
      await services.state.save(
        const BackupState()
            .withFolder('content://tree/backups', 'Backups')
            .withFolderCopy(
              DateTime.now().subtract(const Duration(days: 1)),
              'a' * 16,
            )
            .withJournal('b' * 16, empty: false),
      );
    });
    await start(tester);
    await waitFor(
      tester,
      () async => find
          .byKey(const ValueKey('folder-backup-reminder'))
          .evaluate()
          .isNotEmpty,
    );
    expect(find.byKey(const ValueKey('backup-reminder')), findsNothing);
    expect(find.text('Save today\'s copy'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('folder-backup-save')));
    await waitForWidget(tester, find.text('Copy saved in Backups'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('folder-backup-reminder')), findsNothing);
    await stop(tester);

    // Put off: not again today, and remembered across launches.
    await tester.runAsync(
      () async => services.state.save(
        (await services.state.load())
            .withFolderCopy(
              DateTime.now().subtract(const Duration(days: 1)),
              'a' * 16,
            )
            .withJournal('c' * 16, empty: false),
      ),
    );
    await start(tester);
    await waitFor(
      tester,
      () async => find
          .byKey(const ValueKey('folder-backup-reminder'))
          .evaluate()
          .isNotEmpty,
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('folder-backup-reminder')),
        matching: find.byTooltip('Not now'),
      ),
    );
    await waitFor(
      tester,
      () async => (await services.state.load()).folderDismissedDay != null,
    );
    expect(find.byKey(const ValueKey('folder-backup-reminder')), findsNothing);
    await stop(tester);
    await start(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('folder-backup-reminder')), findsNothing);
    expect(
      (await tester.runAsync(services.state.load))!.folderDismissedDay,
      localDay(DateTime.now()),
    );
    await stop(tester);
  });

  testWidgets('a folder that is gone asks to choose it again', (tester) async {
    folder.available = false;
    await tester.runAsync(() async {
      await JournalRepository(database).createCoffee(name: 'A', roaster: 'R');
      await services.state.save(
        const BackupState().withFolder('content://tree/old', 'Old'),
      );
    });
    await start(tester);
    await waitFor(
      tester,
      () async => find
          .byKey(const ValueKey('folder-backup-lost'))
          .evaluate()
          .isNotEmpty,
    );
    folder.available = true;
    await tester.tap(find.byKey(const ValueKey('folder-backup-choose')));
    await waitForWidget(tester, find.text('Copy saved in Backups'));
    await tester.pumpAndSettle();
    expect(folder.released, ['content://tree/old']);
    expect(find.byKey(const ValueKey('folder-backup-lost')), findsNothing);
    await stop(tester);
  });
}

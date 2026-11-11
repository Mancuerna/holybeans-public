import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/backup_state.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/auto_backups.dart';
import 'package:holybeans/data/services/backup_folder.dart';
import 'package:holybeans/domain/auto_backup.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/backup/backup_center.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:patrol/patrol.dart';

/// Folder created beforehand with
/// `adb shell mkdir -p /sdcard/Documents/HolyBeansPatrol`.
const patrolBackupFolder = 'HolyBeansPatrol';

/// The test's own automatic copies and backup state, emptied first.
Future<BackupServices> openTestBackupServices() async {
  final support = await getApplicationSupportDirectory();
  final copies = Directory(path.join(support.path, 'patrol-auto-backups'));
  if (copies.existsSync()) await copies.delete(recursive: true);
  final state = File(path.join(support.path, 'patrol-backup-state.json'));
  if (state.existsSync()) await state.delete();
  return BackupServices(
    autoBackups: AutoBackups(copies),
    state: BackupStateStore(state),
    folder: const AndroidBackupFolder(),
  );
}

Future<void> _until(Future<bool> Function() done) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (await done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail('Timed out waiting for backup work');
}

Future<void> _openSettingsTile(PatrolIntegrationTester $, String key) async {
  await $.tap(find.byTooltip('Settings'));
  await $.scrollUntilVisible(finder: find.byKey(ValueKey(key)));
}

/// Automatic copy on leaving the app, a real folder picked with Android's
/// picker, the daily reminder on Home and restoring an automatic copy.
Future<void> checkBackups(
  PatrolIntegrationTester $,
  AppDatabase database,
) async {
  final services = await openTestBackupServices();
  final repository = JournalRepository(database);
  await repository.createCoffee(name: 'Backup bean', roaster: 'Test');
  Future<void> launch() async {
    await $.pumpWidgetAndSettle(const SizedBox.shrink());
    await $.pumpWidgetAndSettle(
      HolyBeansApp(
        services: AppServices(database: database, backupServices: services),
        initialLocale: const Locale('en'),
      ),
    );
  }

  await launch();
  await $.waitUntilVisible(find.text('Backup bean'));

  // Leaving the app keeps the first automatic copy.
  await $.platform.mobile.pressHome();
  await _until(() async => (await services.autoBackups.list()).isNotEmpty);
  await $.platform.mobile.openApp();
  await $.pumpAndSettle();

  await _openSettingsTile($, 'auto-backups');
  expect(find.textContaining('Latest:'), findsOneWidget);
  await $.tap(find.byKey(const ValueKey('auto-backups')));
  await $.waitUntilVisible(find.text('Most recent'));
  await $.takeNativeScreenshot('auto-backups-list');
  await $.tester.pageBack();
  await $.pumpAndSettle();

  // A real folder through the storage access framework.
  await $.scrollUntilVisible(
    finder: find.byKey(const ValueKey('backup-folder')),
  );
  await $.tap(find.byKey(const ValueKey('backup-folder')));
  final mobile = $.platform.mobile;
  await mobile.tap(Selector(text: 'Documents'));
  await mobile.tap(Selector(text: patrolBackupFolder));
  await mobile.tap(Selector(text: 'USE THIS FOLDER'));
  await mobile.tap(Selector(text: 'ALLOW'));
  await $.waitUntilVisible(find.text('Copy saved in $patrolBackupFolder'));
  final uri = (await services.state.load()).folderUri!;
  final saved = await const MethodChannel('holybeans/backups')
      .invokeListMethod<String>('list', {'uri': uri});
  expect(
    folderBackupNames(saved ?? const []).any(
      (name) => name.startsWith(
        folderBackupName(DateTime.now()).replaceFirst('.zip', ''),
      ),
    ),
    isTrue,
  );
  expect(
    find.textContaining('$patrolBackupFolder. Last copy:'),
    findsOneWidget,
  );
  await $.takeNativeScreenshot('backup-folder-settings');

  // Home offers the day's copy when the journal changed since the last one.
  await services.state.save(
    (await services.state.load())
        .withFolderCopy(
          DateTime.now().subtract(const Duration(days: 1)),
          'a' * 16,
        )
        .withJournal('b' * 16, empty: false),
  );
  await launch();
  await $.waitUntilVisible(
    find.byKey(const ValueKey('folder-backup-reminder')),
  );
  await $.takeNativeScreenshot('folder-backup-reminder');
  await $.tap(find.byKey(const ValueKey('folder-backup-save')));
  await $.waitUntilVisible(find.text('Copy saved in $patrolBackupFolder'));
  expect(find.byKey(const ValueKey('folder-backup-reminder')), findsNothing);

  // Restoring an automatic copy first keeps the current journal.
  await repository.createCoffee(name: 'Added later', roaster: 'Test');
  await _openSettingsTile($, 'auto-backups');
  await $.tap(find.byKey(const ValueKey('auto-backups')));
  await $.tap(find.byKey(const ValueKey('auto-backup-0')));
  await $.waitUntilVisible(find.textContaining('keeps your current journal'));
  await $.takeNativeScreenshot('auto-backup-restore-dialog');
  await $.tap(find.widgetWithText(FilledButton, 'Restore'));
  await $.waitUntilVisible(find.text('Backup restored'));
  final coffees = await repository.allCoffees();
  expect(coffees.map((coffee) => coffee.name), ['Backup bean']);
  final copies = await services.autoBackups.list();
  expect(copies, hasLength(2));

  // Stop using the folder: access is released, its copies stay.
  await $.tester.pageBack();
  await $.pumpAndSettle();
  await $.scrollUntilVisible(
    finder: find.byKey(const ValueKey('backup-folder')),
  );
  await $.tap(find.byKey(const ValueKey('backup-folder')));
  await $.tap(find.byKey(const ValueKey('backup-folder-forget')));
  await $.waitUntilVisible(
    find.textContaining('Choose a folder on your phone'),
  );
  expect((await services.state.load()).folderUri, isNull);
}

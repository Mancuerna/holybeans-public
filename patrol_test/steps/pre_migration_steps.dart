import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/pre_migration_copies.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/backup/backup_center.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:patrol/patrol.dart';

import '../../test/helpers/legacy_schema.dart';
import 'backup_steps.dart';

/// A journal left in schema 22 by the previous version is copied before
/// this version opens it, listed under "Before updating the app" and
/// restored from there, brought up to date.
Future<void> checkPreMigrationCopy(
  PatrolIntegrationTester $,
  AppDatabase database,
) async {
  final support = await getApplicationSupportDirectory();
  final folder = Directory(path.join(support.path, 'patrol-pre-migration'));
  if (folder.existsSync()) await folder.delete(recursive: true);
  final copies = PreMigrationCopies(folder);

  final journal = File(path.join(support.path, 'patrol-old-journal.sqlite'));
  if (journal.existsSync()) await journal.delete();
  final old = AppDatabase.at(journal);
  await JournalRepository(old)
      .createCoffee(name: 'Before update', roaster: 'Test');
  // The same rebuild the migration tests use, checked against the dumped
  // schemas, so it cannot drift from what schema 22 really was.
  await reconstructLegacySchema(old, 22);
  await old.close();
  final kept = await copies.keepIfUpgrading(
    journal,
    currentSchema: AppDatabase.currentSchema,
  );
  expect(kept?.schema, 22);
  await journal.delete();

  final repository = JournalRepository(database);
  await repository.createCoffee(name: 'Current bean', roaster: 'Test');
  final base = await openTestBackupServices();
  await $.pumpWidgetAndSettle(
    HolyBeansApp(
      services: AppServices(
        database: database,
        backupServices: BackupServices(
          autoBackups: base.autoBackups,
          state: base.state,
          preMigration: copies,
        ),
      ),
      initialLocale: const Locale('en'),
    ),
  );
  await $.tap(find.byTooltip('Settings'));
  await $.scrollUntilVisible(
    finder: find.byKey(const ValueKey('auto-backups')),
  );
  await $.tap(find.byKey(const ValueKey('auto-backups')));
  final copy = find.byKey(const ValueKey('pre-migration-0'));
  await $.scrollUntilVisible(finder: copy);
  await $.takeNativeScreenshot('pre-migration-list');
  await $.tap(copy);
  await $.waitUntilVisible(find.textContaining('keeps your current journal'));
  await $.tap(find.widgetWithText(FilledButton, 'Restore'));
  await $.waitUntilVisible(find.text('Backup restored'));
  expect((await repository.allCoffees()).map((coffee) => coffee.name), [
    'Before update',
  ]);
  // The journal it replaced became an automatic copy.
  expect(await base.autoBackups.list(), hasLength(1));
  await folder.delete(recursive: true);
}

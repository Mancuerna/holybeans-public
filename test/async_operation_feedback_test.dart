import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/backup_state.dart';
import 'package:holybeans/data/preferences/language_setting.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/beanconqueror_archive.dart';
import 'package:holybeans/domain/beanconqueror/bq_import_plan.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/backup/backup_actions.dart';
import 'package:holybeans/ui/backup/backup_center.dart';
import 'package:holybeans/ui/backup/backup_section.dart';
import 'package:holybeans/ui/beans/coffee_form.dart';
import 'package:holybeans/ui/beans/share_bean_sheet.dart';
import 'package:holybeans/ui/settings/beanconqueror_import_page.dart';
import 'package:holybeans/ui/settings/pours_from_curves.dart';
import 'package:holybeans/ui/shell/journal_actions.dart';
import 'package:holybeans/ui/shell/journal_shell.dart';

import 'helpers/beanconqueror_fixture.dart';
import 'helpers/fake_export_folder.dart';
import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

Widget _app(Widget child) => localizedApp(
  locale: const Locale('en'),
  home: Scaffold(body: child),
);

void main() {
  late AppDatabase db;
  late JournalRepository repository;
  late Coffee coffee;
  var closed = false;
  setUp(() async {
    db = memoryDatabase();
    repository = JournalRepository(db);
    coffee = (await repository.coffee(
      await repository.createCoffee(name: 'Bean', roaster: 'Test'),
    ))!;
    closed = false;
  });
  tearDown(() async {
    if (!closed) await db.close();
  });

  for (final extras in [false, true]) {
    testWidgets(
      'BeanConqueror read failure retains diagnostics, extras=$extras',
      (tester) async {
        final messages = <String>[];
        final original = debugPrint;
        debugPrint = (message, {wrapWidth}) => messages.add(message ?? '');
        try {
          if (extras) {
            final plan = planBeanconquerorImport(
              BeanconquerorArchive.read(zip()),
              await repository.beanconquerorJournal(),
              now: DateTime.utc(2026),
            );
            await tester.pumpWidget(
              _app(
                BeanconquerorImportPage(
                  plan: plan,
                  repository: repository,
                  pickFiles: () async => [_UnreadableZip()],
                ),
              ),
            );
            await tester.pumpAndSettle();
            final pick = find.byKey(const ValueKey('bq-pick-files'));
            await tester.scrollUntilVisible(pick, 200);
            await tester.tap(pick);
          } else {
            await tester.pumpWidget(
              _app(
                Builder(
                  builder: (context) => TextButton(
                    onPressed: () => importFromBeanconqueror(
                      context,
                      repository: repository,
                      folder: _UnreadableFolder(),
                    ),
                    child: const Text('Import'),
                  ),
                ),
              ),
            );
            await tester.tap(find.text('Import'));
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(const ValueKey('bq-source-folder')));
          }
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(messages.join('\n'), contains('HolyBeans recovered from:'));
          expect(
            messages.join('\n'),
            contains('Synthetic import read failure'),
          );
          expect(await repository.allCoffees(), hasLength(1));
        } finally {
          debugPrint = original;
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 10));
        }
      },
    );
  }

  for (final operation in ['suggestions', 'pours', 'share']) {
    testWidgets('failed $operation read gives feedback without escaping', (
      tester,
    ) async {
      await db.close();
      closed = true;
      await tester.pumpWidget(
        _app(
          operation == 'suggestions'
              ? CoffeeForm(repository: repository)
              : Builder(
                  builder: (context) => TextButton(
                    onPressed: () => operation == 'pours'
                        ? fillPoursFromCurves(
                            context,
                            repository: repository,
                            message: (_) => fail('Unexpected success'),
                          )
                        : showBeanTransferSheet(
                            context,
                            _Actions(repository),
                            coffee,
                          ),
                    child: const Text('Run'),
                  ),
                ),
        ),
      );
      await tester.pumpAndSettle();
      if (operation != 'suggestions') {
        await tester.tap(find.text('Run'));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      final s = lookupAppLocalizations(const Locale('en'));
      expect(
        find.text(operation == 'share' ? s.shareFailed : s.dataError),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    });
  }

  testWidgets('forgetting a backup folder reports a failed preference write', (
    tester,
  ) async {
    final center = _FailingFolderCenter(db)
      ..state = const BackupState(
        folderUri: 'content://backups',
        folderName: 'Backups',
      );
    addTearDown(center.dispose);
    await tester.pumpWidget(
      _app(
        BackupSection(
          center: center,
          actions: BackupActions(
            center: center,
            repository: repository,
            photos: null,
            message: (_) {},
          ),
          onSaveToFolder: () {},
          onChooseFolder: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('backup-folder')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('backup-folder-forget')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.text(lookupAppLocalizations(const Locale('en')).saveFailed),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('a failed language save is reported and leaves the app usable', (
    tester,
  ) async {
    await LanguageSetting(db).save(const Locale('en'));
    await db.customStatement(
      "CREATE TRIGGER reject_locale BEFORE UPDATE OF locale_code ON app_preferences BEGIN SELECT RAISE(FAIL, 'Language write failed'); END",
    );
    await tester.pumpWidget(
      HolyBeansApp(database: db, initialLocale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    final messages = <String>[];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) => messages.add(message ?? '');
    try {
      tester
          .widget<JournalShell>(find.byType(JournalShell))
          .onLocaleChanged(const Locale('es'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(messages.join('\n'), contains('Language write failed'));
      expect(await LanguageSetting(db).load(), const Locale('en'));
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
        const Locale('es'),
      );
    } finally {
      debugPrint = original;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    }
  });
}

class _Actions extends Fake implements JournalActions {
  _Actions(this.repository);
  @override
  final JournalRepository repository;
}

class _FailingFolderCenter extends BackupCenter {
  _FailingFolderCenter(AppDatabase db) : super(database: db, photos: null);
  @override
  bool get hasAutoBackups => true;
  @override
  bool get canUseFolder => true;
  @override
  Future<void> forgetFolder() async =>
      throw StateError('Cannot save folder preferences');
}

class _UnreadableFolder extends FakeExportFolder {
  _UnreadableFolder() : super({});
  @override
  Future<String?> pick() async =>
      throw const FileSystemException('Synthetic import read failure');
}

class _UnreadableZip extends XFile {
  _UnreadableZip() : super('/unused-extra.zip');
  @override
  Future<Uint8List> readAsBytes() async =>
      throw const FileSystemException('Synthetic import read failure');
}

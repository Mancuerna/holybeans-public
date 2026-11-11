import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/drive_sync_coordinator.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/data/services/journal_write_gate.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/domain/share_template.dart';
import 'package:holybeans/ui/brews/share_template_editor.dart';
import 'package:holybeans/ui/core/form_widgets.dart';
import 'package:holybeans/ui/equipment/tools_page.dart';
import 'package:holybeans/ui/sync/drive_sync_model.dart';
import 'package:holybeans/ui/sync/drive_sync_scope.dart';
import 'package:path/path.dart' as path;

import 'helpers/drive_fake_server.dart';
import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final (drive, observe) in [(false, true), (true, true), (true, false)]) {
    testWidgets('archive: Drive=$drive, navigation observer=$observe', (
      tester,
    ) async {
      final db = memoryDatabase();
      final repo = JournalRepository(db);
      final method = await repo.createMethod(name: 'Lelit Bianca v3');
      final id = await repo.createTool(
        name: 'Lelit by IMS 14 - 18',
        methodIds: [method],
      );
      const channel = MethodChannel('holybeans/drive-sync');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final server = DriveFakeServer();
      messenger.setMockMethodCallHandler(channel, server.handle);
      late Directory directory;
      late DriveSyncModel model;
      final held = Completer<void>();
      final entered = Completer<void>();
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp(
          'archive-drive-repro-',
        );
        model = await DriveSyncModel.open(
          JournalBackup(db),
          PhotoStore(Directory(path.join(directory.path, 'photos'))),
        );
        if (drive) await model.enable();
      });
      try {
        await tester.pumpWidget(
          localizedApp(
            locale: const Locale('en'),
            navigatorObservers: [if (observe) model.observer],
            home: Scaffold(
              body: ToolsList(repository: repo, showArchived: false),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(db.writeGate.writable, isTrue);
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'connect') {
            if (!entered.isCompleted) entered.complete();
            await held.future;
          }
          return server.handle(call);
        });
        await tester.tap(find.byTooltip('Actions'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Archive accessory'));
        await tester.pumpAndSettle();
        final row = (await db.select(db.methodTools).get()).single;
        expect(row.archivedAtMs, isNotNull);
        expect(find.text('Could not save'), findsNothing);
        expect(entered.isCompleted, isFalse);
        // Restore the synthetic row only in the local test database.
        expect((await repo.toolCatalog()).byId[id]!.archivedAtMs, isNotNull);
        await tester.pump(const Duration(minutes: 3));
        expect(entered.isCompleted, isFalse);
        expect(db.writeGate.writable, isTrue);
      } finally {
        held.complete();
        for (var i = 0; model.busy && i < 500; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(model.busy, isFalse);
        model.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await db.close();
        await tester.runAsync(() => directory.delete(recursive: true));
        messenger.setMockMethodCallHandler(channel, null);
      }
    });
  }
  group('shared write coordination', () {
    late AppDatabase db;
    late JournalRepository repo;
    late DriveSyncModel model;
    late Directory directory;
    late DriveFakeServer server;
    var disposed = false;
    const channel = MethodChannel('holybeans/drive-sync');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    setUp(() async {
      disposed = false;
      db = memoryDatabase();
      repo = JournalRepository(db);
      directory = await Directory.systemTemp.createTemp('drive-actions-');
      model = await DriveSyncModel.open(
        JournalBackup(db),
        PhotoStore(Directory(path.join(directory.path, 'photos'))),
      );
      server = DriveFakeServer();
      messenger.setMockMethodCallHandler(channel, server.handle);
      await model.enable();
    });
    tearDown(() async {
      if (!disposed) model.dispose();
      await db.close();
      await directory.delete(recursive: true);
      messenger.setMockMethodCallHandler(channel, null);
    });

    test('a save already writing commits while a backup starts', () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final write = db.transaction(() async {
        await repo.createMethod(name: 'First');
        entered.complete();
        await release.future;
        await repo.createMethod(name: 'Second');
      });
      await entered.future;
      final check = model.synchronize();
      expect(model.busy, isTrue);
      expect(db.writeGate.writable, isTrue);
      release.complete();
      await write;
      await check;
      expect(
        model.status,
        isIn([DriveSyncStatus.current, DriveSyncStatus.pending]),
      );
      expect(
        (await db.select(db.brewMethods).get()).map((m) => m.name),
        containsAll(['First', 'Second']),
      );
    });

    for (final outcome in ['save', 'offline', 'cancel']) {
      testWidgets('shared form saves independently of Drive: $outcome', (
        tester,
      ) async {
        var saves = 0;
        final controller = TextEditingController(text: 'Keep this draft');
        final key = GlobalKey<FormState>();
        await tester.pumpWidget(
          localizedApp(
            locale: const Locale('en'),
            navigatorObservers: [model.observer],
            builder: (_, child) => DriveSyncScope(model: model, child: child!),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  child: const Text('Edit'),
                  onPressed: () => showFormSheet<void>(
                    context,
                    SheetFrame(
                      title: 'Editor',
                      formKey: key,
                      saving: false,
                      onSave: () => saves++,
                      children: [TextFormField(controller: controller)],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Edit'));
        await tester.pumpAndSettle();
        // Deferred checks must not close the gate while a draft is open.
        await tester.pump(const Duration(seconds: 2));
        expect(model.busy, isFalse);
        expect(db.writeGate.writable, isTrue);
        final entered = Completer<void>();
        final held = Completer<void>();
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'connect') {
            if (!entered.isCompleted) entered.complete();
            await held.future;
          }
          return server.handle(call);
        });
        late Future<void> checking;
        checking = model.synchronize();
        for (var i = 0; !entered.isCompleted && i < 500; i++) {
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
        expect(entered.isCompleted, isTrue);
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(find.text('Preparing Drive backup…'), findsNothing);
        expect(saves, 1);
        if (outcome == 'cancel') {
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
        }
        server.offline = outcome == 'offline';
        held.complete();
        for (var i = 0; model.busy && i < 500; i++) {
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
        expect(model.busy, isFalse);
        await checking;
        await tester.pumpAndSettle();
        expect(saves, 1);
        expect(find.byType(AlertDialog), findsNothing);
        expect(db.writeGate.writable, isTrue);
        if (outcome == 'cancel') expect(find.text('Editor'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        model.dispose();
        disposed = true;
        controller.dispose();
      });
    }

    testWidgets(
      'local share templates can still save while Drive is unavailable',
      (tester) async {
        server.offline = true;
        await tester.runAsync(model.synchronize);
        expect(db.writeGate.writable, isTrue);
        var saves = 0;
        await tester.pumpWidget(
          localizedApp(
            builder: (_, child) => DriveSyncScope(model: model, child: child!),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showFormSheet<void>(
                    context,
                    ShareTemplateEditor(
                      style: ShareTemplateStyle.espresso,
                      existing: const ShareTemplate(
                        id: 'local',
                        name: 'Local template',
                        style: ShareTemplateStyle.espresso,
                        body: 'My brew',
                      ),
                      onSave: (_) async {
                        saves++;
                      },
                    ),
                  ),
                  child: const Text('Edit'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Edit'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(saves, 1);
        expect(find.byType(AlertDialog), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'only write protection failures are explained as Drive errors',
      (tester) async {
        late BuildContext context;
        await tester.pumpWidget(
          localizedApp(
            builder: (_, child) => DriveSyncScope(model: model, child: child!),
            home: Builder(
              builder: (value) {
                context = value;
                return const SizedBox();
              },
            ),
          ),
        );
        model.status = DriveSyncStatus.conflict;
        expect(
          journalWriteErrorText(context, StateError('disk'), 'Storage failed'),
          'Storage failed',
        );
        expect(
          journalWriteErrorText(
            context,
            const JournalReadOnlyException(),
            'Failure',
          ),
          contains('being restored'),
        );
        model.status = DriveSyncStatus.editing;
        expect(
          journalWriteErrorText(
            context,
            const JournalReadOnlyException(),
            'Failure',
          ),
          contains('being restored'),
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  });
}

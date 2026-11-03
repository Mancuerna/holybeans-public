import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/drive_sync_remote.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/equipment/tools_page.dart';
import 'package:holybeans/ui/sync/drive_sync_model.dart';
import 'package:holybeans/ui/sync/drive_sync_scope.dart';
import 'package:patrol/patrol.dart';

import '../test/helpers/drive_fake_server.dart';
import 'support/smoke_support.dart';

Future<void> _idle(PatrolIntegrationTester $, DriveSyncModel model) async {
  final watch = Stopwatch()..start();
  while (model.busy && watch.elapsed < const Duration(seconds: 40)) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await $.pump();
  }
  expect(model.busy, isFalse);
  await $.pumpAndSettle();
}

void main() {
  patrolTest(
    'Drive allows archive and preserves an accessory draft',
    tags: ['android', 'drive-actions'],
    ($) async {
      const client = DriveNativeClient();
      expect(DriveRemoteAdapter.space, 'holybeans-journal-patrol-v1');
      expect(
        await client.channel.invokeMethod<String>('package'),
        'com.caffeinateddev.holybeans.patrol',
      );
      final database = await openTestDatabase();
      await clearTestData(database);
      final repository = JournalRepository(database);
      final id = await repository.createTool(
        name: 'Lelit by IMS test',
        methodIds: [],
      );
      final server = DriveFakeServer();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(client.channel, server.handle);
      final model = await DriveSyncModel.open(
        JournalBackup(database),
        await PhotoStore.open(),
      );
      await model.enable();
      try {
        await $.pumpWidgetAndSettle(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            navigatorObservers: [model.observer],
            builder: (_, child) => DriveSyncScope(model: model, child: child!),
            home: Scaffold(
              body: ToolsList(repository: repository, showArchived: true),
            ),
          ),
        );
        await $(find.byTooltip('Actions')).tap();
        await $('Archive accessory').tap();
        expect(
          (await repository.toolCatalog()).byId[id]!.archivedAtMs,
          isNotNull,
        );
        expect(find.byType(AlertDialog), findsNothing);
        await $(find.byTooltip('Actions')).tap();
        await $('Restore accessory').tap();
        expect((await repository.toolCatalog()).byId[id]!.archivedAtMs, isNull);
        await $('Lelit by IMS test').tap();
        await $(const ValueKey('tool-name')).enterText('Lelit draft retained');
        final held = Completer<void>();
        final entered = Completer<void>();
        messenger.setMockMethodCallHandler(client.channel, (call) async {
          if (call.method == 'connect') {
            if (!entered.isCompleted) entered.complete();
            await held.future;
          }
          return server.handle(call);
        });
        unawaited(model.synchronize());
        await entered.future.timeout(const Duration(seconds: 10));
        await $('Save').tap();
        expect(model.busy, isTrue);
        expect(database.writeGate.writable, isTrue);
        expect(
          (await repository.toolCatalog()).byId[id]!.name,
          'Lelit draft retained',
        );
        expect(find.byType(AlertDialog), findsNothing);
        await $.takeNativeScreenshot('drive-form-saved-during-upload');
        server.offline = true;
        held.complete();
        await _idle($, model);
        expect(find.byType(AlertDialog), findsNothing);
        await $('Lelit draft retained').tap();
        await $(const ValueKey('tool-name')).enterText('Lelit saved offline');
        await $('Save').tap();
        expect(
          (await repository.toolCatalog()).byId[id]!.name,
          'Lelit saved offline',
        );
        expect(database.writeGate.writable, isTrue);
        await $.takeNativeScreenshot('drive-form-saved');
      } finally {
        model.dispose();
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
        messenger.setMockMethodCallHandler(client.channel, null);
      }
    },
  );
}

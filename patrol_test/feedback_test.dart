import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/preferences/release_notes_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/drive_sync_remote.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/brews/tasting_widgets.dart';
import 'package:holybeans/ui/sync/drive_sync_model.dart';
import 'package:path/path.dart' as path;
import 'package:patrol/patrol.dart';

import '../test/helpers/drive_fake_server.dart';
import 'acaia_scale_test.dart' show checkAcaiaScale;
import 'support/smoke_support.dart';

Future<void> _idle(PatrolIntegrationTester $, DriveSyncModel model) async {
  final watch = Stopwatch()..start();
  while (model.busy && watch.elapsed < const Duration(seconds: 40)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await $.pump();
  }
  expect(model.busy, isFalse);
  await $.pumpAndSettle();
}

void main() {
  patrolTest(
    'Acaia clock packets cannot start a brew',
    tags: ['feedback-acaia'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkAcaiaScale($, database);
      } finally {
        await database.close();
      }
    },
  );

  patrolTest(
    'Update notes and rating while Drive checks',
    tags: ['feedback-rating'],
    ($) async {
      expect(DriveRemoteAdapter.space, 'holybeans-journal-patrol-v1');
      final channel = const DriveNativeClient().channel;
      expect(
        await channel.invokeMethod<String>('package'),
        'com.caffeinateddev.holybeans.patrol',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final server = DriveFakeServer();
      messenger.setMockMethodCallHandler(channel, server.handle);
      final database = await openTestDatabase();
      final directory = await Directory.systemTemp.createTemp(
        'feedback-patrol-',
      );
      final photos = PhotoStore(Directory(path.join(directory.path, 'photos')));
      final notes = ReleaseNotesSettings(
        File(path.join(directory.path, 'notes.json')),
      );
      final model = await DriveSyncModel.open(JournalBackup(database), photos);
      final held = Completer<void>();
      try {
        await clearTestData(database);
        final repository = JournalRepository(database);
        final coffee = await repository.createCoffee(
          name: 'Patrol rating',
          roaster: 'Test',
        );
        await model.enable();
        await $.pumpWidgetAndSettle(
          HolyBeansApp(
            database: database,
            initialLocale: const Locale('en'),
            photos: photos,
            driveSync: model,
            releaseNotes: notes,
          ),
        );
        await $.takeNativeScreenshot('feedback-release-notes');
        await $('Got it').tap();
        await _idle($, model);
        expect(await notes.pending(existingInstallation: true), isFalse);
        // A fresh save triggers the same automatic check as the brew form.
        await repository.createBrew(
          coffeeId: coffee,
          methodName: 'V60',
          doseGrams: 18,
        );
        final brew = await database.select(database.brews).getSingle();
        final entered = Completer<void>();
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'connect') {
            if (!entered.isCompleted) entered.complete();
            await held.future;
          }
          return server.handle(call);
        });
        unawaited(model.synchronize());
        await entered.future;
        final context = $.tester.element(find.byType(NavigationBar));
        unawaited(
          showRateBrewSheet(context, repository, brew, title: 'Patrol rating'),
        );
        await $.pumpAndSettle();
        await $.enterText(find.byType(TextField).first, 'Fresh rating');
        await $(const ValueKey('rate-brew-save')).tap();
        expect(
          find.text('Waiting for the Drive check to finish…'),
          findsOneWidget,
        );
        await $.takeNativeScreenshot('feedback-rating-wait');
        held.complete();
        await _idle($, model);
        await $.waitUntilVisible(find.byType(NavigationBar));
        expect(
          (await database.select(database.brews).getSingle()).notes,
          'Fresh rating',
        );
        expect(find.byKey(const ValueKey('rate-brew-sheet')), findsNothing);
        await _idle($, model);
        server.offline = true;
        await model.synchronize();
        unawaited(
          showRateBrewSheet(context, repository, brew, title: 'Patrol rating'),
        );
        await $.pumpAndSettle();
        await $(const ValueKey('rate-brew-save')).tap();
        expect(
          find.textContaining('Your rating is still here.'),
          findsOneWidget,
        );
        expect(find.byType(SnackBar), findsNothing);
        await $.takeNativeScreenshot('feedback-rating-error');
        await $('Cancel').tap();
        await _idle($, model);
      } finally {
        if (!held.isCompleted) held.complete();
        await _idle($, model);
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
        await directory.delete(recursive: true);
        messenger.setMockMethodCallHandler(channel, null);
      }
    },
  );
}

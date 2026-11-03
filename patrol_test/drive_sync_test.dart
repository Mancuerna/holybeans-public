import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/drive_sync_coordinator.dart';
import 'package:holybeans/data/services/drive_sync_remote.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/sync/drive_sync_model.dart';
import 'package:holybeans/ui/sync/drive_sync_page.dart';
import 'package:image/image.dart' as image;
import 'package:patrol/patrol.dart';

import '../test/helpers/drive_fake_server.dart';
import 'support/smoke_support.dart';

Future<void> _idle(PatrolIntegrationTester $, DriveSyncModel model) async {
  final watch = Stopwatch()..start();
  while (model.busy && watch.elapsed < const Duration(minutes: 2)) {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await $.pump();
  }
  expect(model.busy, isFalse, reason: 'Drive operation timed out');
  await $.pumpAndSettle();
}

void main() {
  patrolTest(
    'Drive controls and lifecycle keep the journal safe',
    tags: ['android', 'drive-sync'],
    ($) async {
      expect(DriveRemoteAdapter.space, 'holybeans-journal-patrol-v1');
      expect(
        await const DriveNativeClient().channel.invokeMethod<String>('package'),
        'com.caffeinateddev.holybeans.patrol',
      );
      // Patrol clears app data, including the selected Google account. OAuth
      // and actual Drive bytes are covered separately on the release fixture;
      // this repeatable UI/lifecycle test never selects an account for the user.
      final server = DriveFakeServer();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const DriveNativeClient().channel,
        server.handle,
      );
      final database = await openTestDatabase();
      await clearTestData(database);
      final photos = await PhotoStore.open();
      final repository = JournalRepository(database);
      final coffee = await repository.createCoffee(
        name: 'Patrol Drive synthetic',
        roaster: 'Test',
        initialGrams: 500,
      );
      final name = await photos.add(
        Uint8List.fromList(image.encodeJpg(image.Image(width: 16, height: 16))),
      );
      await repository.setCoffeePhotos(coffee, [name]);
      final model = await DriveSyncModel.open(JournalBackup(database), photos);
      try {
        await $.pumpWidgetAndSettle(
          HolyBeansApp(
            database: database,
            photos: photos,
            initialLocale: const Locale('en'),
            driveSync: model,
          ),
        );
        await $(Icons.settings_outlined).tap();
        await $.scrollUntilVisible(finder: $(DriveSyncTile));
        await $(DriveSyncTile).tap();
        await $('Enable with Google').tap(settlePolicy: SettlePolicy.noSettle);
        await _idle($, model);
        expect(model.status, DriveSyncStatus.current);
        expect(database.writeGate.writable, isTrue);
        await $('Browse backups to restore')
            .tap(settlePolicy: SettlePolicy.noSettle);
        await _idle($, model);
        expect(model.copies, hasLength(1));
        await $.takeNativeScreenshot('drive-backup-copies');
        await $.scrollUntilVisible(finder: $('Restore this backup'));
        await $('Restore this backup').tap();
        await $('Cancel').tap();
        await $('Restore this backup').tap();
        await $('Continue').tap(settlePolicy: SettlePolicy.noSettle);
        await _idle($, model);
        expect(
          (await database.select(database.coffees).get()).single.id,
          coffee,
        );
        await $.scrollUntilVisible(finder: $('Turn off Drive backups'));
        await $('Turn off Drive backups').tap();
        await $('Cancel').tap();
        expect(model.enabled, isTrue);
        Navigator.of($.tester.element(find.byType(DriveSyncPage))).pop();
        await $.pumpAndSettle();
        await $.tester.pageBack();
        await _idle($, model);
        final bottom = $.tester.getRect(find.byType(NavigationBar));
        final held = Completer<void>();
        messenger.setMockMethodCallHandler(const DriveNativeClient().channel, (
          call,
        ) async {
          if (call.method == 'connect') await held.future;
          return server.handle(call);
        });
        try {
          await repository.createCoffee(
            name: 'Lifecycle copy',
            roaster: 'Test',
          );
          await $.platform.mobile.pressHome();
          await $.platform.mobile.openApp();
          await $.pump();
          expect(model.busy, isTrue);
          expect(model.applying, isFalse);
          expect(find.text('Preparing Drive backup…'), findsNothing);
          expect(database.writeGate.writable, isTrue);
          expect($.tester.getRect(find.byType(NavigationBar)), bottom);
          await $.takeNativeScreenshot('drive-silent-check');
          await $(Icons.settings_outlined).tap();
          expect(database.writeGate.writable, isTrue);
          await $.tester.pageBack();
          await $.pumpAndSettle();
          expect(model.busy, isTrue);
          expect($.tester.getRect(find.byType(NavigationBar)), bottom);
        } finally {
          held.complete();
          await _idle($, model);
        }
        expect(model.status, DriveSyncStatus.current);
        expect(await photos.file(name).readAsBytes(), isNotEmpty);
        server.offline = true;
        await model.synchronize();
        await $.pumpAndSettle();
        expect(model.status, DriveSyncStatus.unavailable);
        expect(find.textContaining('could not finish'), findsNothing);
        await repository.createCoffee(name: 'Offline works', roaster: 'Test');
        await $.takeNativeScreenshot('drive-offline-journal');
        server.offline = false;
        await model.synchronize();
        await $.pumpAndSettle();
        expect(model.status, DriveSyncStatus.current);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
        messenger.setMockMethodCallHandler(
          const DriveNativeClient().channel,
          null,
        );
      }
    },
  );
}

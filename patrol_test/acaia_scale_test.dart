import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/scale_settings.dart';
import 'package:holybeans/data/services/ble_scale.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/settings/scale_section.dart';
import 'package:patrol/patrol.dart';
import 'package:universal_ble/universal_ble.dart';

import '../test/helpers/fake_acaia_ble_platform.dart';
import 'steps/filter_scale_steps.dart';
import 'support/smoke_support.dart';

/// Pairs a simulated peripheral through the real BLE adapter, then brews.
Future<void> checkAcaiaScale(
  PatrolIntegrationTester $,
  AppDatabase database,
) async {
  final platform = FakeAcaiaBlePlatform(pearl: true)
    ..settingsDelay = const Duration(milliseconds: 250)
    ..ignoreAcknowledgedHandshake = true
    ..settingsAfterSubscription = true;
  UniversalBle.setInstance(platform);
  final scale = BleScale(ScaleSettings(database));
  try {
    await $.pumpWidgetAndSettle(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SafeArea(
            child: ListView(children: [ScaleSection(scale: scale)]),
          ),
        ),
      ),
    );
    await $.tap(find.byKey(const ValueKey('scale-find')));
    await $.waitUntilVisible(find.text(platform.name));
    expect(find.text('DiFluid R2'), findsNothing);
    final found = find.byKey(ValueKey('scale-found-${platform.id}'));
    await $.tap(find.descendant(of: found, matching: find.text('Connect')));
    await $.waitUntilVisible(find.text('18.0 g'));
    expect(find.text('Battery 73 %'), findsOneWidget);
    expect((await scale.settings.load())!.name, platform.name);
    await $.takeNativeScreenshot('acaia-scale-paired');
    await $.tap(find.byKey(const ValueKey('scale-tare')));
    await $.waitUntilVisible(find.text('0.0 g'));
    expect(platform.tareCount, 1);
    await checkFilterScale(
      $,
      database,
      connectedScale: scale,
      feedReading: platform.emit,
      screenshotPrefix: 'acaia-scale',
      verifyStoppedTimer: (toggle) async {
        await Future<void>.delayed(const Duration(milliseconds: 2300));
        for (var second = 1; second <= 4; second++) {
          platform.seconds = second;
          platform.emit(platform.grams);
          await $.pump();
        }
        expect(
          find.descendant(of: toggle, matching: find.text('Start')),
          findsOneWidget,
          reason: 'Clock packets must not start a stopped brew',
        );
      },
    );
    expect(
      platform.tareCount,
      2,
      reason: 'Only settings Tare and fresh brew Start',
    );
    expect(
      platform.writes.every(
        (frame) => [0, 4, 6, 11, 12, 13].contains(frame[2]),
      ),
      isTrue,
    );
    await scale.forget();
    expect(await scale.settings.load(), isNull);
  } finally {
    await $.pumpWidgetAndSettle(const SizedBox.shrink());
    await scale.disconnect();
    scale.dispose();
  }
}

void main() {
  patrolTest(
    'Acaia pairs, tares and records a filter brew',
    tags: ['android', 'acaia-scale'],
    ($) async {
      final db = await openTestDatabase();
      try {
        await clearTestData(db);
        await checkAcaiaScale($, db);
      } finally {
        await db.close();
      }
    },
  );
}

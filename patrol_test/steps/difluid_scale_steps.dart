import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/scale_settings.dart';
import 'package:holybeans/data/services/ble_scale.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/settings/scale_section.dart';
import 'package:patrol/patrol.dart';
import 'package:universal_ble/universal_ble.dart';

import '../../test/helpers/fake_scale_ble_platform.dart';
import 'filter_scale_steps.dart';

/// Pairs a simulated peripheral through the real BLE adapter, then brews.
Future<void> checkDifluidScale(
  PatrolIntegrationTester $,
  AppDatabase database,
) async {
  final platform = FakeScaleBlePlatform();
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
    expect(find.text('Battery 64 %'), findsOneWidget);
    expect((await scale.settings.load())!.name, platform.name);
    await $.takeNativeScreenshot('difluid-scale-paired');
    await $.tap(find.byKey(const ValueKey('scale-tare')));
    await $.waitUntilVisible(find.text('0.0 g'));
    expect(platform.tareCount, 1);
    await checkFilterScale(
      $,
      database,
      connectedScale: scale,
      feedReading: platform.emit,
      screenshotPrefix: 'difluid-scale',
    );
    expect(
      platform.tareCount,
      2,
      reason: 'Only settings Tare and fresh brew Start',
    );
    expect(
      platform.writes.every(
        (frame) =>
            frame[4] == 0 ||
            frame[2] == 3 && frame[4] == 1 && (frame[3] == 1 || frame[3] == 2),
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

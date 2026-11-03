import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/scale_settings.dart';
import 'package:holybeans/data/services/ble_scale.dart';
import 'package:holybeans/data/services/scale_discovery.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/settings/scale_section.dart';
import 'package:patrol/patrol.dart';
import 'package:universal_ble/universal_ble.dart';

import '../../test/helpers/multi_scale_ble_platform.dart';

Future<void> checkMultiScale(PatrolIntegrationTester $, AppDatabase db) async {
  final platform = MultiScalePlatform()..nearby = [ultra, mini];
  UniversalBle.setInstance(platform);
  final scale = BleScale(
    ScaleSettings(db),
    discovery: ScaleDiscovery(duration: const Duration(milliseconds: 100)),
  );
  try {
    await $.pumpWidgetAndSettle(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SafeArea(
            child: ListView(children: [ScaleSection(scale: scale)]),
          ),
        ),
      ),
    );
    Future<void> pair(String id) async {
      final search = find.byKey(const ValueKey('scale-find'));
      await $.tester.ensureVisible(search);
      await $.tap(search);
      final row = find.byKey(ValueKey('scale-found-$id'));
      await $.waitUntilVisible(row);
      await $.tester.ensureVisible(row);
      await $.tap(find.descendant(of: row, matching: find.text('Conectar')));
      await $.waitUntilVisible(find.byKey(ValueKey('scale-saved-$id')));
    }

    await pair(ultra.id);
    await pair(mini.id);
    expect(scale.rememberedScales.map((d) => d.id), [mini.id, ultra.id]);
    await $.takeNativeScreenshot('multi-scale-paired-es');
    platform.lose(mini.id);
    await $.pump();
    platform.nearby = [ultra];
    await scale.connect(automatic: true);
    await $.pumpAndSettle();
    expect(scale.activeScaleId, ultra.id);
    final forget = find.byKey(ValueKey('scale-forget-${mini.id}'));
    await $.tester.ensureVisible(forget);
    await $.tap(forget);
    await $.pumpAndSettle();
    expect(scale.rememberedScales.map((d) => d.id), [ultra.id]);
    expect(scale.activeScaleId, ultra.id);
    expect((await scale.settings.loadAll()).map((d) => d.deviceId), [ultra.id]);
    await $.takeNativeScreenshot('multi-scale-remaining-es');
    expect(platform.writes, isEmpty);
  } finally {
    await $.pumpWidgetAndSettle(const SizedBox.shrink());
    await scale.disconnect();
    scale.dispose();
  }
}

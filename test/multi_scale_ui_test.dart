import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/scale_settings.dart';
import 'package:holybeans/data/services/ble_scale.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/settings/scale_section.dart';
import 'package:universal_ble/universal_ble.dart';

import 'helpers/multi_scale_ble_platform.dart';

void main() {
  for (final language in ['es', 'en']) {
    testWidgets('settings add and forget individual scales in $language', (
      tester,
    ) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final scale = BleScale(ScaleSettings(db));
      final platform = MultiScalePlatform()..nearby = [ultra, mini];
      UniversalBle.setInstance(platform);
      addTearDown(() async {
        await scale.disconnect();
        scale.dispose();
        await db.close();
      });
      tester.view.physicalSize = const Size(440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(language),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ListView(children: [ScaleSection(scale: scale)]),
          ),
        ),
      );
      Future<void> pair(String id) async {
        await tester.tap(find.byKey(const ValueKey('scale-find')));
        await tester.pump();
        final row = find.byKey(ValueKey('scale-found-$id'));
        await tester.ensureVisible(row);
        await tester.tap(
          find.descendant(of: row, matching: find.byType(FilledButton)),
        );
        for (
          var i = 0;
          i < 100 && !scale.rememberedScales.any((d) => d.id == id);
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey('scale-saved-$id')),
          findsOneWidget,
          reason:
              '${scale.status}: ${platform.events}; saved: ${scale.rememberedScales.map((d) => d.id)}',
        );
      }

      await pair(ultra.id);
      expect(find.byKey(const ValueKey('scale-find')), findsOneWidget);
      await pair(mini.id);
      expect(scale.rememberedScales.map((s) => s.id), [mini.id, ultra.id]);
      final forget = find.byKey(ValueKey('scale-forget-${ultra.id}'));
      await tester.ensureVisible(forget);
      await tester.tap(forget);
      for (var i = 0; i < 100 && scale.rememberedScales.length > 1; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('scale-saved-${ultra.id}')), findsNothing);
      expect(scale.activeScaleId, mini.id);
      expect(tester.takeException(), isNull);
    });
  }
}

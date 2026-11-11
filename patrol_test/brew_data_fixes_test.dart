import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/preferences/scale_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/ble_scale.dart';
import 'package:holybeans/data/services/scale.dart';
import 'package:holybeans/domain/brew_pours.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:patrol/patrol.dart';
import 'package:universal_ble/universal_ble.dart';

import '../test/helpers/fake_scale_ble_platform.dart';
import 'gaggimate_test.dart' as gaggimate;
import 'support/smoke_support.dart';

void main() {
  gaggimate.main();
  patrolTest(
    'water breakdown saves planned pours without a Bluetooth scale',
    tags: ['android', 'brew-data-fixes'],
    ($) async {
      final db = await openTestDatabase();
      try {
        await clearTestData(db);
        final repo = JournalRepository(db);
        await repo.createCoffee(
          name: 'Plan beans',
          roaster: 'Test',
          initialGrams: 250,
        );
        await repo.createMethod(name: 'Plan V60', category: 'pourover');
        await $.pumpWidgetAndSettle(
          HolyBeansApp(
            services: AppServices(database: db),
            initialLocale: const Locale('en'),
          ),
        );
        await _openMethod($, 'Plan V60');
        final form = verticalScrollable(find.byType(BrewForm));
        for (final (label, value) in [
          ('Dose (g)', '18'),
          ('Water (g)', '300'),
        ]) {
          final field = find.widgetWithText(TextFormField, label);
          await $.scrollUntilVisible(finder: field, view: form);
          await $.enterText(field, value);
        }
        for (final (label, value) in [('Blooms', '1'), ('Pours', '3')]) {
          final field = find.byWidgetPredicate(
            (w) =>
                w is DropdownButtonFormField<int> &&
                w.decoration.labelText == label,
          );
          await $.scrollUntilVisible(finder: field, view: form);
          await $.tap(field);
          await $.tap(find.text(value).last);
        }
        final plan = find.text('Water breakdown · 300 g');
        await $.scrollUntilVisible(finder: plan, view: form);
        await $.tap(plan);
        final ratio = find.byKey(const ValueKey('water-plan-bloom-ratio'));
        await $.scrollUntilVisible(finder: ratio, view: form);
        await $.tap(ratio);
        await $.tap(find.text('1:3').last);
        await $.takeNativeScreenshot('planned-water-before-save');
        await $.tap(find.text('Save').last);
        final brew = (await repo.allBrews()).single;
        final pours = BrewPours.fromStorage(
          bloomCount: brew.bloomCount,
          pourCount: brew.pourCount,
          phasesJson: brew.pourPhasesJson,
        );
        expect(pours.phases.map((p) => p.waterGrams), [54, 82, 82, 82]);
        expect(
          pours.phases.every(
            (p) =>
                p.waterFromPlan &&
                p.durationSeconds == null &&
                p.restSeconds == null &&
                p.flowGramsPerSecond == null,
          ),
          isTrue,
        );
        expect(await repo.brewCurve(brew.id), isNull);
        expect(
          (await db.select(db.coffeeLots).getSingle()).remainingGrams,
          232,
        );
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await db.close();
      }
    },
  );
  patrolTest(
    'DiFluid first drip ignores automatic timer stops and retains manual pause',
    tags: ['android', 'brew-data-fixes'],
    ($) async {
      final db = await openTestDatabase();
      final platform = FakeScaleBlePlatform();
      UniversalBle.setInstance(platform);
      final scale = BleScale(ScaleSettings(db));
      try {
        await clearTestData(db);
        final repo = JournalRepository(db);
        await repo.createCoffee(
          name: 'Drip beans',
          roaster: 'Test',
          initialGrams: 250,
        );
        await repo.createMethod(name: 'Drip espresso', category: 'espresso');
        await scale.pair(FoundDevice(id: platform.id, name: platform.name));
        expect(scale.connected, isTrue);
        await $.pumpWidgetAndSettle(
          HolyBeansApp(
            services: AppServices(database: db, scale: scale),
            initialLocale: const Locale('en'),
          ),
        );
        await _openMethod($, 'Drip espresso');
        final form = verticalScrollable(find.byType(BrewForm));
        final dose = find.widgetWithText(TextFormField, 'Dose (g)');
        await $.scrollUntilVisible(finder: dose, view: form);
        await $.enterText(dose, '18');
        final wait = find.byKey(const ValueKey('scale-wait-drip'));
        await $.scrollUntilVisible(finder: wait, view: form);
        await $.tap(wait);
        await Future<void>.delayed(const Duration(milliseconds: 2400));
        for (final state in [10, 14, 13]) {
          platform.publishStatus(state);
          platform.seconds = state == 13 ? 0 : 2;
          platform.emit(0);
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
        await $.pumpAndSettle();
        expect(find.text('Waiting for the first drop…'), findsOneWidget);
        await $.takeNativeScreenshot('difluid-wait-survives-auto-stop');
        for (final grams in [0.0, 0.1, 1.2, 1.5, 2.0]) {
          platform.emit(grams);
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
        await Future<void>.delayed(const Duration(milliseconds: 2400));
        platform.publishStatus(10);
        platform.seconds = 2;
        platform.emit(2);
        await Future<void>.delayed(const Duration(milliseconds: 150));
        platform.publishStatus(14);
        platform.emit(2);
        await $.pumpAndSettle();
        final toggle = find.byKey(const ValueKey('chart-timer-toggle'));
        await $.scrollUntilVisible(finder: toggle, view: form);
        expect(
          find.descendant(of: toggle, matching: find.text('Stop')),
          findsOneWidget,
        );
        await $.takeNativeScreenshot('difluid-recording-after-auto-stop');
        platform.publishStatus(11);
        platform.emit(2);
        await $.pumpAndSettle();
        expect(
          find.descendant(of: toggle, matching: find.text('Start')),
          findsOneWidget,
        );
        expect(
          platform.writes.where((f) => f[2] == 1).every((f) => f[4] == 0),
          isTrue,
        );
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await scale.disconnect();
        scale.dispose();
        await db.close();
      }
    },
  );
}

Future<void> _openMethod(PatrolIntegrationTester $, String name) async {
  await $.tap(find.text('Brew').last);
  final method = find.byWidgetPredicate(
    (w) =>
        w is DropdownButtonFormField<String> &&
        w.decoration.labelText == 'Choose a method',
  );
  await $.scrollUntilVisible(
    finder: method,
    view: verticalScrollable(find.byType(BrewForm)),
  );
  await $.tap(method);
  await $.tap(find.text(name).last);
}

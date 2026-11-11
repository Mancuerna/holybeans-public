import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/paired_device_file.dart';
import 'package:holybeans/data/services/pressure_sensor.dart';
import 'package:holybeans/domain/bookoo_pressure_protocol.dart';
import 'package:holybeans/domain/curve_flow_stats.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:patrol/patrol.dart';
import 'package:universal_ble/universal_ble.dart';

import '../../test/helpers/fake_pressure_ble_platform.dart';
import '../../test/helpers/fake_scale.dart';
import '../support/smoke_support.dart';

/// Uses BOOKOO protocol notifications and an independent scale clock to retain
/// a brief peak, overwrite on Stop and keep the user's later correction.
Future<void> checkPressureChart(
  PatrolIntegrationTester $,
  AppDatabase database,
) async {
  final repository = JournalRepository(database);
  await repository.createCoffeeWithComponents(
    name: 'Patrol pressure',
    roaster: 'Fixture',
    components: const [],
    initialGrams: 100,
  );
  await repository.createMethod(name: 'Patrol lever', category: 'espresso');
  final directory = await Directory.systemTemp.createTemp('pressure-chart-');
  final platform = FakePressureBlePlatform();
  UniversalBle.setInstance(platform);
  final sensor = BlePressureSensor(
    PairedDeviceFile(File('${directory.path}/sensor.json')),
  );
  final scale = FakeScale(name: 'BOOKOO_SC_U', connected: true);
  void pressure(double bar) {
    final raw = (bar * 100).round();
    platform.updateCharacteristicValue(
      'BOOKOO-TEST',
      BookooPressureUuids.pressure,
      Uint8List.fromList([2, 27, 0, 0, raw >> 8, raw & 255, 85, 0, 0, 0]),
      null,
    );
  }

  try {
    await sensor.pair(
      const FoundDevice(id: 'BOOKOO-TEST', name: 'BOOKOO_EM-TEST'),
    );
    await $.pumpWidgetAndSettle(
      HolyBeansApp(
        services: AppServices(
          database: database,
          scale: scale,
          pressureSensor: sensor,
        ),
        initialLocale: const Locale('en'),
      ),
    );
    await $.tap(find.text('Brew'));
    await $.waitUntilVisible(find.byType(BrewForm));
    final form = verticalScrollable(find.byType(BrewForm));
    final method = find.byWidgetPredicate(
      (w) =>
          w is DropdownButtonFormField<String> &&
          w.decoration.labelText == 'Choose a method',
    );
    await $.scrollUntilVisible(finder: method, view: form);
    await $.tap(method);
    await $.tap(find.text('Patrol lever').last);
    final dose = find.widgetWithText(TextFormField, 'Dose (g)');
    await $.scrollUntilVisible(finder: dose, view: form);
    await $.enterText(dose, '16');
    final plus = find.byKey(const ValueKey('brew-ratio-increase'));
    await $.scrollUntilVisible(finder: plus, view: form);
    await $.tap(plus);
    expect(
      $.tester
          .widget<Text>(find.byKey(const ValueKey('brew-ratio-target')))
          .data,
      'Target beverage: 33.6 g',
    );
    await $.takeNativeScreenshot('espresso-ratio-target');
    final field = find.byKey(const ValueKey('brew-pressure'));
    await $.scrollUntilVisible(finder: field, view: form);
    await $.enterText(field, '9');
    final toggle = find.byKey(const ValueKey('chart-timer-toggle'));
    await $.scrollUntilVisible(finder: toggle, view: form);
    await $.tap(toggle);
    expect(
      find.byKey(const ValueKey('espresso-brew-progress')),
      findsOneWidget,
    );
    for (final grams in [0.0, 5.0, 15.0, 25.0, 38.0]) {
      scale.emit(grams, flow: grams == 0 ? 0 : 4);
      pressure(4.3);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (grams == 15) {
        pressure(7.2);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        pressure(4.7);
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    // A transient load at the end must not become yield or native flow.
    for (final (grams, flow) in [
      (252.0, 135.95),
      (206.0, 4.63),
      (38.9, -165.52),
      (-310.0, -100.0),
    ]) {
      scale.emit(grams, flow: flow);
      pressure(0);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    await $.pumpAndSettle();
    await $.scrollUntilVisible(
      finder: toggle,
      view: form,
      scrollDirection: AxisDirection.up,
    );
    await $.tap(toggle);
    pressure(12);
    await $.pumpAndSettle();
    expect(find.text('Target beverage: 33.6 g'), findsNWidgets(2));
    expect(find.text('Weight: 38.9 g'), findsOneWidget);
    final readout = find.byKey(const ValueKey('curve-readout'));
    expect(
      find.descendant(of: readout, matching: find.text('max 7.2 bar')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: readout, matching: find.text('Mean')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: readout, matching: find.text('Median')),
      findsOneWidget,
    );
    await $.scrollUntilVisible(finder: find.text('Median'), view: form);
    await $.takeNativeScreenshot('pressure-chart-stopped-summary');
    await $.scrollUntilVisible(
      finder: field,
      view: form,
      scrollDirection: AxisDirection.up,
    );
    expect($.tester.widget<TextFormField>(field).controller!.text, '7.2');
    await $.takeNativeScreenshot('pressure-chart-replaced-field');
    await $.enterText(field, '6.8');
    await $.tap(find.text('Save').last);
    await $.pumpAndSettle();
    final brew = await database.select(database.brews).getSingle();
    expect(brew.pressureBar, 6.8);
    expect(brew.beverageGrams, 38.9);
    final saved = (await repository.brewCurve(brew.id))!.curve;
    expect(saved.weight, isNot(contains(252)));
    expect(saved.weight, isNot(contains(206)));
    expect(saved.weight.last, 38.9);
    expect(saved.maxOf(CurveSeries.flow), lessThan(10));
    expect(saved.maxOf(CurveSeries.pressure), 7.2);
    expect(
      CurveFlowStats.fromCurve(
        saved,
        firstDripMs: brew.firstDripSeconds == null
            ? null
            : brew.firstDripSeconds! * 1000,
      ),
      isNotNull,
    );
    final nav = $.tester.getRect(find.byType(NavigationBar));
    await $.tester.tapAt(Offset(nav.left + nav.width * 2.5 / 4, nav.center.dy));
    await $.pumpAndSettle();
    await $.tap(find.text('Patrol pressure').first);
    final details = verticalScrollable(find.byType(BottomSheet));
    await $.scrollUntilVisible(finder: find.text('Median'), view: details);
    await $.takeNativeScreenshot('pressure-chart-detail-summary');
    final pressureControl = find.byKey(const ValueKey('curve-series-pressure'));
    await $.scrollUntilVisible(
      finder: pressureControl,
      view: details,
      scrollDirection: AxisDirection.up,
    );
    await $.tap(pressureControl);
    expect(find.byKey(const ValueKey('curve-pressure-value')), findsNothing);
    await $.tap(pressureControl);
    expect(find.byKey(const ValueKey('curve-pressure-value')), findsOneWidget);
    await $.tap(find.byKey(const ValueKey('curve-replay')));
    await $.pump(const Duration(milliseconds: 100));
    await $.pumpAndSettle();
    await $.takeNativeScreenshot('pressure-chart-detail-legend');
  } finally {
    await $.pumpWidgetAndSettle(const SizedBox.shrink());
    await sensor.disconnect();
    sensor.dispose();
    scale.dispose();
    await directory.delete(recursive: true);
  }
}

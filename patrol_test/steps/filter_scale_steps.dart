import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/scale.dart';
import 'package:holybeans/domain/filter_brew_progress.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:patrol/patrol.dart';

import '../../test/helpers/fake_scale.dart';
import '../support/smoke_support.dart';

/// Live filter controls and measured water, using synthetic scale readings.
Future<void> checkFilterScale(
  PatrolIntegrationTester $,
  AppDatabase database, {
  Scale? connectedScale,
  void Function(double, {double flow})? feedReading,
  String screenshotPrefix = 'filter-scale',
  Future<void> Function(Finder toggle)? verifyStoppedTimer,
}) async {
  final repository = JournalRepository(database);
  await repository.createCoffeeWithComponents(
    name: 'Patrol filter',
    roaster: 'Patrol',
    components: const [],
    initialGrams: 250,
  );
  await repository.createMethod(name: 'Patrol V60', category: 'pourover');
  final ownedScale = connectedScale == null
      ? (FakeScale(name: 'BOOKOO_SC_U', connected: true)..emit(18))
      : null;
  final scale = connectedScale ?? ownedScale!;
  final emit = feedReading ?? ownedScale!.emit;
  try {
    await $.pumpWidgetAndSettle(
      HolyBeansApp(
        services: AppServices(database: database, scale: scale),
        initialLocale: const Locale('en'),
      ),
    );
    await $.tap(find.text('Brew'));
    await $.waitUntilVisible(find.byType(BrewForm));
    final form = verticalScrollable(find.byType(BrewForm));
    final method = find.byWidgetPredicate(
      (widget) =>
          widget is DropdownButtonFormField<String> &&
          widget.decoration.labelText == 'Choose a method',
    );
    await $.scrollUntilVisible(finder: method, view: form);
    await $.tap(method);
    await $.tap(find.text('Patrol V60').last);
    final dose = find.widgetWithText(TextFormField, 'Dose (g)');
    await $.scrollUntilVisible(finder: dose, view: form);
    await $.enterText(dose, '18');
    final ratioPlus = find.byKey(const ValueKey('brew-ratio-increase'));
    await $.scrollUntilVisible(finder: ratioPlus, view: form);
    await $.tap(ratioPlus);
    await $.tap(find.byKey(const ValueKey('brew-ratio-decrease')));
    final water = find.widgetWithText(TextFormField, 'Water (g)');
    expect($.tester.widget<TextFormField>(water).controller!.text, '288');
    if (ownedScale != null) {
      for (final (label, count) in [('Blooms', '2'), ('Pours', '3')]) {
        final field = find.byWidgetPredicate(
          (w) =>
              w is DropdownButtonFormField<int> &&
              w.decoration.labelText == label,
        );
        await $.scrollUntilVisible(finder: field, view: form);
        await $.tap(field);
        await $.tap(find.text(count).last);
      }
      final plan = find.text('Water breakdown · 288 g');
      await $.scrollUntilVisible(finder: plan, view: form);
      await $.tap(plan);
      final bloomRatio = find.byKey(const ValueKey('water-plan-bloom-ratio'));
      await $.scrollUntilVisible(finder: bloomRatio, view: form);
      await $.tap(bloomRatio);
      await $.tap(find.text('1:3').last);
      await $.scrollUntilVisible(finder: find.text('288 g').last, view: form);
      await $.takeNativeScreenshot('filter-water-breakdown');
      expect(find.text('60 g'), findsNWidgets(3));
      await $.scrollUntilVisible(
        finder: plan,
        view: form,
        scrollDirection: AxisDirection.up,
      );
      await $.tap(plan);
    }
    final toggle = find.byKey(const ValueKey('chart-timer-toggle'));
    await $.scrollUntilVisible(
      finder: toggle,
      view: form,
      scrollDirection: ownedScale == null
          ? AxisDirection.down
          : AxisDirection.up,
    );
    await verifyStoppedTimer?.call(toggle);
    await $.tap(toggle);
    if (ownedScale != null) {
      ownedScale.emit(0, timerMs: 100);
      ownedScale.emit(0); // Physical reset during our own command window.
      await Future<void>.delayed(const Duration(milliseconds: 2300));
      ownedScale.emit(0);
      await $.pumpAndSettle();
      expect(
        find.descendant(of: toggle, matching: find.text('Start')),
        findsOneWidget,
      );
      await $.tap(toggle);
    }
    for (final grams in [0.0, 20.0, 55.0, 110.0, 165.0, 230.0, 281.0]) {
      emit(grams, flow: grams == 281 ? 0 : 5);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    if (connectedScale != null) {
      // Repeated whole-second values must not look like a stopped timer.
      await Future<void>.delayed(const Duration(milliseconds: 2300));
    }
    await $.pumpAndSettle();
    expect(
      find.descendant(of: toggle, matching: find.text('Stop')),
      findsOneWidget,
    );
    final progress = find.byKey(const ValueKey('filter-brew-progress'));
    await $.scrollUntilVisible(finder: find.text('281 g'), view: form);
    await $.takeNativeScreenshot('$screenshotPrefix-live-progress');
    expect(find.byKey(const ValueKey('scale-readout')), findsNothing);
    expect(find.byKey(const ValueKey('scale-tare')), findsNothing);
    expect(find.byKey(const ValueKey('curve-readout')), findsNothing);
    expect(
      find.descendant(of: progress, matching: find.text('281 g')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: progress, matching: find.text('1:15.6')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: progress, matching: find.text('1:16')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: progress, matching: find.text('7 g')),
      findsOneWidget,
    );
    final weightChip = find.byKey(const ValueKey('curve-series-weight'));
    final flowChip = find.byKey(const ValueKey('curve-series-flow'));
    expect(
      $.tester.getRect(flowChip).left - $.tester.getRect(weightChip).right,
      closeTo(6, 0.1),
    );
    expect($.tester.getRect(weightChip).top, $.tester.getRect(flowChip).top);
    expect($.tester.getRect(weightChip).top, $.tester.getRect(toggle).top);
    expect(
      $.tester.getSize(weightChip).height,
      $.tester.getSize(toggle).height,
    );
    await $.scrollUntilVisible(
      finder: toggle,
      view: form,
      scrollDirection: AxisDirection.up,
    );
    await $.tap(toggle);
    emit(-120);
    await $.pumpAndSettle();
    await verifyStoppedTimer?.call(toggle);
    await $.scrollUntilVisible(finder: find.text('281 g'), view: form);
    await $.takeNativeScreenshot('$screenshotPrefix-stopped-progress');
    await $.scrollUntilVisible(
      finder: water,
      view: form,
      scrollDirection: AxisDirection.up,
    );
    expect($.tester.widget<TextFormField>(water).controller!.text, '281');
    await $.takeNativeScreenshot('$screenshotPrefix-measured-water');
    await $.tap(find.text('Save').last);
    await $.pumpAndSettle();
    final brew = await database.select(database.brews).getSingle();
    expect(brew.waterGrams, 281);
    final saved = await repository.brewCurve(brew.id);
    expect(recordedWaterGrams(saved!.curve), 281);
    expect(
      (await database.select(database.coffeeLots).getSingle()).remainingGrams,
      232,
    );
  } finally {
    await $.pumpWidgetAndSettle(const SizedBox.shrink());
    ownedScale?.dispose();
  }
}

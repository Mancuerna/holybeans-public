import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/domain/brew_pours.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:holybeans/ui/brews/brew_form_model.dart';
import 'package:holybeans/ui/brews/brew_form_sections.dart';
import 'package:holybeans/ui/core/app_services.dart';

import 'helpers/fake_scale.dart';
import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

typedef _Brew = ({BrewFormModel model, FakeScale scale, Finder scrollable});

Future<_Brew> _openBrew(
  WidgetTester tester, {
  bool jug = false,
  bool adjust = false,
  bool espresso = false,
  bool hiddenWeight = false,
}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final db = memoryDatabase();
  final repository = JournalRepository(db);
  final settings = BrewParameterSettings(db);
  final coffee = await repository.createCoffee(name: 'Coffee', roaster: 'Test');
  final method = await repository.createMethod(
    name: espresso ? 'Espresso' : 'V60',
    category: espresso ? 'espresso' : 'pourover',
  );
  final recipient = jug
      ? await repository.saveRecipient(name: 'Glass jug', emptyGrams: 200)
      : null;
  if (hiddenWeight) await settings.saveHidden({BrewParameter.beverage});
  final coffees = await repository.allCoffees();
  final scale = FakeScale(name: 'BOOKOO', connected: true);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    scale.dispose();
    await db.close();
  });
  await tester.pumpWidget(
    localizedApp(
      locale: const Locale('en'),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => BrewForm(
                services: AppServices.forJournal(
                  repository,
                  parameterSettings: settings,
                  scale: scale,
                ),

                coffees: coffees,
                initialCoffeeId: coffee,
                initialMethodId: method,
                initialDoseGrams: 15,
                adjust: adjust,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  final model = tester
      .widget<BrewTimingSection>(find.byType(BrewTimingSection))
      .model;
  model.selectRecipient(recipient);
  model.draft.pours
    ..setCount(BrewPourKind.bloom, 0)
    ..setCount(BrewPourKind.pour, 1);
  await tester.pumpAndSettle();
  return (
    model: model,
    scale: scale,
    scrollable: find
        .descendant(
          of: find.byType(BrewForm),
          matching: find.byType(Scrollable),
        )
        .first,
  );
}

Future<void> _start(
  WidgetTester tester,
  _Brew brew, {
  bool curve = true,
}) async {
  final toggle = find.byKey(const ValueKey('chart-timer-toggle'));
  await tester.ensureVisible(toggle);
  await tester.pumpAndSettle();
  await tester.tap(toggle);
  await tester.pumpAndSettle();
  expect(brew.model.timer.running, isTrue);
  if (curve) {
    brew.model.scaleSession!.pourFinished(
      ShotCurve(
        timesMs: [for (var i = 0; i <= 60; i++) i * 500],
        weight: [for (var i = 0; i <= 60; i++) i <= 50 ? i * 5.0 : 250.0],
        flow: const [],
      ),
    );
  }
}

void main() {
  for (final (jug, adjust, scaleStop) in [
    (false, false, false),
    (true, false, true),
    (false, true, true),
  ]) {
    testWidgets('filter stop reveals final weight without opening details '
        '(jug=$jug, adjust=$adjust, scaleStop=$scaleStop)', (tester) async {
      final brew = await _openBrew(tester, jug: jug, adjust: adjust);
      await _start(tester, brew);
      final position = tester.state<ScrollableState>(brew.scrollable).position;
      final before = position.pixels;
      if (scaleStop) {
        brew.model.scaleSession!.requestStop!(30);
      } else {
        await tester.tap(find.byKey(const ValueKey('chart-timer-toggle')));
      }
      await tester.pumpAndSettle();

      expect(position.pixels, greaterThan(before));
      expect(brew.model.timer.running, isFalse);
      expect(brew.model.draft.pours.fromCurve, isTrue);
      expect(brew.model.draft.pours.value.phases, isNotEmpty);
      expect(brew.model.draft.pours.detailsExpanded, isFalse);
      expect(find.byKey(const ValueKey('scale-live-chart')), findsOneWidget);
      final fill = find.byKey(
        ValueKey(jug ? 'scale-to-jug-total' : 'scale-to-beverage'),
      );
      final viewport = tester.getRect(brew.scrollable);
      final button = tester.getRect(fill);
      expect(button.top, greaterThanOrEqualTo(viewport.top));
      expect(button.bottom, lessThanOrEqualTo(viewport.bottom));
      expect(fill.hitTestable(), findsOneWidget);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(brew.model.draft.beverage.text, isEmpty);

      brew.scale.emit(jug ? 430 : 230);
      await tester.pump();
      await tester.tap(fill);
      await tester.pumpAndSettle();
      expect(brew.model.draft.beverage.text, '230');

      // Later readings and edits must not keep pulling the user down.
      position.jumpTo(0);
      await tester.pumpAndSettle();
      brew.scale.emit(231);
      brew.model.draft.durationSeconds.text = '31';
      await tester.pumpAndSettle();
      expect(position.pixels, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  for (final scenario in [
    'espresso',
    'hidden weight',
    'reset',
    'no curve',
    'covered',
  ]) {
    testWidgets('does not scroll on $scenario', (tester) async {
      final brew = await _openBrew(
        tester,
        espresso: scenario == 'espresso',
        hiddenWeight: scenario == 'hidden weight',
      );
      await _start(tester, brew, curve: scenario != 'no curve');
      final position = tester.state<ScrollableState>(brew.scrollable).position;
      if (scenario == 'covered') {
        Navigator.of(tester.element(find.byType(BrewForm))).push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('Other screen')),
          ),
        );
        await tester.pumpAndSettle();
      }
      final before = position.pixels;
      if (scenario == 'reset') {
        brew.model.timer.reset();
      } else {
        brew.model.scaleSession!.requestStop!(30);
      }
      await tester.pumpAndSettle();
      expect(position.pixels, closeTo(before, 0.1));
      expect(tester.testTextInput.isVisible, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}

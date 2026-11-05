import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/brew_pours.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/brews/brew_details_sheet.dart';

import 'helpers/ui_test_support.dart';

/// Labels of the detail tiles, in reading order.
List<String> tileLabels(WidgetTester tester, List<String> labels) {
  final found = [
    for (final label in labels)
      if (find.text(label).evaluate().isNotEmpty) label,
  ];
  Offset at(String label) => tester.getTopLeft(find.text(label).first);
  return found..sort((a, b) {
    final dy = at(a).dy.compareTo(at(b).dy);
    return dy != 0 ? dy : at(a).dx.compareTo(at(b).dx);
  });
}

void main() {
  const labels = [
    'Dose',
    'Grind setting',
    'Water',
    'Beverage weight',
    'Ratio',
    'Temperature',
    'Time',
    'Pre-infusion',
    'First drip',
    'Peak pressure',
    'Blooms',
    'Bloom time',
    'Pours',
    'TDS',
    'EY',
    'Rating',
  ];

  Future<void> openBrew(WidgetTester tester, AppDatabase database) async {
    await tester.pumpWidget(
      HolyBeansApp(database: database, initialLocale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    await tapBottomDestination(tester, 2);
    await tester.tap(find.text('Ordered coffee').first);
    await tester.pumpAndSettle();
  }

  for (final category in ['filter', 'espresso']) {
    testWidgets(
      '$category saved curve chooses statistics by method, not pressure',
      (tester) async {
        final database = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(database.close);
        final repository = JournalRepository(database);
        final coffee = await repository.createCoffee(
          name: 'Ordered coffee',
          roaster: 'R',
        );
        final method = await repository.createMethod(
          name: 'Custom method',
          category: category,
        );
        final water = await repository.createWaterProfile(name: 'Detail water');
        final brew = await repository.createBrew(
          coffeeId: coffee,
          methodId: method,
          methodName: 'Custom method',
          doseGrams: 18,
          grinderName: 'Detail grinder',
          waterProfileId: water,
          notes: 'Detail notes',
        );
        await repository.saveScaleCurve(
          brew,
          ShotCurve(
            timesMs: const [0, 1000, 2000, 3000],
            flow: const [0, 2, 1, 0],
            weight: const [0, 1, 2, 3],
          ),
        );
        await openBrew(tester, database);
        final curveHeading = find.text('Extraction curve');
        for (final value in [
          'Detail grinder',
          'Detail water',
          'Detail notes',
        ]) {
          expect(
            tester
                .getBottomLeft(
                  find.descendant(
                    of: find.byType(BrewDetailsSheet),
                    matching: find.text(value),
                  ),
                )
                .dy,
            lessThan(tester.getTopLeft(curveHeading).dy),
          );
        }
        await tester.ensureVisible(find.byKey(const ValueKey('curve-readout')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('curve-flow-value')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('curve-flow-mean')),
          category == 'espresso' ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const ValueKey('curve-flow-median')),
          category == 'espresso' ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 10));
      },
    );
  }

  testWidgets('filter details read recipe, timing, pours, then results', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = JournalRepository(database);
    final coffee = await repository.createCoffee(
      name: 'Ordered coffee',
      roaster: 'R',
    );
    final method = await repository.createMethod(
      name: 'V60',
      category: 'filter',
    );
    await repository.createBrew(
      coffeeId: coffee,
      methodName: 'V60',
      methodId: method,
      doseGrams: 15,
      grindSetting: '22',
      waterGrams: 250,
      beverageGrams: 210,
      timeSeconds: 180,
      temperatureC: 93,
      bloomSeconds: 30,
      pours: BrewPours(bloomCount: 2, pourCount: 3),
      tdsPercent: 1.35,
      rating: 8,
    );
    await openBrew(tester, database);
    expect(tileLabels(tester, labels), [
      'Dose',
      'Grind setting',
      'Water',
      'Beverage weight',
      'Ratio',
      'Temperature',
      'Time',
      'Blooms',
      'Bloom time',
      'Pours',
      'TDS',
      'EY',
      'Rating',
    ]);
    expect(
      tester.getTopLeft(find.text('Beverage weight')).dy,
      greaterThan(tester.getBottomLeft(find.text('Grind setting').first).dy),
    );
    // The old ambiguous "Bloom" label is gone from the tiles.
    expect(find.text('Bloom'), findsNothing);
    // The grind setting is a figure, not repeated beside the grinder.
    await tester.drag(find.text('Ratio'), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('Grind setting', skipOffstage: false), findsOneWidget);
    expect(
      find.byKey(const ValueKey('open-sensory-map-button')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('espresso details keep the three shot times together', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = JournalRepository(database);
    final coffee = await repository.createCoffee(
      name: 'Ordered coffee',
      roaster: 'R',
    );
    final method = await repository.createMethod(
      name: 'Linea',
      category: 'espresso',
    );
    await repository.createBrew(
      coffeeId: coffee,
      methodName: 'Linea',
      methodId: method,
      doseGrams: 17,
      beverageGrams: 42,
      timeSeconds: 34,
      preinfusionSeconds: 8,
      firstDripSeconds: 4,
      temperatureC: 90,
      pressureBar: 7.1,
      tdsPercent: 8.66,
    );
    await openBrew(tester, database);
    // The sensory map is for filter coffee only.
    expect(find.byKey(const ValueKey('open-sensory-map-button')), findsNothing);
    expect(
      find.byKey(const ValueKey('open-espresso-map-button')),
      findsOneWidget,
    );
    expect(tileLabels(tester, labels), [
      'Dose',
      'Beverage weight',
      'Ratio',
      'Time',
      'Pre-infusion',
      'First drip',
      'Temperature',
      'Peak pressure',
      'TDS',
      'EY',
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}

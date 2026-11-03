import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/brew_pours.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/main.dart';
import 'package:patrol/patrol.dart';

/// Two blooms of 50 g with 25 s rests and two pours of 90 g, then a swirl
/// that settles back, sampled every 100 ms like a scale.
ShotCurve _filterCurve() {
  final times = <int>[];
  final weight = <double>[];
  var grams = 0.0;
  void add(int tenths, double Function(int i) at) {
    for (var i = 1; i <= tenths; i++) {
      times.add(times.isEmpty ? 0 : times.last + 100);
      weight.add(at(i));
    }
  }

  void wait(int seconds) => add(seconds * 10, (_) => grams);
  void pour(int seconds, double water) {
    final from = grams;
    add(seconds * 10, (i) => from + water * i / (seconds * 10));
    grams += water;
  }

  wait(2);
  pour(6, 50);
  wait(25);
  pour(6, 50);
  wait(25);
  pour(10, 90);
  wait(20);
  pour(8, 90);
  add(30, (i) => grams + (i.isEven ? 60 : -60) * (1 - i / 30));
  wait(20);
  return ShotCurve(timesMs: times, flow: const [], weight: weight);
}

/// A saved filter brew with a curve offers its blooms and pours in its
/// details; Settings fills the rest at once.
Future<void> checkPoursFromCurves(
  PatrolIntegrationTester $,
  AppDatabase database,
) async {
  final repository = JournalRepository(database);
  final coffee = await repository.createCoffee(
    name: 'Curve bean',
    roaster: 'Test',
  );
  final method = await repository.createMethod(
    name: 'Curve V60',
    category: 'pourover',
  );
  final brews = <String>[];
  for (var i = 0; i < 3; i++) {
    final id = await repository.createBrew(
      coffeeId: coffee,
      methodId: method,
      methodName: 'Curve V60',
      doseGrams: 16,
      pours: i == 0 ? null : BrewPours(pourCount: i == 1 ? 3 : 4),
      brewedAt: DateTime.now().subtract(Duration(hours: i + 1)),
    );
    await repository.saveScaleCurve(id, _filterCurve());
    brews.add(id);
  }
  await $.pumpWidgetAndSettle(
    HolyBeansApp(database: database, initialLocale: const Locale('en')),
  );
  await $.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Brews'),
    ),
  );
  final card = find.byKey(ValueKey('brew-card-${brews.first}'));
  await $.scrollUntilVisible(finder: card);
  await $.tap(card);
  await $.waitUntilVisible(find.text('The curve shows 2 blooms and 2 pours.'));
  await $.takeNativeScreenshot('pours-from-curve-details');
  await $.tap(find.byKey(const ValueKey('brew-detail-pours-save')));
  final offer = find.byKey(const ValueKey('brew-detail-pours-from-curve'));
  for (var i = 0; i < 50 && offer.evaluate().isNotEmpty; i++) {
    await $.pump(const Duration(milliseconds: 100));
  }
  expect(offer, findsNothing);
  final saved = (await repository.brew(brews.first))!;
  expect((saved.bloomCount, saved.pourCount), (2, 2));
  await $.platform.android.pressBack();
  await $.pumpAndSettle();

  await $.tap(find.byTooltip('Settings'));
  await $.scrollUntilVisible(
    finder: find.byKey(const ValueKey('pours-from-curves')),
  );
  await $.tap(find.byKey(const ValueKey('pours-from-curves')));
  await $.waitUntilVisible(find.textContaining('of 2 brews will be filled'));
  await $.takeNativeScreenshot('pours-from-curves-confirm');
  await $.tap(find.byKey(const ValueKey('pours-from-curves-fill')));
  await $.waitUntilVisible(find.text('2 brews filled'));
  for (final (i, id) in brews.indexed) {
    final brew = (await repository.brew(id))!;
    expect((brew.bloomCount, brew.pourCount), (2 - i, 2 + i));
    expect(
      BrewPours.fromStorage(
        bloomCount: brew.bloomCount,
        pourCount: brew.pourCount,
        phasesJson: brew.pourPhasesJson,
      ).phases.map((phase) => phase.waterGrams),
      [50, 50, 90, 90],
    );
  }
}

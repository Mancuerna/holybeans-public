import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/brew_stats.dart';
import 'package:holybeans/domain/freshness.dart';
import 'package:holybeans/domain/stats_insights.dart';
import 'package:holybeans/ui/core/detail_widgets.dart';
import 'package:holybeans/ui/stats/stats_brews_tab.dart';
import 'package:holybeans/ui/stats/stats_costs_tab.dart';
import 'package:holybeans/ui/stats/stats_data.dart';
import 'package:holybeans/ui/stats/stats_view_model.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

class _Reads<T> extends ListBase<T> {
  _Reads(this.source);
  final List<T> source;
  int reads = 0;
  @override
  int get length => source.length;
  @override
  set length(int value) => throw UnsupportedError('immutable');
  @override
  T operator [](int index) {
    reads++;
    return source[index];
  }

  @override
  void operator []=(int index, T value) => throw UnsupportedError('immutable');
}

class _Data extends StatsData {
  _Data(StatsData source)
    : super(
        stats: source.stats,
        range: source.range,
        now: source.now,
        allBrews: source.allBrews,
        coffees: source.coffees,
        lots: source.lots,
        pricePerKg: source.pricePerKg,
        styleOf: source.styleOf,
        remainingGrams: source.remainingGrams,
        frozenGrams: source.frozenGrams,
        previous: source.previous,
      );
  late final countedPurchases = _Reads<Purchase>(super.bought);
  late final countedValues = _Reads<CoffeeValue>(super.values);
  int styleCalls = 0;
  @override
  List<Purchase> get bought => countedPurchases;
  @override
  List<CoffeeValue> get values => countedValues;
  @override
  BrewStyle Function(Brew) get styleOf => _style;
  BrewStyle _style(Brew brew) {
    styleCalls++;
    return super.styleOf(brew);
  }
}

void main() {
  testWidgets('statistics tabs reuse snapshot aggregates across rebuilds', (
    tester,
  ) async {
    final db = memoryDatabase();
    final repository = JournalRepository(db);
    final method = await repository.createMethod(
      name: 'Fixture',
      category: 'espresso',
    );
    for (var i = 0; i < 3; i++) {
      final coffee = await repository.createCoffee(
        name: 'Fixture $i',
        roaster: 'Test $i',
        initialGrams: 250,
        paidPriceCents: 1500 + i * 500,
      );
      final lot = (await repository.coffeeLots(coffee)).single.id;
      for (var j = 0; j < 3; j++) {
        await repository.createBrew(
          coffeeId: coffee,
          lotId: lot,
          methodId: method,
          methodName: 'Fixture',
          doseGrams: 18,
          beverageGrams: 36,
          timeSeconds: 20 + j * 10,
          rating: 8,
          brewedAt: DateTime(2026, 3, 10 + j),
        );
      }
    }
    final coffees = await db.select(db.coffees).get();
    final lots = await db.select(db.coffeeLots).get();
    final data = _Data(
      prepareStats((
        brews: await db.select(db.brews).get(),
        coffees: coffees,
        components: const [],
        methods: await db.select(db.brewMethods).get(),
        lots: lots,
        prices: pricePerKgByCoffee(coffees, lots),
        range: StatsRange.all,
        now: DateTime(2026, 3, 20),
        language: 'en',
        remaining: 0,
        frozen: 0,
      )),
    );
    final refresh = ValueNotifier(0);
    addTearDown(() async {
      refresh.dispose();
      await db.close();
    });
    await tester.pumpWidget(
      localizedApp(
        locale: const Locale('en'),
        home: Scaffold(
          body: ValueListenableBuilder(
            valueListenable: refresh,
            builder: (_, _, _) => Row(
              children: [
                Expanded(child: StatsBrewsTab(data: data)),
                Expanded(child: StatsCostsTab(data: data)),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    List<String> summary() => tester
        .widget<StatGrid>(find.byKey(const ValueKey('stats-costs-overview')))
        .items
        .map((item) => item.value)
        .toList();
    final initial = summary();
    data.styleCalls = data.countedPurchases.reads = data.countedValues.reads =
        0;
    for (var i = 0; i < 100; i++) {
      refresh.value++;
      await tester.pump();
    }
    final counts = {
      'styleCalls': data.styleCalls,
      'purchases': data.countedPurchases.reads,
      'values': data.countedValues.reads,
    };
    stdout.writeln('STATS_AGGREGATION_READS ${jsonEncode(counts)}');
    expect(summary(), initial);
    expect(counts, {'styleCalls': 0, 'purchases': 0, 'values': 0});
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

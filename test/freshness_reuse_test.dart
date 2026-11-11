import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_data.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/coffee_freshness.dart';
import 'package:holybeans/ui/beans/freshness_widgets.dart';
import 'package:holybeans/ui/beans/live_freshness_section.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  for (final count in [0, 201]) {
    testWidgets('unchanged lots reuse freshness with $count brews', (
      tester,
    ) async {
      final db = memoryDatabase();
      final repository = JournalRepository(db);
      final today = DateTime.now();
      String daysAgo(int days) => DateTime(
        today.year,
        today.month,
        today.day - days,
      ).toIso8601String().substring(0, 10);
      final id = await repository.createCoffee(
        name: 'Fixture',
        roaster: 'Test',
        roastDate: daysAgo(10),
        initialGrams: 250,
      );
      await repository.createBrew(
        coffeeId: id,
        lotId: (await repository.coffeeLots(id)).single.id,
        methodName: 'V60',
        doseGrams: 18,
        rating: 8,
      );
      final brew = (await db.select(db.brews).get()).single;
      var data = JournalData(
        coffees: await db.select(db.coffees).get(),
        brews: [for (var i = 0; i < count; i++) brew.copyWith(id: 'b$i')],
        lots: await db.select(db.coffeeLots).get(),
        components: const [],
      );
      var lots = data.lots;
      int? frozenAge;
      final refresh = ValueNotifier(0);
      addTearDown(() async {
        refresh.dispose();
        await db.close();
      });
      await tester.pumpWidget(
        localizedApp(
          locale: const Locale('en'),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ValueListenableBuilder(
                valueListenable: refresh,
                builder: (_, _, _) => LiveFreshnessSection(
                  data: data,
                  coffee: data.coffees.single,
                  lots: [...lots],
                  allLots: data.lots,
                  methods: const [],
                  frozenAge: frozenAge,
                ),
              ),
            ),
          ),
        ),
      );
      await settleWithWorkers(tester);
      CoffeeFreshness value() => tester
          .widget<FreshnessSection>(find.byType(FreshnessSection))
          .freshness;
      Object calculation() => count <= 200
          ? value()
          : tester
                .widget<FutureBuilder<CoffeeFreshness?>>(
                  find.byType(FutureBuilder<CoffeeFreshness?>),
                )
                .future!;
      var previous = calculation();
      var calculations = 0;
      for (var i = 0; i < 100; i++) {
        refresh.value++;
        await tester.pump();
        final current = calculation();
        if (!identical(previous, current)) calculations++;
        previous = current;
        await settleWithWorkers(tester);
      }
      stdout.writeln('FRESHNESS_CALCULATIONS brews=$count new=$calculations');
      expect(calculations, 0);
      expect(value().day, 10);
      lots = [lots.single.copyWith(roastDate: Value(daysAgo(7)))];
      refresh.value++;
      await settleWithWorkers(tester);
      expect(value().day, 7);
      frozenAge = 20;
      refresh.value++;
      await settleWithWorkers(tester);
      expect(value().day, 20);
      data = JournalData(
        coffees: data.coffees,
        brews: [
          ...data.brews,
          brew.copyWith(id: 'new'),
        ],
        lots: data.lots,
        components: data.components,
      );
      refresh.value++;
      await settleWithWorkers(tester);
      expect(value().ratedDays, hasLength(count + 1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

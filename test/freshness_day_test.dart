import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_data.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/ui/beans/freshness_widgets.dart';
import 'package:holybeans/ui/beans/live_freshness_section.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  testWidgets('freshness reuses the same day and refreshes on the next day', (
    tester,
  ) async {
    final db = memoryDatabase();
    await JournalRepository(
      db,
    ).createCoffee(name: 'Fixture', roaster: 'Test', roastDate: '2026-03-01');
    final data = JournalData(
      coffees: await db.select(db.coffees).get(),
      brews: const [],
      lots: await db.select(db.coffeeLots).get(),
      components: const [],
    );
    final now = ValueNotifier(DateTime(2026, 3, 10));
    addTearDown(() async {
      now.dispose();
      await db.close();
    });
    await tester.pumpWidget(
      localizedApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ValueListenableBuilder(
              valueListenable: now,
              builder: (_, date, _) => LiveFreshnessSection(
                data: data,
                coffee: data.coffees.single,
                lots: [...data.lots],
                allLots: data.lots,
                methods: const [],
                frozenAge: null,
                now: date,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    FreshnessSection section() => tester.widget(find.byType(FreshnessSection));
    final first = section().freshness;
    expect(first.day, 9);
    now.value = DateTime(2026, 3, 10, 23, 59);
    await tester.pump();
    expect(section().freshness, same(first));
    now.value = DateTime(2026, 3, 11);
    await tester.pump();
    expect(section().freshness.day, 10);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

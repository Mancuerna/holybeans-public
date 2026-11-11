import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/list_options.dart';
import 'package:holybeans/ui/beans/bean_card.dart';
import 'package:holybeans/ui/beans/beans_tab.dart';
import 'package:holybeans/ui/core/journal_search_toolbar.dart';
import 'package:holybeans/ui/shell/journal_actions.dart';

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

class _Data extends JournalData {
  _Data(List<Coffee> coffees, this.countedLots, this.countedComponents)
    : super(
        coffees: coffees,
        brews: const [],
        lots: countedLots,
        components: countedComponents,
      );
  final _Reads<CoffeeLot> countedLots;
  final _Reads<CoffeeComponent> countedComponents;
  @override
  List<CoffeeLot> get lots => countedLots;
  @override
  List<CoffeeComponent> get components => countedComponents;
}

class _Actions extends Fake implements JournalActions {
  @override
  List<FrozenPortion> portions = const [];
}

void main() {
  testWidgets(
    'search reuses aggregates and follows journal and freezer inputs',
    (tester) async {
      final db = memoryDatabase();
      final repository = JournalRepository(db);
      for (var i = 0; i < 3; i++) {
        await repository.createCoffeeWithComponents(
          name: 'Fixture $i',
          roaster: 'Test',
          initialGrams: 250,
          components: [
            CoffeeComponentInput(country: i == 0 ? 'México' : 'Brazil'),
          ],
        );
      }
      Future<_Data> snapshot() async => _Data(
        await db.select(db.coffees).get(),
        _Reads(await db.select(db.coffeeLots).get()),
        _Reads(await db.select(db.coffeeComponents).get()),
      );
      var data = await snapshot();
      final actions = _Actions();
      final tabs = TabController(length: 3, vsync: const TestVSync());
      final refresh = ValueNotifier(0);
      addTearDown(() async {
        refresh.dispose();
        tabs.dispose();
        await db.close();
      });
      await tester.pumpWidget(
        localizedApp(
          locale: const Locale('en'),
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: refresh,
              builder: (_, _, _) => BeansTab(
                data: data,
                actions: actions,
                tabs: tabs,
                options: const ListOptions(beansCompact: true),
                onOpenCalendar: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final search = tester
          .widget<JournalSearchToolbar>(find.byType(JournalSearchToolbar))
          .controller;
      search.text = 'missing';
      await tester.pumpAndSettle();
      data.countedLots.reads = data.countedComponents.reads = 0;
      for (var i = 0; i < 100; i++) {
        search.text = 'missing$i';
        await tester.pump();
      }
      final counts = {
        'lots': data.countedLots.reads,
        'components': data.countedComponents.reads,
      };
      stdout.writeln('BEAN_SEARCH_READS ${jsonEncode(counts)}');
      expect(counts, {'lots': 0, 'components': 0});
      List<String> names() => tester
          .widgetList<BeanCard>(find.byType(BeanCard))
          .map((card) => card.coffee.name)
          .toList();
      search.text = 'mexico';
      await tester.pumpAndSettle();
      expect(names(), ['Fixture 0']);
      final lot = data.lots.singleWhere(
        (lot) => lot.coffeeId == data.coffees.first.id,
      );
      await repository.freezeCoffee(
        lotId: lot.id,
        grams: 50,
        frozenDate: '2026-03-01',
      );
      actions.portions = await db.select(db.frozenPortions).get();
      refresh.value++;
      await tester.pumpAndSettle();
      tabs.index = 1;
      await tester.pumpAndSettle();
      expect(names(), ['Fixture 0']);
      expect(find.text('Frozen (1)'), findsOneWidget);
      await repository.createCoffee(
        name: 'New fixture',
        roaster: 'New roaster',
      );
      data = await snapshot();
      refresh.value++;
      tabs.index = 0;
      search.text = 'new roaster';
      await tester.pumpAndSettle();
      expect(names(), ['New fixture']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

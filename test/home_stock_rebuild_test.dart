import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/freezer_repository.dart';
import 'package:holybeans/data/repositories/journal_mutations.dart';
import 'package:holybeans/data/repositories/journal_queries.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/repositories/stock_adjustment_repository.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/domain/freshness.dart';
import 'package:holybeans/ui/backup/backup_center.dart';
import 'package:holybeans/ui/core/detail_widgets.dart';
import 'package:holybeans/ui/home/home_tab.dart';
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
  _Data(this.counted, List<Brew> brews, List<CoffeeLot> lots)
    : super(coffees: counted, brews: brews, lots: lots, components: const []);
  final _Reads<Coffee> counted;
  @override
  List<Coffee> get coffees => counted;
}

class _Actions extends Fake
    implements JournalRead, JournalNavigation, JournalCommands {
  _Actions(this.repository, this.backupCenter);
  JournalActions get actions =>
      JournalActions(read: this, navigation: this, commands: this);

  final JournalRepository repository;
  @override
  late final queries = JournalQueries(repository);
  @override
  late final mutations = JournalMutations(repository);
  @override
  StockAdjustmentRepository get stockEdits => repository.stockEdits;
  @override
  FreezerRepository get freezer => repository.freezer;
  @override
  final BackupCenter backupCenter;
  @override
  List<FrozenPortion> portions = const [];
  @override
  List<BrewMethod> get methods => const [];
  @override
  Set<BrewParameter> get hiddenParameters => const {};
  @override
  PhotoStore? get photos => null;
  @override
  FreshnessToday? freshnessToday(Coffee coffee, {BrewStyle? style}) => null;
}

void main() {
  testWidgets(
    'home reuses stock work and invalidates journal and freezer inputs',
    (tester) async {
      final db = memoryDatabase();
      final repository = JournalRepository(db);
      var now = DateTime(2026, 3);
      for (var i = 0; i < 3; i++) {
        final id = await repository.createCoffee(
          name: 'Fixture $i',
          roaster: 'Test',
          initialGrams: 50,
        );
        await repository.createBrew(
          coffeeId: id,
          lotId: (await repository.coffeeLots(id)).single.id,
          methodName: 'V60',
          doseGrams: 18,
          brewedAt: now,
        );
      }
      Future<_Data> snapshot() async => _Data(
        _Reads(await db.select(db.coffees).get()),
        await db.select(db.brews).get(),
        await db.select(db.coffeeLots).get(),
      );
      var data = await snapshot();
      final center = BackupCenter(database: db, photos: null);
      final actions = _Actions(repository, center);
      final refresh = ValueNotifier(0);
      addTearDown(() async {
        refresh.dispose();
        center.dispose();
        await db.close();
      });
      await tester.pumpWidget(
        localizedApp(
          locale: const Locale('en'),
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: refresh,
              builder: (_, _, _) =>
                  HomeTab(data: data, actions: actions.actions, now: now),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      data.counted.reads = 0;
      for (var i = 0; i < 100; i++) {
        refresh.value++;
        await tester.pump();
      }
      stdout.writeln('HOME_COFFEE_READS ${data.counted.reads}');
      expect(data.counted.reads, 0);
      StatGrid summary() =>
          tester.widget(find.byKey(const ValueKey('home-summary')));
      expect(summary().items.first.value, '96 g');
      await repository.freezeCoffee(
        lotId: data.lots.first.id,
        grams: 10,
        frozenDate: '2026-03-01',
      );
      actions.portions = await db.select(db.frozenPortions).get();
      refresh.value++;
      await tester.pump();
      expect(data.counted.reads, greaterThan(0));
      expect(summary().items.singleWhere((item) => item.frozen).value, '10 g');
      data = await snapshot();
      data.counted.reads = 0;
      refresh.value++;
      await tester.pump();
      expect(data.counted.reads, greaterThan(0));
      expect(summary().items.first.value, '86 g');
      data.counted.reads = 0;
      now = now.add(const Duration(days: 8));
      refresh.value++;
      await tester.pump();
      expect(
        summary().items
            .singleWhere(
              (item) => item.key == const ValueKey('home-week-brews'),
            )
            .value,
        '0 brews',
      );
      expect(data.counted.reads, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

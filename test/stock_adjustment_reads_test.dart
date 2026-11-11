import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/preferences/list_options_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/repositories/stock.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/ui/beans/coffee_details_sheet.dart';
import 'package:holybeans/ui/beans/stock_adjustment_section.dart';
import 'package:holybeans/ui/shell/journal_actions.dart';
import 'package:holybeans/ui/shell/journal_view_model.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'helpers/ui_test_support.dart';

class _Reads extends QueryInterceptor {
  int rows = 0;
  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await executor.runSelect(statement, args);
    if (statement.contains('FROM "stock_adjustments"')) rows += result.length;
    return result;
  }
}

class _Actions extends Fake implements JournalActions {
  _Actions(this.repository);
  @override
  final JournalRepository repository;
  @override
  PhotoStore? get photos => null;
  @override
  List<FrozenPortion> get portions => const [];
  @override
  List<BrewMethod> get methods => const [];
}

StockAdjustment _adjustment(
  String id,
  String coffee,
  String lot, {
  bool reversed = false,
}) => StockAdjustment(
  id: id,
  operationId: id,
  coffeeId: coffee,
  lotId: lot,
  reason: 'gift',
  previousGrams: 100,
  resultingGrams: 95,
  createdAtMs: 1,
  reversedAtMs: reversed ? 2 : null,
);

Future<
  ({AppDatabase db, JournalRepository repo, _Reads reads, JournalData data})
>
_fixture() async {
  final reads = _Reads();
  final db = AppDatabase.forTesting(
    NativeDatabase.memory().interceptWith(reads),
  );
  final repo = JournalRepository(db);
  await db.batch((batch) {
    batch.insertAll(db.coffees, [
      for (final id in ['target', 'other', 'archived'])
        CoffeesCompanion.insert(
          id: id,
          name: id,
          roaster: 'Test',
          createdAtMs: 1,
          updatedAtMs: 1,
          archivedAtMs: Value(id == 'archived' ? 2 : null),
        ),
    ]);
    batch.insertAll(db.coffeeLots, [
      for (final (id, coffee) in [
        ('active', 'target'),
        ('old', 'target'),
        ('other', 'other'),
        ('archived-owner', 'archived'),
      ])
        CoffeeLotsCompanion.insert(
          id: id,
          coffeeId: coffee,
          initialGrams: const Value(100),
          remainingGrams: const Value(70),
          createdAtMs: 1,
          updatedAtMs: 1,
          archivedAtMs: Value(id == 'old' ? 2 : null),
        ),
    ]);
    batch.insertAll(db.stockAdjustments, [
      _adjustment('active-0', 'target', 'active'),
      _adjustment('active-1', 'target', 'active'),
      _adjustment('reversed', 'target', 'active', reversed: true),
      for (var i = 0; i < 50; i++) _adjustment('old-$i', 'target', 'old'),
      for (var i = 0; i < 100; i++)
        _adjustment('other-$i', 'other', 'other', reversed: true),
      _adjustment('archived-owner', 'archived', 'archived-owner'),
    ]);
  });
  final data = JournalData(
    coffees: await repo.allCoffees(),
    brews: const [],
    lots: await db.select(db.coffeeLots).get(),
    components: const [],
  );
  reads.rows = 0;
  return (db: db, repo: repo, reads: reads, data: data);
}

void main() {
  setUpAll(initializeDateFormatting);
  test('shell reads only adjustments that affect active inventory', () async {
    final fixture = await _fixture();
    addTearDown(fixture.db.close);
    final model = JournalViewModel(
      repository: fixture.repo,
      parameterSettings: BrewParameterSettings(fixture.db),
      listOptionsSettings: ListOptionsSettings(fixture.db),
    );
    addTearDown(model.dispose);
    for (var i = 0; i < 50 && model.loading; i++) {
      await pumpEventQueue();
    }
    expect(model.loading, false);
    final rows = fixture.reads.rows;
    stdout.writeln('SHELL_ADJUSTMENT_ROWS $rows');
    final stock = CoffeeStock(
      lots: model.data.activeLotsOf('target'),
      portions: const [],
      adjustments: model.data.adjustments,
    );
    expect(stock.consumedGrams, 20);
    expect(model.data.adjustments.map((r) => r.id).toSet(), {
      'active-0',
      'active-1',
      'archived-owner',
    });
    expect(rows, 3);
  });

  test(
    'active stream follows lot changes and preserves unknown adjustments',
    () async {
      final fixture = await _fixture();
      addTearDown(fixture.db.close);
      final db = fixture.db;
      final stream = StreamIterator(
        fixture.repo.watchStockAdjustments(activeOnly: true),
      );
      addTearDown(stream.cancel);
      expect(await stream.moveNext(), true);
      expect(stream.current.map((r) => r.id).toSet(), {
        'active-0',
        'active-1',
        'archived-owner',
      });
      await (db.update(db.coffeeLots)..where((r) => r.id.equals('active')))
          .write(const CoffeeLotsCompanion(archivedAtMs: Value(3)));
      expect(await stream.moveNext(), true);
      expect(stream.current.map((r) => r.id), ['archived-owner']);
      await (db.update(db.coffeeLots)..where((r) => r.id.equals('old'))).write(
        const CoffeeLotsCompanion(archivedAtMs: Value(null)),
      );
      expect(await stream.moveNext(), true);
      expect(stream.current, hasLength(51));
      await (db.update(db.stockAdjustments)
            ..where((r) => r.id.equals('archived-owner')))
          .write(const StockAdjustmentsCompanion(reversedAtMs: Value(4)));
      expect(await stream.moveNext(), true);
      expect(stream.current, hasLength(50));
      await (db.update(db.stockAdjustments)..where((r) => r.id.equals('old-0')))
          .write(const StockAdjustmentsCompanion(previousGrams: Value(null)));
      expect(await stream.moveNext(), true);
      final lots = await fixture.repo.coffeeLots('target');
      expect(
        stream.current.singleWhere((r) => r.id == 'old-0').previousGrams,
        null,
      );
      expect(
        CoffeeStock(
          lots: lots,
          portions: const [],
          adjustments: stream.current,
        ).consumedGrams,
        null,
      );
      // The unscoped API still exposes complete history in stable order.
      final all = await fixture.repo.watchStockAdjustments().first;
      expect(all, hasLength(154));
      expect(all.map((r) => r.id), [...all.map((r) => r.id)]..sort());
    },
  );

  testWidgets(
    'coffee detail keeps complete own history without unrelated rows',
    (tester) async {
      final fixture = (await tester.runAsync(_fixture))!;
      addTearDown(fixture.db.close);
      await tester.pumpWidget(
        localizedApp(
          home: Scaffold(
            body: CoffeeDetailsSheet(
              actions: _Actions(fixture.repo),
              coffee: fixture.data.coffees.singleWhere((c) => c.id == 'target'),
              data: fixture.data,
            ),
          ),
        ),
      );
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();
      final section = tester.widget<StockAdjustmentSection>(
        find.byType(StockAdjustmentSection),
      );
      stdout.writeln('DETAIL_ADJUSTMENT_ROWS ${fixture.reads.rows}');
      expect(section.adjustments, hasLength(53));
      expect(section.adjustments.every((r) => r.coffeeId == 'target'), true);
      expect(section.adjustments.any((r) => r.id == 'reversed'), true);
      expect(section.adjustments.where((r) => r.lotId == 'old'), hasLength(50));
      expect(section.stock.consumedGrams, 20);
      expect(fixture.reads.rows, 53);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    },
  );
}

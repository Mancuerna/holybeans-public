import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/history_query.dart';
import 'package:holybeans/data/repositories/journal_data.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/text_suggestions.dart';
import 'package:holybeans/ui/brews/history_view_model.dart';

import 'helpers/test_database.dart';

const HistoryQuery empty = (
  text: '',
  archived: false,
  ascending: false,
  coffeeId: null,
  methodId: null,
  methodName: null,
  startMs: null,
  endMs: null,
  minimumRating: null,
);
HistoryQuery query(String text) => (
  text: foldSuggestion(text),
  archived: false,
  ascending: false,
  coffeeId: null,
  methodId: null,
  methodName: null,
  startMs: null,
  endMs: null,
  minimumRating: null,
);

void main() {
  late JournalData data;
  setUp(() async {
    final db = memoryDatabase();
    addTearDown(db.close);
    final repo = JournalRepository(db);
    final coffee = await repo.createCoffee(
      name: 'Café Alpha',
      roaster: 'North',
    );
    await repo.createBrew(
      coffeeId: coffee,
      methodName: 'V60',
      grinderName: 'Mill',
      notes: 'Cítrico jazmín',
      brewedAt: DateTime(2026),
      rating: 4,
    );
    final first = (await repo.allBrews()).single;
    data = JournalData(
      coffees: await repo.allCoffees(),
      brews: [
        first,
        for (var i = 1; i < 300; i++)
          first.copyWith(id: 'brew-$i', notes: Value('Chocolate $i')),
      ],
      lots: const [],
      components: const [],
    );
  });

  test('matching preserves accents, metadata and phrases across fields', () {
    List<int> search(String text) => selectHistory((
      brews: data.brews,
      coffees: data.coffees,
      query: query(text),
    ));
    expect(search('citrico jazmin'), [0]);
    expect(search('mill citrico'), [0]);
    expect(search('alpha north'), hasLength(300));
    expect(search('not in diary'), isEmpty);
  });

  test('combines all filters and retains timestamp tie ordering', () {
    final rows = [
      data.brews[0].copyWith(
        id: 'z',
        methodId: const Value('method'),
        brewedAtMs: 100,
        createdAtMs: 10,
      ),
      data.brews[0].copyWith(
        id: 'b',
        methodId: const Value('other'),
        brewedAtMs: 100,
        createdAtMs: 20,
      ),
      data.brews[0].copyWith(
        id: 'a',
        methodId: const Value('method'),
        brewedAtMs: 100,
        createdAtMs: 20,
      ),
      data.brews[0].copyWith(id: 'old', brewedAtMs: 10),
      data.brews[0].copyWith(id: 'archived', archivedAtMs: const Value(1)),
    ];
    final filter = (
      text: 'citrico',
      archived: false,
      ascending: true,
      coffeeId: rows.first.coffeeId,
      methodId: 'method',
      methodName: 'V60',
      startMs: 100,
      endMs: 101,
      minimumRating: 4.0,
    );
    expect(selectHistory((brews: rows, coffees: data.coffees, query: filter)), [
      2,
      0,
    ]);
  });

  test('a method ID without a legacy name excludes rows without that ID', () {
    const filter = (
      text: '',
      archived: false,
      ascending: false,
      coffeeId: null,
      methodId: 'known',
      methodName: null,
      startMs: null,
      endMs: null,
      minimumRating: null,
    );
    expect(
      selectHistory((brews: data.brews, coffees: data.coffees, query: filter)),
      isEmpty,
    );
  });

  test('coalesces typing and rejects obsolete worker results', () async {
    final requests = <HistoryRequest>[];
    final results = <Completer<List<int>>>[];
    final model = HistoryViewModel(
      search: (request) {
        requests.add(request);
        final result = Completer<List<int>>();
        results.add(result);
        return result.future;
      },
    );
    addTearDown(model.dispose);
    model.update(data, query('c'));
    model.update(data, query('ci'));
    model.update(data, query('citrico'));
    expect(requests, hasLength(1));
    results.first.complete([1]);
    await pumpEventQueue();
    expect(model.visible, isEmpty);
    expect(requests.map((r) => r.query.text), ['c', 'citrico']);
    results.last.complete([0]);
    await pumpEventQueue();
    expect(model.visible.single, same(data.brews.first));
    expect(model.busy, isFalse);
  });

  test('clearing a query supersedes pending work immediately', () async {
    final pending = Completer<List<int>>();
    final model = HistoryViewModel(search: (_) => pending.future);
    addTearDown(model.dispose);
    model.update(data, query('citrico'));
    model.update(data, empty);
    expect(model.visible, hasLength(300));
    expect(model.busy, isFalse);
    pending.complete([0]);
    await pumpEventQueue();
    expect(model.visible, hasLength(300));
  });

  test(
    'journal changes supersede pending indices and disposal cancels the queue',
    () async {
      final pending = <Completer<List<int>>>[];
      final model = HistoryViewModel(
        search: (_) {
          final result = Completer<List<int>>();
          pending.add(result);
          return result.future;
        },
      );
      model.update(data, query('citrico'));
      final changed = JournalData(
        coffees: data.coffees,
        brews: data.brews.reversed.toList(),
        lots: const [],
        components: const [],
      );
      model.update(changed, query('citrico'));
      pending.first.complete([0]);
      await pumpEventQueue();
      expect(model.visible, isEmpty);
      expect(pending, hasLength(2));
      pending.last.complete([299]);
      await pumpEventQueue();
      expect(model.visible.single, same(data.brews.first));
      model.update(data, query('next'));
      model.update(data, query('never started'));
      model.dispose();
      pending.last.complete([]);
      await pumpEventQueue();
      expect(pending, hasLength(3));
    },
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/history_pages.dart';
import 'package:holybeans/data/repositories/history_query.dart';
import 'package:holybeans/data/repositories/journal_data.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/ui/brews/history_view_model.dart';
import 'package:holybeans/ui/brews/paged_history_view_model.dart';

import 'helpers/test_database.dart';

HistoryQuery selection({
  List<String> tools = const [],
  String? method,
  String text = '',
  bool archived = false,
  bool ascending = false,
  double? rating,
}) => (
  text: text,
  archived: archived,
  ascending: ascending,
  coffeeId: null,
  methodId: null,
  methodName: method,
  toolIds: tools,
  startMs: null,
  endMs: null,
  minimumRating: rating,
);

void main() {
  late AppDatabase db;
  late JournalRepository repo;
  late String coffee;
  setUp(() async {
    db = memoryDatabase();
    repo = JournalRepository(db);
    coffee = await repo.createCoffee(name: 'Coffee', roaster: 'Roaster');
  });
  tearDown(() => db.close());

  Future<JournalData> snapshot() async => JournalData(
    coffees: await repo.allCoffees(),
    brews: await repo.allBrews(),
    lots: const [],
    components: const [],
    tools: await db.select(db.methodTools).get(),
    toolSelections: await db.select(db.brewToolSelections).get(),
  );

  test(
    'accessories work alone, intersect and retain merged and archived history',
    () async {
      final v60 = await repo.createMethod(name: 'V60');
      final espresso = await repo.createMethod(name: 'Espresso');
      final paper = await repo.createTool(
        name: 'Cafec abacá',
        methodIds: [v60, espresso],
      );
      final basket = await repo.createTool(
        name: '58 mm basket',
        methodIds: [espresso],
      );
      final oldPaper = await repo.createTool(
        name: 'Old paper',
        methodIds: [v60],
      );
      Future<String> brew(
        String method,
        String name,
        List<String> tools, {
        double? rating,
      }) => repo.createBrew(
        coffeeId: coffee,
        methodId: method,
        methodName: name,
        methodToolIds: tools,
        rating: rating,
        notes: 'cítrico ${'x' * 17000}',
      );
      final pour = await brew(v60, 'V60', [oldPaper]);
      final shot = await brew(espresso, 'Espresso', [paper, basket], rating: 9);
      final basketOnly = await brew(espresso, 'Espresso', [basket]);
      final noTools = await brew(v60, 'V60', []);
      final archived = await brew(v60, 'V60', [paper]);
      await repo.setBrewArchived(archived, archived: true);
      await repo.mergeTools(sourceId: oldPaper, targetId: paper);
      await repo.setMethodToolArchived(paper, archived: true);
      // Compatibility changes must not rewrite recorded accessory usage.
      await repo.dissociateTool(paper, v60);

      final data = await snapshot();
      final model = HistoryViewModel();
      addTearDown(model.dispose);
      final pages = HistoryPages(repo.reads);
      for (final (query, expected) in [
        (selection(tools: [paper]), {pour, shot}),
        (selection(tools: [oldPaper]), {pour, shot}),
        (selection(tools: [basket]), {shot, basketOnly}),
        (selection(tools: [paper, basket]), {shot}),
        (selection(tools: [basket], method: 'V60'), <String>{}),
        (selection(method: 'V60'), {pour, noTools}),
        (selection(tools: [paper], method: 'V60'), {pour}),
        (selection(tools: [paper], archived: true), {pour, shot, archived}),
        (selection(tools: [paper], rating: 8), {shot}),
        (selection(tools: [paper], text: 'citrico'), {pour, shot}),
        (selection(tools: ['missing']), <String>{}),
      ]) {
        final page = await pages.page(query, data.coffees);
        expect(page.rows.map((row) => row.id).toSet(), expected);
        model.update(data, query);
        await _until(() => !model.busy);
        expect(model.visible.map((row) => row.id).toSet(), expected);
        expect(model.error, isNull);
      }
    },
  );

  test(
    'accessory matches are paginated before the limit without duplicates',
    () async {
      final paper = await repo.createTool(name: 'Paper');
      final old = await repo.createTool(name: 'Duplicate');
      await db.batch((batch) {
        batch.insertAll(db.brews, [
          for (var i = 0; i < 240; i++)
            BrewsCompanion.insert(
              id: 'b$i',
              coffeeId: coffee,
              methodName: 'V60',
              brewedAtMs: i,
              createdAtMs: i,
              updatedAtMs: i,
            ),
        ]);
        batch.insertAll(db.brewToolSelections, [
          for (var i = 0; i < 240; i += 3) ...[
            BrewToolSelection(brewId: 'b$i', toolId: paper),
            BrewToolSelection(brewId: 'b$i', toolId: old),
          ],
        ]);
      });
      await repo.mergeTools(sourceId: old, targetId: paper);
      for (final ascending in [false, true]) {
        final pages = HistoryPages(repo.reads);
        final query = selection(tools: [paper], ascending: ascending);
        final first = await pages.page(query, []);
        final second = await pages.page(
          query,
          [],
          after: first.next,
          expectedRevision: first.revision,
        );
        expect(first.rows, hasLength(50));
        expect(first.more, isTrue);
        expect(second.rows, hasLength(30));
        expect(second.more, isFalse);
        final expected = [for (var i = 0; i < 240; i += 3) 'b$i'];
        expect(
          [...first.rows, ...second.rows].map((row) => row.id),
          ascending ? expected : expected.reversed,
        );
      }
    },
  );

  test(
    'live history reloads after accessory selection and catalog edits',
    () async {
      final paper = await repo.createTool(name: 'Paper');
      final other = await repo.createTool(name: 'Other');
      final brew = await repo.createBrew(coffeeId: coffee, methodName: 'V60');
      final data = await snapshot();
      final model = PagedHistoryViewModel(repo.reads);
      addTearDown(model.dispose);
      model.update(data, selection(tools: [paper]));
      await _until(() => !model.busy && model.toolOptions.length == 2);
      expect(model.length, 0);
      await db
          .into(db.brewToolSelections)
          .insert(BrewToolSelection(brewId: brew, toolId: other));
      await repo.mergeTools(sourceId: other, targetId: paper);
      await _until(() => !model.busy && model.brewAt(0)?.id == brew);
      await repo.updateTool(id: paper, name: 'Renamed paper', methodIds: []);
      await _until(
        () => model.toolOptions.any((tool) => tool.name == 'Renamed paper'),
      );
      await db.delete(db.brewToolSelections).go();
      await _until(() => !model.busy && model.length == 0);
      expect(model.error, isNull);
    },
  );
}

Future<void> _until(bool Function() ready) async {
  final watch = Stopwatch()..start();
  while (!ready()) {
    if (watch.elapsed > const Duration(seconds: 20)) {
      fail('History did not settle');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

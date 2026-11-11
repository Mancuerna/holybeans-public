import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';

class _Queries extends QueryInterceptor {
  int selections = 0;
  int links = 0;
  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await executor.runSelect(statement, args);
    if (statement.contains('FROM "brew_tool_selections"')) {
      selections += rows.length;
    }
    if (statement.contains('FROM "tool_method_links"')) links += rows.length;
    return rows;
  }

  void reset() => selections = links = 0;
  Map<String, int> get snapshot => {'selections': selections, 'links': links};
}

void main() {
  test('tool lookups avoid unrelated history and preserve merged selections', () async {
    final counts = _Queries();
    final db = AppDatabase.forTesting(
      NativeDatabase.memory().interceptWith(counts),
    );
    addTearDown(db.close);
    final repo = JournalRepository(db);
    final coffee = await repo.createCoffee(name: 'Fixture', roaster: 'Test');
    final method = await repo.createMethod(name: 'V60');
    final other = await repo.createMethod(name: 'Other');
    final source = await repo.createTool(
      name: 'Old filter',
      methodIds: [method],
    );
    final target = await repo.createTool(name: 'Filter', methodIds: [method]);
    for (var i = 0; i < 20; i++) {
      await repo.createTool(name: 'Other $i', methodIds: [other]);
    }
    await db.batch((batch) {
      batch.insertAll(db.brews, [
        for (var i = 0; i < 100; i++)
          BrewsCompanion.insert(
            id: 'brew-$i',
            coffeeId: coffee,
            methodId: Value(method),
            methodName: 'V60',
            brewedAtMs: i,
            createdAtMs: i,
            updatedAtMs: i,
          ),
      ]);
      batch.insertAll(db.brewToolSelections, [
        for (var i = 0; i < 100; i++)
          BrewToolSelection(brewId: 'brew-$i', toolId: source),
      ]);
    });
    await repo.mergeTools(sourceId: source, targetId: target);
    await repo.setMethodToolArchived(target, archived: true);
    counts.reset();
    expect(
      (await repo.methodTools(method, retainedIds: [source])).single.id,
      target,
    );
    final methodReads = counts.snapshot;
    counts.reset();
    expect(await repo.brewToolIds('brew-0'), [target]);
    final brewReads = counts.snapshot;
    counts.reset();
    await repo.saveBrew(
      id: 'brew-0',
      coffeeId: coffee,
      methodId: method,
      methodName: 'V60',
    );
    final saveReads = counts.snapshot;
    stdout.writeln(
      'TOOL_LOOKUP_ROWS ${jsonEncode({'method': methodReads, 'brew': brewReads, 'save': saveReads})}',
    );
    expect(methodReads, {'selections': 0, 'links': 1});
    expect(brewReads, {'selections': 1, 'links': 0});
    expect(saveReads, {'selections': 1, 'links': 1});
    expect(await repo.brewToolIds('brew-0'), [target]);
    expect(await repo.methodTools(method), isEmpty);
    expect((await repo.toolCatalog()).useCounts[target], 100);
    expect(
      (await db.select(db.brewToolSelections).get())
          .where((row) => row.brewId != 'brew-0')
          .map((row) => row.toolId)
          .toSet(),
      {source},
    );
  });
}

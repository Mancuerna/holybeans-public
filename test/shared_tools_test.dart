import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/repositories/tool_catalog.dart';
import 'package:holybeans/data/services/beanconqueror_archive.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/domain/beanconqueror/bq_import_plan.dart';

import 'helpers/beanconqueror_fixture.dart' as bq;

import 'helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late JournalRepository repo;
  late String coffee;
  late String v60;
  late String origami;

  setUp(() async {
    db = memoryDatabase();
    repo = JournalRepository(db);
    coffee = await repo.createCoffee(
      name: 'Coffee',
      roaster: 'Local',
      initialGrams: 250,
    );
    v60 = await repo.createMethod(name: 'V60');
    origami = await repo.createMethod(name: 'Origami');
  });
  tearDown(() => db.close());

  Future<String> brew(String method, List<String> tools) => repo.createBrew(
    coffeeId: coffee,
    methodId: method,
    methodName: method == v60 ? 'V60' : 'Origami',
    doseGrams: 15,
    methodToolIds: tools,
  );

  test(
    'one identity works in two methods; counts include archived brews',
    () async {
      final tool = await repo.createTool(
        name: 'Cafec Abaca',
        methodIds: [v60, origami],
      );
      final first = await brew(v60, [tool]);
      final second = await brew(origami, [tool]);
      await repo.setBrewArchived(second, archived: true);
      expect((await repo.methodTools(v60)).single.id, tool);
      expect((await repo.methodTools(origami)).single.id, tool);
      expect((await repo.toolCatalog()).useCounts[tool], 2);
      await repo.updateTool(id: tool, name: 'Abaca', methodIds: [origami]);
      expect(await repo.methodTools(v60), isEmpty);
      expect(await repo.brewToolIds(first), [tool]);
      // A removed association does not erase selections when editing history.
      await repo.saveBrew(
        id: first,
        coffeeId: coffee,
        methodId: v60,
        methodName: 'V60',
        doseGrams: 15,
        methodToolIds: [tool],
      );
      expect(await repo.brewToolIds(first), [tool]);
      await expectLater(brew(v60, [tool]), throwsStateError);
      expect((await repo.toolCatalog()).byId[tool]!.name, 'Abaca');
    },
  );

  test('unassigned tool can be reused; archives protect history and reject new use', () async {
    final tool = await repo.createTool(name: 'Paper');
    expect(await repo.methodTools(v60), isEmpty);
    await repo.associateTool(tool, v60);
    await repo.associateTool(tool, v60); // Idempotent reuse.
    expect(await db.select(db.toolMethodLinks).get(), hasLength(1));
    final id = await brew(v60, [tool]);
    await repo.setMethodToolArchived(tool, archived: true);
    expect(await repo.methodTools(v60), isEmpty);
    await repo.saveBrew(
      id: id,
      coffeeId: coffee,
      methodId: v60,
      methodName: 'V60',
      methodToolIds: [tool],
    );
    expect(await repo.brewToolIds(id), [tool]);
    await expectLater(brew(v60, [tool]), throwsStateError);
    await repo.setMethodToolArchived(tool, archived: false);
    await repo.associateTool(tool, origami);
    expect((await repo.methodTools(origami)).single.id, tool);
  });

  test(
    'same names stay distinct until explicit merge; counts deduplicate brews',
    () async {
      final source = await repo.createTool(name: 'Paper', methodIds: [v60]);
      final target = await repo.createTool(
        name: 'Paper',
        methodIds: [v60, origami],
      );
      final both = await brew(v60, [source, target]);
      final old = await brew(origami, [target]);
      await repo.setBrewArchived(old, archived: true);
      final selections = await db.select(db.brewToolSelections).get();
      expect((await repo.toolCatalog()).visible(), hasLength(2));
      await repo.mergeTools(sourceId: source, targetId: target);
      expect(await db.select(db.brewToolSelections).get(), selections);
      final merged = await repo.toolCatalog();
      expect(merged.visible().single.id, target);
      expect(merged.useCounts[target], 2);
      expect(merged.methodsByTool[target], {v60, origami});
      expect(await repo.brewToolIds(both), [target]);
      await expectLater(
        repo.mergeTools(sourceId: target, targetId: source),
        throwsArgumentError,
      );
      await repo.saveBrew(
        id: both,
        coffeeId: coffee,
        methodId: v60,
        methodName: 'V60',
        methodToolIds: [target],
      );
      expect((await repo.toolCatalog()).useCounts[target], 2);
    },
  );

  test('current backup retains merge identities, detached history and unassigned tools', () async {
    final source = await repo.createTool(name: 'Old paper', methodIds: [v60]);
    final target = await repo.createTool(name: 'Paper', methodIds: [origami]);
    final unassigned = await repo.createTool(name: 'Brush');
    final id = await brew(v60, [source]);
    await repo.mergeTools(sourceId: source, targetId: target);
    await repo.dissociateTool(target, v60);
    await repo.setMethodToolArchived(target, archived: true);
    final tools = await db.select(db.methodTools).get();
    final selections = await db.select(db.brewToolSelections).get();
    final exported = await JournalBackup(db).exportJson();
    expect(jsonDecode(exported)['version'], JournalBackup.version);
    await JournalBackup(db).restoreJson(exported);
    expect(await db.select(db.methodTools).get(), unorderedEquals(tools));
    expect(
      await db.select(db.brewToolSelections).get(),
      unorderedEquals(selections),
    );
    expect(await repo.brewToolIds(id), [target]);
    expect((await repo.toolCatalog()).methodsByTool[unassigned], isNull);
    expect((await repo.toolCatalog()).useCounts[target], 1);
  });

  test(
    'v19 creates associations with the original IDs and archived states',
    () async {
      final tool = await repo.createMethodTool(
        methodId: v60,
        name: 'Old filter',
      );
      final id = await brew(v60, [tool]);
      await repo.setMethodToolArchived(tool, archived: true);
      final backup = jsonDecode(
        await JournalBackup(db).exportJson(),
      ) as Map<String, dynamic>;
      backup['version'] = 19;
      final data = backup['data'] as Map<String, dynamic>;
      data.remove('toolMethodLinks');
      (data['methodTools'] as List).single
        ..['methodId'] = v60
        ..remove('mergedIntoId');
      await JournalBackup(db).restoreJson(jsonEncode(backup));
      final catalog = await repo.toolCatalog();
      expect(catalog.methodsByTool[tool], {v60});
      expect(catalog.byId[tool]!.archivedAtMs, isNotNull);
      expect(await repo.brewToolIds(id), [tool]);
    },
  );

  test('invalid merge graph or associations reject restore without changing the diary', () async {
    final tool = await repo.createTool(name: 'Brush');
    final original = await JournalBackup(db).exportJson();
    for (final damage in ['cycle', 'missing', 'duplicate', 'absent']) {
      final backup = jsonDecode(original) as Map<String, dynamic>;
      final data = backup['data'] as Map<String, dynamic>;
      if (damage == 'cycle') {
        (data['methodTools'] as List).single['mergedIntoId'] = tool;
      } else if (damage == 'missing') {
        data['toolMethodLinks'] = [
          {'toolId': tool, 'methodId': 'missing'},
        ];
      } else if (damage == 'duplicate') {
        data['toolMethodLinks'] = [
          for (var i = 0; i < 2; i++) {'toolId': tool, 'methodId': v60},
        ];
      } else {
        data.remove('toolMethodLinks');
      }
      await expectLater(
        JournalBackup(db).restoreJson(jsonEncode(backup)),
        throwsFormatException,
      );
      expect((await db.select(db.methodTools).getSingle()).id, tool);
      expect(await db.select(db.toolMethodLinks).get(), isEmpty);
    }
  });

  test(
    'BeanConqueror reimport keeps merged tool IDs and counts new uses once',
    () async {
      final json = bq.exportJson();
      Future<void> import() async {
        final exported = BeanconquerorArchive.read(
          Uint8List.fromList(utf8.encode(jsonEncode(json))),
        );
        await repo.importBeanconqueror(
          planBeanconquerorImport(
            exported,
            await repo.beanconquerorJournal(),
            now: DateTime.utc(2026),
          ),
        );
      }

      await import();
      final imported = await db.select(db.methodTools).getSingle();
      expect(
        (await repo.methodTools(imported.methodId!)).single.id,
        imported.id,
      );
      final target = await repo.createTool(
        name: 'Shared basket',
        methodIds: [v60],
      );
      await repo.mergeTools(sourceId: imported.id, targetId: target);
      final records = await db.select(db.importRecords).get();
      final first = Map<String, dynamic>.from(
        (json['BREWS'] as List).single as Map,
      );
      first['config'] = bq.config('another-shot', DateTime(2025, 1, 6));
      json['BREWS'] = [...(json['BREWS'] as List), first];
      await import();
      await import();
      expect(await db.select(db.methodTools).get(), hasLength(2));
      final catalog = await repo.toolCatalog();
      expect(catalog.visible().single.id, target);
      expect(catalog.useCounts[target], 2);
      expect(await db.select(db.importRecords).get(), containsAll(records));
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    },
  );

  test('merge resolver rejects a missing target and cycles', () {
    expect(
      () => ToolCatalog(
        tools: [const MethodTool(id: 'a', name: 'A', mergedIntoId: 'missing')],
        links: [],
        selections: [],
      ),
      throwsStateError,
    );
    expect(
      () => ToolCatalog(
        tools: [
          const MethodTool(id: 'a', name: 'A', mergedIntoId: 'b'),
          const MethodTool(id: 'b', name: 'B', mergedIntoId: 'a'),
        ],
        links: [],
        selections: [],
      ),
      throwsStateError,
    );
  });
}

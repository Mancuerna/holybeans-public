import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:path/path.dart' as path;

class JournalFixture {
  const JournalFixture(this.brews, this.noteCharacters);

  final int brews;
  final int noteCharacters;
  int get coffees => max(1, min(250, brews ~/ 20));
  String get name => '${brews}x$noteCharacters';

  Map<String, Object> get metadata => {
    'fixture': name,
    'brews': brews,
    'coffees': coffees,
    'noteCharacters': noteCharacters,
    'seed': 'deterministic; all coffees active; 10% brews archived',
  };

  Future<void> seed(AppDatabase database) async {
    final repository = JournalRepository(database);
    final coffeeIds = <String>[];
    final lotIds = <String>[];
    final methodId = await repository.createMethod(
      name: 'V60',
      category: 'pourover',
    );
    for (var i = 0; i < coffees; i++) {
      final id = await repository.createCoffee(
        name: 'Audit coffee $i',
        roaster: 'Synthetic roaster ${i % 10}',
        roastDate: '2026-10-20',
        initialGrams: 1000,
      );
      coffeeIds.add(id);
      lotIds.add((await repository.coffeeLots(id)).single.id);
    }
    // Populate in chunks without exercising the save path under measurement.
    // Each note is distinct, so memory cannot benefit from one shared string.
    const phrase = 'Café jazmín chocolate cítrico y textura suave. ';
    final body = List.filled(
      noteCharacters ~/ phrase.length + 1,
      phrase,
    ).join().substring(0, noteCharacters);
    for (var start = 0; start < brews; start += 100) {
      await database.batch((batch) {
        batch.insertAll(database.brews, [
          for (var i = start; i < min(start + 100, brews); i++)
            BrewsCompanion.insert(
              id: 'audit-brew-$i',
              coffeeId: coffeeIds[i % coffees],
              lotId: Value(lotIds[i % coffees]),
              methodId: Value(methodId),
              methodName: 'V60',
              doseGrams: const Value(18),
              waterGrams: const Value(300),
              rating: Value(1.0 + i % 5),
              notes: Value(noteCharacters == 0 ? null : '$i $body'),
              brewedAtMs: auditNow.millisecondsSinceEpoch - i * 57600000,
              createdAtMs: auditNow.millisecondsSinceEpoch - i * 57600000,
              updatedAtMs: auditNow.millisecondsSinceEpoch,
              archivedAtMs: Value(i % 10 == 9 ? 1 : null),
            ),
        ]);
      });
    }
  }
}

final auditNow = DateTime.utc(2026, 11, 4, 12);

const auditFixtures = [
  JournalFixture(100, 0),
  JournalFixture(100, 2048),
  JournalFixture(1000, 0),
  JournalFixture(1000, 2048),
  JournalFixture(5000, 0),
  JournalFixture(5000, 2048),
  JournalFixture(10000, 0),
  JournalFixture(10000, 2048),
  JournalFixture(10000, 8192),
];

class AuditDatabase {
  AuditDatabase._(this.directory, this.database, this.queries);

  final Directory directory;
  final AppDatabase database;
  final QueryCounts queries;

  static Future<AuditDatabase> open() async {
    final directory = await Directory.systemTemp.createTemp('holybeans-audit-');
    final queries = QueryCounts();
    // Match AppDatabase.open: file-backed SQLite in a background isolate.
    final database = AppDatabase.forTesting(
      NativeDatabase.createInBackground(
        File(path.join(directory.path, 'journal.sqlite')),
      ).interceptWith(queries),
    );
    return AuditDatabase._(directory, database, queries);
  }

  Future<void> close() async {
    await database.close();
    await directory.delete(recursive: true);
  }
}

class QueryCounts extends QueryInterceptor {
  int selects = 0;
  int rows = 0;
  int brewSelects = 0;
  int brewRows = 0;

  void reset() {
    selects = rows = brewSelects = brewRows = 0;
  }

  Map<String, int> get snapshot => {
    'selects': selects,
    'rows': rows,
    'brewSelects': brewSelects,
    'brewRows': brewRows,
  };

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await executor.runSelect(statement, args);
    selects++;
    rows += result.length;
    if (RegExp(
      r'\b(?:FROM|JOIN)\s+"?brews"?\b',
      caseSensitive: false,
    ).hasMatch(statement)) {
      brewSelects++;
      brewRows += result.length;
    }
    return result;
  }
}

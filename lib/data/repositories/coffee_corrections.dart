import 'package:drift/drift.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/roaster_profile.dart';

enum CorrectionField {
  country,
  region,
  farm,
  producer,
  variety,
  process,
  roaster,
}

typedef CorrectionRow = ({
  String coffeeId,
  String name,
  bool archived,
  String value,
  String id,
  int? position,
});

class CorrectionConflict implements Exception {}

class CoffeeCorrections {
  const CoffeeCorrections(this.db);
  final AppDatabase db;

  Future<List<CorrectionRow>> rows(
    CorrectionField field, {
    required bool archived,
  }) async {
    final roaster = field == CorrectionField.roaster;
    final query = db.customSelect(
      'SELECT c.id AS coffee_id, c.name, c.archived_at_ms, '
      '${roaster ? "c.id, NULL AS position, c.roaster" : "o.id, o.position, o.${field.name}"} AS value '
      'FROM coffees c '
      '${roaster ? "" : "JOIN coffee_components o ON o.coffee_id = c.id"} '
      '${archived ? "" : "WHERE c.archived_at_ms IS NULL"} '
      'ORDER BY c.name COLLATE NOCASE, c.id, position',
    );
    return [
      for (final r in await query.get())
        if (r.readNullable<String>('value') case final String value
            when value.trim().isNotEmpty)
          (
            coffeeId: r.read<String>('coffee_id'),
            id: r.read<String>('id'),
            name: r.read<String>('name'),
            archived: r.readNullable<int>('archived_at_ms') != null,
            position: r.readNullable<int>('position'),
            value: value,
          ),
    ];
  }

  Future<List<String>> roasterNames() async => [
    for (final row in await db.select(db.roasters).get()) row.name,
  ];

  Future<void> apply(
    CorrectionField field,
    Set<CorrectionRow> selected,
    String replacement,
  ) async {
    final roaster = field == CorrectionField.roaster;
    final target = roaster ? roasterName(replacement) : replacement.trim();
    if (target.isEmpty || (roaster && target.length > 200)) {
      throw ArgumentError.value(replacement);
    }
    await db.transaction(() async {
      final current = (await rows(field, archived: true)).toSet();
      if (!current.containsAll(selected)) throw CorrectionConflict();
      final touched = <String>{};
      final registry = RoasterRegistry(db);
      for (final row in selected) {
        if (row.value == target) continue;
        touched.add(row.coffeeId);
        if (roaster) {
          await (db.update(db.coffees)..where((c) => c.id.equals(row.id)))
              .write(CoffeesCompanion(roaster: Value(target)));
          await registry.linkCoffee(row.id, target);
        } else {
          await db.customUpdate(
            'UPDATE coffee_components SET ${field.name} = ? WHERE id = ?',
            variables: [
              Variable.withString(target),
              Variable.withString(row.id),
            ],
            updates: {db.coffeeComponents},
          );
        }
      }
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      for (final id in touched) {
        await (db.update(db.coffees)..where((c) => c.id.equals(id))).write(
          CoffeesCompanion(updatedAtMs: Value(now)),
        );
      }
    });
  }
}

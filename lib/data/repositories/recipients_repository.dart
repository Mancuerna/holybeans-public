import 'package:drift/drift.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/catalog_validation.dart';
import 'package:uuid/uuid.dart';

/// Recipient catalog and the methods that retain each recipient.
class RecipientRepository {
  RecipientRepository(this.database);
  final AppDatabase database;
  final Uuid _uuid = const Uuid();

  Stream<List<Recipient>> watchRecipients({bool includeArchived = false}) {
    final query = database.select(database.recipients)
      ..orderBy([(r) => OrderingTerm.asc(r.name)]);
    if (!includeArchived) query.where((r) => r.archivedAtMs.isNull());
    return query.watch();
  }

  Future<Recipient> saveRecipient({
    String? id,
    required String name,
    required double emptyGrams,
    bool isPortafilter = false,
  }) => database.transaction(() async {
    final row = Recipient(
      id: id ?? _uuid.v4(),
      name: requireCatalogName(name, 'name'),
      emptyGrams: emptyGrams,
      isPortafilter: isPortafilter,
    );
    checkJug(row.name, row.emptyGrams);
    if (id == null) {
      await database.into(database.recipients).insert(row);
    } else {
      final previous = await requireRecipient(id);
      if (previous!.isPortafilter != isPortafilter) {
        throw ArgumentError('Recipient use cannot change');
      }
      final count =
          await (database.update(
            database.recipients,
          )..where((r) => r.id.equals(id))).write(
            RecipientsCompanion(
              name: Value(row.name),
              emptyGrams: Value(emptyGrams),
            ),
          );
      if (count == 0) throw StateError('Recipient not found');
    }
    await (database.update(
      database.brewMethods,
    )..where((m) => m.defaultRecipientId.equals(row.id))).write(
      BrewMethodsCompanion(
        vesselName: Value(row.name),
        vesselGrams: Value(row.emptyGrams),
      ),
    );
    return row;
  });

  Future<void> setRecipientArchived(String id, {required bool archived}) async {
    final count =
        await (database.update(
          database.recipients,
        )..where((r) => r.id.equals(id))).write(
          RecipientsCompanion(
            archivedAtMs: Value(
              archived ? DateTime.now().millisecondsSinceEpoch : null,
            ),
          ),
        );
    if (count == 0) throw StateError('Recipient not found');
  }

  Future<Recipient?> requireRecipient(String? id) async {
    if (id == null) return null;
    final row = await (database.select(
      database.recipients,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
    if (row == null) throw StateError('Recipient not found');
    return row;
  }
}

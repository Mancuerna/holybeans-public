import 'package:drift/drift.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/catalog_validation.dart';
import 'package:holybeans/data/repositories/equipment_deletion.dart';
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

  Future<List<EquipmentDeletionBlocker>> portafilterDeletionBlockers(
    String id,
  ) => database.transaction(() => _portafilterDeletionBlockers(id));

  Future<List<EquipmentDeletionBlocker>> _portafilterDeletionBlockers(
    String id,
  ) async {
    final recipient = await requireRecipient(id);
    if (!recipient!.isPortafilter) {
      throw ArgumentError('Recipient is not a portafilter');
    }
    // Archived records still retain their references.
    final brew =
        await (database.select(database.brews)
              ..where((row) => row.recipientId.equals(id))
              ..limit(1))
            .getSingleOrNull();
    final method =
        await (database.select(database.brewMethods)
              ..where((row) => row.defaultRecipientId.equals(id))
              ..limit(1))
            .getSingleOrNull();
    return [
      if (brew != null) EquipmentDeletionBlocker.brews,
      if (method != null) EquipmentDeletionBlocker.methods,
    ];
  }

  Future<void> deleteUnusedPortafilter(String id) =>
      database.transaction(() async {
        final blockers = await _portafilterDeletionBlockers(id);
        if (blockers.isNotEmpty) throw EquipmentInUseException(blockers);
        await (database.delete(
          database.recipients,
        )..where((row) => row.id.equals(id))).go();
      });

  Future<Recipient?> requireRecipient(String? id) async {
    if (id == null) return null;
    final row = await (database.select(
      database.recipients,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
    if (row == null) throw StateError('Recipient not found');
    return row;
  }
}

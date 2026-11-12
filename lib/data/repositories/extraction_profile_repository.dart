import 'package:drift/drift.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/extraction_profile.dart';

class ExtractionProfileRepository {
  ExtractionProfileRepository(this.database);
  final AppDatabase database;

  Stream<List<ExtractionProfileRow>> watch() =>
      (database.select(database.extractionProfiles)..orderBy([
            (r) => OrderingTerm.desc(r.isFavorite),
            (r) => OrderingTerm.desc(r.lastUsedAtMs),
            (r) => OrderingTerm.desc(r.updatedAtMs),
          ]))
          .watch();

  Future<void> save(ExtractionProfile profile) async {
    profile.validate();
    await database
        .into(database.extractionProfiles)
        .insertOnConflictUpdate(
          ExtractionProfilesCompanion(
            id: Value(profile.id),
            dataJson: Value(profile.encode()),
            updatedAtMs: Value(DateTime.now().millisecondsSinceEpoch),
          ),
        );
  }

  Future<void> favorite(String id, bool value) async {
    await (database.update(database.extractionProfiles)
          ..where((r) => r.id.equals(id)))
        .write(ExtractionProfilesCompanion(isFavorite: Value(value)));
  }

  Future<void> used(String id) async {
    await (database.update(
      database.extractionProfiles,
    )..where((r) => r.id.equals(id))).write(
      ExtractionProfilesCompanion(
        lastUsedAtMs: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  Future<void> delete(String id) async {
    await (database.delete(
      database.extractionProfiles,
    )..where((r) => r.id.equals(id))).go();
  }
}

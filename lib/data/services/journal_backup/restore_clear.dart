part of '../journal_backup.dart';

/// Empties every table, children before the rows they reference.
Future<void> _clearJournal(AppDatabase database) async {
  await database.delete(database.extractionProfiles).go();
  await _PistonBackup.clear(database);
  await _CafeBackup.clear(database);
  await database.delete(database.stockAdjustments).go();
  await database.delete(database.cuppingSessionCups).go();
  await database.delete(database.cuppingSessions).go();
  await database.delete(database.appPreferences).go();
  await database.delete(database.legacyPayloads).go();
  await database.delete(database.importRecords).go();
  await database.delete(database.brewToolSelections).go();
  await database.delete(database.brewCurves).go();
  await database.delete(database.brewPhotos).go();
  await database.delete(database.coffeePhotos).go();
  await database.delete(database.brews).go();
  await database.delete(database.waterProfiles).go();
  await database.delete(database.toolMethodLinks).go();
  // Redirects reference other tools. Clear them before deleting the
  // catalog, inside the confirmed restore transaction.
  await database.customStatement(
    'UPDATE method_tools SET merged_into_id = NULL',
  );
  await database.delete(database.methodTools).go();
  await database.delete(database.grinders).go();
  await database.delete(database.frozenPortions).go();
  await database.delete(database.coffeeLots).go();
  await database.delete(database.coffeeComponents).go();
  await database.delete(database.brewMethods).go();
  await database.delete(database.recipients).go();
  await database.delete(database.coffees).go();
}

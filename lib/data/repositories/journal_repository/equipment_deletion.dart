part of '../journal_repository.dart';

extension EquipmentDeletion on JournalRepository {
  Future<List<EquipmentDeletionBlocker>> methodDeletionBlockers(String id) =>
      equipment.methodDeletionBlockers(id);
  Future<List<EquipmentDeletionBlocker>> waterProfileDeletionBlockers(
    String id,
  ) => equipment.waterProfileDeletionBlockers(id);
  Future<void> deleteUnusedMethod(String id) =>
      equipment.deleteUnusedMethod(id);
  Future<void> deleteUnusedWaterProfile(String id) =>
      equipment.deleteUnusedWaterProfile(id);
}

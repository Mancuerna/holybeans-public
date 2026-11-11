part of '../journal_repository.dart';

extension EquipmentOperations on JournalRepository {
  Future<String> createWaterProfile({
    required String name,
    double? ghPpmAsCaCO3,
    double? khPpmAsCaCO3,
    double? tdsPpm,
    double? ph,
    WaterMinerals minerals = const WaterMinerals(),
    String? notes,
    String? recipeJson,
  }) => equipment.createWaterProfile(
    name: name,
    ghPpmAsCaCO3: ghPpmAsCaCO3,
    khPpmAsCaCO3: khPpmAsCaCO3,
    tdsPpm: tdsPpm,
    ph: ph,
    minerals: minerals,
    notes: notes,
    recipeJson: recipeJson,
  );
  Future<void> updateWaterProfile({
    required String id,
    required String name,
    double? ghPpmAsCaCO3,
    double? khPpmAsCaCO3,
    double? tdsPpm,
    double? ph,
    WaterMinerals minerals = const WaterMinerals(),
    String? notes,
    String? recipeJson,
  }) => equipment.updateWaterProfile(
    id: id,
    name: name,
    ghPpmAsCaCO3: ghPpmAsCaCO3,
    khPpmAsCaCO3: khPpmAsCaCO3,
    tdsPpm: tdsPpm,
    ph: ph,
    minerals: minerals,
    notes: notes,
    recipeJson: recipeJson,
  );
  Future<void> setWaterProfileArchived(String id, {required bool archived}) =>
      equipment.setWaterProfileArchived(id, archived: archived);
  Future<String> createMethod({
    required String name,
    String? category,
    String? templateType,
    String? notes,
    String? machine,
    String? machineAddress,
    String? vesselName,
    double? vesselGrams,
    String? defaultRecipientId,
    bool useRecipientCatalog = false,
  }) => equipment.createMethod(
    name: name,
    category: category,
    templateType: templateType,
    notes: notes,
    machine: machine,
    machineAddress: machineAddress,
    vesselName: vesselName,
    vesselGrams: vesselGrams,
    defaultRecipientId: defaultRecipientId,
    useRecipientCatalog: useRecipientCatalog,
  );
  Future<void> updateMethod({
    required String id,
    required String name,
    String? category,
    String? templateType,
    String? notes,
    String? machine,
    String? machineAddress,
    String? vesselName,
    double? vesselGrams,
    String? defaultRecipientId,
    bool useRecipientCatalog = false,
  }) => equipment.updateMethod(
    id: id,
    name: name,
    category: category,
    templateType: templateType,
    notes: notes,
    machine: machine,
    machineAddress: machineAddress,
    vesselName: vesselName,
    vesselGrams: vesselGrams,
    defaultRecipientId: defaultRecipientId,
    useRecipientCatalog: useRecipientCatalog,
  );

  /// Remembers [plan] as the guided pour recipe of a method; null forgets
  /// it. The dose is not kept: it changes from brew to brew.
  Future<void> setMethodPourPlan(String id, PourPlan? plan) =>
      equipment.setMethodPourPlan(id, plan);
  Future<void> setMethodArchived(String id, {required bool archived}) =>
      equipment.setMethodArchived(id, archived: archived);
  Future<String> createGrinder({
    required String name,
    String? notes,
    bool hasAdjustableRpm = false,
    bool hasAdjustableFeederRpm = false,
  }) => equipment.createGrinder(
    name: name,
    notes: notes,
    hasAdjustableRpm: hasAdjustableRpm,
    hasAdjustableFeederRpm: hasAdjustableFeederRpm,
  );
  Future<void> updateGrinder({
    required String id,
    required String name,
    String? notes,
    bool? hasAdjustableRpm,
    bool? hasAdjustableFeederRpm,
  }) => equipment.updateGrinder(
    id: id,
    name: name,
    notes: notes,
    hasAdjustableRpm: hasAdjustableRpm,
    hasAdjustableFeederRpm: hasAdjustableFeederRpm,
  );
  Future<void> setGrinderArchived(String id, {required bool archived}) =>
      equipment.setGrinderArchived(id, archived: archived);
}

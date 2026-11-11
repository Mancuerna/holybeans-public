part of '../journal_repository.dart';

extension CuppingOperations on JournalRepository {
  Future<CuppingShareData> cuppingShareData(String id) =>
      cupping.cuppingShareData(id);
  Future<
    ({
      List<Coffee> coffees,
      List<CoffeeLot> lots,
      List<FrozenPortion> portions,
      List<Grinder> grinders,
      List<WaterProfile> waters,
    })
  >
  cuppingCatalog() => cupping.cuppingCatalog();
  Stream<List<CuppingSession>> watchCuppingSessions() =>
      cupping.watchCuppingSessions();
  Future<CuppingSession?> cuppingSession(String id) =>
      cupping.cuppingSession(id);
  Future<List<CuppingSessionCup>> cuppingCups(String id) =>
      cupping.cuppingCups(id);
  Future<String> createCuppingSession(CuppingDraft draft) =>
      cupping.createCuppingSession(draft);
  Future<void> saveCuppingDraft(String id, CuppingDraft draft) =>
      cupping.saveCuppingDraft(id, draft);

  /// Discards only an unfinished session; no brew or inventory was created.
  Future<void> discardCuppingDraft(String id) =>
      cupping.discardCuppingDraft(id);

  /// Finishing is idempotent and atomic, including thawing and repeated cups.
  Future<List<String>> finishCupping(String id, CuppingDraft draft) =>
      cupping.finishCupping(id, draft);
  Future<void> validateCuppingSetup(CuppingDraft draft) =>
      cupping.validateCuppingSetup(draft);
}

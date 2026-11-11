part of '../journal_repository.dart';

extension BeanconquerorImport on JournalRepository {
  static const source = BeanconquerorRepository.source;

  /// What an import has to know about the journal: previous imports,
  /// catalog names and freezer labels.
  Future<BqJournal> beanconquerorJournal() =>
      beanconqueror.beanconquerorJournal();

  /// Writes [plan] in one transaction. [photos] maps BeanConqueror photo
  /// file names to the names they were stored under; references to
  /// missing photos are left out.
  Future<BqImportSummary> importBeanconqueror(
    BqImportPlan plan, {
    Map<String, String> photos = const {},
    Map<String, ShotCurve> curves = const {},
  }) => beanconqueror.importBeanconqueror(plan, photos: photos, curves: curves);
}

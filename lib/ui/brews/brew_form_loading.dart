part of 'brew_form_model.dart';

/// Coordinates retries across the form-owned catalog and tool notifiers.
extension BrewFormLoading on BrewFormModel {
  Future<void> _loadProfileSuggestions() => catalogs.loadProfileSuggestions();
  Future<void> _loadSavedTools() => toolSelection.loadSaved();
  Future<void> _loadLots(String id, {String? preferred}) =>
      catalogs.loadLots(id, preferred: preferred);
  Future<void> _loadTools(
    String id, {
    Iterable<String> preferredIds = const [],
  }) => toolSelection.load(id, preferredIds: preferredIds);
  Future<void> retryLoads() async {
    if (_retrying || _disposed) return;
    _retrying = true;
    _notify();
    try {
      await catalogs.restart();
      if (_disposed) return;
      if (!savedToolsLoaded) await _loadSavedTools();
      if (_disposed) return;
      if (coffeeId case final coffee? when catalogs.lotsFailed) {
        catalogs.prepareLots();
        await _loadLots(
          coffee,
          preferred: lotId ?? existing?.lotId ?? seed?.lotId,
        );
      }
      if (_disposed) return;
      if (methodId case final method?) {
        await _loadTools(method, preferredIds: selectedToolIds.toList());
      }
    } finally {
      _retrying = false;
      _notify();
    }
  }
}

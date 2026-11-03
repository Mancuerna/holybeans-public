part of 'brew_form_model.dart';

/// Loads selections without treating failed reads as empty user choices.
extension BrewFormLoading on BrewFormModel {
  Future<void> _loadProfileSuggestions() async {
    try {
      final profiles = await repository.profileSuggestions();
      if (_disposed) return;
      _profiles = profiles;
      _notify();
    } catch (error, stack) {
      // Suggestions are optional: a failed read must not block free text/save.
      reportError(error, stack);
    }
  }

  /// Selects the tools saved with the brew edited or repeated.
  Future<void> _loadSavedTools() async {
    final selectedBrew = existing ?? (repeat ? seed : null);
    if (selectedBrew == null) {
      savedToolsLoaded = true;
      return;
    }
    final edit = _toolsEdit;
    final selectedMethod = methodId;
    List<String> ids;
    try {
      ids = await repository.brewToolIds(selectedBrew.id);
    } catch (error, stack) {
      reportError(error, stack);
      if (!_disposed) {
        _loadErrors.add('savedTools');
        _notify();
      }
      return;
    }
    if (_disposed) return;
    savedToolsLoaded = true;
    _loadErrors.remove('savedTools');
    if (edit == _toolsEdit && selectedMethod == methodId && !_toolsTouched) {
      selectedToolIds
        ..clear()
        ..addAll(ids);
      if (methodId case final method?) {
        unawaited(_loadTools(method, preferredIds: ids.toSet()));
      }
    }
    _notify();
  }

  Future<void> _loadLots(String selectedCoffeeId, {String? preferred}) async {
    final request = ++_lotRequest;
    _loadErrors.remove('lots');
    List<CoffeeLot> rows;
    try {
      rows = await repository.coffeeLots(selectedCoffeeId);
    } catch (error, stack) {
      reportError(error, stack);
      if (_disposed || request != _lotRequest) return;
      _loadErrors.add('lots');
      loadingLots = false;
      _notify();
      return;
    }
    if (_disposed || request != _lotRequest) return;
    lots = rows;
    lotId = rows.any((lot) => lot.id == preferred)
        ? preferred
        : rows.firstOrNull?.id;
    loadingLots = false;
    _notify();
  }

  Future<void> _loadTools(
    String selectedMethodId, {
    Iterable<String> preferredIds = const [],
  }) async {
    final request = ++_toolRequest;
    _loadErrors.remove('tools');
    final toolsEdit = _toolsEdit;
    loadingTools = true;
    _notify();
    try {
      final catalog = await repository.toolCatalog();
      final retained = existing?.methodId == selectedMethodId
          ? await repository.brewToolIds(existing!.id)
          : const <String>[];
      final rows = catalog.forMethod(selectedMethodId, retainedIds: retained);
      if (_disposed || request != _toolRequest) return;
      final availableIds = rows.map((tool) => tool.id).toSet();
      tools = rows;
      toolUseCounts = catalog.useCounts;
      selectedToolIds
        ..removeWhere((id) => !availableIds.contains(id))
        ..addAll(
          toolsEdit == _toolsEdit
              ? preferredIds.where(availableIds.contains)
              : const <String>[],
        );
    } catch (error, stack) {
      reportError(error, stack);
      if (_disposed || request != _toolRequest) return;
      _loadErrors.add('tools');
    }
    loadingTools = false;
    _notify();
  }

  Future<void> retryLoads() async {
    if (_retrying || _disposed) return;
    _retrying = true;
    _notify();
    try {
      for (final subscription in _catalogSubscriptions) {
        await subscription.cancel();
      }
      _catalogSubscriptions.clear();
      if (_disposed) return;
      loadingMethods = loadingGrinders = loadingWaterProfiles =
          loadingRecipients = true;
      _watchCatalogs();
      if (!savedToolsLoaded) await _loadSavedTools();
      if (_disposed) return;
      if (coffeeId case final coffee? when _loadErrors.contains('lots')) {
        loadingLots = true;
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

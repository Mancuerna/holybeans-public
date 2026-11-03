part of 'brew_form_model.dart';

/// The method, grinder and water catalogs the form chooses from: kept in
/// step with the journal, keeping the choice of the brew edited or repeated,
/// and extended with what is created from the form.
extension BrewFormCatalogs on BrewFormModel {
  void _watchCatalogs() {
    _watch('recipients', repository.watchRecipients(includeArchived: true), (
      rows,
    ) {
      recipients = rows;
      loadingRecipients = false;
      if (existing == null &&
          recipient != null &&
          rows.any((r) => r.id == recipient!.id && r.archivedAtMs != null)) {
        recipient = null;
        _recipientChosen = false;
      }
      _defaultRecipient();
      _notify();
    }, onError: () => loadingRecipients = false);
    _watch(
      'methods',
      repository.watchMethods(includeArchived: true),
      _methodsChanged,
      onError: () => loadingMethods = false,
    );
    _watch(
      'grinders',
      repository.watchGrinders(includeArchived: true),
      _grindersChanged,
      onError: () => loadingGrinders = false,
    );
    _watch(
      'water',
      repository.watchWaterProfiles(includeArchived: true),
      _waterProfilesChanged,
      onError: () => loadingWaterProfiles = false,
    );
  }

  /// Listens to [stream] until disposed, notifying after an error too.
  void _watch<T>(
    String key,
    Stream<T> stream,
    void Function(T rows) onData, {
    required VoidCallback onError,
  }) => _catalogSubscriptions.add(
    stream.listen(
      (rows) {
        if (_disposed) return;
        _loadErrors.remove(key);
        onData(rows);
      },
      onError: (Object error, StackTrace stack) {
        reportError(error, stack);
        if (_disposed) return;
        _loadErrors.add(key);
        onError();
        _notify();
      },
    ),
  );

  void _methodsChanged(List<BrewMethod> rows) {
    methods = rows;
    loadingMethods = false;
    if (!rows.any((row) => row.id == methodId)) {
      final name = existing?.methodName ?? seed?.methodName;
      methodId = rows.where((row) => row.name == name).firstOrNull?.id;
    }
    _defaultRecipient();
    _notify();
    if (methodId case final method? when savedToolsLoaded) {
      _loadTools(method, preferredIds: selectedToolIds);
    }
  }

  void _grindersChanged(List<Grinder> rows) {
    grinders = rows;
    loadingGrinders = false;
    if (!isPreGround &&
        !grinderTouched &&
        !rows.any((row) => row.id == grinderId)) {
      final name = existing?.grinderName ?? seed?.grinderName;
      grinderId = rows.where((row) => row.name == name).firstOrNull?.id;
    }
    _notify();
  }

  void _waterProfilesChanged(List<WaterProfile> rows) {
    final repeatedId = repeat ? seed?.waterProfileId : null;
    waterProfiles = rows;
    loadingWaterProfiles = false;
    // A repeated brew does not bring back an archived water, and a deleted
    // one is dropped.
    final current = rows.where((row) => row.id == waterProfileId).firstOrNull;
    if (waterProfileId != null &&
        (current == null ||
            (waterProfileId == repeatedId && current.archivedAtMs != null))) {
      waterProfileId = null;
    }
    _notify();
  }

  List<T> _inserted<T>(
    List<T> rows,
    T row,
    String Function(T) id,
    String Function(T) name,
  ) =>
      [...rows.where((other) => id(other) != id(row)), row]
        ..sort((a, b) => name(a).compareTo(name(b)));

  /// Adds a method just created from the form and selects it.
  Future<void> methodCreated(BrewMethod method) async {
    methods = _inserted(methods, method, (row) => row.id, (row) => row.name);
    _notify();
    await selectMethod(method.id);
  }

  /// Adds a grinder just created from the form and selects it.
  void grinderCreated(Grinder grinder) {
    grinders = _inserted(grinders, grinder, (row) => row.id, (row) => row.name);
    grinderId = grinder.id;
    isPreGround = false;
    grinderTouched = true;
    _notify();
  }

  /// Adds a water profile just created from the form and selects it.
  void waterProfileCreated(WaterProfile profile) {
    waterProfiles = _inserted(
      waterProfiles,
      profile,
      (row) => row.id,
      (row) => row.name,
    );
    waterProfileId = profile.id;
    _notify();
  }
}

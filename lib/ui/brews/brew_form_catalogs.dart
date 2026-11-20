part of 'brew_form_model.dart';

/// Reconciles the form choices after its independent catalog changes.
extension BrewFormCatalogs on BrewFormModel {
  Future<void> selectMethod(String? id) async {
    if (id == null || id == methodId) return;
    selectedPreset = null;
    importedGaggimateShot = null;
    importedShot = null;
    importedFreePour = null;
    methodId = id;
    _repeatedRecipientId = null;
    _recipientChosen = false;
    _defaultRecipient();
    draft.jugTotal.clear();
    toolSelection.resetForMethod();
    draft.applyTare(jugGrams);
    toolSelection.publish();
    if (isNew) unawaited(_loadDialIn());
    if (_fresh) {
      await _applyMethodMemory(id);
    } else {
      await _loadTools(id);
    }
  }

  void _applyPresetEquipment(PresetDetails details) {
    selectedPreset = details;
    isPreGround = false;
    grinderTouched = true;
    grinderId = details.preset.grinderId;
    _waterTouched = true;
    waterProfileId = details.preset.waterProfileId;
    toolSelection.replace(details.toolIds);
  }

  void selectPreset(PresetDetails? details) {
    if (details == null) {
      selectedPreset = null;
      _notify();
      return;
    }
    // selectMethod synchronously resets the old method before loading memory.
    unawaited(selectMethod(details.preset.methodId));
    _applyPresetEquipment(details);
    unawaited(
      _loadTools(details.preset.methodId, preferredIds: details.toolIds),
    );
    _notify();
  }

  void _watchPresets() {
    if (_fresh) {
      _subscriptions.add(
        repository.presets.watch().listen(
          (rows) {
            presetChoices = rows.where((p) => p.available).toList();
            presetsFailed = false;
            _notify();
          },
          onError: (Object error, StackTrace stack) {
            reportError(error, stack);
            presetsFailed = true;
            _notify();
          },
        ),
      );
    }
  }

  void _watchCatalogs() => catalogs.watch();

  void _recipientsChanged(List<Recipient> rows) {
    if (_repeatedRecipientId != null) {
      // Repeat starts a new brew with today's catalog weight, not its seed's tare.
      recipient = rows
          .where(
            (r) =>
                r.id == _repeatedRecipientId &&
                r.isPortafilter == seed?.recipientIsPortafilter &&
                r.archivedAtMs == null,
          )
          .firstOrNull;
      _repeatedRecipientId = null;
      _recipientChosen = recipient != null;
    }
    if (existing == null &&
        recipient != null &&
        rows.any((r) => r.id == recipient!.id && r.archivedAtMs != null)) {
      recipient = null;
      _recipientChosen = false;
    }
    _defaultRecipient();
  }

  void _methodsChanged(List<BrewMethod> rows) {
    if (!rows.any((row) => row.id == methodId)) {
      final name = existing?.methodName ?? seed?.methodName;
      methodId = rows.where((row) => row.name == name).firstOrNull?.id;
    }
    _defaultRecipient();
  }

  void _grindersChanged(List<Grinder> rows) {
    if (!isPreGround &&
        !grinderTouched &&
        !rows.any((row) => row.id == grinderId)) {
      final name = existing?.grinderName ?? seed?.grinderName;
      grinderId = rows.where((row) => row.name == name).firstOrNull?.id;
    }
  }

  void _waterProfilesChanged(List<WaterProfile> rows) {
    if (_fresh && !_waterTouched) {
      waterProfileId = _recipes.memory?.brew.waterProfileId;
    }
    final current = rows.where((row) => row.id == waterProfileId).firstOrNull;
    if (waterProfileId != null &&
        (current == null ||
            (waterProfileId != existing?.waterProfileId &&
                current.archivedAtMs != null))) {
      waterProfileId = null;
    }
  }

  Future<void> methodCreated(BrewMethod method) async {
    catalogs.insertMethod(method);
    catalogs.publish();
    await selectMethod(method.id);
  }

  void grinderCreated(Grinder grinder) {
    catalogs.insertGrinder(grinder);
    selectedPreset = null;
    grinderId = grinder.id;
    isPreGround = false;
    grinderTouched = true;
    catalogs.publish();
  }

  void waterProfileCreated(WaterProfile profile) {
    catalogs.insertWaterProfile(profile);
    selectedPreset = null;
    _waterTouched = true;
    waterProfileId = profile.id;
    catalogs.publish();
  }
}

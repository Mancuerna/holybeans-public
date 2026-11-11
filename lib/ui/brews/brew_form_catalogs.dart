part of 'brew_form_model.dart';

/// Reconciles the form choices after its independent catalog changes.
extension BrewFormCatalogs on BrewFormModel {
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
    final repeatedId = repeat ? seed?.waterProfileId : null;
    // A repeated brew does not bring back an archived water, and a deleted
    // one is dropped.
    final current = rows.where((row) => row.id == waterProfileId).firstOrNull;
    if (waterProfileId != null &&
        (current == null ||
            (waterProfileId == repeatedId && current.archivedAtMs != null))) {
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
    grinderId = grinder.id;
    isPreGround = false;
    grinderTouched = true;
    catalogs.publish();
  }

  void waterProfileCreated(WaterProfile profile) {
    catalogs.insertWaterProfile(profile);
    waterProfileId = profile.id;
    catalogs.publish();
  }
}

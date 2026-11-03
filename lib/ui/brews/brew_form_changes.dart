import 'dart:convert';

import 'package:holybeans/ui/brews/brew_form_model.dart';

class BrewFormChanges {
  BrewFormChanges(this.model) : _initial = _snapshot(model);

  final BrewFormModel model;
  String _initial;
  bool _ready = false;
  bool _interacted = false;

  bool get ready =>
      !model.loadingRecipients &&
      !model.loadingLots &&
      !model.loadingMethods &&
      !model.loadingGrinders &&
      !model.loadingWaterProfiles &&
      !model.loadingTools &&
      model.savedToolsLoaded &&
      !model.loadingMemory;

  // A touch before catalogue/memory loading finishes prevents later baseline
  // capture from treating user-entered values as automatic defaults.
  void interacted() => _interacted = true;

  void settleInitial() {
    if (!_ready && ready) {
      _ready = true;
      if (!_interacted) _initial = _snapshot(model);
    }
  }

  bool get changed =>
      model.timer.running ||
      model.devices.curve != null ||
      model.importedShot != null ||
      model.importedGaggimateShot != null ||
      model.importedFreePour != null ||
      _snapshot(model) != _initial;

  static String _snapshot(BrewFormModel model) => jsonEncode([
    for (final field in model.draft.fields) field.text,
    model.coffeeId,
    model.lotId,
    model.methodId,
    model.grinderId,
    model.isPreGround,
    model.waterProfileId,
    model.recipient?.id,
    model.recipient?.name,
    model.recipient?.emptyGrams,
    model.selectedToolIds.toList()..sort(),
    model.brewedAt.toIso8601String(),
    model.rating,
    model.photoDraft.current,
    model.draft.pours.editState,
  ]);
}

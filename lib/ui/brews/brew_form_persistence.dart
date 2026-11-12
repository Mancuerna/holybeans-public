import 'package:flutter/widgets.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/meticulous_client.dart';
import 'package:holybeans/data/services/meticulous_free_pour.dart';
import 'package:holybeans/domain/brew_input.dart';
import 'package:holybeans/domain/brew_pours.dart';
import 'package:holybeans/domain/frozen_brew.dart';
import 'package:holybeans/domain/gaggimate/shot.dart';
import 'package:holybeans/domain/recipient_snapshot.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/ui/brews/brew_draft.dart';
import 'package:holybeans/ui/core/form_widgets.dart';
import 'package:holybeans/ui/core/photos_draft.dart';

/// Maps a form snapshot to one repository save, then cleans unused photos.
class BrewFormPersistence {
  BrewFormPersistence(this.repository, this.draft, this.photoDraft);

  final JournalRepository repository;
  final BrewDraft draft;
  final PhotosDraft photoDraft;

  Future<BrewSaveOutcome> save({
    String? id,
    required String coffeeId,
    String? lotId,
    FrozenBrewSource? frozenSource,
    required BrewMethod method,
    Grinder? grinder,
    String? grinderName,
    String? waterProfileId,
    RecipientSnapshot? recipient,
    required bool isPreGround,
    required List<String> toolIds,
    required bool espresso,
    required bool grinderHasRpm,
    double? rating,
    required DateTime brewedAt,
    MeticulousShot? shot,
    GaggimateShot? gaggimateShot,
    MeticulousFreePour? freePour,
    ShotCurve? curve,
    String? extractionProfileJson,
  }) async {
    int? integer(TextEditingController field) =>
        int.tryParse(field.text.trim());
    final hasCurve =
        curve != null ||
        freePour?.curve != null ||
        !espresso &&
            draft.pours.waterPlanUsed &&
            id != null &&
            await repository.brewCurve(id) != null;
    final pours = espresso
        ? BrewPours()
        : draft.pours.valueForSave(
            dose: parseNumber(draft.dose.text),
            water: parseNumber(draft.water.text),
            hasCurve: hasCurve,
          );
    final outcome = await repository.saveBrewWithOutcome(
      BrewInput(
        coffeeId: coffeeId,
        lotId: lotId,
        frozenSource: frozenSource,
        methodId: method.id,
        methodName: method.name,
        grinderId: grinder?.id,
        grinderName: grinderName,
        waterProfileId: waterProfileId,
        recipient: recipient,
        replaceRecipient: true,
        isPreGround: isPreGround,
        grindSetting: isPreGround ? null : draft.grindSetting.text,
        methodToolIds: toolIds,
        doseGrams: parseNumber(draft.dose.text),
        waterGrams: espresso ? null : parseNumber(draft.water.text),
        temperatureC: parseNumber(draft.temperature.text),
        beverageGrams: parseNumber(draft.beverage.text),
        timeSeconds: draft.timeSeconds,
        tdsPercent: draft.effectiveTds,
        brix: draft.brixMode ? parseNumber(draft.brix.text) : null,
        brixFactor: draft.brixMode && parseNumber(draft.brix.text) != null
            ? parseNumber(draft.brixFactor.text)
            : null,
        feederRpm: !isPreGround && grinder?.hasAdjustableFeederRpm == true
            ? integer(draft.feederRpm)
            : null,
        grindRpm: grinderHasRpm ? integer(draft.grindRpm) : null,
        pressureBar: espresso ? parseNumber(draft.pressure.text) : null,
        preinfusionSeconds: espresso ? integer(draft.preinfusion) : null,
        bloomSeconds: espresso || draft.pours.bloomCount == 0
            ? null
            : integer(draft.bloom),
        pours: pours,
        firstDripSeconds: espresso ? integer(draft.firstDrip) : null,
        rating: rating,
        notes: draft.notes.text,
        profileName: draft.profile.text,
        extractionProfileJson: espresso ? extractionProfileJson : null,
        replaceExtractionProfile: true,
        brewedAt: brewedAt,
      ),
      id: id,
      shot: espresso ? shot : null,
      gaggimateShot: espresso ? gaggimateShot : null,
      freePour: espresso ? null : freePour,
      curve: curve,
      photos: photoDraft.changed ? photoDraft.current : null,
    );
    await photoDraft.commit();
    return outcome;
  }
}

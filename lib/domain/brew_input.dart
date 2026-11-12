import 'package:holybeans/domain/brew_pours.dart';
import 'package:holybeans/domain/brix.dart';
import 'package:holybeans/domain/extraction_profile.dart';
import 'package:holybeans/domain/frozen_brew.dart';
import 'package:holybeans/domain/recipient_snapshot.dart';

/// Immutable recipe and selection submitted to the journal.
///
/// Validates values without storage. The repository checks references and stock
/// inside the same transaction that writes the brew.
class BrewInput {
  BrewInput({
    required this.coffeeId,
    required this.methodName,
    this.lotId,
    this.methodId,
    this.grinderName,
    this.grinderId,
    this.waterProfileId,
    this.recipient,
    this.replaceRecipient = false,
    this.isPreGround = false,
    this.grindSetting,
    List<String>? methodToolIds,
    this.doseGrams,
    this.frozenSource,
    this.waterGrams,
    this.beverageGrams,
    this.timeSeconds,
    this.temperatureC,
    this.tdsPercent,
    this.brix,
    this.brixFactor,
    this.grindRpm,
    this.feederRpm,
    this.pressureBar,
    this.preinfusionSeconds,
    this.bloomSeconds,
    this.pours,
    this.firstDripSeconds,
    this.rating,
    this.notes,
    this.profileName,
    this.extractionProfileJson,
    this.replaceExtractionProfile = false,
    this.brewedAt,
  }) : methodToolIds = methodToolIds == null
           ? null
           : List.unmodifiable(methodToolIds);

  final String coffeeId;
  final String methodName;
  final String? lotId;
  final String? methodId;
  final String? grinderName;
  final String? grinderId;
  final String? waterProfileId;
  final RecipientSnapshot? recipient;
  final bool replaceRecipient;
  final bool isPreGround;
  final String? grindSetting;
  final List<String>? methodToolIds;
  final double? doseGrams;
  final FrozenBrewSource? frozenSource;
  final double? waterGrams;
  final double? beverageGrams;
  final int? timeSeconds;
  final double? temperatureC;
  final double? tdsPercent;
  final double? brix;
  final double? brixFactor;
  final int? grindRpm;
  final int? feederRpm;
  final double? pressureBar;
  final int? preinfusionSeconds;
  final int? bloomSeconds;
  final BrewPours? pours;
  final int? firstDripSeconds;
  final double? rating;
  final String? notes;
  final String? profileName;
  final String? extractionProfileJson;
  final bool replaceExtractionProfile;
  final DateTime? brewedAt;

  /// Rejects invalid recipe values before any writes take place.
  void validate() {
    recipient?.validate();
    if (extractionProfileJson case final source?) {
      ExtractionProfile.decode(source);
    }
    final timeSeconds = this.timeSeconds;
    final temperatureC = this.temperatureC;
    final tdsPercent = this.tdsPercent;
    final pressureBar = this.pressureBar;
    final cleanMethod = methodName.trim();
    if (cleanMethod.isEmpty) {
      throw ArgumentError.value(methodName, 'methodName');
    }
    _checkPositive(doseGrams, 'doseGrams');
    _checkPositive(waterGrams, 'waterGrams');
    _checkPositive(beverageGrams, 'beverageGrams');
    if (timeSeconds != null && timeSeconds <= 0) {
      throw ArgumentError.value(timeSeconds, 'timeSeconds');
    }
    if (isPreGround &&
        (grinderId != null || (grinderName?.trim().isNotEmpty ?? false))) {
      throw ArgumentError(
        'A pre-ground brew cannot reference a grinder',
        'grinderId/grinderName',
      );
    }
    if (temperatureC != null && !temperatureC.isFinite) {
      throw ArgumentError.value(temperatureC, 'temperatureC');
    }
    if (tdsPercent != null &&
        (!tdsPercent.isFinite || tdsPercent <= 0 || tdsPercent > 100)) {
      throw ArgumentError.value(tdsPercent, 'tdsPercent');
    }
    if (brix != null || brixFactor != null) {
      final computed = brixToTds(brix, brixFactor);
      if (computed == null ||
          tdsPercent == null ||
          (computed - tdsPercent).abs() > 0.000001) {
        throw ArgumentError(
          'Brix requires a valid coefficient and matching TDS',
        );
      }
    }
    pours?.validate();
    final rating = this.rating;
    if (rating != null) {
      final doubled = rating * 2;
      if (!rating.isFinite ||
          rating < 0 ||
          rating > 10 ||
          (doubled - doubled.round()).abs() > 0.000001) {
        throw ArgumentError.value(rating, 'rating');
      }
    }
    for (final (value, name) in [
      (grindRpm, 'grindRpm'),
      (feederRpm, 'feederRpm'),
      (preinfusionSeconds, 'preinfusionSeconds'),
      (bloomSeconds, 'bloomSeconds'),
      (firstDripSeconds, 'firstDripSeconds'),
    ]) {
      if (value != null && value <= 0) throw ArgumentError.value(value, name);
    }
    if (pressureBar != null &&
        (!pressureBar.isFinite || pressureBar < 0 || pressureBar > 30)) {
      throw ArgumentError.value(pressureBar, 'pressureBar');
    }
  }
}

void _checkPositive(double? value, String field) {
  if (value != null && (!value.isFinite || value <= 0)) {
    throw ArgumentError.value(value, field);
  }
}

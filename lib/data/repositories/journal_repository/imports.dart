part of '../journal_repository.dart';

extension ImportOperations on JournalRepository {
  static const meticulousSource = RecordingRepository.meticulousSource;
  static const gaggimateSource = RecordingRepository.gaggimateSource;
  static const meticulousFreePourSource =
      RecordingRepository.meticulousFreePourSource;
  static const scaleSource = RecordingRepository.scaleSource;
  Future<Set<String>> importedGaggimateShots() =>
      recordings.importedGaggimateShots();
  Future<void> attachGaggimateShot(String brewId, GaggimateShot shot) =>
      recordings.attachGaggimateShot(brewId, shot);

  /// IDs of the Meticulous shots already saved with a brew. A brew that
  /// was given another shot only counts its latest one.
  Future<Set<String>> importedMeticulousShots() =>
      recordings.importedMeticulousShots();

  /// IDs of the Meticulous free pours already saved with a brew.
  Future<Set<String>> importedMeticulousFreePours() =>
      recordings.importedMeticulousFreePours();

  /// Links [brewId] to the Meticulous [shot] it was filled from and keeps
  /// the shot's curve with it. Importing the same shot again moves the
  /// link to the new brew, and a brew given another shot drops the old one.
  Future<void> attachMeticulousShot(String brewId, MeticulousShot shot) =>
      recordings.attachMeticulousShot(brewId, shot);

  /// Like [attachMeticulousShot], for a free pour on the machine's scale.
  Future<void> attachMeticulousFreePour(
    String brewId,
    MeticulousFreePour pour,
  ) => recordings.attachMeticulousFreePour(brewId, pour);

  /// Keeps the weight [curve] a scale recorded during [brewId], replacing
  /// any curve the brew had.
  Future<void> saveScaleCurve(String brewId, ShotCurve curve) =>
      recordings.saveScaleCurve(brewId, curve);

  /// The curve recorded with [brewId] and where it came from
  /// ([meticulousSource] or [scaleSource]), if any.
  Future<({ShotCurve curve, String source})?> brewCurve(String brewId) =>
      recordings.brewCurve(brewId);

  /// Read-only pressure references, newest first; invalid curves are excluded.
  Future<List<({Brew brew, PressureGuide guide})>> pressureReferences() =>
      recordings.pressureReferences();
  Future<List<({Brew brew, FlowGuide guide})>> flowReferences() =>
      recordings.flowReferences();

  /// Records the blooms, pours and total bloom time found on [brewId]'s curve.
  ///
  /// Like marking a favourite, it does not change the brew's edit timestamp.
  Future<void> setBrewPours(String brewId, BrewPours pours) =>
      recordings.setBrewPours(brewId, pours);

  /// Filter brews with a curve and no bloom or pour details yet, with what
  /// their curves show (see [brewPoursFromCurve]): counts already recorded, typed
  /// or copied from a repeated brew, are kept, and one the curve disagrees
  /// with is left alone.
  Future<List<({Brew brew, BrewPours pours})>> poursFromCurves() =>
      recordings.poursFromCurves();

  /// Saves [found] (from [poursFromCurves]) in one go.
  Future<void> savePoursFromCurves(
    List<({Brew brew, BrewPours pours})> found,
  ) => recordings.savePoursFromCurves(found);
}

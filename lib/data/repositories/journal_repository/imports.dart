part of '../journal_repository.dart';

/// Curves recorded by connected devices: shots from a machine, with the
/// record of which shot each came from so the shot list can mark it, and
/// weights from a scale.
extension ImportOperations on JournalRepository {
  static const meticulousSource = 'meticulous';
  static const gaggimateSource = 'gaggimate';

  Future<Set<String>> importedGaggimateShots() =>
      _imported(_shotKind, source: gaggimateSource);

  Future<void> attachGaggimateShot(String brewId, GaggimateShot shot) =>
      _attachMachineRecording(
        brewId,
        source: gaggimateSource,
        kind: _shotKind,
        externalId: shot.externalId,
        brewedAt: shot.brewedAt,
        curve: shot.curve,
        curveSource: gaggimateSource,
      );

  /// A free pour on the Meticulous's scale: its flow is weighed (g/s), not
  /// the pump's (ml/s).
  static const meticulousFreePourSource = 'meticulous_free_pour';
  static const scaleSource = 'scale';
  static const _shotKind = 'shot';
  static const _freePourKind = 'free_pour';

  /// IDs of the Meticulous shots already saved with a brew. A brew that
  /// was given another shot only counts its latest one.
  Future<Set<String>> importedMeticulousShots() => _imported(_shotKind);

  /// IDs of the Meticulous free pours already saved with a brew.
  Future<Set<String>> importedMeticulousFreePours() => _imported(_freePourKind);

  Future<Set<String>> _imported(
    String kind, {
    String source = meticulousSource,
  }) async {
    final records = await (database.select(
      database.importRecords,
    )..where((row) => row.source.equals(source) & row.kind.equals(kind))).get();
    final latestByBrew = <String, ImportRecord>{};
    final unlinked = <String>{};
    for (final record in records) {
      final brewId = record.localId;
      if (brewId == null) {
        unlinked.add(record.externalId);
        continue;
      }
      final latest = latestByBrew[brewId];
      if (latest == null || record.importedAtMs > latest.importedAtMs) {
        latestByBrew[brewId] = record;
      }
    }
    return {
      ...unlinked,
      for (final record in latestByBrew.values) record.externalId,
    };
  }

  /// Links [brewId] to the Meticulous [shot] it was filled from and keeps
  /// the shot's curve with it. Importing the same shot again moves the
  /// link to the new brew, and a brew given another shot drops the old one.
  Future<void> attachMeticulousShot(String brewId, MeticulousShot shot) =>
      _attachMachineRecording(
        brewId,
        kind: _shotKind,
        externalId: shot.id,
        brewedAt: shot.brewedAt,
        curve: shot.curve,
        curveSource: meticulousSource,
      );

  /// Like [attachMeticulousShot], for a free pour on the machine's scale.
  Future<void> attachMeticulousFreePour(
    String brewId,
    MeticulousFreePour pour,
  ) => _attachMachineRecording(
    brewId,
    kind: _freePourKind,
    externalId: pour.id,
    brewedAt: pour.brewedAt,
    curve: pour.curve,
    curveSource: meticulousFreePourSource,
  );

  Future<void> _attachMachineRecording(
    String brewId, {
    required String kind,
    required String externalId,
    required DateTime brewedAt,
    required ShotCurve? curve,
    required String curveSource,
    String source = meticulousSource,
  }) => database.transaction(() async {
    final brew = await (database.select(
      database.brews,
    )..where((row) => row.id.equals(brewId))).getSingleOrNull();
    if (brew == null) throw StateError('Brew not found');
    if (curve != null && !curve.isEmpty) {
      await database
          .into(database.brewCurves)
          .insertOnConflictUpdate(
            BrewCurvesCompanion.insert(
              brewId: brewId,
              source: curveSource,
              samplesJson: curve.toJson(),
            ),
          );
    }
    if (curve == null || curve.isEmpty) {
      await (database.delete(
        database.brewCurves,
      )..where((r) => r.brewId.equals(brewId))).go();
    }
    await (database.delete(database.importRecords)..where(
          (row) =>
              (row.source.equals(source) &
                  row.kind.equals(kind) &
                  row.externalId.equals(externalId)) |
              (row.source.isIn([meticulousSource, gaggimateSource]) &
                  row.localEntity.equals('brew') &
                  row.localId.equals(brewId)),
        ))
        .go();
    await database
        .into(database.importRecords)
        .insert(
          ImportRecordsCompanion.insert(
            id: _uuid.v4(),
            source: source,
            kind: kind,
            externalId: externalId,
            fingerprint: '${brewedAt.millisecondsSinceEpoch}',
            localEntity: const Value('brew'),
            localId: Value(brewId),
            importedAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
          ),
        );
  });

  /// Keeps the weight [curve] a scale recorded during [brewId], replacing
  /// any curve the brew had.
  Future<void> saveScaleCurve(String brewId, ShotCurve curve) async {
    if (curve.isEmpty) return;
    await database
        .into(database.brewCurves)
        .insertOnConflictUpdate(
          BrewCurvesCompanion.insert(
            brewId: brewId,
            source: scaleSource,
            samplesJson: curve.toJson(),
          ),
        );
  }

  /// The curve recorded with [brewId] and where it came from
  /// ([meticulousSource] or [scaleSource]), if any.
  Future<({ShotCurve curve, String source})?> brewCurve(String brewId) async {
    final row = await (database.select(
      database.brewCurves,
    )..where((curve) => curve.brewId.equals(brewId))).getSingleOrNull();
    if (row == null) return null;
    try {
      return (curve: ShotCurve.fromJson(row.samplesJson), source: row.source);
    } on FormatException {
      return null;
    }
  }

  /// Read-only pressure references, newest first; invalid curves are excluded.
  Future<List<({Brew brew, PressureGuide guide})>> pressureReferences() =>
      _guideReferences(PressureGuide.fromCurve);

  Future<List<({Brew brew, FlowGuide guide})>> flowReferences() =>
      _guideReferences(FlowGuide.fromCurve);

  Future<List<({Brew brew, T guide})>> _guideReferences<T>(
    T? Function(ShotCurve) fromCurve,
  ) async {
    final methods = {
      for (final method in await allMethods()) method.id: method,
    };
    final query = database.select(database.brews).join([
      innerJoin(
        database.brewCurves,
        database.brewCurves.brewId.equalsExp(database.brews.id),
      ),
    ])..orderBy([OrderingTerm.desc(database.brews.brewedAtMs)]);
    final result = <({Brew brew, T guide})>[];
    for (final row in await query.get()) {
      final brew = row.readTable(database.brews);
      if (!isEspressoMethod(
        category: methods[brew.methodId]?.category,
        methodName: brew.methodName,
      )) {
        continue;
      }
      try {
        final guide = fromCurve(
          ShotCurve.fromJson(row.readTable(database.brewCurves).samplesJson),
        );
        if (guide != null) result.add((brew: brew, guide: guide));
      } on FormatException {
        continue;
      }
    }
    return result;
  }

  /// Records the blooms and pours of [brewId], as found on its curve. Like
  /// marking a favourite, it is not an edit of the brew.
  Future<void> setBrewPours(String brewId, BrewPours pours) async {
    pours.validate();
    final updated =
        await (database.update(
          database.brews,
        )..where((row) => row.id.equals(brewId))).write(
          BrewsCompanion(
            bloomCount: Value(pours.bloomCount),
            pourCount: Value(pours.pourCount),
            pourPhasesJson: Value(pours.phasesJson),
          ),
        );
    if (updated == 0) throw StateError('Brew not found');
  }

  /// Filter brews with a curve and no bloom or pour details yet, with what
  /// their curves show (see [poursToFill]): counts already recorded, typed
  /// or copied from a repeated brew, are kept, and one the curve disagrees
  /// with is left alone.
  Future<List<({Brew brew, BrewPours pours})>> poursFromCurves() async {
    final methods = {
      for (final method in await database.select(database.brewMethods).get())
        method.id: method,
    };
    final query = database.select(database.brews).join([
      innerJoin(
        database.brewCurves,
        database.brewCurves.brewId.equalsExp(database.brews.id),
      ),
    ])..where(database.brews.pourPhasesJson.isNull());
    final found = <({Brew brew, BrewPours pours})>[];
    for (final row in await query.get()) {
      final brew = row.readTable(database.brews);
      if (isEspressoMethod(
        category: methods[brew.methodId]?.category,
        methodName: brew.methodName,
      )) {
        continue;
      }
      final ShotCurve curve;
      try {
        curve = ShotCurve.fromJson(
          row.readTable(database.brewCurves).samplesJson,
        );
      } on FormatException {
        continue;
      }
      if (poursToFill(
            curve,
            doseGrams: brew.doseGrams,
            bloomCount: brew.bloomCount,
            pourCount: brew.pourCount,
          )
          case final pours?) {
        found.add((brew: brew, pours: pours));
      }
    }
    return found;
  }

  /// Saves [found] (from [poursFromCurves]) in one go.
  Future<void> savePoursFromCurves(
    List<({Brew brew, BrewPours pours})> found,
  ) => database.transaction(() async {
    for (final (:brew, :pours) in found) {
      await setBrewPours(brew.id, pours);
    }
  });
}

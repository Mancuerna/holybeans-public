part of '../journal_repository.dart';

/// What an import from BeanConqueror added.
class BqImportSummary {
  const BqImportSummary({
    required this.coffees,
    required this.brews,
    required this.methods,
    required this.grinders,
    required this.waters,
    required this.photos,
    this.curves = 0,
    this.updated = 0,
  });

  final int coffees;
  final int brews;
  final int methods;
  final int grinders;
  final int waters;
  final int photos;
  final int curves;

  /// Beans and brews brought up to date with BeanConqueror.
  final int updated;
}

/// Importing a BeanConqueror export: every record keeps its BeanConqueror
/// ID and original JSON in `import_records` and `legacy_payloads`, so a
/// second import skips it and fields HolyBeans does not show are kept.
extension BeanconquerorImport on JournalRepository {
  static const source = 'beanconqueror';

  /// What an import has to know about the journal: previous imports,
  /// catalog names and freezer labels.
  Future<BqJournal> beanconquerorJournal() async {
    final records = await (database.select(
      database.importRecords,
    )..where((row) => row.source.equals(source))).get();
    final imported = <String, Map<String, String>>{};
    final fingerprints = <String, Map<String, String>>{};
    final importedAt = <String, int>{};
    for (final record in records) {
      imported.putIfAbsent(record.kind, () => {})[record.externalId] =
          record.localId ?? '';
      fingerprints.putIfAbsent(record.kind, () => {})[record.externalId] =
          record.fingerprint;
      if (record.localId case final id?) importedAt[id] = record.importedAtMs;
    }
    // Coffees and brews saved here after they were imported.
    Future<Set<String>> editedIds<T extends Table, D>(
      TableInfo<T, D> table,
      GeneratedColumn<String> id,
      GeneratedColumn<int> updatedAt,
    ) async {
      final rows = await (database.selectOnly(
        table,
      )..addColumns([id, updatedAt])).get();
      return {
        for (final row in rows)
          if (row.read(updatedAt)! >
              (importedAt[row.read(id)!] ?? row.read(updatedAt)!))
            row.read(id)!,
      };
    }

    Future<Map<String, String>> byName<T extends Table, D>(
      TableInfo<T, D> table,
      GeneratedColumn<String> id,
      GeneratedColumn<String> name,
    ) async {
      final rows = await (database.selectOnly(
        table,
      )..addColumns([id, name])).get();
      return {
        for (final row in rows)
          row.read(name)!.trim().toLowerCase(): row.read(id)!,
      };
    }

    Future<Set<String>> values<T extends Table, D>(
      TableInfo<T, D> table,
      GeneratedColumn<String> column,
    ) async => {
      for (final row in await (database.selectOnly(
        table,
        distinct: true,
      )..addColumns([column])).get())
        row.read(column)!,
    };

    return BqJournal(
      imported: imported,
      fingerprints: fingerprints,
      editedHere: {
        ...await editedIds(
          database.coffees,
          database.coffees.id,
          database.coffees.updatedAtMs,
        ),
        ...await editedIds(
          database.brews,
          database.brews.id,
          database.brews.updatedAtMs,
        ),
      },
      methodsByName: await byName(
        database.brewMethods,
        database.brewMethods.id,
        database.brewMethods.name,
      ),
      grindersByName: await byName(
        database.grinders,
        database.grinders.id,
        database.grinders.name,
      ),
      watersByName: await byName(
        database.waterProfiles,
        database.waterProfiles.id,
        database.waterProfiles.name,
      ),
      frozenLabels: await values(
        database.frozenPortions,
        database.frozenPortions.label,
      ),
      withCurves: await values(database.brewCurves, database.brewCurves.brewId),
      withPhotos: {
        ...await values(database.coffeePhotos, database.coffeePhotos.coffeeId),
        ...await values(database.brewPhotos, database.brewPhotos.brewId),
      },
    );
  }

  /// Writes [plan] in one transaction. [photos] maps BeanConqueror photo
  /// file names to the names they were stored under; references to
  /// missing photos are left out.
  Future<BqImportSummary> importBeanconqueror(
    BqImportPlan plan, {
    Map<String, String> photos = const {},
    Map<String, ShotCurve> curves = const {},
  }) => database.transaction(() async {
    final writer = _BqWriter(
      this,
      known: (await beanconquerorJournal()).imported,
      photos: photos,
      curves: curves,
    );
    final newMethods = await writer.writeMethods(plan.methods);
    final newGrinders = await writer.writeGrinders(plan.grinders);
    final newWaters = await writer.writeWaters(plan.waters);
    await writer.writeCoffees(plan.coffees);
    final methodNames = {
      for (final row in await database.select(database.brewMethods).get())
        row.id: row.name,
    };
    final grinderNames = {
      for (final row in await database.select(database.grinders).get())
        row.id: row.name,
    };
    final brewCount = await writer.addBrews(
      plan.brews,
      methodNames: methodNames,
      grinderNames: grinderNames,
    );
    await writer.completeEarlier(plan.updates);
    final changes = await _applyBqChanges(
      plan,
      now: writer.now,
      favorites: writer.favorites,
      local: writer.local,
      lotOf: writer.lotOf,
      jugOf: writer.jugOf,
      stored: writer.stored,
      curves: curves,
      methodNames: methodNames,
      grinderNames: grinderNames,
    );
    await writer.flush();
    await RoasterRegistry(database).backfill();
    await _adoptBqFavorites(writer.favorites);
    return BqImportSummary(
      coffees: plan.coffees.length,
      brews: brewCount,
      methods: newMethods,
      grinders: newGrinders,
      waters: newWaters,
      photos: writer.photoCount + changes.photos,
      curves: writer.curveCount + changes.curves,
      updated: changes.updated,
    );
  });

  static FavoriteCandidate _bqFavorite(
    String id,
    String coffeeId,
    String methodId,
    PlannedBrew brew,
  ) => (
    id: id,
    coffeeId: coffeeId,
    methodId: methodId,
    best: brew.isBestBrew,
    rating: brew.rating,
    brewedAtMs: brew.brewedAtMs,
  );

  /// Brews marked in BeanConqueror become the favourite of their coffee and
  /// method, unless the pair has one here already (local choices win).
  Future<void> _adoptBqFavorites(List<FavoriteCandidate> candidates) async {
    final chosen = pickFavorites(candidates);
    for (final candidate in candidates) {
      if (!chosen.contains(candidate.id)) continue;
      final taken =
          await (database.select(database.brews)
                ..where(
                  (row) =>
                      row.coffeeId.equals(candidate.coffeeId) &
                      row.methodId.equals(candidate.methodId) &
                      row.isFavorite.equals(true),
                )
                ..limit(1))
              .getSingleOrNull();
      if (taken != null) continue;
      await (database.update(database.brews)
            ..where((row) => row.id.equals(candidate.id)))
          .write(const BrewsCompanion(isFavorite: Value(true)));
    }
  }

  /// Brings beans and brews that changed in BeanConqueror, and not here,
  /// up to date. Stock stays as it is here. Returns how many changed and
  /// the curves and photos they brought.
  Future<({int updated, int curves, int photos})> _applyBqChanges(
    BqImportPlan plan, {
    required int now,
    required List<FavoriteCandidate> favorites,
    required String? Function(String kind, String? externalId) local,
    required Future<String?> Function(String coffeeId) lotOf,
    required Future<Recipient?> Function(
      PlannedBrew brew,
      String? methodId,
      String methodName,
    )
    jugOf,
    required List<String> Function(List<String> names) stored,
    required Map<String, ShotCurve> curves,
    required Map<String, String> methodNames,
    required Map<String, String> grinderNames,
  }) async {
    // The record keeps the new version and counts as imported now.
    Future<void> refresh(BqOrigin origin) async {
      final record =
          await (database.select(database.importRecords)..where(
                (row) =>
                    row.source.equals(BeanconquerorImport.source) &
                    row.kind.equals(origin.kind) &
                    row.externalId.equals(origin.externalId),
              ))
              .getSingle();
      await (database.update(
        database.importRecords,
      )..where((row) => row.id.equals(record.id))).write(
        ImportRecordsCompanion(
          fingerprint: Value(bqFingerprint(origin.rawJson)),
          importedAtMs: Value(now),
        ),
      );
      await database
          .into(database.legacyPayloads)
          .insertOnConflictUpdate(
            LegacyPayloadsCompanion.insert(
              importRecordId: record.id,
              rawJson: origin.rawJson,
            ),
          );
    }

    var updated = 0;
    var curveCount = 0;
    var photoCount = 0;
    for (final PlannedChange(:localId, planned: coffee)
        in plan.changedCoffees) {
      final current = await (database.select(
        database.coffees,
      )..where((row) => row.id.equals(localId))).getSingleOrNull();
      if (current == null) continue;
      await (database.update(
        database.coffees,
      )..where((row) => row.id.equals(localId))).write(
        CoffeesCompanion(
          name: Value(coffee.name),
          roaster: Value(coffee.roaster),
          notes: Value(coffee.notes),
          paidPriceCents: Value(coffee.paidPriceCents),
          rating: Value(coffee.rating),
          roastLevel: Value(coffee.roastLevel),
          flavorProfile: Value(coffee.flavorProfile),
          // Marking a favourite here is not an edit, so the coffee may be
          // updated; a heart set on either side stays.
          isFavorite: Value(current.isFavorite || coffee.isFavorite),
          isDecaf: Value(coffee.isDecaf),
          shopUrl: Value(coffee.shopUrl),
          updatedAtMs: Value(now),
        ),
      );
      await (database.delete(
        database.coffeeComponents,
      )..where((row) => row.coffeeId.equals(localId))).go();
      for (final (position, component) in coffee.components.indexed) {
        await database
            .into(database.coffeeComponents)
            .insert(
              CoffeeComponentsCompanion.insert(
                id: _uuid.v4(),
                coffeeId: localId,
                position: position,
                country: Value(component.country),
                region: Value(component.region),
                farm: Value(component.farm),
                producer: Value(component.producer),
                variety: Value(component.variety),
                process: Value(component.process),
                altitudeMeters: Value(component.altitudeMeters),
                altitudeMaxMeters: Value(component.altitudeMaxMeters),
                harvest: Value(component.harvest),
              ),
            );
      }
      if (await lotOf(localId) case final lotId?) {
        await (database.update(
          database.coffeeLots,
        )..where((row) => row.id.equals(lotId))).write(
          CoffeeLotsCompanion(
            roastDate: Value(coffee.lot.roastDate),
            purchaseDate: Value(coffee.lot.purchaseDate),
            openedDate: Value(coffee.lot.openedDate),
            initialGrams: Value(coffee.lot.initialGrams),
            updatedAtMs: Value(now),
          ),
        );
      }
      // Finished or back in use: its brews follow, as when archiving here.
      final archived = coffee.archivedAtMs;
      if ((archived != null) != (current.archivedAtMs != null)) {
        await (database.update(database.coffees)
              ..where((row) => row.id.equals(localId)))
            .write(CoffeesCompanion(archivedAtMs: Value(archived)));
        await (database.update(database.brews)..where(
              (row) =>
                  row.coffeeId.equals(localId) &
                  (archived == null
                      ? row.archivedByCoffee.equals(true)
                      : row.archivedAtMs.isNull()),
            ))
            .write(
              BrewsCompanion(
                archivedAtMs: Value(archived),
                archivedByCoffee: Value(archived != null),
              ),
            );
      }
      final files = stored(coffee.photos);
      if (files.isNotEmpty && (await coffeePhotos(localId)).isEmpty) {
        await setCoffeePhotos(localId, files);
        photoCount += files.length;
      }
      await refresh(coffee.origin);
      updated++;
    }

    for (final PlannedChange(:localId, planned: brew) in plan.changedBrews) {
      final current = await (database.select(
        database.brews,
      )..where((row) => row.id.equals(localId))).getSingleOrNull();
      final coffeeId = local(BqKind.bean, brew.beanId);
      if (current == null || coffeeId == null || coffeeId.isEmpty) continue;
      final methodId = local(BqKind.preparation, brew.preparationId);
      final grinderId = local(BqKind.mill, brew.millId);
      if (methodId != null && brew.isFavorite) {
        favorites.add(_bqFavorite(localId, coffeeId, methodId, brew));
      }
      final methodName = methodNames[methodId] ?? brew.methodName;
      final jug = await jugOf(brew, methodId, methodName);
      await (database.update(
        database.brews,
      )..where((row) => row.id.equals(localId))).write(
        BrewsCompanion(
          // A favourite that moved to another coffee or method leaves it.
          isFavorite: Value(
            current.isFavorite &&
                current.coffeeId == coffeeId &&
                current.methodId == methodId,
          ),
          coffeeId: Value(coffeeId),
          lotId: Value(
            coffeeId == current.coffeeId
                ? current.lotId
                : await lotOf(coffeeId),
          ),
          methodId: Value(methodId),
          grinderId: Value(grinderId),
          waterProfileId: Value(local(BqKind.water, brew.waterId)),
          waterProfileName: Value(brew.waterName),
          methodName: Value(methodName),
          grinderName: Value(grinderNames[grinderId] ?? brew.grinderName),
          grindSetting: Value(brew.grindSetting),
          doseGrams: Value(brew.doseGrams),
          waterGrams: Value(brew.waterGrams),
          beverageGrams: Value(brew.beverageGrams),
          recipientId: Value(jug?.id),
          recipientName: Value(jug?.name),
          recipientGrams: Value(jug?.emptyGrams),
          timeSeconds: Value(brew.timeSeconds),
          temperatureC: Value(brew.temperatureC),
          tdsPercent: Value(brew.tdsPercent),
          grindRpm: Value(brew.grindRpm),
          preinfusionSeconds: Value(brew.preinfusionSeconds),
          bloomSeconds: Value(brew.bloomSeconds),
          firstDripSeconds: Value(brew.firstDripSeconds),
          profileName: Value(brew.profileName),
          rating: Value(brew.rating),
          notes: Value(brew.notes),
          brewedAtMs: Value(brew.brewedAtMs),
          updatedAtMs: Value(now),
        ),
      );
      await (database.delete(
        database.brewToolSelections,
      )..where((row) => row.brewId.equals(localId))).go();
      for (final toolId in {
        for (final external in brew.toolIds) ?local(BqKind.tool, external),
      }) {
        await database
            .into(database.brewToolSelections)
            .insert(
              BrewToolSelectionsCompanion.insert(
                brewId: localId,
                toolId: toolId,
              ),
            );
      }
      // A curve recorded since replaces the one here.
      if (curves[brew.flowProfile] case final curve? when !curve.isEmpty) {
        await database
            .into(database.brewCurves)
            .insertOnConflictUpdate(
              BrewCurvesCompanion.insert(
                brewId: localId,
                source: BeanconquerorImport.source,
                samplesJson: curve.toJson(),
              ),
            );
        curveCount++;
      }
      final files = stored(brew.photos);
      if (files.isNotEmpty && (await brewPhotos(localId)).isEmpty) {
        await setBrewPhotos(localId, files);
        photoCount += files.length;
      }
      await refresh(brew.origin);
      updated++;
    }
    return (updated: updated, curves: curveCount, photos: photoCount);
  }
}

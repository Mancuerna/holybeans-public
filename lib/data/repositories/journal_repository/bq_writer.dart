part of '../journal_repository.dart';

/// Writes one BeanConqueror import plan, a kind of record at a time,
/// remembering where each record went so later ones can point to it.
///
/// Runs inside the import's transaction; brews and the import records are
/// kept in memory and written together by [flush].
class _BqWriter {
  _BqWriter(
    this.repository, {
    required this.known,
    required this.photos,
    required this.curves,
  }) : now = DateTime.now().toUtc().millisecondsSinceEpoch;

  final JournalRepository repository;

  /// Local IDs of the records imported so far, by kind and external ID.
  final Map<String, Map<String, String>> known;

  /// Stored photo names, by BeanConqueror file name.
  final Map<String, String> photos;
  final Map<String, ShotCurve> curves;
  final int now;

  AppDatabase get _database => repository.database;
  Uuid get _uuid => repository._uuid;

  final _records = <ImportRecordsCompanion>[];
  final _payloads = <LegacyPayloadsCompanion>[];
  final _lotOfCoffee = <String, String>{};
  final _brewRows = <BrewsCompanion>[];
  final _toolRows = <BrewToolSelectionsCompanion>[];
  final _photoRows = <BrewPhotosCompanion>[];
  final _curveRows = <BrewCurvesCompanion>[];

  /// Brews marked as favourite in BeanConqueror.
  final favorites = <FavoriteCandidate>[];
  int photoCount = 0;

  int get curveCount => _curveRows.length;

  List<Recipient>? _jugs;
  final _methodJugs = <String, String?>{};

  /// The catalog jug [brew] was weighed in, by its name (or its method's,
  /// [methodName]) and weight, preferring its method's own jug; added to
  /// the catalog when there is none.
  Future<Recipient?> jugOf(
    PlannedBrew brew,
    String? methodId,
    String methodName,
  ) async {
    final vessel = brew.vessel;
    if (vessel == null) return null;
    final jugs = _jugs ??= await _database.select(_database.recipients).get();
    String? preferred;
    if (methodId != null) {
      preferred = _methodJugs.containsKey(methodId)
          ? _methodJugs[methodId]
          : _methodJugs[methodId] =
                (await (_database.select(_database.brewMethods)
                          ..where((row) => row.id.equals(methodId)))
                        .getSingleOrNull())
                    ?.defaultRecipientId;
    }
    return _database.recipientFor(
      vessel.name ?? methodName,
      vessel.grams,
      jugs,
      preferredId: preferred,
    );
  }

  /// Notes that [origin] became [localId], keeping its original JSON.
  void remember(BqOrigin origin, String entity, String localId) {
    final recordId = _uuid.v4();
    _records.add(
      ImportRecordsCompanion.insert(
        id: recordId,
        source: BeanconquerorImport.source,
        kind: origin.kind,
        externalId: origin.externalId,
        fingerprint: bqFingerprint(origin.rawJson),
        localEntity: Value(entity),
        localId: Value(localId),
        importedAtMs: now,
      ),
    );
    _payloads.add(
      LegacyPayloadsCompanion.insert(
        importRecordId: recordId,
        rawJson: origin.rawJson,
      ),
    );
    known.putIfAbsent(origin.kind, () => {})[origin.externalId] = localId;
  }

  /// The local ID of a BeanConqueror record, if it was imported.
  String? local(String kind, String? externalId) =>
      externalId == null ? null : known[kind]?[externalId];

  /// The stored names of [names]; a coffee or brew keeps at most 8 photos.
  List<String> stored(List<String> names) =>
      [for (final name in names) ?photos[name]].take(8).toList();

  /// The lot brews of [coffeeId] draw from: the one imported with it, or
  /// for beans imported earlier, their first lot.
  Future<String?> lotOf(String coffeeId) async {
    if (_lotOfCoffee[coffeeId] case final lot?) return lot;
    final first =
        await (_database.select(_database.coffeeLots)
              ..where((row) => row.coffeeId.equals(coffeeId))
              ..orderBy([(row) => OrderingTerm(expression: row.createdAtMs)])
              ..limit(1))
            .getSingleOrNull();
    if (first != null) _lotOfCoffee[coffeeId] = first.id;
    return first?.id;
  }

  /// Adds the methods not reused and their tools; returns how many methods
  /// are new.
  Future<int> writeMethods(List<PlannedMethod> methods) async {
    var added = 0;
    for (final method in methods) {
      var id = method.reuseId;
      if (id == null) {
        id = _uuid.v4();
        added++;
        final recipientId = method.vesselGrams == null
            ? null
            : 'method-recipient:$id';
        if (recipientId != null) {
          await _database
              .into(_database.recipients)
              .insert(
                Recipient(
                  id: recipientId,
                  name: method.vesselName ?? method.name,
                  emptyGrams: method.vesselGrams!,
                ),
              );
        }
        await _database
            .into(_database.brewMethods)
            .insert(
              BrewMethodsCompanion.insert(
                id: id,
                name: method.name,
                category: Value(method.category),
                templateType: Value(method.templateType),
                machine: Value(method.machine),
                machineAddress: Value(method.machineAddress),
                notes: Value(method.notes),
                vesselName: Value(method.vesselName),
                vesselGrams: Value(method.vesselGrams),
                defaultRecipientId: Value(recipientId),
                archivedAtMs: Value(method.archived ? now : null),
              ),
            );
      }
      remember(method.origin, 'method', id);
      for (final tool in method.tools) {
        final toolId = _uuid.v4();
        await _database
            .into(_database.methodTools)
            .insert(
              MethodToolsCompanion.insert(
                id: toolId,
                methodId: Value(id),
                name: tool.name,
                archivedAtMs: Value(tool.archived ? now : null),
              ),
            );
        remember(tool.origin, 'tool', toolId);
        await _database
            .into(_database.toolMethodLinks)
            .insert(ToolMethodLink(toolId: toolId, methodId: id));
      }
    }
    return added;
  }

  /// Adds the grinders not reused; returns how many.
  Future<int> writeGrinders(List<PlannedGrinder> grinders) async {
    var added = 0;
    for (final grinder in grinders) {
      var id = grinder.reuseId;
      if (id == null) {
        id = _uuid.v4();
        added++;
        await _database
            .into(_database.grinders)
            .insert(
              GrindersCompanion.insert(
                id: id,
                name: grinder.name,
                notes: Value(grinder.notes),
                hasAdjustableRpm: Value(grinder.hasAdjustableRpm),
                archivedAtMs: Value(grinder.archived ? now : null),
              ),
            );
      }
      remember(grinder.origin, 'grinder', id);
    }
    return added;
  }

  /// Adds the water profiles not reused; returns how many.
  Future<int> writeWaters(List<PlannedWater> waters) async {
    var added = 0;
    for (final water in waters) {
      var id = water.reuseId;
      if (id == null) {
        id = _uuid.v4();
        added++;
        await _database
            .into(_database.waterProfiles)
            .insert(
              WaterProfilesCompanion.insert(
                id: id,
                name: water.name,
                ghPpmAsCaCO3: Value(water.ghPpm),
                khPpmAsCaCO3: Value(water.khPpm),
                tdsPpm: Value(water.tdsPpm),
                calciumPpm: Value(water.calciumPpm),
                magnesiumPpm: Value(water.magnesiumPpm),
                sodiumPpm: Value(water.sodiumPpm),
                potassiumPpm: Value(water.potassiumPpm),
                chloridePpm: Value(water.chloridePpm),
                sulfatePpm: Value(water.sulfatePpm),
                notes: Value(water.notes),
                archivedAtMs: Value(water.archived ? now : null),
              ),
            );
      }
      remember(water.origin, 'water', id);
    }
    return added;
  }

  /// Adds each coffee with its origins, its single lot, its frozen portion
  /// and its photos.
  Future<void> writeCoffees(List<PlannedCoffee> coffees) =>
      _database.batch((batch) {
        for (final coffee in coffees) {
          final id = _uuid.v4();
          final lotId = _uuid.v4();
          _lotOfCoffee[id] = lotId;
          batch.insert(
            _database.coffees,
            CoffeesCompanion.insert(
              id: id,
              name: coffee.name,
              roaster: coffee.roaster,
              notes: Value(coffee.notes),
              paidPriceCents: Value(coffee.paidPriceCents),
              rating: Value(coffee.rating),
              roastLevel: Value(coffee.roastLevel),
              flavorProfile: Value(coffee.flavorProfile),
              isFavorite: Value(coffee.isFavorite),
              isDecaf: Value(coffee.isDecaf),
              shopUrl: Value(coffee.shopUrl),
              createdAtMs: coffee.createdAtMs,
              updatedAtMs: now,
              archivedAtMs: Value(coffee.archivedAtMs),
            ),
          );
          for (final (position, component) in coffee.components.indexed) {
            batch.insert(
              _database.coffeeComponents,
              CoffeeComponentsCompanion.insert(
                id: _uuid.v4(),
                coffeeId: id,
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
          _insertLot(batch, coffee, id: id, lotId: lotId);
          for (final (position, file) in stored(coffee.photos).indexed) {
            photoCount++;
            batch.insert(
              _database.coffeePhotos,
              CoffeePhotosCompanion.insert(
                coffeeId: id,
                position: position,
                fileName: file,
              ),
            );
          }
          remember(coffee.origin, 'coffee', id);
        }
      });

  void _insertLot(
    Batch batch,
    PlannedCoffee coffee, {
    required String id,
    required String lotId,
  }) {
    final lot = coffee.lot;
    batch.insert(
      _database.coffeeLots,
      CoffeeLotsCompanion.insert(
        id: lotId,
        coffeeId: id,
        roastDate: Value(lot.roastDate),
        purchaseDate: Value(lot.purchaseDate),
        openedDate: Value(lot.openedDate),
        initialGrams: Value(lot.initialGrams),
        remainingGrams: Value(lot.remainingGrams),
        overdrawGrams: Value(lot.overdrawGrams),
        frozenPauseDays: Value(lot.frozenPauseDays),
        createdAtMs: coffee.createdAtMs,
        updatedAtMs: now,
        archivedAtMs: Value(coffee.archivedAtMs),
      ),
    );
    if (coffee.portion case final portion?) {
      batch.insert(
        _database.frozenPortions,
        FrozenPortionsCompanion.insert(
          id: _uuid.v4(),
          lotId: lotId,
          label: portion.label,
          container: Value(portion.container),
          frozenDate: portion.frozenDate,
          initialGrams: portion.grams,
          remainingGrams: portion.grams,
          notes: Value(portion.notes),
          createdAtMs: coffee.createdAtMs,
          updatedAtMs: now,
        ),
      );
    }
  }

  /// Prepares the brews whose coffee was imported, with their tools,
  /// photos and curve; returns how many.
  ///
  /// Brews keep the name their method and grinder have here
  /// ([methodNames], [grinderNames]), which a reused one may write
  /// differently, so filters by name find them.
  Future<int> addBrews(
    List<PlannedBrew> brews, {
    required Map<String, String> methodNames,
    required Map<String, String> grinderNames,
  }) async {
    var added = 0;
    for (final brew in brews) {
      final coffeeId = local(BqKind.bean, brew.beanId);
      if (coffeeId == null || coffeeId.isEmpty) continue;
      final id = _uuid.v4();
      final methodId = local(BqKind.preparation, brew.preparationId);
      final grinderId = local(BqKind.mill, brew.millId);
      if (methodId != null && brew.isFavorite) {
        favorites.add(
          BeanconquerorImport._bqFavorite(id, coffeeId, methodId, brew),
        );
      }
      final methodName = methodNames[methodId] ?? brew.methodName;
      final jug = await jugOf(brew, methodId, methodName);
      _brewRows.add(
        BrewsCompanion.insert(
          id: id,
          coffeeId: coffeeId,
          lotId: Value(await lotOf(coffeeId)),
          methodId: Value(methodId),
          grinderId: Value(grinderId),
          waterProfileId: Value(local(BqKind.water, brew.waterId)),
          waterProfileName: Value(brew.waterName),
          methodName: methodName,
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
          brewedAtMs: brew.brewedAtMs,
          createdAtMs: brew.brewedAtMs,
          updatedAtMs: now,
          archivedAtMs: Value(brew.archivedAtMs),
          archivedByCoffee: Value(brew.archivedAtMs == null ? null : true),
        ),
      );
      _addBrewExtras(id, brew);
      remember(brew.origin, 'brew', id);
      added++;
    }
    return added;
  }

  /// The tools, photos and curve of a new brew.
  void _addBrewExtras(String id, PlannedBrew brew) {
    for (final toolId in {
      for (final external in brew.toolIds) ?local(BqKind.tool, external),
    }) {
      _toolRows.add(
        BrewToolSelectionsCompanion.insert(brewId: id, toolId: toolId),
      );
    }
    for (final (position, file) in stored(brew.photos).indexed) {
      photoCount++;
      _photoRows.add(
        BrewPhotosCompanion.insert(
          brewId: id,
          position: position,
          fileName: file,
        ),
      );
    }
    if (curves[brew.flowProfile] case final curve? when !curve.isEmpty) {
      _addCurve(id, curve);
    }
  }

  void _addCurve(String brewId, ShotCurve curve) => _curveRows.add(
    BrewCurvesCompanion.insert(
      brewId: brewId,
      source: BeanconquerorImport.source,
      samplesJson: curve.toJson(),
    ),
  );

  /// Gives records imported before the photos and curve they lack.
  Future<void> completeEarlier(List<PlannedUpdate> updates) async {
    for (final update in updates) {
      final localId = local(update.kind, update.externalId);
      if (localId == null || localId.isEmpty) continue;
      if (curves[update.flowProfile] case final curve?
          when !curve.isEmpty && await repository.brewCurve(localId) == null) {
        final exists = await (_database.select(
          _database.brews,
        )..where((row) => row.id.equals(localId))).getSingleOrNull();
        if (exists != null) _addCurve(localId, curve);
      }
      final files = stored(update.photos);
      if (files.isEmpty) continue;
      try {
        if (update.kind == BqKind.bean) {
          if ((await repository.coffeePhotos(localId)).isNotEmpty) continue;
          await repository.setCoffeePhotos(localId, files);
        } else {
          if ((await repository.brewPhotos(localId)).isNotEmpty) continue;
          await repository.setBrewPhotos(localId, files);
        }
      } on StateError {
        // Deleted here since it was imported.
        continue;
      }
      photoCount += files.length;
    }
  }

  /// Writes the brews prepared and the import records.
  Future<void> flush() => _database.batch((batch) {
    batch
      ..insertAll(_database.brews, _brewRows)
      ..insertAll(_database.brewToolSelections, _toolRows)
      ..insertAll(_database.brewPhotos, _photoRows)
      ..insertAll(_database.brewCurves, _curveRows)
      ..insertAll(_database.importRecords, _records)
      ..insertAll(_database.legacyPayloads, _payloads);
  });
}

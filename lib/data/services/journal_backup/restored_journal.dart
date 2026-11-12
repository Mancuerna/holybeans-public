part of '../journal_backup.dart';

/// A backup's rows, decoded and upgraded from older versions, checked
/// against the journal's rules and then written in place of the journal.
///
/// Checks run in a fixed order, so a damaged backup always fails with the
/// same message.
class _RestoredJournal {
  _RestoredJournal._({
    required this.recipients,
    required this.extractionProfiles,
    required this.cafeData,
    required this.pistonData,
    required this.adjustments,
    required this.sessions,
    required this.sessionCups,
    required this.coffees,
    required this.components,
    required this.lots,
    required this.frozenPortions,
    required this.methods,
    required this.grinders,
    required this.waterProfiles,
    required this.methodTools,
    required this.legacyTools,
    required this.toolMethodLinks,
    required this.brews,
    required this.brewToolSelections,
    required this.importRecords,
    required this.legacyPayloads,
    required this.preferences,
    required this.curves,
    required this.coffeePhotoRows,
    required this.brewPhotoRows,
    required this.restoreBrewJugs,
  });

  /// Decodes every collection of [data]. Photos are kept only when
  /// [keepPhoto] accepts their file name. [restoreBrewJugs] gives brews
  /// saved before the jug catalog their jug back, for backups up to v30.
  factory _RestoredJournal.decode(
    Map<String, dynamic> data, {
    required bool Function(String name) keepPhoto,
    bool restoreBrewJugs = false,
  }) {
    // Up to v15, the single photo of a coffee or brew, by its ID.
    Map<String, String> legacyPhotos(String key) => {
      for (final entry in data[key] as List? ?? const [])
        if (entry case {'id': final String id, 'photoFile': final String name})
          id: name,
    };
    final legacyCoffeePhotos = legacyPhotos('coffees');
    final legacyBrewPhotos = legacyPhotos('brews');

    final coffees = _decode(
      data,
      'coffees',
      (json) =>
          Coffee.fromJson({'isFavorite': false, 'isDecaf': false, ...json}),
      ignoredFields: const {'photoFile'},
    );
    final components = _decode(data, 'components', CoffeeComponent.fromJson);
    final lots = _decode(data, 'lots', CoffeeLot.fromJson);
    final frozenPortions = data.containsKey('frozenPortions')
        ? _decode(data, 'frozenPortions', FrozenPortion.fromJson)
        : <FrozenPortion>[];
    var methods = _decode(data, 'methods', BrewMethod.fromJson);
    final recipients = data.containsKey('recipients')
        ? _decode(
            data,
            'recipients',
            (json) => Recipient.fromJson({'isPortafilter': false, ...json}),
          )
        : <Recipient>[];
    if (!data.containsKey('recipients')) {
      methods = [
        for (final method in methods)
          if (method.vesselGrams != null)
            method.copyWith(
              defaultRecipientId: Value('method-recipient:${method.id}'),
            )
          else
            method,
      ];
      for (final method in methods) {
        if (method.vesselGrams case final grams?) {
          recipients.add(
            Recipient(
              isPortafilter: false,
              id: method.defaultRecipientId!,
              name: method.vesselName?.trim().isNotEmpty == true
                  ? method.vesselName!
                  : method.name,
              emptyGrams: grams,
            ),
          );
        }
      }
    }
    final grinders = _decode(
      data,
      'grinders',
      (json) => Grinder.fromJson({
        'hasAdjustableRpm': false,
        'hasAdjustableFeederRpm': false,
        ...json,
      }),
    );
    final waterProfiles = data.containsKey('waterProfiles')
        ? _decode(data, 'waterProfiles', WaterProfile.fromJson)
        : <WaterProfile>[];
    final methodTools = _decode(data, 'methodTools', MethodTool.fromJson);
    final legacyTools = !data.containsKey('toolMethodLinks');
    final toolMethodLinks = legacyTools
        ? [
            for (final tool in methodTools)
              if (tool.methodId case final methodId?)
                ToolMethodLink(toolId: tool.id, methodId: methodId),
          ]
        : _decode(data, 'toolMethodLinks', ToolMethodLink.fromJson);
    final brews = _decode(data, 'brews', (json) {
      for (final key in ['bloomCount', 'pourCount']) {
        if (json[key] != null && json[key] is! int) {
          throw const FormatException('Brew has a non-integer pour count');
        }
      }
      // Favourites arrived in v22.
      return Brew.fromJson({
        'isFavorite': false,
        'recipientIsPortafilter': false,
        'stockReviewPending':
            json['archivedAtMs'] != null && json['archivedByCoffee'] != true,
        ...json,
      });
    }, ignoredFields: const {'photoFile', 'vesselId'});
    final brewToolSelections = _decode(
      data,
      'brewToolSelections',
      BrewToolSelection.fromJson,
    );
    final importRecords = _decode(data, 'importRecords', ImportRecord.fromJson);
    final legacyPayloads = _decode(
      data,
      'legacyPayloads',
      LegacyPayload.fromJson,
    );
    // v14 kept the Meticulous address in the preferences; it now belongs
    // to the machine's method.
    final preferences = _decode(
      data,
      'preferences',
      AppPreference.fromJson,
      ignoredFields: const {'meticulousAddress'},
    );
    for (final preference in preferences) {
      ShareConfiguration.decode(preference.shareFieldsJson);
      if (preference.scalesJson case final json?) {
        RememberedScale.decodeList(json);
      }
    }

    // Curves arrived in v15; older backups have none.
    final curves = data.containsKey('brewCurves')
        ? _decode(data, 'brewCurves', BrewCurve.fromJson)
        : const <BrewCurve>[];

    // Photos whose file did not come with the backup are dropped and the
    // rest closes ranks, so the first remaining one becomes the cover.
    List<(String, String)> photoRows<T>(
      String key,
      T Function(Map<String, dynamic>) fromJson,
      (String, int, String) Function(T) fields,
      Map<String, String> legacy,
    ) {
      final rows = data.containsKey(key)
          ? [for (final row in _decode(data, key, fromJson)) fields(row)]
          : [
              for (final MapEntry(:key, :value) in legacy.entries)
                (key, 0, value),
            ];
      _ensureUnique(rows.map((row) => _photoKey(row.$1, row.$2)), key);
      rows.sort(
        (a, b) => _photoKey(a.$1, a.$2).compareTo(_photoKey(b.$1, b.$2)),
      );
      return [
        for (final (owner, _, name) in rows)
          if (keepPhoto(name)) (owner, name),
      ];
    }

    return _RestoredJournal._(
      extractionProfiles: data.containsKey('extractionProfiles')
          ? _decode(data, 'extractionProfiles', ExtractionProfileRow.fromJson)
          : [],
      recipients: recipients,
      adjustments: data.containsKey('stockAdjustments')
          ? _decode(data, 'stockAdjustments', StockAdjustment.fromJson)
          : [],
      sessions: data.containsKey('cuppingSessions')
          ? _decode(data, 'cuppingSessions', CuppingSession.fromJson)
          : [],
      sessionCups: data.containsKey('cuppingSessionCups')
          ? _decode(data, 'cuppingSessionCups', CuppingSessionCup.fromJson)
          : [],
      cafeData: _CafeBackup(data, keepPhoto),
      pistonData: _PistonBackup(data),
      coffees: coffees,
      components: components,
      lots: lots,
      frozenPortions: frozenPortions,
      methods: methods,
      grinders: grinders,
      waterProfiles: waterProfiles,
      methodTools: methodTools,
      legacyTools: legacyTools,
      toolMethodLinks: toolMethodLinks,
      brews: brews,
      brewToolSelections: brewToolSelections,
      importRecords: importRecords,
      legacyPayloads: legacyPayloads,
      preferences: preferences,
      curves: curves,
      coffeePhotoRows: photoRows(
        'coffeePhotos',
        CoffeePhoto.fromJson,
        (CoffeePhoto row) => (row.coffeeId, row.position, row.fileName),
        legacyCoffeePhotos,
      ),
      brewPhotoRows: photoRows(
        'brewPhotos',
        BrewPhoto.fromJson,
        (BrewPhoto row) => (row.brewId, row.position, row.fileName),
        legacyBrewPhotos,
      ),
      restoreBrewJugs: restoreBrewJugs,
    );
  }

  final _CafeBackup cafeData;
  final _PistonBackup pistonData;
  final bool restoreBrewJugs;
  final List<Recipient> recipients;
  final List<ExtractionProfileRow> extractionProfiles;
  final List<StockAdjustment> adjustments;
  final List<CuppingSession> sessions;
  final List<CuppingSessionCup> sessionCups;
  final List<Coffee> coffees;
  final List<CoffeeComponent> components;
  final List<CoffeeLot> lots;
  final List<FrozenPortion> frozenPortions;
  final List<BrewMethod> methods;
  final List<Grinder> grinders;
  final List<WaterProfile> waterProfiles;
  final List<MethodTool> methodTools;

  /// Whether tools come from before v21, each tied to a single method.
  final bool legacyTools;
  final List<ToolMethodLink> toolMethodLinks;
  final List<Brew> brews;
  final List<BrewToolSelection> brewToolSelections;
  final List<ImportRecord> importRecords;
  final List<LegacyPayload> legacyPayloads;
  final List<AppPreference> preferences;
  final List<BrewCurve> curves;

  /// Kept photos as (owner, file name), sorted by owner and position.
  final List<(String, String)> coffeePhotoRows;
  final List<(String, String)> brewPhotoRows;

  late final _coffeeIds = {for (final coffee in coffees) coffee.id};
  late final _methodsById = {for (final method in methods) method.id: method};
  late final _grindersById = {
    for (final grinder in grinders) grinder.id: grinder,
  };
  late final _waterProfilesById = {
    for (final profile in waterProfiles) profile.id: profile,
  };
  late final _toolsById = {for (final tool in methodTools) tool.id: tool};
  late final _brewsById = {for (final brew in brews) brew.id: brew};
  late final _lotsById = {for (final lot in lots) lot.id: lot};

  BackupSummary get summary => BackupSummary(
    cafeDrinks: cafeData.drinks.length,
    cafes: cafeData.cafes.length,
    cuppingSessions: sessions.length,
    coffees: coffees.length,
    components: components.length,
    lots: lots.length,
    frozenPortions: frozenPortions.length,
    methods: methods.length,
    grinders: grinders.length,
    waterProfiles: waterProfiles.length,
    methodTools: methodTools.length,
    brews: brews.length,
    brewToolSelections: brewToolSelections.length,
    importRecords: importRecords.length,
    legacyPayloads: legacyPayloads.length,
  );

  /// Throws a [FormatException] at the first row that breaks the journal's
  /// rules: repeated IDs, missing relations or impossible values.
  void validate() {
    final ids = <String>{};
    for (final row in extractionProfiles) {
      final profile = ExtractionProfile.decode(row.dataJson);
      if (profile.id != row.id || !ids.add(row.id)) {
        throw const FormatException('Invalid profile identity');
      }
    }
    for (final brew in brews) {
      if (brew.extractionProfileJson case final source?) {
        ExtractionProfile.decode(source);
      }
    }

    cafeData.validate(coffees);
    pistonData.validate(methods);
    _checkUniqueIds();
    _checkCupping();
    _checkCurves();
    _checkInventory();
    _checkAdjustments();
    _checkTools();
    _checkEquipment();
    _checkPhotos();
    _checkBrews();
    _checkImports();
    _checkToolSelections();
  }

  void _checkCupping() {
    _ensureUnique(sessions.map((s) => s.id), 'cupping sessions');
    _ensureUnique(sessionCups.map((c) => c.id), 'cupping cups');
    _ensureUnique(sessionCups.map((c) => c.brewId), 'cupping brews');
    _ensureUnique(
      sessionCups.map((c) => '${c.sessionId}:${c.position}'),
      'cupping positions',
    );
    final drafts = <String, CuppingDraft>{};
    final completed = <String>{};
    for (final session in sessions) {
      final draft = CuppingDraft.fromJson(session.draftJson);
      if (session.id.isEmpty ||
          session.name.length > 120 ||
          session.startedAtMs != draft.startedAtMs ||
          session.createdAtMs < 0 ||
          session.updatedAtMs < session.createdAtMs ||
          (session.completedAtMs != null &&
              (!draft.ready ||
                  draft.tastingAtMs == null ||
                  session.completedAtMs! < draft.tastingAtMs!))) {
        throw const FormatException('Invalid cupping session');
      }
      drafts[session.id] = draft;
      if (session.completedAtMs != null) completed.add(session.id);
    }
    for (final cup in sessionCups) {
      final draft = drafts[cup.sessionId];
      if (draft == null ||
          !completed.contains(cup.sessionId) ||
          !_brewsById.containsKey(cup.brewId) ||
          cup.position < 0 ||
          cup.position >= draft.cups.length) {
        throw const FormatException('Invalid cupping cup relation');
      }
    }
  }

  void _checkUniqueIds() {
    _ensureUnique(coffees.map((coffee) => coffee.id), 'coffee IDs');
    _ensureUnique(components.map((component) => component.id), 'component IDs');
    _ensureUnique(lots.map((lot) => lot.id), 'lot IDs');
    _ensureUnique(
      frozenPortions.map((portion) => portion.id),
      'frozen portion IDs',
    );
    _ensureUnique(
      frozenPortions.map((portion) => portion.label),
      'frozen portion labels',
    );
    _ensureUnique(methods.map((method) => method.id), 'method IDs');
    _ensureUnique(grinders.map((grinder) => grinder.id), 'grinder IDs');
    _ensureUnique(
      waterProfiles.map((profile) => profile.id),
      'water profile IDs',
    );
    _ensureUnique(methodTools.map((tool) => tool.id), 'method tool IDs');
    _ensureUnique(brews.map((brew) => brew.id), 'brew IDs');
    _ensureUnique(
      importRecords.map((record) => record.id),
      'import record IDs',
    );
    _ensureUnique(
      legacyPayloads.map((payload) => payload.importRecordId),
      'legacy payload import record IDs',
    );
    _ensureUnique(
      preferences.map((preference) => '${preference.id}'),
      'preference IDs',
    );
  }

  void _checkCurves() {
    _ensureUnique(curves.map((curve) => curve.brewId), 'brew curves');
    for (final curve in curves) {
      if (!_brewsById.containsKey(curve.brewId)) {
        throw const FormatException('Curve references a missing brew');
      }
      ShotCurve.fromJson(curve.samplesJson);
    }
  }

  void _checkInventory() {
    for (final component in components) {
      if (!_coffeeIds.contains(component.coffeeId)) {
        throw const FormatException('Component references a missing coffee');
      }
      if (component.altitudeMaxMeters != null &&
          !validAltitudeRange(
            component.altitudeMeters,
            component.altitudeMaxMeters,
          )) {
        throw const FormatException('Invalid altitude range');
      }
    }
    for (final lot in lots) {
      if (!_coffeeIds.contains(lot.coffeeId)) {
        throw const FormatException('Lot references a missing coffee');
      }
    }
    for (final portion in frozenPortions) {
      if (!_lotsById.containsKey(portion.lotId)) {
        throw const FormatException('Frozen portion references a missing lot');
      }
      if (!portion.initialGrams.isFinite ||
          portion.initialGrams <= 0 ||
          !portion.remainingGrams.isFinite ||
          portion.remainingGrams < 0 ||
          portion.remainingGrams > portion.initialGrams) {
        throw const FormatException('Frozen portion has invalid weights');
      }
    }
  }

  void _checkAdjustments() {
    _ensureUnique(adjustments.map((r) => r.id), 'stock adjustments');
    final groups = <String, StockAdjustment>{};
    for (final row in adjustments) {
      final lot = _lotsById[row.lotId];
      final portion = frozenPortions
          .where((p) => p.id == row.frozenPortionId)
          .firstOrNull;
      final previous = row.previousGrams;
      if (row.id.isEmpty ||
          row.operationId.isEmpty ||
          lot == null ||
          lot.coffeeId != row.coffeeId ||
          (row.frozenPortionId != null &&
              (portion == null || portion.lotId != row.lotId)) ||
          !{'gift', 'waste', 'correction'}.contains(row.reason) ||
          !row.resultingGrams.isFinite ||
          (previous != null && !previous.isFinite) ||
          (row.reason != 'correction' &&
              (previous == null || row.resultingGrams >= previous)) ||
          (row.frozenPortionId != null &&
              (previous == null || previous < 0 || row.resultingGrams < 0)) ||
          (row.notes?.length ?? 0) > 500 ||
          row.createdAtMs < 0 ||
          (row.reversedAtMs != null && row.reversedAtMs! < row.createdAtMs)) {
        throw const FormatException('Invalid stock adjustment');
      }
      final first = groups.putIfAbsent(row.operationId, () => row);
      if (first.coffeeId != row.coffeeId ||
          first.reason != row.reason ||
          first.notes != row.notes ||
          first.createdAtMs != row.createdAtMs ||
          first.reversedAtMs != row.reversedAtMs) {
        throw const FormatException('Inconsistent stock adjustment operation');
      }
    }
    _ensureUnique(
      adjustments.map(
        (r) => '${r.operationId}:${r.lotId}:${r.frozenPortionId}',
      ),
      'stock adjustment allocations',
    );
  }

  void _checkTools() {
    for (final tool in methodTools) {
      if (tool.methodId != null && !_methodsById.containsKey(tool.methodId)) {
        throw const FormatException('Method tool references a missing method');
      }
      if (legacyTools && tool.methodId == null) {
        throw const FormatException('Legacy tool has no method');
      }
      if (tool.name.trim().isEmpty || tool.name.length > 120) {
        throw const FormatException('Tool has an invalid name');
      }
    }
    _ensureUnique(
      toolMethodLinks.map((link) => '${link.toolId}\u0000${link.methodId}'),
      'tool method links',
    );
    for (final link in toolMethodLinks) {
      if (!_toolsById.containsKey(link.toolId) ||
          !_methodsById.containsKey(link.methodId)) {
        throw const FormatException('Tool association has a missing relation');
      }
    }
    try {
      ToolCatalog(
        tools: methodTools,
        links: toolMethodLinks,
        selections: brewToolSelections,
      );
    } on StateError {
      throw const FormatException('Invalid tool merge or selection');
    }
  }

  void _checkEquipment() {
    _ensureUnique(recipients.map((r) => r.id), 'recipient IDs');
    final recipientsById = {for (final r in recipients) r.id: r};
    final ids = recipientsById.keys.toSet();
    try {
      for (final r in recipients) {
        RecipientSnapshot(
          id: r.id,
          name: r.name,
          grams: r.emptyGrams,
        ).validate();
      }
      for (final b in brews) {
        if (b.recipientId != null) {
          if (!ids.contains(b.recipientId) ||
              b.recipientName == null ||
              b.recipientGrams == null ||
              recipientsById[b.recipientId]!.isPortafilter !=
                  b.recipientIsPortafilter) {
            throw ArgumentError('Missing recipient');
          }
          RecipientSnapshot(
            id: b.recipientId!,
            name: b.recipientName!,
            grams: b.recipientGrams!,
          ).validate();
        } else if (b.recipientName != null ||
            b.recipientGrams != null ||
            b.recipientIsPortafilter) {
          throw ArgumentError('Incomplete recipient');
        }
      }
    } on ArgumentError {
      throw const FormatException('Invalid recipient');
    }
    for (final m in methods) {
      if (m.defaultRecipientId != null && !ids.contains(m.defaultRecipientId)) {
        throw const FormatException('Missing default recipient');
      }
    }
    for (final profile in waterProfiles) {
      _validateWaterProfile(profile);
    }
    for (final method in methods) {
      final jug = method.vesselGrams;
      if (jug != null && (!jug.isFinite || jug <= 0 || jug > 10000)) {
        throw const FormatException('Method has an invalid jug weight');
      }
      if (method.pourPlanJson case final plan?) {
        try {
          PourPlan.fromJson(plan, doseGrams: 1);
        } on Object {
          throw const FormatException('Method has an invalid pour plan');
        }
      }
    }
  }

  void _checkPhotos() {
    for (final (coffeeId, _) in coffeePhotoRows) {
      if (!_coffeeIds.contains(coffeeId)) {
        throw const FormatException('Photo references a missing coffee');
      }
    }
    for (final (brewId, _) in brewPhotoRows) {
      if (!_brewsById.containsKey(brewId)) {
        throw const FormatException('Photo references a missing brew');
      }
    }
  }

  void _checkBrews() {
    final favoritePairs = <(String, String)>{};
    final frozenUsed = <String, double>{};
    for (final brew in brews) {
      _checkBrewRelations(brew);
      if (brew.brix != null || brew.brixFactor != null) {
        final computed = brixToTds(brew.brix, brew.brixFactor);
        if (computed == null ||
            brew.tdsPercent == null ||
            !brew.tdsPercent!.isFinite ||
            (computed - brew.tdsPercent!).abs() > 0.000001) {
          throw const FormatException('Inconsistent Brix and TDS');
        }
      }
      if (brew.feederRpm != null && brew.feederRpm! <= 0) {
        throw const FormatException('Invalid feeder RPM');
      }
      if (brew.frozenPortionId case final portionId?
          when brew.stockReviewPending != true) {
        frozenUsed.update(
          portionId,
          (grams) => grams + brew.frozenDoseGrams!,
          ifAbsent: () => brew.frozenDoseGrams!,
        );
      }
      if (brew.isFavorite &&
          (brew.methodId == null ||
              !favoritePairs.add((brew.coffeeId, brew.methodId!)))) {
        throw const FormatException(
          'Brew favourite needs a method and must be the only one',
        );
      }
      if (brew.isPreGround &&
          (brew.grinderId != null ||
              brew.grinderName?.trim().isNotEmpty == true)) {
        throw const FormatException('Pre-ground brew references a grinder');
      }
      if (brew.timeSeconds != null && brew.timeSeconds! <= 0) {
        throw const FormatException('Brew has an invalid extraction duration');
      }
      BrewPours.fromStorage(
        bloomCount: brew.bloomCount,
        pourCount: brew.pourCount,
        phasesJson: brew.pourPhasesJson,
      );
      if (brew.firstDripSeconds != null && brew.firstDripSeconds! <= 0) {
        throw const FormatException('Brew has an invalid first drip time');
      }
    }
    for (final portion in frozenPortions) {
      if ((frozenUsed[portion.id] ?? 0) >
          portion.initialGrams - portion.remainingGrams + 0.000001) {
        throw const FormatException('Frozen doses exceed the thawed coffee');
      }
    }
  }

  /// The coffee, lot, method, grinder and water profile [brew] names exist,
  /// and its lot belongs to its coffee.
  void _checkBrewRelations(Brew brew) {
    if (brew.frozenPortionId case final portionId?) {
      final portion = frozenPortions
          .where((row) => row.id == portionId)
          .firstOrNull;
      final grams = brew.frozenDoseGrams;
      if (portion == null ||
          portion.lotId != brew.lotId ||
          grams == null ||
          !grams.isFinite ||
          grams <= 0 ||
          grams > (brew.doseGrams ?? 0)) {
        throw const FormatException('Brew has an invalid frozen source');
      }
    } else if (brew.frozenDoseGrams != null) {
      throw const FormatException('Frozen dose has no source portion');
    }
    if (!_coffeeIds.contains(brew.coffeeId)) {
      throw const FormatException('Brew references a missing coffee');
    }
    final lotId = brew.lotId;
    if (lotId != null) {
      final lot = _lotsById[lotId];
      if (lot == null) {
        throw const FormatException('Brew references a missing lot');
      }
      if (lot.coffeeId != brew.coffeeId) {
        throw const FormatException('Brew references a lot of another coffee');
      }
    }
    if (brew.methodId != null && !_methodsById.containsKey(brew.methodId)) {
      throw const FormatException('Brew references a missing method');
    }
    if (brew.grinderId != null && !_grindersById.containsKey(brew.grinderId)) {
      throw const FormatException('Brew references a missing grinder');
    }
    if (brew.waterProfileId != null &&
        !_waterProfilesById.containsKey(brew.waterProfileId)) {
      throw const FormatException('Brew references a missing water profile');
    }
  }

  void _checkImports() {
    final importRecordIds = {for (final record in importRecords) record.id};
    for (final payload in legacyPayloads) {
      if (!importRecordIds.contains(payload.importRecordId)) {
        throw const FormatException(
          'Legacy payload references a missing import record',
        );
      }
    }
  }

  void _checkToolSelections() {
    final selectionKeys = <String>{};
    for (final selection in brewToolSelections) {
      final brew = _brewsById[selection.brewId];
      final tool = _toolsById[selection.toolId];
      if (brew == null || tool == null) {
        throw const FormatException('Tool selection has a missing relation');
      }
      if (legacyTools &&
          (brew.methodId == null || brew.methodId != tool.methodId)) {
        throw const FormatException(
          'Selected tool does not belong to brew method',
        );
      }
      if (!selectionKeys.add('${selection.brewId}\u0000${selection.toolId}')) {
        throw const FormatException('Duplicate brew tool selection');
      }
    }
  }

  /// Replaces every table of [database] with these rows, in one
  /// transaction: a failure leaves the journal as it was.
  Future<void> replace(AppDatabase database) => database.transaction(() async {
    await _clearJournal(database);
    await database.batch((batch) {
      batch.insertAll(database.extractionProfiles, extractionProfiles);
      batch.insertAll(database.coffees, coffees);
      batch.insertAll(database.coffeeComponents, components);
      batch.insertAll(database.coffeeLots, lots);
      batch.insertAll(database.frozenPortions, frozenPortions);
      batch.insertAll(database.stockAdjustments, adjustments);
      batch.insertAll(database.recipients, recipients);
      batch.insertAll(database.brewMethods, methods);
      batch.insertAll(database.grinders, grinders);
      batch.insertAll(database.waterProfiles, waterProfiles);
      batch.insertAll(database.methodTools, [
        for (final tool in methodTools)
          tool.copyWith(mergedIntoId: const Value(null)),
      ]);
      batch.insertAll(database.toolMethodLinks, toolMethodLinks);
      batch.insertAll(database.brews, brews);
      batch.insertAll(database.cuppingSessions, sessions);
      batch.insertAll(database.cuppingSessionCups, sessionCups);
      batch.insertAll(
        database.coffeePhotos,
        _numbered(
          coffeePhotoRows,
          (owner, position, name) =>
              CoffeePhoto(coffeeId: owner, position: position, fileName: name),
        ),
      );
      batch.insertAll(
        database.brewPhotos,
        _numbered(
          brewPhotoRows,
          (owner, position, name) =>
              BrewPhoto(brewId: owner, position: position, fileName: name),
        ),
      );
      batch.insertAll(database.brewToolSelections, brewToolSelections);
      batch.insertAll(database.brewCurves, curves);
      batch.insertAll(database.importRecords, importRecords);
      batch.insertAll(database.legacyPayloads, legacyPayloads);
      batch.insertAll(database.appPreferences, preferences);
    });
    await cafeData.write(database);
    await pistonData.write(database);
    // Both endpoints now exist even when a redirect sorts before its target.
    await database.batch((batch) {
      for (final tool in methodTools) {
        if (tool.mergedIntoId != null) {
          batch.update(
            database.methodTools,
            MethodToolsCompanion(mergedIntoId: Value(tool.mergedIntoId)),
            where: (row) => row.id.equals(tool.id),
          );
        }
      }
    });
    await database.mergeMigratedRecipients();
    if (restoreBrewJugs) await database.restoreLegacyBrewRecipients();
  });
}

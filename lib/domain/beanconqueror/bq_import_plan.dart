import 'dart:convert';

import 'package:holybeans/domain/beanconqueror/bq_plan_models.dart';
import 'package:holybeans/domain/beanconqueror/bq_values.dart';
import 'package:holybeans/domain/flavor_notes.dart';
import 'package:holybeans/domain/https_link.dart';

export 'package:holybeans/domain/beanconqueror/bq_plan_models.dart';

typedef BqObject = Map<String, dynamic>;

/// The collections of a BeanConqueror export, already merged from its
/// chunks.
class BqExport {
  const BqExport({
    this.beans = const [],
    this.brews = const [],
    this.mills = const [],
    this.preparations = const [],
    this.waters = const [],
    this.settings = const {},
  });

  final List<BqObject> beans;
  final List<BqObject> brews;
  final List<BqObject> mills;
  final List<BqObject> preparations;
  final List<BqObject> waters;
  final BqObject settings;
}

/// The kinds of BeanConqueror records, as kept in `import_records`.
abstract final class BqKind {
  static const bean = 'bean';
  static const brew = 'brew';
  static const mill = 'mill';
  static const preparation = 'preparation';
  static const tool = 'tool';
  static const water = 'water';
}

/// What the journal already has that an import has to respect: records
/// imported before (by kind, external ID → local ID), catalog entries the
/// import reuses by name, and the freezer labels in use.
class BqJournal {
  const BqJournal({
    this.imported = const {},
    this.methodsByName = const {},
    this.grindersByName = const {},
    this.watersByName = const {},
    this.frozenLabels = const {},
    this.withPhotos = const {},
    this.withCurves = const {},
    this.fingerprints = const {},
    this.editedHere = const {},
  });

  final Map<String, Map<String, String>> imported;

  /// Local coffees and brews that already have photos.
  final Set<String> withPhotos;

  /// Local brews that already have a curve.
  final Set<String> withCurves;

  /// The fingerprint of each record when it was imported, by kind and
  /// external ID.
  final Map<String, Map<String, String>> fingerprints;

  /// Local coffees and brews edited here since they were imported.
  final Set<String> editedHere;

  /// Whether the record [id] of [kind] changed in BeanConqueror since it
  /// was imported, judging by its original JSON.
  bool changed(String kind, String id, String json) =>
      switch (fingerprints[kind]?[id]) {
        final print? => print != bqFingerprint(json),
        null => false,
      };

  /// Lower-cased trimmed name → local ID.
  final Map<String, String> methodsByName;
  final Map<String, String> grindersByName;
  final Map<String, String> watersByName;
  final Set<String> frozenLabels;

  bool wasImported(String kind, String id) =>
      imported[kind]?.containsKey(id) ?? false;
}

String? _id(BqObject object) => switch (object['config']) {
  {'uuid': final String uuid} when uuid.isNotEmpty => uuid,
  _ => null,
};

bool _flag(Object? value) => value == true;

List<String> _photos(Object? attachments) => [
  if (attachments is List)
    for (final path in attachments)
      if (path is String && path.trim().isNotEmpty) bqFileName(path.trim()),
];

String _name(Object? value, String fallback, int max) {
  final text = bqText(value) ?? fallback;
  return text.length > max ? text.substring(0, max) : text;
}

String _key(String name) => name.trim().toLowerCase();

/// The address of the Meticulous a preparation is connected to, if any.
String? _meticulousAddress(BqObject preparation) =>
    switch (preparation['connectedPreparationDevice']) {
      {'type': 'METICULOUS', 'url': final String url}
          when url.trim().isNotEmpty =>
        url.trim(),
      _ => null,
    };

/// The file name of a brew's flow profile, if it recorded one.
String? _flowProfile(BqObject brew) => switch (bqText(brew['flow_profile'])) {
  final path? => bqFileName(path),
  null => null,
};

/// Works out what importing [export] into [journal] adds. Records with an
/// ID imported before are skipped (local edits win); methods, grinders and
/// waters named like one of the journal reuse it.
BqImportPlan planBeanconquerorImport(BqExport export, BqJournal journal) =>
    _Planner(export, journal).plan();

/// One planning run: the export, the journal and the tallies the plan
/// reports.
class _Planner {
  _Planner(this.export, this.journal)
    : brewScale = _ratingScale(export.settings['brew_rating']),
      beanScale = _ratingScale(export.settings['bean_rating']),
      preparations = {
        for (final preparation in export.preparations)
          ?_id(preparation): preparation,
      },
      labels = {...journal.frozenLabels};

  final BqExport export;
  final BqJournal journal;
  final num brewScale;
  final num beanScale;
  final Map<String, BqObject> preparations;

  /// Freezer labels taken, including the ones this import hands out.
  final Set<String> labels;

  final skipped = <String, int>{};
  final warnings = <BqWarning, int>{};
  final updates = <PlannedUpdate>[];
  final changedCoffees = <PlannedChange<PlannedCoffee>>[];
  final changedBrews = <PlannedChange<PlannedBrew>>[];
  int conflicts = 0;

  // Filled while planning, in this order: brews take their names from the
  // equipment and their archive date from their bean.
  final methods = <String, PlannedMethod>{};
  final millNames = <String, String>{};
  final waterNames = <String, String>{};
  final beanIds = <String>{};
  final archivedBeans = <String, int>{};

  static num _ratingScale(Object? max) => switch (max) {
    final num max when max > 0 => max,
    _ => 5,
  };

  BqImportPlan plan() {
    _planMethods();
    final grinders = _planGrinders();
    final waters = _planWaters();
    final coffees = _planCoffees();
    final brews = _planBrews();
    return BqImportPlan(
      methods: methods.values.toList(),
      grinders: grinders,
      waters: waters,
      coffees: coffees,
      brews: brews,
      skipped: skipped,
      warnings: warnings,
      updates: updates,
      changedCoffees: changedCoffees,
      changedBrews: changedBrews,
      conflicts: conflicts,
    );
  }

  void _skip(String kind) =>
      skipped.update(kind, (n) => n + 1, ifAbsent: () => 1);

  void _warn(BqWarning warning) =>
      warnings.update(warning, (n) => n + 1, ifAbsent: () => 1);

  /// Skips a record imported before, which may have gained photos or a
  /// curve in BeanConqueror since.
  void _skipWithUpdates(String kind, String id, BqObject record) {
    _skip(kind);
    final localId = journal.imported[kind]?[id];
    final photos = journal.withPhotos.contains(localId)
        ? const <String>[]
        : _photos(record['attachments']);
    final curve = kind == BqKind.brew && !journal.withCurves.contains(localId)
        ? _flowProfile(record)
        : null;
    if (photos.isNotEmpty || curve != null) {
      updates.add(
        PlannedUpdate(
          kind: kind,
          externalId: id,
          photos: photos,
          flowProfile: curve,
        ),
      );
    }
  }

  /// The local ID of record [id] when it changed in BeanConqueror and not
  /// here, so it is updated; otherwise null, after counting it as skipped
  /// or as a conflict. Either way it still gets the photos or curve it
  /// lacks here: adding them changes nothing done here (such as archiving
  /// its coffee).
  String? _changedOnlyThere(String kind, String id, BqObject record) {
    final localId = journal.imported[kind]?[id];
    if (localId == null || !journal.changed(kind, id, jsonEncode(record))) {
      _skipWithUpdates(kind, id, record);
      return null;
    }
    if (journal.editedHere.contains(localId)) {
      conflicts++;
      _skipWithUpdates(kind, id, record);
      return null;
    }
    return localId;
  }

  void _planMethods() {
    for (final MapEntry(key: id, value: preparation) in preparations.entries) {
      if (journal.wasImported(BqKind.preparation, id)) {
        _skip(BqKind.preparation);
        continue;
      }
      final name = _name(preparation['name'], 'BeanConqueror', 120);
      methods[id] = PlannedMethod(
        origin: BqOrigin(BqKind.preparation, id, jsonEncode(preparation)),
        name: name,
        category: bqMethodCategory(preparation['style_type']),
        templateType: bqText(preparation['type']),
        notes: bqText(preparation['note']),
        archived: _flag(preparation['finished']),
        reuseId: journal.methodsByName[_key(name)],
        machine: _meticulousAddress(preparation) == null ? null : 'meticulous',
        machineAddress: _meticulousAddress(preparation),
        tools: [
          if (preparation['tools'] case final List<Object?> tools)
            for (final tool in tools.whereType<BqObject>())
              if (_id(tool) case final toolId?
                  when !journal.wasImported(BqKind.tool, toolId))
                PlannedTool(
                  origin: BqOrigin(BqKind.tool, toolId, jsonEncode(tool)),
                  name: _name(tool['name'], 'Tool', 120),
                  archived: _flag(tool['archived']),
                ),
        ],
      );
    }
  }

  List<PlannedGrinder> _planGrinders() {
    final millsWithSpeed = {
      for (final brew in export.brews)
        if (bqPositive(brew['mill_speed']) != null && brew['mill'] is String)
          brew['mill'] as String,
    };
    final grinders = <PlannedGrinder>[];
    for (final mill in export.mills) {
      final id = _id(mill);
      if (id == null) continue;
      final name = _name(mill['name'], 'BeanConqueror', 120);
      millNames[id] = name;
      if (journal.wasImported(BqKind.mill, id)) {
        _skip(BqKind.mill);
        continue;
      }
      grinders.add(
        PlannedGrinder(
          origin: BqOrigin(BqKind.mill, id, jsonEncode(mill)),
          name: name,
          notes: bqText(mill['note']),
          archived: _flag(mill['finished']),
          hasAdjustableRpm: millsWithSpeed.contains(id),
          reuseId: journal.grindersByName[_key(name)],
        ),
      );
    }
    return grinders;
  }

  List<PlannedWater> _planWaters() {
    final waters = <PlannedWater>[];
    for (final water in export.waters) {
      final id = _id(water);
      if (id == null) continue;
      final name = _name(water['name'], 'BeanConqueror', 120);
      waterNames[id] = name;
      if (journal.wasImported(BqKind.water, id)) {
        _skip(BqKind.water);
        continue;
      }
      waters.add(_water(id, name, water));
    }
    return waters;
  }

  PlannedWater _water(String id, String name, BqObject water) {
    double? ion(String field, double molarMass, {int charge = 2}) => bqIonPpm(
      water[field],
      water['${field}_type'],
      molarMass: molarMass,
      charge: charge,
    );
    return PlannedWater(
      origin: BqOrigin(BqKind.water, id, jsonEncode(water)),
      name: name,
      ghPpm: bqHardnessPpm(
        water['general_hardness'],
        water['general_hardness_type'],
      ),
      khPpm: bqHardnessPpm(
        water['total_alkalinity'],
        water['total_alkalinity_type'],
      ),
      tdsPpm: bqPositive(water['tds']),
      calciumPpm: ion('calcium', 40.078),
      magnesiumPpm: ion('magnesium', 24.305),
      sodiumPpm: ion('sodium', 22.990, charge: 1),
      potassiumPpm: ion('potassium', 39.098, charge: 1),
      chloridePpm: ion('chloride', 35.453, charge: 1),
      sulfatePpm: ion('sulfate', 96.06),
      notes: bqText(water['note']),
      archived: _flag(water['finished']),
      reuseId: journal.watersByName[_key(name)],
    );
  }

  /// A freezer label like [wanted] that no other portion uses.
  String _freeLabel(String wanted) {
    var label = wanted.length > 10 ? wanted.substring(0, 10) : wanted;
    var suffix = 2;
    while (labels.contains(label)) {
      final base = wanted.length > 8 ? wanted.substring(0, 8) : wanted;
      label = '$base-${suffix++}';
    }
    labels.add(label);
    return label;
  }

  List<PlannedCoffee> _planCoffees() {
    // Coffee used per bean, for what is left in each bag, and the last
    // brew, for when a finished bean was archived.
    final usedGrams = <String, double>{};
    final lastBrewMs = <String, int>{};
    for (final brew in export.brews) {
      final bean = brew['bean'];
      if (bean is! String) continue;
      usedGrams[bean] =
          (usedGrams[bean] ?? 0) + (bqPositive(brew['grind_weight']) ?? 0);
      if (bqTimestampMs(brew['config']) case final ms?) {
        if (ms > (lastBrewMs[bean] ?? 0)) lastBrewMs[bean] = ms;
      }
    }

    final coffees = <PlannedCoffee>[];
    for (final bean in export.beans) {
      final id = _id(bean);
      if (id == null) continue;
      beanIds.add(id);
      final createdMs = bqTimestampMs(bean['config']);
      final archivedMs = _flag(bean['finished'])
          ? lastBrewMs[id] ?? createdMs ?? DateTime.now().millisecondsSinceEpoch
          : null;
      if (archivedMs != null) archivedBeans[id] = archivedMs;
      String? changeOf;
      if (journal.wasImported(BqKind.bean, id)) {
        changeOf = _changedOnlyThere(BqKind.bean, id, bean);
        if (changeOf == null) continue;
      } else if (createdMs == null) {
        _warn(BqWarning.missingDate);
      }
      final coffee = _coffee(
        id,
        bean,
        createdMs: createdMs,
        archivedMs: archivedMs,
        usedGrams: usedGrams[id] ?? 0,
        changeOf: changeOf,
      );
      if (changeOf case final localId?) {
        changedCoffees.add(PlannedChange(localId, coffee));
      } else {
        coffees.add(coffee);
      }
    }
    return coffees;
  }

  /// Bean [id] as a coffee with one bag, holding what [usedGrams] left;
  /// [changeOf] is the local coffee it updates, if any.
  PlannedCoffee _coffee(
    String id,
    BqObject bean, {
    required int? createdMs,
    required int? archivedMs,
    required double usedGrams,
    required String? changeOf,
  }) {
    final finished = _flag(bean['finished']);
    final weight = bqPositive(bean['weight']);
    // Tenths of a gram, as scales show them, without float leftovers.
    final left = weight == null
        ? null
        : ((weight - usedGrams) * 10).round() / 10;
    final frozenDate = bqLocalDate(bean['frozenDate']);
    final thawedDate = bqLocalDate(bean['unfrozenDate']);
    final stillFrozen = frozenDate != null && thawedDate == null;
    final keepsCoffee = !finished && left != null && left > 0;
    // A bean imported before keeps its stock here; only new bags go to the
    // freezer.
    final portion = changeOf == null && stillFrozen && keepsCoffee
        ? PlannedPortion(
            label: _freeLabel(bqText(bean['frozenId']) ?? 'BQ'),
            frozenDate: frozenDate,
            grams: left,
            container: bqContainer(bean['frozenStorageType']),
            notes: bqText(bean['frozenNote']),
          )
        : null;
    // These are calendar dates; a daylight-saving change is still one day.
    final pauseDays = frozenDate != null && thawedDate != null
        ? DateTime.parse('${thawedDate}T00:00:00Z')
              .difference(DateTime.parse('${frozenDate}T00:00:00Z'))
              .inDays
        : null;

    return PlannedCoffee(
      origin: BqOrigin(BqKind.bean, id, jsonEncode(bean)),
      name: _name(bean['name'], 'BeanConqueror', 200),
      roaster: _name(bean['roaster'], '', 200),
      createdAtMs: createdMs ?? DateTime.now().millisecondsSinceEpoch,
      notes: bqText(bean['note']),
      paidPriceCents: switch (bqPositive(bean['cost'])) {
        final cost? => (cost * 100).round(),
        null => null,
      },
      rating: bqRating(bean['rating'], beanScale),
      roastLevel: bqRoastLevel(bean['roast']),
      flavorProfile: switch (bqText(bean['aromatics'])) {
        final notes? => normalizeFlavorNotes(notes),
        null => null,
      },
      isFavorite: _flag(bean['favourite']),
      isDecaf: _flag(bean['decaffeinated']),
      shopUrl: httpsLink(bqText(bean['url'])),
      archivedAtMs: archivedMs,
      components: [
        if (bean['bean_information'] case final List<Object?> origins)
          for (final origin in origins.whereType<BqObject>())
            PlannedComponent(
              country: bqText(origin['country']),
              region: bqText(origin['region']),
              farm: bqText(origin['farm']),
              producer: bqText(origin['farmer']),
              variety: bqText(origin['variety']),
              process: bqText(origin['processing']),
              altitudeMeters: bqAltitude(origin['elevation']),
              altitudeMaxMeters: bqAltitudeMax(origin['elevation']),
              harvest: bqText(origin['harvest_time']),
            ),
      ].where((component) => !component.isEmpty).toList(),
      lot: PlannedLot(
        roastDate: bqLocalDate(bean['roastingDate']),
        purchaseDate: bqLocalDate(bean['buyDate']),
        openedDate: bqLocalDate(bean['openDate']),
        initialGrams: weight,
        remainingGrams: left == null
            ? null
            : finished || portion != null || left < 0
            ? 0
            : left,
        overdrawGrams: left != null && left < 0 ? -left : null,
        frozenPauseDays: pauseDays != null && pauseDays > 0 ? pauseDays : null,
      ),
      portion: portion,
      // A record that has photos here keeps them.
      photos: journal.withPhotos.contains(changeOf)
          ? const []
          : _photos(bean['attachments']),
    );
  }

  List<PlannedBrew> _planBrews() {
    final espressoPreparations = {
      for (final MapEntry(:key, :value) in preparations.entries)
        if (bqMethodCategory(value['style_type']) == 'espresso') key,
    };
    final brews = <PlannedBrew>[];
    for (final brew in export.brews) {
      final id = _id(brew);
      if (id == null) continue;
      String? changeOf;
      if (journal.wasImported(BqKind.brew, id)) {
        changeOf = _changedOnlyThere(BqKind.brew, id, brew);
        if (changeOf == null) continue;
      }
      final bean = brew['bean'];
      if (bean is! String ||
          !(beanIds.contains(bean) || journal.wasImported(BqKind.bean, bean))) {
        _warn(BqWarning.brewWithoutBean);
        continue;
      }
      final brewedMs = bqTimestampMs(brew['config']);
      if (brewedMs == null) {
        _warn(BqWarning.missingDate);
        continue;
      }
      final preparationId = bqText(brew['method_of_preparation']);
      final espresso = espressoPreparations.contains(preparationId);
      _lendVessel(brew, preparationId, espresso: espresso);
      final planned = _brew(
        id,
        brew,
        bean: bean,
        brewedMs: brewedMs,
        preparationId: preparationId,
        espresso: espresso,
        changeOf: changeOf,
      );
      if (changeOf case final localId?) {
        changedBrews.add(PlannedChange(localId, planned));
      } else {
        brews.add(planned);
      }
    }
    return brews;
  }

  /// A filter brew that names a jug lends it to its method, if the method
  /// has none yet.
  void _lendVessel(
    BqObject brew,
    String? preparationId, {
    required bool espresso,
  }) {
    if (methods[preparationId] case final method?
        when method.vesselName == null && !espresso) {
      final vessel = bqText(brew['vessel_name']);
      final grams = bqPositive(brew['vessel_weight']);
      if (vessel != null || grams != null) {
        method
          ..vesselName = vessel
          ..vesselGrams = grams;
      }
    }
  }

  /// Brew [id] of [bean]; [changeOf] is the local brew it updates, if any.
  PlannedBrew _brew(
    String id,
    BqObject brew, {
    required String bean,
    required int brewedMs,
    required String? preparationId,
    required bool espresso,
    required String? changeOf,
  }) {
    final millId = bqText(brew['mill']);
    final waterId = bqText(brew['water']);
    final phase = bqSeconds(
      brew['coffee_blooming_time'],
      brew['coffee_blooming_time_milliseconds'],
    );
    return PlannedBrew(
      origin: BqOrigin(BqKind.brew, id, jsonEncode(brew)),
      beanId: bean,
      preparationId: preparationId,
      millId: millId,
      waterId: waterId,
      toolIds: [
        if (brew['method_of_preparation_tools'] case final List<Object?> tools)
          ...tools.whereType<String>(),
      ],
      methodName: _name(
        preparations[preparationId]?['name'],
        'BeanConqueror',
        120,
      ),
      grinderName: millNames[millId],
      waterName: waterNames[waterId],
      brewedAtMs: brewedMs,
      grindSetting: bqText(brew['grind_size']),
      doseGrams: bqPositive(brew['grind_weight']),
      waterGrams: espresso
          ? null
          : bqQuantity(brew['brew_quantity'], brew['brew_quantity_type']),
      beverageGrams: bqQuantity(
        brew['brew_beverage_quantity'],
        brew['brew_beverage_quantity_type'],
      ),
      timeSeconds: bqSeconds(brew['brew_time'], brew['brew_time_milliseconds']),
      temperatureC: bqPositive(brew['brew_temperature']),
      tdsPercent: bqPositive(brew['tds']),
      grindRpm: bqPositive(brew['mill_speed'])?.round(),
      preinfusionSeconds: espresso ? phase : null,
      bloomSeconds: espresso ? null : phase,
      firstDripSeconds: espresso
          ? bqSeconds(
              brew['coffee_first_drip_time'],
              brew['coffee_first_drip_time_milliseconds'],
            )
          : null,
      profileName: bqText(brew['pressure_profile']),
      rating: bqRating(brew['rating'], brewScale),
      notes: bqText(brew['note']),
      archivedAtMs: archivedBeans[bean],
      photos: journal.withPhotos.contains(changeOf)
          ? const []
          : _photos(brew['attachments']),
      flowProfile: _flowProfile(brew),
      isFavorite: _flag(brew['favourite']) || _flag(brew['best_brew']),
      isBestBrew: _flag(brew['best_brew']),
      vessel: espresso ? null : bqBrewVessel(brew),
    );
  }
}

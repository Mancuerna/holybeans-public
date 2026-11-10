part of '../journal_backup.dart';

// Reading, checking and writing the rows of a backup.

({Map<String, dynamic> data, int version}) _readBackup(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map<String, dynamic> ||
      decoded['format'] != JournalBackup.format ||
      decoded['version'] is! int ||
      !JournalBackup._readableVersions.contains(decoded['version']) ||
      decoded['data'] is! Map<String, dynamic>) {
    throw const FormatException('Unsupported HolyBeans backup');
  }
  final data = decoded['data'] as Map<String, dynamic>;
  if ((decoded['version'] as int) >= 21 &&
      !data.containsKey('toolMethodLinks')) {
    throw const FormatException('Missing tool associations');
  }
  if ((decoded['version'] as int) >= 27 &&
      (!data.containsKey('cuppingSessions') ||
          !data.containsKey('cuppingSessionCups'))) {
    throw const FormatException('Missing cupping collections');
  }
  if ((decoded['version'] as int) >= 29 &&
      !data.containsKey('stockAdjustments')) {
    throw const FormatException('Missing stock adjustments');
  }
  if ((decoded['version'] as int) >= 30 && !data.containsKey('recipients')) {
    throw const FormatException('Missing recipients');
  }
  if ((decoded['version'] as int) >= 33 &&
      !const {
        'roasters',
        'coffeeRoasterLinks',
        'cafes',
        'cafeDrinks',
        'cafeDrinkPhotos',
      }.every(data.containsKey)) {
    throw const FormatException('Missing cafe collections');
  }
  if ((decoded['version'] as int) >= 35 &&
      !const {
        'pistonMachines',
        'pistonMethodLinks',
        'pistonMeasurements',
        'pistonMaintenances',
      }.every((key) => data[key] is List)) {
    throw const FormatException('Missing piston collections');
  }
  const keys = JournalBackup._collections;
  if (data.keys.toSet().difference(keys).isNotEmpty) {
    throw const FormatException('Unknown backup collection');
  }
  return (data: data, version: decoded['version'] as int);
}

Future<List<Map<String, dynamic>>> _encode<T>(
  Future<List<T>> future,
  String Function(T) id,
  Map<String, dynamic> Function(T) toJson,
) async {
  final rows = await future;
  rows.sort((left, right) => id(left).compareTo(id(right)));
  return rows.map(toJson).toList();
}

List<T> _decode<T>(
  Map<String, dynamic> data,
  String key,
  T Function(Map<String, dynamic>) fromJson, {
  Set<String> ignoredFields = const {},
}) {
  final raw = data[key];
  if (raw is! List) throw FormatException('Missing backup collection: $key');
  return raw.map((entry) {
    if (entry is! Map<String, dynamic>) {
      throw FormatException('Invalid record in backup collection: $key');
    }
    entry = {...entry}
      ..removeWhere((field, _) => ignoredFields.contains(field));
    final T value;
    try {
      value = fromJson(entry);
    } on TypeError {
      throw FormatException('Invalid field type in backup collection: $key');
    }
    final knownKeys = switch (value) {
      final PistonMachine row => row.toJson().keys.toSet(),
      final PistonMethodLink row => row.toJson().keys.toSet(),
      final PistonMeasurement row => row.toJson().keys.toSet(),
      final PistonMaintenance row => row.toJson().keys.toSet(),
      final Roaster row => row.toJson().keys.toSet(),
      final CoffeeRoasterLink row => row.toJson().keys.toSet(),
      final Cafe row => row.toJson().keys.toSet(),
      final CafeDrink row => row.toJson().keys.toSet(),
      final CafeDrinkPhoto row => row.toJson().keys.toSet(),

      final CuppingSession row => row.toJson().keys.toSet(),
      final CuppingSessionCup row => row.toJson().keys.toSet(),
      final StockAdjustment row => row.toJson().keys.toSet(),
      final Coffee row => row.toJson().keys.toSet(),
      final CoffeeComponent row => row.toJson().keys.toSet(),
      final CoffeeLot row => row.toJson().keys.toSet(),
      final FrozenPortion row => row.toJson().keys.toSet(),
      final Recipient row => row.toJson().keys.toSet(),
      final BrewMethod row => row.toJson().keys.toSet(),
      final Grinder row => row.toJson().keys.toSet(),
      final WaterProfile row => row.toJson().keys.toSet(),
      final CoffeePhoto row => row.toJson().keys.toSet(),
      final BrewPhoto row => row.toJson().keys.toSet(),
      final MethodTool row => row.toJson().keys.toSet(),
      final ToolMethodLink row => row.toJson().keys.toSet(),
      final Brew row => row.toJson().keys.toSet(),
      final BrewToolSelection row => row.toJson().keys.toSet(),
      final BrewCurve row => row.toJson().keys.toSet(),
      final ImportRecord row => row.toJson().keys.toSet(),
      final LegacyPayload row => row.toJson().keys.toSet(),
      final AppPreference row => row.toJson().keys.toSet(),
      _ => <String>{},
    };
    if (entry.keys.toSet().difference(knownKeys).isNotEmpty) {
      throw FormatException('Unknown field in backup collection: $key');
    }
    return value;
  }).toList();
}

String _photoKey(String owner, int position) =>
    '$owner\u0000${position.toString().padLeft(4, '0')}';

/// Rows for [photos] (sorted by owner), numbered from 0 within each owner.
List<T> _numbered<T>(
  List<(String, String)> photos,
  T Function(String owner, int position, String name) row,
) {
  final next = <String, int>{};
  return [
    for (final (owner, name) in photos)
      row(owner, next.update(owner, (n) => n + 1, ifAbsent: () => 0), name),
  ];
}

void _ensureUnique(Iterable<String> values, String description) {
  final seen = <String>{};
  for (final value in values) {
    if (!seen.add(value)) throw FormatException('Duplicate $description');
  }
}

void _validateWaterProfile(WaterProfile profile) {
  if (profile.recipeJson != null) WaterRecipe.fromJson(profile.recipeJson!);
  if (profile.name.trim().isEmpty || profile.name.length > 120) {
    throw const FormatException('Water profile has an invalid name');
  }
  for (final value in [
    profile.ghPpmAsCaCO3,
    profile.khPpmAsCaCO3,
    profile.tdsPpm,
    profile.calciumPpm,
    profile.magnesiumPpm,
    profile.sodiumPpm,
    profile.potassiumPpm,
    profile.chloridePpm,
    profile.sulfatePpm,
    profile.bicarbonatePpm,
  ]) {
    if (value != null && (!value.isFinite || value < 0)) {
      throw const FormatException('Water profile has an invalid ppm value');
    }
  }
  final ph = profile.ph;
  if (ph != null && (!ph.isFinite || ph < 0 || ph > 14)) {
    throw const FormatException('Water profile has an invalid pH value');
  }
}

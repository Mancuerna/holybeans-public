import 'dart:convert';

enum WaterIon {
  calcium,
  magnesium,
  sodium,
  potassium,
  chloride,
  sulfate,
  bicarbonate,
}

enum WaterSaltGroup { magnesium, calcium, alkalinity }

enum WaterSalt {
  epsom(WaterSaltGroup.magnesium),
  magnesiumChloride(WaterSaltGroup.magnesium),
  calciumChloride(WaterSaltGroup.calcium),
  sodiumBicarbonate(WaterSaltGroup.alkalinity),
  potassiumBicarbonate(WaterSaltGroup.alkalinity);

  const WaterSalt(this.group);
  final WaterSaltGroup group;
  bool get contributesGh => group != WaterSaltGroup.alkalinity;
}

enum CalciumForm { anhydrous, dihydrate }

enum WaterCalculationMode { preset, custom, quantities }

const calciumCarbonateMass = 100.0869;
const bicarbonateMass = 61.0168;

class WaterComposition {
  factory WaterComposition.fromMap(Map<String, dynamic> map) {
    final values = map['ions'];
    if (values is! Map<String, dynamic>) {
      throw const FormatException('Missing water ions');
    }
    double? number(Object? value) {
      if (value == null) return null;
      if (value is! num || !value.isFinite || value < 0) {
        throw const FormatException('Invalid water concentration');
      }
      return value.toDouble();
    }

    return WaterComposition(
      ions: {for (final ion in WaterIon.values) ion: number(values[ion.name])},
      measuredGh: number(map['gh']),
      measuredKh: number(map['kh']),
    );
  }
  WaterComposition({
    Map<WaterIon, double?> ions = const {},
    this.measuredGh,
    this.measuredKh,
  }) : ions = Map.unmodifiable({
         for (final ion in WaterIon.values) ion: ions[ion],
       }) {
    for (final value in [...this.ions.values, measuredGh, measuredKh]) {
      if (value != null && (!value.isFinite || value < 0)) {
        throw ArgumentError.value(value, 'water concentration');
      }
    }
  }

  factory WaterComposition.distilled() =>
      WaterComposition(ions: {for (final ion in WaterIon.values) ion: 0});

  final Map<WaterIon, double?> ions;
  final double? measuredGh;
  final double? measuredKh;

  double? operator [](WaterIon ion) => ions[ion];
  double? get gh => measuredGh ?? calculatedGh;

  double? get calculatedGh {
    final ca = this[WaterIon.calcium];
    final mg = this[WaterIon.magnesium];
    return ca == null || mg == null
        ? null
        : calciumCarbonateMass * (ca / 40.078 + mg / 24.305);
  }

  double? get calciumMagnesiumMassRatio {
    final ca = this[WaterIon.calcium];
    final mg = this[WaterIon.magnesium];
    return ca == null || mg == null || mg == 0 ? null : ca / mg;
  }

  double? get kh =>
      measuredKh ??
      (this[WaterIon.bicarbonate] == null
          ? null
          : this[WaterIon.bicarbonate]! *
                calciumCarbonateMass /
                (2 * bicarbonateMass));
  double? get mineralSum => ions.values.any((v) => v == null)
      ? null
      : ions.values.fold<double>(0, (sum, v) => sum + v!);

  WaterComposition add(WaterComposition addition) => WaterComposition(
    ions: {
      for (final ion in WaterIon.values)
        ion: this[ion] == null || addition[ion] == null
            ? null
            : this[ion]! + addition[ion]!,
    },
    measuredGh: gh == null || addition.gh == null ? null : gh! + addition.gh!,
    measuredKh: kh == null || addition.kh == null ? null : kh! + addition.kh!,
  );

  Map<String, Object?> toMap() => {
    'ions': {for (final ion in WaterIon.values) ion.name: this[ion]},
    'gh': measuredGh,
    'kh': measuredKh,
  };
}

double saltMolarMass(WaterSalt salt, CalciumForm calcium) => switch (salt) {
  WaterSalt.epsom => 246.47,
  WaterSalt.magnesiumChloride => 203.30,
  WaterSalt.calciumChloride =>
    calcium == CalciumForm.anhydrous ? 110.99 : 147.02,
  WaterSalt.sodiumBicarbonate => 84.01,
  WaterSalt.potassiumBicarbonate => 100.115,
};

Map<WaterIon, double> _ionMasses(WaterSalt salt) => switch (salt) {
  WaterSalt.epsom => {WaterIon.magnesium: 24.305, WaterIon.sulfate: 96.063},
  WaterSalt.magnesiumChloride => {
    WaterIon.magnesium: 24.305,
    WaterIon.chloride: 70.90,
  },
  WaterSalt.calciumChloride => {
    WaterIon.calcium: 40.078,
    WaterIon.chloride: 70.90,
  },
  WaterSalt.sodiumBicarbonate => {
    WaterIon.sodium: 22.989769,
    WaterIon.bicarbonate: bicarbonateMass,
  },
  WaterSalt.potassiumBicarbonate => {
    WaterIon.potassium: 39.0983,
    WaterIon.bicarbonate: bicarbonateMass,
  },
};

WaterComposition saltContribution(
  WaterSalt salt,
  CalciumForm calcium,
  double gramsPerLitre,
) {
  if (!gramsPerLitre.isFinite || gramsPerLitre < 0) {
    throw ArgumentError.value(gramsPerLitre, 'gramsPerLitre');
  }
  final masses = _ionMasses(salt);
  return WaterComposition(
    ions: {
      for (final ion in WaterIon.values)
        ion:
            gramsPerLitre *
            1000 *
            (masses[ion] ?? 0) /
            saltMolarMass(salt, calcium),
    },
  );
}

WaterComposition waterFromSalts(
  Map<WaterSalt, double> grams,
  double litres,
  CalciumForm calcium,
) {
  if (!litres.isFinite || litres <= 0) {
    throw ArgumentError.value(litres, 'litres');
  }
  var result = WaterComposition.distilled();
  for (final salt in WaterSalt.values) {
    result = result.add(
      saltContribution(salt, calcium, (grams[salt] ?? 0) / litres),
    );
  }
  return result;
}

class WaterRecipe {
  factory WaterRecipe.fromJson(String json) {
    try {
      final raw = jsonDecode(json);
      if (raw is! Map<String, dynamic> ||
          raw['version'] != 1 ||
          raw['grams'] is! Map<String, dynamic>) {
        throw const FormatException('Unsupported water recipe');
      }
      final amounts = raw['grams'] as Map<String, dynamic>;
      return WaterRecipe(
        litres: (raw['litres'] as num).toDouble(),
        calcium: CalciumForm.values.byName(raw['calcium'] as String),
        mode: WaterCalculationMode.values.byName(raw['mode'] as String),
        base: WaterComposition.fromMap(raw['base'] as Map<String, dynamic>),
        target: raw['target'] == null
            ? null
            : WaterComposition.fromMap(raw['target'] as Map<String, dynamic>),
        grams: {
          for (final salt in WaterSalt.values)
            salt: (amounts[salt.name] as num).toDouble(),
        },
        presetId: raw['preset'] as String?,
        ghSource: WaterSalt.values.byName(raw['ghSource'] as String),
        khSource: WaterSalt.values.byName(raw['khSource'] as String),
        calciumGhFraction: (raw['calciumGhFraction'] as num?)?.toDouble(),
        ionTargets: raw['ionTargets'] as bool? ?? false,
        availableSalts: raw['availableSalts'] == null
            ? null
            : (raw['availableSalts'] as List<dynamic>)
                  .map((s) => WaterSalt.values.byName(s as String))
                  .toSet(),
      );
    } catch (_) {
      throw const FormatException('Invalid water recipe');
    }
  }
  WaterRecipe({
    required this.litres,
    required this.calcium,
    required this.mode,
    required this.base,
    required Map<WaterSalt, double> grams,
    this.target,
    this.presetId,
    this.ghSource = WaterSalt.epsom,
    this.khSource = WaterSalt.sodiumBicarbonate,
    this.calciumGhFraction,
    this.ionTargets = false,
    Set<WaterSalt>? availableSalts,
  }) : availableSalts = availableSalts == null
           ? null
           : Set.unmodifiable(availableSalts),
       grams = Map.unmodifiable({
         for (final salt in WaterSalt.values) salt: grams[salt] ?? 0,
       }) {
    if (!litres.isFinite || litres <= 0 || litres > 10000) {
      throw ArgumentError.value(litres, 'litres');
    }
    for (final amount in this.grams.values) {
      if (!amount.isFinite || amount < 0 || amount > 100000) {
        throw ArgumentError.value(amount, 'salt mass');
      }
    }
    if (calciumGhFraction != null &&
        (!calciumGhFraction!.isFinite ||
            calciumGhFraction! < 0 ||
            calciumGhFraction! > 1 ||
            ghSource.group != WaterSaltGroup.magnesium)) {
      throw ArgumentError('Invalid hardness mixture');
    }
    if (ionTargets &&
        (mode != WaterCalculationMode.custom ||
            target?[WaterIon.calcium] == null ||
            target?[WaterIon.magnesium] == null ||
            calciumGhFraction != null)) {
      throw ArgumentError('Invalid ion targets');
    }
    if (availableSalts != null &&
        this.grams.entries.any(
          (e) => e.value > 0 && !availableSalts.contains(e.key),
        )) {
      throw ArgumentError('Dose requires an unavailable salt');
    }
    if (!ghSource.contributesGh || khSource.contributesGh) {
      throw ArgumentError('Invalid salt sources');
    }
    if (mode != WaterCalculationMode.quantities &&
        (target?.gh == null || target?.kh == null)) {
      throw ArgumentError('Missing target');
    }
  }

  final double litres;
  final CalciumForm calcium;
  final WaterCalculationMode mode;
  final WaterComposition base;
  final WaterComposition? target;
  final Map<WaterSalt, double> grams;
  final String? presetId;
  final WaterSalt ghSource;
  final WaterSalt khSource;
  final double? calciumGhFraction;
  final bool ionTargets;
  final Set<WaterSalt>? availableSalts;

  WaterComposition get added => waterFromSalts(grams, litres, calcium);

  WaterComposition get result => base.add(added);

  String toJson() => jsonEncode({
    'version': 1,
    'litres': litres,
    'calcium': calcium.name,
    'mode': mode.name,
    'base': base.toMap(),
    'target': target?.toMap(),
    'preset': presetId,
    'ghSource': ghSource.name,
    'khSource': khSource.name,
    if (calciumGhFraction != null) 'calciumGhFraction': calciumGhFraction,
    if (ionTargets) 'ionTargets': true,
    if (availableSalts != null)
      'availableSalts': [
        for (final salt in WaterSalt.values)
          if (availableSalts!.contains(salt)) salt.name,
      ],
    'grams': {for (final salt in WaterSalt.values) salt.name: grams[salt]},
  });
}

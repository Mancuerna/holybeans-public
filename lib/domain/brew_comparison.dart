import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/domain/brew_ratio.dart';
import 'package:holybeans/domain/shot_curve.dart';

typedef ComparisonBrew = ({
  double? beverageGrams,
  int? bloomCount,
  int? bloomSeconds,
  double? doseGrams,
  int? feederRpm,
  int? firstDripSeconds,
  int? grindRpm,
  String? grindSetting,
  String? grinderName,
  String id,
  bool isPreGround,
  String methodName,
  int? pourCount,
  int? preinfusionSeconds,
  double? pressureBar,
  String? profileName,
  double? rating,
  double? tdsPercent,
  double? temperatureC,
  int? timeSeconds,
  double? waterGrams,
  String? waterProfileName,
});

class BrewComparisonValue {
  const BrewComparisonValue(this.parameter, this.a, this.b, this.unit);

  final BrewParameter parameter;
  final double? a;
  final double? b;
  final String unit;

  double? get difference => a == null || b == null ? null : b! - a!;
}

class BrewDifference {
  const BrewDifference(
    this.parameter,
    this.a,
    this.b, {
    this.unit = '',
    this.result = false,
  });
  final BrewParameter parameter;
  final Object? a;
  final Object? b;
  final String unit;
  final bool result;
}

class BrewComparison {
  BrewComparison(this.a, this.b, {String? categoryA, String? categoryB})
    : espressoA = isEspressoMethod(
        category: categoryA,
        methodName: a.methodName,
      ),
      espressoB = isEspressoMethod(
        category: categoryB,
        methodName: b.methodName,
      );

  final ComparisonBrew a;
  final ComparisonBrew b;
  final bool espressoA;
  final bool espressoB;

  static double? _ratio(ComparisonBrew brew, bool espresso) {
    final output = espresso ? brew.beverageGrams : brew.waterGrams;
    final dose = brew.doseGrams;
    if (output == null || dose == null || output <= 0 || dose <= 0) return null;
    return output / dose;
  }

  double? get ratioA => _ratio(a, espressoA);
  double? get ratioB => _ratio(b, espressoB);
  double? get ratioDifference =>
      espressoA == espressoB && ratioA != null && ratioB != null
      ? ratioB! - ratioA!
      : null;

  List<BrewDifference> differences({
    String? coffeeA,
    String? coffeeB,
    required String preGroundLabel,
    String? toolsA,
    String? toolsB,
  }) {
    const results = {
      BrewParameter.beverage,
      BrewParameter.time,
      BrewParameter.firstDrip,
      BrewParameter.pressure,
      BrewParameter.tds,
      BrewParameter.ey,
      BrewParameter.rating,
    };
    String? text(String? value) =>
        value == null || value.trim().isEmpty ? null : value.trim();
    final rows = <BrewDifference>[
      BrewDifference(BrewParameter.coffee, text(coffeeA), text(coffeeB)),
      BrewDifference(
        BrewParameter.method,
        text(a.methodName),
        text(b.methodName),
      ),
      BrewDifference(
        BrewParameter.grinder,
        a.isPreGround ? preGroundLabel : text(a.grinderName),
        b.isPreGround ? preGroundLabel : text(b.grinderName),
      ),
      BrewDifference(
        BrewParameter.grindSetting,
        a.isPreGround ? null : text(a.grindSetting),
        b.isPreGround ? null : text(b.grindSetting),
      ),
      BrewDifference(
        BrewParameter.waterProfile,
        text(a.waterProfileName),
        text(b.waterProfileName),
      ),
      BrewDifference(
        BrewParameter.profile,
        text(a.profileName),
        text(b.profileName),
      ),
      BrewDifference(BrewParameter.tools, text(toolsA), text(toolsB)),
      for (final row in numbers)
        if (!(row.parameter == BrewParameter.water && espressoA && espressoB) &&
            !((row.parameter == BrewParameter.grindRpm ||
                    row.parameter == BrewParameter.feederRpm) &&
                a.isPreGround &&
                b.isPreGround))
          BrewDifference(
            row.parameter,
            (row.parameter == BrewParameter.grindRpm ||
                        row.parameter == BrewParameter.feederRpm) &&
                    a.isPreGround
                ? null
                : row.a,
            (row.parameter == BrewParameter.grindRpm ||
                        row.parameter == BrewParameter.feederRpm) &&
                    b.isPreGround
                ? null
                : row.b,
            unit: row.unit,
            result: results.contains(row.parameter),
          ),
      if (espressoA == espressoB)
        BrewDifference(BrewParameter.ratio, ratioA, ratioB, result: espressoA),
    ];
    return rows.where((row) {
      if (row.a is num && row.b is num) {
        return ((row.a! as num) - (row.b! as num)).abs() > .000001;
      }
      return row.a != row.b;
    }).toList();
  }

  List<BrewComparisonValue> get numbers => [
    BrewComparisonValue(BrewParameter.dose, a.doseGrams, b.doseGrams, 'g'),
    BrewComparisonValue(BrewParameter.water, a.waterGrams, b.waterGrams, 'g'),
    BrewComparisonValue(
      BrewParameter.beverage,
      a.beverageGrams,
      b.beverageGrams,
      'g',
    ),
    BrewComparisonValue(
      BrewParameter.temperature,
      a.temperatureC,
      b.temperatureC,
      '°C',
    ),
    BrewComparisonValue(
      BrewParameter.time,
      a.timeSeconds?.toDouble(),
      b.timeSeconds?.toDouble(),
      's',
    ),
    BrewComparisonValue(
      BrewParameter.grindRpm,
      a.grindRpm?.toDouble(),
      b.grindRpm?.toDouble(),
      'RPM',
    ),

    BrewComparisonValue(
      BrewParameter.feederRpm,
      a.feederRpm?.toDouble(),
      b.feederRpm?.toDouble(),
      'RPM',
    ),
    BrewComparisonValue(
      BrewParameter.pressure,
      a.pressureBar,
      b.pressureBar,
      'bar',
    ),
    BrewComparisonValue(
      BrewParameter.preinfusion,
      a.preinfusionSeconds?.toDouble(),
      b.preinfusionSeconds?.toDouble(),
      's',
    ),
    BrewComparisonValue(
      BrewParameter.firstDrip,
      a.firstDripSeconds?.toDouble(),
      b.firstDripSeconds?.toDouble(),
      's',
    ),
    BrewComparisonValue(
      BrewParameter.bloom,
      a.bloomSeconds?.toDouble(),
      b.bloomSeconds?.toDouble(),
      's',
    ),
    BrewComparisonValue(
      BrewParameter.bloomCount,
      a.bloomCount?.toDouble(),
      b.bloomCount?.toDouble(),
      '',
    ),
    BrewComparisonValue(
      BrewParameter.pourCount,
      a.pourCount?.toDouble(),
      b.pourCount?.toDouble(),
      '',
    ),
    BrewComparisonValue(BrewParameter.tds, a.tdsPercent, b.tdsPercent, '%'),
    BrewComparisonValue(
      BrewParameter.ey,
      extractionYieldPercent(
        doseGrams: a.doseGrams,
        beverageGrams: a.beverageGrams,
        tdsPercent: a.tdsPercent,
      ),
      extractionYieldPercent(
        doseGrams: b.doseGrams,
        beverageGrams: b.beverageGrams,
        tdsPercent: b.tdsPercent,
      ),
      '%',
    ),
    BrewComparisonValue(BrewParameter.rating, a.rating, b.rating, '/ 10'),
  ];
}

bool hasSensoryComparison(ComparisonBrew a, ComparisonBrew b) {
  bool complete(ComparisonBrew brew) {
    final ey = extractionYieldPercent(
      doseGrams: brew.doseGrams,
      beverageGrams: brew.beverageGrams,
      tdsPercent: brew.tdsPercent,
    );
    final tds = brew.tdsPercent;
    return ey != null &&
        ey.isFinite &&
        ey > 0 &&
        tds != null &&
        tds.isFinite &&
        tds > 0;
  }

  return complete(a) && complete(b);
}

class ComparisonCurve {
  const ComparisonCurve(this.curve, this.flowUnit);

  final ShotCurve curve;
  final String flowUnit;

  String unit(CurveSeries series) => switch (series) {
    CurveSeries.weight => 'g',
    CurveSeries.flow => flowUnit,
    CurveSeries.pressure => 'bar',
  };

  List<({int timeMs, double value})> samples(CurveSeries series) {
    final values = curve.values(series);
    return [
      for (var i = 0; i < curve.timesMs.length && i < values.length; i++)
        if (curve.timesMs[i] >= 0 && values[i].isFinite)
          (timeMs: curve.timesMs[i], value: values[i]),
    ];
  }
}

bool canOverlayCurves(
  ComparisonCurve a,
  ComparisonCurve b,
  CurveSeries series,
) => a.unit(series) == b.unit(series);

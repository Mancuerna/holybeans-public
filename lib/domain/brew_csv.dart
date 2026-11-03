import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/brew_ratio.dart';
import 'package:holybeans/domain/brew_stats.dart';

/// All brews, archived ones included, as CSV for spreadsheets: one row per
/// brew, oldest first, local times, dots as decimal separators and a UTF-8
/// byte order mark so spreadsheet apps read accents correctly.
String brewsCsv({
  required List<Brew> brews,
  required List<Coffee> coffees,
  required List<CoffeeLot> lots,
}) {
  final coffeeById = {for (final coffee in coffees) coffee.id: coffee};
  final prices = pricePerKgByCoffee(coffees, lots);
  String two(int value) => value.toString().padLeft(2, '0');
  String number(num? value) {
    if (value == null) return '';
    final text = value.toStringAsFixed(3);
    return text.contains('.') ? text.replaceFirst(RegExp(r'\.?0+$'), '') : text;
  }

  const header = [
    'brewed_at',
    'coffee',
    'roaster',
    'roast_level',
    'method',
    'profile',
    'grinder',
    'grind_setting',
    'grind_rpm',
    'dose_g',
    'water_g',
    'yield_g',
    'time_s',
    'temperature_c',
    'pressure_bar',
    'preinfusion_s',
    'bloom_s',
    'first_drip_s',
    'tds_percent',
    'ey_percent',
    'rating',
    'balance',
    'strength',
    'acidity',
    'sweetness',
    'bitterness',
    'body',
    'aftertaste',
    'cost_eur',
    'water_profile',
    'notes',
    'archived',
    'feeder_rpm',
    'brix',
    'brix_factor',
  ];
  final sorted = [...brews]
    ..sort((a, b) => a.brewedAtMs.compareTo(b.brewedAtMs));
  final rows = <List<String>>[
    header,
    for (final brew in sorted)
      () {
        final coffee = coffeeById[brew.coffeeId];
        final at = DateTime.fromMillisecondsSinceEpoch(brew.brewedAtMs);
        final date = '${at.year}-${two(at.month)}-${two(at.day)}';
        final time = '${two(at.hour)}:${two(at.minute)}';
        return [
          '$date $time',
          coffee?.name ?? '',
          coffee?.roaster ?? '',
          coffee?.roastLevel ?? '',
          brew.methodName,
          brew.profileName ?? '',
          brew.isPreGround ? 'pre-ground' : brew.grinderName ?? '',
          brew.grindSetting ?? '',
          number(brew.grindRpm),
          number(brew.doseGrams),
          number(brew.waterGrams),
          number(brew.beverageGrams),
          number(brew.timeSeconds),
          number(brew.temperatureC),
          number(brew.pressureBar),
          number(brew.preinfusionSeconds),
          number(brew.bloomSeconds),
          number(brew.firstDripSeconds),
          number(brew.tdsPercent),
          number(brewExtractionYield(brew)),
          number(brew.rating),
          number(brew.tasteBalance),
          number(brew.tasteStrength),
          number(brew.acidity),
          number(brew.sweetness),
          number(brew.bitterness),
          number(brew.body),
          number(brew.aftertaste),
          number(brewCost(brew, prices)),
          brew.waterProfileName ?? '',
          brew.notes ?? '',
          brew.archivedAtMs == null ? '' : 'yes',
          number(brew.feederRpm),
          number(brew.brix),
          number(brew.brixFactor),
        ];
      }(),
  ];
  String field(String value) => value.contains(RegExp(r'[",\r\n]'))
      ? '"${value.replaceAll('"', '""')}"'
      : value;
  return '\uFEFF${rows.map((row) => row.map(field).join(',')).join('\r\n')}'
      '\r\n';
}

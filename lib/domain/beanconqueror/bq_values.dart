/// Reading single values from a BeanConqueror export. BeanConqueror writes
/// 0 or "" where nothing was measured, keeps ratings on its own scale and
/// stores enum keys; these helpers turn them into HolyBeans values.
library;

import 'dart:convert';

import 'package:holybeans/domain/altitude.dart';
import 'package:holybeans/domain/fingerprint.dart';
import 'package:holybeans/domain/journal_codes.dart';

/// A positive number, or null for 0, negatives and anything else.
double? bqPositive(Object? value) =>
    value is num && value.isFinite && value > 0 ? value.toDouble() : null;

/// The jug a BeanConqueror brew was weighed in: its name, if any, and its
/// empty weight; null when the brew names no weight.
({String? name, double grams})? bqBrewVessel(Object? brew) {
  if (brew is! Map) return null;
  final grams = bqPositive(brew['vessel_weight']);
  if (grams == null) return null;
  return (name: bqText(brew['vessel_name']), grams: grams);
}

/// Trimmed text, or null when empty.
String? bqText(Object? value) {
  if (value is! String) return null;
  final text = value.trim();
  return text.isEmpty ? null : text;
}

/// Whole seconds from BeanConqueror's seconds plus optional milliseconds.
int? bqSeconds(Object? seconds, [Object? milliseconds]) {
  final whole = seconds is num ? seconds.toDouble() : 0.0;
  final extra = milliseconds is num ? milliseconds / 1000 : 0.0;
  final total = (whole + extra).round();
  return total > 0 ? total : null;
}

/// A rating on BeanConqueror's 0–[scaleMax] scale as HolyBeans' 0–10, in
/// half points. BeanConqueror's 0 means "not rated".
double? bqRating(Object? value, num scaleMax) {
  if (value is! num || value <= 0 || scaleMax <= 0) return null;
  final rescaled = (value / scaleMax * 10).clamp(0, 10);
  return (rescaled * 2).round() / 2;
}

/// The local calendar date (`yyyy-MM-dd`) of an ISO timestamp.
String? bqLocalDate(Object? iso) {
  final text = bqText(iso);
  if (text == null) return null;
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return null;
  final local = parsed.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year.toString().padLeft(4, '0')}-${two(local.month)}-'
      '${two(local.day)}';
}

/// Milliseconds since the epoch of a BeanConqueror `unix_timestamp`
/// (seconds), or null.
int? bqTimestampMs(Object? config) {
  if (config is! Map) return null;
  final seconds = config['unix_timestamp'];
  return seconds is num && seconds > 0 ? (seconds * 1000).round() : null;
}

/// The altitude in metres written as text: "1400", "1.800 msnm",
/// "1800-2000 m" (the first figure). Dots or commas followed by three
/// digits are thousands separators.
int? bqAltitude(Object? value) {
  final text = bqText(value);
  if (text == null) return null;
  final match = RegExp(r'\d{1,3}(?:[.,]\d{3})+|\d+').firstMatch(text);
  if (match == null) return null;
  final metres = int.tryParse(match.group(0)!.replaceAll(RegExp('[.,]'), ''));
  return metres != null && metres > 0 && metres < 10000 ? metres : null;
}

/// BeanConqueror's named roast degrees in HolyBeans' levels.
String? bqRoastLevel(Object? roast) => switch (roast) {
  'CINNAMON_ROAST' ||
  'AMERICAN_ROAST' ||
  'NEW_ENGLAND_ROAST' ||
  'HALF_CITY_ROAST' ||
  'MODERATE_LIGHT_ROAST' => RoastLevel.light.code,
  'CITY_ROAST' ||
  'CITY_PLUS_ROAST' ||
  'FULL_CITY_ROAST' => RoastLevel.medium.code,
  'FULL_CITY_PLUS_ROAST' ||
  'ITALIAN_ROAST' ||
  'VIEANNA_ROAST' ||
  'FRENCH_ROAST' => RoastLevel.dark.code,
  _ => null,
};

/// A preparation's style as a HolyBeans method category.
String? bqMethodCategory(Object? styleType) => switch (styleType) {
  'ESPRESSO' => MethodCategory.espresso.code,
  'POUR OVER' || 'PERCOLATION' => MethodCategory.pourover.code,
  'FULL_IMMERSION' => MethodCategory.immersion.code,
  _ => null,
};

/// The freezer container of a frozen bean.
String? bqContainer(Object? storage) => switch (storage) {
  'COFFEE_BAG' => FrozenContainer.originalBag.code,
  'COFFEE_JAR' => FrozenContainer.jar.code,
  'ZIP_LOCK' => FrozenContainer.zipBag.code,
  'VACUUM_SEALED' => FrozenContainer.vacuumBag.code,
  'TUBE' => FrozenContainer.tube.code,
  _ => null,
};

/// Grams from a brew quantity: grams and millilitres of water or coffee
/// are taken as the same; other units are not read.
double? bqQuantity(Object? value, Object? unit) =>
    unit == null || unit == 'GR' || unit == 'ML' ? bqPositive(value) : null;

/// The file name at the end of a BeanConqueror attachment path, which is
/// how picked files are matched to it.
String bqFileName(String path) => path.split(RegExp(r'[/\\]')).last;

/// Molar mass of calcium carbonate, which hardness is expressed as.
const _caco3 = 100.09;

/// Hardness or alkalinity in ppm as CaCO3. One mmol/l is 100.09 ppm and
/// one German degree 17.85 ppm; mg/l and unknown units are read as ppm.
double? bqHardnessPpm(Object? value, Object? unit) {
  final amount = bqPositive(value);
  if (amount == null) return null;
  return switch (unit) {
    'MMOL_L' => amount * _caco3,
    'DH' => amount * 17.85,
    _ => amount,
  };
}

/// An ion's concentration in ppm (mg/l) of the ion itself, given its
/// [molarMass] and [charge]. "ppm as CaCO3" counts the CaCO3 carrying the
/// same charge, so it scales by molar mass over 100.09 × charge / 2.
double? bqIonPpm(
  Object? value,
  Object? unit, {
  required double molarMass,
  int charge = 2,
}) {
  final amount = bqPositive(value);
  if (amount == null) return null;
  final perCaCO3 = molarMass / (_caco3 * charge / 2);
  return switch (unit) {
    'PPM' => amount * perCaCO3,
    'MMOL_L' => amount * molarMass,
    'DH' => amount * 17.85 * perCaCO3,
    _ => amount,
  };
}

/// A short stable hash of a record's original JSON (64-bit FNV-1a), to
/// tell whether it changed in BeanConqueror since it was imported.
String bqFingerprint(String json) {
  final hash = fnv1a64(utf8.encode(json));
  return hash.toUnsigned(64).toRadixString(16).padLeft(16, '0');
}

/// Upper end of an explicit, valid BeanConqueror elevation range.
int? bqAltitudeMax(Object? value) {
  final range = parseAltitude(value);
  return range != null && bqAltitude(value) == range.$1 ? range.$2 : null;
}

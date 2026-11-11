import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/catalog_validation.dart';
import 'package:holybeans/domain/altitude.dart';
import 'package:holybeans/domain/journal_codes.dart';

final allowedFrozenContainers = List<String>.unmodifiable(
  FrozenContainer.values.map((value) => value.code),
);

class BrewStockReviewRequiredException implements Exception {
  const BrewStockReviewRequiredException();
}

class BrewArchivedWithCoffeeException implements Exception {
  const BrewArchivedWithCoffeeException();
}

class BrewCoffeeArchivedException implements Exception {
  const BrewCoffeeArchivedException();
}

class CoffeeHasBrewsException implements Exception {
  const CoffeeHasBrewsException();
}

class BrewSaveOutcome {
  const BrewSaveOutcome({
    required this.id,
    required this.coffeeId,
    required this.overdrawIncreased,
  });

  final String id;
  final String coffeeId;
  final bool overdrawIncreased;
}

/// The origin and processing details for one part of a coffee blend.
///
/// [id] is optional when creating a component. For profile edits, pass the
/// existing row ID to preserve that component's identity while reordering it.
class CoffeeComponentInput {
  const CoffeeComponentInput({
    this.id,
    this.country,
    this.region,
    this.farm,
    this.producer,
    this.variety,
    this.process,
    this.altitudeMeters,
    this.altitudeMaxMeters,
    this.harvest,
  });

  final String? id;
  final String? country;
  final String? region;
  final String? farm;
  final String? producer;
  final String? variety;
  final String? process;
  final int? altitudeMeters;
  final int? altitudeMaxMeters;

  /// When it was harvested, as written ("2025", "Jan 2025").
  final String? harvest;

  CoffeeComponentInput _normalized() {
    final clean = CoffeeComponentInput(
      id: trimOrNull(id),
      country: trimOrNull(country),
      region: trimOrNull(region),
      farm: trimOrNull(farm),
      producer: trimOrNull(producer),
      variety: trimOrNull(variety),
      process: trimOrNull(process),
      altitudeMeters: altitudeMeters,
      altitudeMaxMeters: altitudeMaxMeters,
      harvest: trimOrNull(harvest),
    );
    if (id != null && clean.id == null) {
      throw ArgumentError.value(id, 'id', 'Component ID cannot be blank');
    }
    if (!validAltitudeRange(clean.altitudeMeters, clean.altitudeMaxMeters)) {
      throw ArgumentError('Invalid altitude range');
    }
    if ([
      clean.country,
      clean.region,
      clean.farm,
      clean.producer,
      clean.variety,
      clean.process,
      clean.altitudeMeters?.toString(),
      clean.harvest,
    ].every((value) => value == null)) {
      throw ArgumentError('Each coffee component must contain origin data');
    }
    return clean;
  }
}

/// Tasting notes of a brew: the extraction compass and flavour scores.
class BrewTasting {
  const BrewTasting({
    this.balance,
    this.strength,
    this.acidity,
    this.sweetness,
    this.bitterness,
    this.body,
    this.aftertaste,
  });

  factory BrewTasting.of(Brew brew) => BrewTasting(
    balance: brew.tasteBalance,
    strength: brew.tasteStrength,
    acidity: brew.acidity,
    sweetness: brew.sweetness,
    bitterness: brew.bitterness,
    body: brew.body,
    aftertaste: brew.aftertaste,
  );

  /// -1 sour, 0 balanced, 1 bitter.
  final int? balance;

  /// -1 weak, 0 balanced, 1 strong.
  final int? strength;
  final int? acidity;
  final int? sweetness;
  final int? bitterness;
  final int? body;
  final int? aftertaste;

  List<int?> get scores => [acidity, sweetness, bitterness, body, aftertaste];

  bool get isEmpty =>
      balance == null && strength == null && scores.every((s) => s == null);

  void validate() {
    for (final (value, name) in [
      (balance, 'balance'),
      (strength, 'strength'),
    ]) {
      if (value != null && (value < -1 || value > 1)) {
        throw ArgumentError.value(value, name);
      }
    }
    for (final score in scores) {
      if (score != null && (score < 0 || score > 5)) {
        throw ArgumentError.value(score, 'score');
      }
    }
  }
}

/// Coffee to freeze right after it is added.
class FreezeRequest {
  const FreezeRequest({
    required this.grams,
    required this.frozenDate,
    this.container,
    this.notes,
  });

  final double grams;

  /// Local calendar date, ISO `yyyy-MM-dd`.
  final String frozenDate;
  final String? container;
  final String? notes;
}

(double, double) materializeBalance(double balance) {
  if (!balance.isFinite) throw ArgumentError.value(balance, 'balance');
  final normalized = balance.abs() < 0.000001 ? 0.0 : balance;
  return (normalized > 0 ? normalized : 0, normalized < 0 ? -normalized : 0);
}

void validateBrewRating(double? rating, String name) {
  if (rating == null) return;
  final doubled = rating * 2;
  if (!rating.isFinite ||
      rating < 0 ||
      rating > 10 ||
      (doubled - doubled.round()).abs() > 0.000001) {
    throw ArgumentError.value(rating, name);
  }
}

void validatePositive(double? value, String field) {
  if (value != null && (!value.isFinite || value <= 0)) {
    throw ArgumentError.value(value, field);
  }
}

const stockTolerance = 1e-6;

/// Visible unfrozen balance of a lot, or null when it is unknown.
double? freshStockGrams(CoffeeLot lot) {
  final remaining = lot.remainingGrams;
  if (remaining == null) return null;
  final balance = remaining - (lot.overdrawGrams ?? 0);
  return balance < 0 ? 0 : balance;
}

double roundStockGrams(num grams) => (grams * 1000).round() / 1000;

void validatePositiveGrams(double value, String name) {
  if (!value.isFinite || value <= 0) throw ArgumentError.value(value, name);
}

void validateFrozenContainer(String? value) {
  if (value != null && FrozenContainer.fromCode(value) == null) {
    throw ArgumentError.value(value, 'container');
  }
}

void validateRestDays(int? value) {
  if (value != null && (value < 0 || value > 365)) {
    throw ArgumentError.value(value, 'restDays');
  }
}

void validateCoffeePrice(int? value) {
  if (value != null && value < 0) {
    throw ArgumentError.value(value, 'paidPriceCents');
  }
}

void validateRoastLevel(String? value) {
  if (value != null && RoastLevel.fromCode(value) == null) {
    throw ArgumentError.value(value, 'roastLevel');
  }
}

void validateStockDate(String? value) {
  if (value == null) return;
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw ArgumentError.value(value, 'roastDate');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || parsed.toIso8601String().substring(0, 10) != value) {
    throw ArgumentError.value(value, 'roastDate');
  }
}

List<CoffeeComponentInput> normalizeCoffeeComponents(
  List<CoffeeComponentInput> components,
) {
  final normalized = components
      .map((component) => component._normalized())
      .toList(growable: false);
  final ids = normalized
      .map((component) => component.id)
      .whereType<String>()
      .toList(growable: false);
  if (ids.toSet().length != ids.length) {
    throw ArgumentError.value(components, 'components', 'IDs must be unique');
  }
  return normalized;
}

bool brewAdjustsStock(Brew brew) => brew.stockReviewPending != true;

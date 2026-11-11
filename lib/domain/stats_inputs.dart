import 'package:holybeans/domain/freshness.dart';

typedef StatsBrew = ({
  String id,
  String coffeeId,
  String? lotId,
  String methodName,
  int brewedAtMs,
  int createdAtMs,
  double? doseGrams,
  double? rating,
  int? tasteBalance,
  int? tasteStrength,
  double? temperatureC,
  double? beverageGrams,
  double? waterGrams,
  int? timeSeconds,
  BrewStyle style,
});

typedef StatsCoffee = ({
  String id,
  String name,
  String roaster,
  int? paidPriceCents,
});

typedef StatsLot = ({
  String id,
  String coffeeId,
  double? initialGrams,
  String? purchaseDate,
  String? roastDate,
  int createdAtMs,
});

typedef StatsComponent = ({
  String coffeeId,
  String? process,
  String? variety,
  String? country,
});

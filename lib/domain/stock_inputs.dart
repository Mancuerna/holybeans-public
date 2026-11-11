typedef StockCoffeeFacts = ({String id, int? archivedAtMs});

typedef StockBrewFacts = ({
  String coffeeId,
  double? doseGrams,
  int brewedAtMs,
  String? methodId,
  String methodName,
});

typedef StockLotFacts = ({
  String id,
  String coffeeId,
  int? archivedAtMs,
  double? initialGrams,
  double? remainingGrams,
  double? overdrawGrams,
  String? roastDate,
});

typedef StockPortionFacts = ({
  String id,
  String lotId,
  double remainingGrams,
  String frozenDate,
  String label,
});

typedef StockAdjustmentFacts = ({
  String lotId,
  double? previousGrams,
  double resultingGrams,
  int? reversedAtMs,
});

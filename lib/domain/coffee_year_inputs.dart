/// Immutable inputs for the annual summary, independent of storage and UI.
typedef YearBrew = ({
  String id,
  String coffeeId,
  String? methodId,
  String methodName,
  double? doseGrams,
  double? rating,
  int brewedAtMs,
});
typedef YearCoffee = ({String id, String name, String roaster});
typedef YearOrigin = ({String coffeeId, String? country});
typedef YearMethod = ({String id, String name});

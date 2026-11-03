import 'package:holybeans/data/database/app_database.dart';

Coffee yearCoffee(
  String id, {
  String? name,
  String roaster = 'A roaster',
  bool archived = false,
  int? paidPriceCents,
}) => Coffee(
  id: id,
  paidPriceCents: paidPriceCents,
  name: name ?? 'Coffee $id',
  roaster: roaster,
  isFavorite: false,
  isDecaf: false,
  createdAtMs: 0,
  updatedAtMs: 0,
  archivedAtMs: archived ? 1 : null,
);
Brew yearBrew(
  String id,
  DateTime date, {
  String coffee = 'a',
  String? methodId = 'v60',
  String method = 'V60',
  double? dose,
  double? rating,
  bool archived = false,
}) => Brew(
  id: id,
  coffeeId: coffee,
  methodId: methodId,
  methodName: method,
  isPreGround: false,
  isFavorite: false,
  brewedAtMs: date.millisecondsSinceEpoch,
  createdAtMs: DateTime(2026, 10).millisecondsSinceEpoch,
  updatedAtMs: 0,
  archivedAtMs: archived ? 1 : null,
  doseGrams: dose,
  rating: rating,
);
const yearMethods = [
  BrewMethod(id: 'v60', name: 'V60'),
  BrewMethod(id: 'espresso', name: 'Espresso'),
];
const yearComponents = [
  CoffeeComponent(
    id: 'origin',
    coffeeId: 'a',
    position: 0,
    country: 'Colombia',
  ),
];

CoffeeLot yearLot(
  String id, {
  String coffee = 'a',
  double? grams = 250,
  String? purchased = '2026-01-01',
  String? roasted,
  DateTime? added,
}) => CoffeeLot(
  id: id,
  coffeeId: coffee,
  initialGrams: grams,
  purchaseDate: purchased,
  roastDate: roasted,
  createdAtMs: (added ?? DateTime(2026, 10, 13)).millisecondsSinceEpoch,
  updatedAtMs: 0,
);

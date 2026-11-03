part of 'app_database.dart';

class Roasters extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  TextColumn get nameKey => text().unique()();
  @override
  Set<Column> get primaryKey => {id};
}

// Kept separately so adding cafe drinks never rewrites a historical coffee.
class CoffeeRoasterLinks extends Table {
  TextColumn get coffeeId =>
      text().references(Coffees, #id, onDelete: KeyAction.cascade)();
  TextColumn get roasterId =>
      text().references(Roasters, #id, onDelete: KeyAction.restrict)();
  @override
  Set<Column> get primaryKey => {coffeeId};
}

class Cafes extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  TextColumn get country => text().nullable()();
  TextColumn get city => text().nullable()();
  TextColumn get address => text().nullable()();
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  TextColumn get sourceKey => text().nullable().unique()();
  TextColumn get sourceUrl => text().nullable()();
  IntColumn get createdAtMs => integer()();
  IntColumn get updatedAtMs => integer()();
  @override
  Set<Column> get primaryKey => {id};
}

class CafeDrinks extends Table {
  TextColumn get id => text()();
  TextColumn get cafeId =>
      text().references(Cafes, #id, onDelete: KeyAction.restrict)();
  TextColumn get roasterId => text().nullable().references(
    Roasters,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get drinkType => text().withLength(min: 1, max: 120)();
  TextColumn get coffeeName => text().nullable()();
  TextColumn get originCountry => text().nullable()();
  TextColumn get process => text().nullable()();
  TextColumn get variety => text().nullable()();
  TextColumn get notes => text().nullable()();
  RealColumn get rating => real().nullable()();
  IntColumn get priceCents => integer().nullable()();
  TextColumn get currency => text().withDefault(const Constant('EUR'))();
  IntColumn get drankAtMs => integer()();
  IntColumn get createdAtMs => integer()();
  IntColumn get updatedAtMs => integer()();
  @override
  Set<Column> get primaryKey => {id};
}

class CafeDrinkPhotos extends Table {
  TextColumn get drinkId =>
      text().references(CafeDrinks, #id, onDelete: KeyAction.cascade)();
  IntColumn get position => integer()();
  TextColumn get fileName => text()();
  @override
  Set<Column> get primaryKey => {drinkId, position};
}

part of 'app_database.dart';

class StockAdjustments extends Table {
  TextColumn get id => text()();
  TextColumn get operationId => text()();
  TextColumn get coffeeId =>
      text().references(Coffees, #id, onDelete: KeyAction.cascade)();
  TextColumn get lotId =>
      text().references(CoffeeLots, #id, onDelete: KeyAction.cascade)();
  TextColumn get frozenPortionId => text().nullable().references(
    FrozenPortions,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get reason => text()();
  RealColumn get previousGrams => real().nullable()();
  RealColumn get resultingGrams => real()();
  TextColumn get notes => text().nullable()();
  IntColumn get createdAtMs => integer()();
  IntColumn get reversedAtMs => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

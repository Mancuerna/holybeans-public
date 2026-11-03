part of 'app_database.dart';

class PistonMachines extends Table {
  TextColumn get serial => text()();
  IntColumn get cursorMs => integer().nullable()();
  IntColumn get checkedAtMs => integer().nullable()();
  BoolColumn get complete => boolean().withDefault(const Constant(false))();
  @override
  Set<Column> get primaryKey => {serial};
}

class PistonMethodLinks extends Table {
  TextColumn get methodId =>
      text().references(BrewMethods, #id, onDelete: KeyAction.cascade)();
  TextColumn get serial => text().references(
    PistonMachines,
    #serial,
    onDelete: KeyAction.restrict,
  )();
  @override
  Set<Column> get primaryKey => {methodId};
}

class PistonMeasurements extends Table {
  TextColumn get serial =>
      text().references(PistonMachines, #serial, onDelete: KeyAction.cascade)();
  TextColumn get shotId => text()();
  IntColumn get timeMs => integer()();
  RealColumn get current => real().nullable()();
  RealColumn get speed => real().nullable()();
  IntColumn get samples => integer()();
  IntColumn get algorithm => integer()();
  @override
  Set<Column> get primaryKey => {serial, shotId};
}

class PistonMaintenances extends Table {
  TextColumn get id => text()();
  TextColumn get serial =>
      text().references(PistonMachines, #serial, onDelete: KeyAction.cascade)();
  IntColumn get timeMs => integer()();
  TextColumn get kind => text()();
  TextColumn get notes => text()();
  @override
  Set<Column> get primaryKey => {id};
}

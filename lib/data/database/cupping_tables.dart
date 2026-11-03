part of 'app_database.dart';

class CuppingSessions extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get draftJson => text()();
  IntColumn get startedAtMs => integer().nullable()();
  IntColumn get completedAtMs => integer().nullable()();
  IntColumn get createdAtMs => integer()();
  IntColumn get updatedAtMs => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class CuppingSessionCups extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId =>
      text().references(CuppingSessions, #id, onDelete: KeyAction.cascade)();
  TextColumn get brewId =>
      text().references(Brews, #id, onDelete: KeyAction.cascade)();
  IntColumn get position => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {sessionId, position},
    {brewId},
  ];
}

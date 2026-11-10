import 'package:drift/native.dart';
import 'package:holybeans/data/database/app_database.dart';

/// Creates an isolated in-memory journal. The caller owns closing it.
AppDatabase memoryDatabase() => AppDatabase.forTesting(NativeDatabase.memory());

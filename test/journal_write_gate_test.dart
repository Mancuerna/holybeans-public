import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/database/journal_write_gate.dart';
import 'package:holybeans/data/preferences/language_setting.dart';
import 'package:holybeans/data/preferences/scale_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/journal_backup.dart';

import 'helpers/test_database.dart';

void main() {
  late AppDatabase database;
  late JournalRepository repository;
  setUp(() async {
    database = memoryDatabase();
    repository = JournalRepository(database);
    await database.customSelect('SELECT 1').get();
  });
  tearDown(() => database.close());

  test(
    'transactional scale preferences acquire their lock before SQLite',
    () async {
      database.writeGate.writable = false;
      final locked = Completer<void>();
      final resume = Completer<void>();
      final restoring = database.writeGate.withPreferencesLock(() async {
        locked.complete();
        await resume.future;
        await database.transaction(() => LanguageSetting(database).load());
      });
      await locked.future;
      final saving = ScaleSettings(database)
          .save(const RememberedScale(deviceId: 'test', name: 'Test scale'));
      resume.complete();
      await Future.wait([restoring, saving])
          .timeout(const Duration(seconds: 5));
      expect((await ScaleSettings(database).loadAll()).single.deviceId, 'test');
    },
  );

  test(
    'closed gate blocks repository writes but allows consistent exports',
    () async {
      database.writeGate.writable = false;
      await expectLater(
        repository.createCoffee(name: 'Blocked', roaster: 'Test'),
        throwsA(isA<JournalReadOnlyException>()),
      );
      expect(await database.select(database.coffees).get(), isEmpty);
      expect(
        await JournalBackup(database).exportJson(),
        contains('holybeans-backup'),
      );
      database.writeGate.writable = true;
      await repository.createCoffee(name: 'Allowed', roaster: 'Test');
      expect(
        (await database.select(database.coffees).get()).single.name,
        'Allowed',
      );
    },
  );

  test(
    'closing gate during a transaction rolls back the entire write',
    () async {
      final written = Completer<void>();
      final resume = Completer<void>();
      final transaction = database.transaction(() async {
        await repository.createCoffee(name: 'Interrupted', roaster: 'Test');
        written.complete();
        await resume.future;
      });
      final checked = expectLater(
        transaction,
        throwsA(isA<JournalReadOnlyException>()),
      );
      await written.future;
      database.writeGate.writable = false;
      resume.complete();
      await checked;
      expect(await database.select(database.coffees).get(), isEmpty);
    },
  );

  test('restore permission is limited to its asynchronous zone', () async {
    database.writeGate.writable = false;
    await database.writeGate.restoring(
      () => repository.createCoffee(name: 'Restored', roaster: 'Test'),
    );
    await expectLater(
      repository.createCoffee(name: 'Blocked', roaster: 'Test'),
      throwsA(isA<JournalReadOnlyException>()),
    );
    expect(
      (await database.select(database.coffees).get()).single.name,
      'Restored',
    );
  });

  test('returning statements cannot bypass the read-only gate', () async {
    await repository.createCoffee(name: 'Keep', roaster: 'Test');
    database.writeGate.writable = false;
    await expectLater(
      database.customSelect('DELETE FROM coffees RETURNING id').get(),
      throwsA(isA<JournalReadOnlyException>()),
    );
    expect((await database.select(database.coffees).get()).single.name, 'Keep');
  });

  test(
    'local settings work offline and wait for preference-preserving restore',
    () async {
      database.writeGate.writable = false;
      final locked = Completer<void>();
      final resume = Completer<void>();
      final restoring = database.writeGate.withPreferencesLock(() async {
        locked.complete();
        await resume.future;
      });
      await locked.future;
      final saving = LanguageSetting(database).save(const Locale('es'));
      expect(await LanguageSetting(database).load(), isNull);
      resume.complete();
      await restoring;
      await saving;
      expect((await LanguageSetting(database).load())?.languageCode, 'es');
      await expectLater(
        repository.createCoffee(name: 'Still blocked', roaster: 'Test'),
        throwsA(isA<JournalReadOnlyException>()),
      );
    },
  );

  test('queued local preference writes do not turn a read transaction into a writer', () async {
    database.writeGate.writable = false;
    final reading = Completer<void>();
    final resume = Completer<void>();
    final transaction = database.transaction(() async {
      await LanguageSetting(database).load();
      reading.complete();
      await resume.future;
    });
    await reading.future;
    final saving = LanguageSetting(database).save(const Locale('en'));
    resume.complete();
    await transaction;
    await saving;
    expect((await LanguageSetting(database).load())?.languageCode, 'en');
  });
}

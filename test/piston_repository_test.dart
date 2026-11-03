import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/repositories/piston_repository.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/domain/meticulous/piston_analysis.dart';

import 'helpers/piston_fake.dart';

void main() {
  late AppDatabase db;
  late JournalRepository repo;
  late String method;
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = JournalRepository(db);
    method = await repo.createMethod(
      name: 'Meticulous',
      machine: 'meticulous',
      machineAddress: 'meticulous.local',
    );
  });
  tearDown(() async => db.close());
  Future<void> sync(FakePistonSource s, {bool Function()? cancelled}) => repo
      .piston
      .sync(method, s, cancelled: cancelled ?? () => false, onProgress: (_) {});
  test('first download is paged; reopening reads only new details and survives another method/address', () async {
    final rows = pistonFixture();
    final first = FakePistonSource(rows);
    await sync(first);
    expect(first.starts.length, greaterThan(1));
    expect(first.fetched.length, 280);
    expect(first.closed, true);
    expect((await repo.piston.load(method)).complete, true);
    final next = FakePistonSource(pistonFixture(count: 282));
    await sync(next);
    expect(next.starts.first, rows.last.timeMs - 1000);
    expect(next.fetched, ['shot-280', 'shot-281']);
    final same = FakePistonSource(pistonFixture(count: 282));
    await sync(same);
    expect(same.fetched, isEmpty);
    final other = await repo.createMethod(name: 'Same machine');
    await repo.piston.sync(
      other,
      FakePistonSource(pistonFixture(count: 282)),
      cancelled: () => false,
      onProgress: (_) {},
    );
    expect((await repo.piston.load(other)).readings.length, 282);
    expect(await db.select(db.pistonMeasurements).get(), hasLength(282));
    expect(await repo.allBrews(), isEmpty);
    expect(await repo.allCoffees(), isEmpty);
  });
  test('failed block does not advance cursor and resume skips already saved details', () async {
    final first = FakePistonSource(pistonFixture(), failAfter: 140);
    await expectLater(sync(first), throwsStateError);
    final partial = await repo.piston.load(method);
    expect(partial.complete, false);
    expect(partial.readings.length, 148);
    final resumed = FakePistonSource(pistonFixture());
    await sync(resumed);
    expect(
      resumed.fetched.toSet().intersection(first.fetched.toSet()),
      isEmpty,
    );
    expect((await repo.piston.load(method)).readings.length, 280);
  });
  test(
    'identical timestamps and repeated current values preserve every UUID',
    () async {
      final rows = [
        for (final r in pistonFixture(count: 270))
          PistonReading(
            shotId: r.shotId,
            timeMs: 1000000,
            samples: 5,
            current: 1,
            speed: 9,
          ),
      ];
      final source = FakePistonSource(rows);
      await sync(source);
      expect((await repo.piston.load(method)).readings, hasLength(270));
      expect(source.fetched.toSet(), hasLength(270));
    },
  );
  test(
    'offline and cancellation keep cache; a different serial never mixes it',
    () async {
      await sync(FakePistonSource(pistonFixture(count: 3)));
      await expectLater(
        sync(FakePistonSource([], offline: true)),
        throwsStateError,
      );
      expect((await repo.piston.load(method)).readings, hasLength(3));
      await expectLater(
        sync(FakePistonSource(pistonFixture()), cancelled: () => true),
        throwsA(isA<PistonSyncCancelled>()),
      );
      await sync(FakePistonSource(pistonFixture(count: 2), machine: 'second'));
      expect((await repo.piston.load(method)).readings, hasLength(2));
      expect(await db.select(db.pistonMeasurements).get(), hasLength(5));
    },
  );
  test('backup round trip preserves cache, cursor and maintenance; older backups clear only new data', () async {
    await sync(FakePistonSource(pistonFixture(count: 4)));
    await repo.piston.saveService(
      'machine',
      PistonService(
        id: 'service',
        timeMs: DateTime(2026, 1, 2).millisecondsSinceEpoch,
        kind: 'grease',
        notes: 'Recorded',
      ),
    );
    final backup = JournalBackup(db);
    final source = await backup.exportJson();
    await backup.restoreJson(source);
    final restored = await repo.piston.load(method);
    expect(restored.readings, hasLength(4));
    expect(restored.services.single.notes, 'Recorded');
    expect(restored.complete, true);
    final next = FakePistonSource(pistonFixture(count: 5));
    await sync(next);
    expect(next.fetched, ['shot-4']);
    final decoded = jsonDecode(source) as Map<String, dynamic>;
    decoded['version'] = 34;
    (decoded['data'] as Map).removeWhere(
      (k, v) => k.toString().startsWith('piston'),
    );
    await backup.restoreJson(jsonEncode(decoded));
    expect((await repo.piston.load(method)).serial, isNull);
    expect(await repo.allMethods(), hasLength(1));
  });
  test('invalid backup is rejected before replacing data', () async {
    await sync(FakePistonSource(pistonFixture(count: 2)));
    final source = jsonDecode(await JournalBackup(db).exportJson());
    source['data']['pistonMeasurements'][0]['serial'] = 'missing';
    await expectLater(
      JournalBackup(db).restoreJson(jsonEncode(source)),
      throwsFormatException,
    );
    expect((await repo.piston.load(method)).readings, hasLength(2));
    source['data'].remove('pistonMaintenances');
    await expectLater(
      JournalBackup(db).restoreJson(jsonEncode(source)),
      throwsFormatException,
    );
  });
}

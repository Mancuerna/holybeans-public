import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/data/services/refractometer.dart';
import 'package:holybeans/domain/brew_input.dart';
import 'package:holybeans/domain/brix.dart';
import 'package:holybeans/ui/brews/brew_devices.dart';
import 'package:holybeans/ui/brews/brew_draft.dart';
import 'package:holybeans/ui/brews/brew_timer.dart';

import 'helpers/fake_refractometer.dart';
import 'helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('repeated R2 value exits Brix mode and refreshes computed results', () {
    final draft = BrewDraft();
    final timer = BrewTimer(
      minutes: draft.durationMinutes,
      seconds: draft.durationSeconds,
    );
    final r2 = FakeRefractometer(name: 'R2', connected: true);
    var updates = 0;
    final devices = BrewDevices(
      draft: draft,
      timer: timer,
      isEspresso: () => true,
      refractometer: r2,
      onMeasurement: () => updates++,
    );
    r2.emit(const R2Result(6.8));
    draft.brixMode = true;
    draft.brix.text = '2';
    expect(draft.effectiveTds, 1.7);
    r2.emit(const R2Result(6.8));
    expect(draft.brixMode, isFalse);
    expect(draft.effectiveTds, 6.8);
    expect(updates, 2);
    devices.dispose();
    timer.dispose();
    draft.dispose();
    r2.dispose();
  });
  test('Brix estimates use the saved factor and reject invalid values', () {
    expect(brixToTds(8, 0.85), closeTo(6.8, 1e-10));
    for (final invalid in [double.nan, double.infinity, -1.0, 0.0]) {
      expect(brixToTds(invalid, 0.85), isNull);
      expect(brixToTds(8, invalid), isNull);
    }
    expect(
      () => BrewInput(
        coffeeId: 'c',
        methodName: 'Espresso',
        brix: 8,
        brixFactor: 0.85,
        tdsPercent: 8,
      ).validate(),
      throwsArgumentError,
    );
  });
  test(
    'feeder and original Brix survive repository and backup restore',
    () async {
      final db = memoryDatabase();
      final repo = JournalRepository(db);
      try {
        final coffee = await repo.createCoffee(name: 'Test', roaster: 'Test');
        final grinder = await repo.createGrinder(
          name: 'Independent feeder',
          hasAdjustableFeederRpm: true,
        );
        final id = await repo.createBrew(
          coffeeId: coffee,
          methodName: 'Espresso',
          grinderId: grinder,
          feederRpm: 60,
          brix: 8,
          brixFactor: 0.85,
          tdsPercent: 6.8,
          doseGrams: 20,
          beverageGrams: 50,
        );
        final brew = await (db.select(
          db.brews,
        )..where((b) => b.id.equals(id))).getSingle();
        expect(brew.feederRpm, 60);
        expect(brew.grindRpm, isNull);
        final backup = JournalBackup(db);
        final before = await backup.exportJson();
        await backup.restoreJson(before);
        final after = jsonDecode(await backup.exportJson()) as Map;
        expect(after['data'], (jsonDecode(before) as Map)['data']);
        final restored = await db.select(db.brews).getSingle();
        expect(restored.brix, 8);
        expect(restored.brixFactor, 0.85);
        expect(restored.tdsPercent, 6.8);
      } finally {
        await db.close();
      }
    },
  );
}

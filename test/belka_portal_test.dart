import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/data/services/meticulous_client.dart';
import 'package:holybeans/data/services/portal_sensor.dart';
import 'package:holybeans/domain/brew_input.dart';
import 'package:holybeans/domain/portal_protocol.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/ui/brews/brew_devices.dart';
import 'package:holybeans/ui/brews/brew_draft.dart';
import 'package:holybeans/ui/brews/brew_portal_session.dart';
import 'package:holybeans/ui/brews/brew_timer.dart';

import 'helpers/fake_scale.dart';
import 'helpers/manual_stopwatch.dart';
import 'helpers/test_database.dart';

class _Portal extends Fake with ChangeNotifier implements BlePortalSensor {
  final stream = StreamController<PortalReading>.broadcast(sync: true);
  @override
  Stream<PortalReading> get readings => stream.stream;
  @override
  bool connected = true;
  @override
  String get name => 'Portal';
  @override
  Future<void> connect({bool automatic = false}) async {}
  @override
  void dispose() {
    unawaited(stream.close());
    super.dispose();
  }

  void lose() {
    connected = false;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const reading = (ec: 1.25, internal: 20.0, outlet: 85.5, status: 200);

  test('Portal decodes little-endian floats and retains the status byte', () {
    final bytes = Uint8List.fromList([
      0,
      0,
      160,
      63,
      0,
      0,
      160,
      65,
      0,
      0,
      171,
      66,
      200,
    ]);
    expect(PortalProtocol.parse(bytes), reading);
    expect(PortalProtocol.parse(bytes.sublist(1)), isNull);
    ByteData.sublistView(bytes).setFloat32(8, double.infinity, Endian.little);
    expect(PortalProtocol.parse(bytes), isNull);
    expect(PortalProtocol.showGraph, [64, 0, 1, 45]);
    expect(PortalProtocol.hideGraph, [64, 0, 1, 46]);
  });

  test(
    'only running timer samples are kept and disconnects break the trace',
    () {
      final sensor = _Portal();
      final session = BrewPortalSession(sensor);
      addTearDown(sensor.dispose);
      addTearDown(session.dispose);
      sensor.stream.add(reading);
      expect(session.recording, isNull);
      session.start(2);
      sensor.stream.add(reading);
      sensor.stream.add(reading);
      sensor.lose();
      sensor.connected = true;
      sensor.stream.add(reading);
      session.stop();
      sensor.stream.add(reading);
      expect(session.recording!.samples.map((s) => s.start), [
        true,
        false,
        true,
      ]);
      expect(session.recording!.samples.first.ms, greaterThanOrEqualTo(2000));
      session.reset();
      expect(session.recording, isNull);
    },
  );

  test(
    'one timer records Portal and Bluetooth scale at independent rates',
    () async {
      final draft = BrewDraft();
      final timer = BrewTimer(
        minutes: draft.durationMinutes,
        seconds: draft.durationSeconds,
      );
      final scale = FakeScale(name: 'Scale', connected: true);
      final sensor = _Portal();
      final watch = ManualStopwatch();
      final devices = BrewDevices(
        draft: draft,
        timer: timer,
        isEspresso: () => true,
        scale: scale,
        portalSensor: sensor,
        stopwatch: watch,
      );
      addTearDown(draft.dispose);
      addTearDown(timer.dispose);
      addTearDown(scale.dispose);
      addTearDown(sensor.dispose);
      addTearDown(devices.dispose);
      devices.timerStarted(0);
      scale.emit(0);
      sensor.stream.add(reading);
      watch.elapsed = const Duration(milliseconds: 200);
      scale.emit(2);
      sensor.stream.add(reading);
      sensor.stream.add(reading);
      devices.timerStopped();
      expect(devices.curve!.weight, contains(2));
      expect(devices.curve!.portal!.samples, hasLength(3));
      devices.timerReset();
      expect(devices.curve?.portal, isNull);
    },
  );
  for (final withScale in [true, false]) {
    test(
      'save, align, import and restore Portal samples (scale: $withScale)',
      () async {
        final db = memoryDatabase();
        addTearDown(db.close);
        final repo = JournalRepository(db);
        final input = BrewInput(
          coffeeId: await repo.createCoffee(name: 'A', roaster: 'B'),
          methodName: 'Espresso',
        );
        final portal = PortalRecording([
          (ms: 135, reading: reading, start: true),
        ]);
        final weight = ShotCurve(timesMs: [0, 800], flow: [], weight: [0, 2]);
        final saved = await repo.saveBrewWithOutcome(
          input,
          curve: withScale
              ? weight.withPortal(portal)
              : ShotCurve.portalOnly(portal),
        );
        final first = (await repo.brewCurve(saved.id))!;
        expect(first.curve.portal!.samples, portal.samples);
        expect(first.curve.weight, withScale ? weight.weight : isEmpty);

        final shifted = PortalRecording(portal.samples, offsetMs: -500);
        final machine = MeticulousShot(
          id: 'machine',
          brewedAt: DateTime.utc(2026),
          profileName: 'P',
          curve: weight,
        );
        await repo.saveBrewWithOutcome(
          input,
          id: saved.id,
          shot: machine,
          curve: ShotCurve.portalOnly(shifted),
        );
        await repo.attachMeticulousShot(
          saved.id,
          MeticulousShot(
            id: 'summary',
            brewedAt: machine.brewedAt,
            profileName: 'P',
          ),
        );
        expect((await repo.brewCurve(saved.id))!.curve.portal!.offsetMs, -500);
        await repo.attachMeticulousShot(saved.id, machine);
        final target = memoryDatabase();
        addTearDown(target.close);
        await JournalBackup(target)
            .restoreJson(await JournalBackup(db).exportJson());
        final restored = (await JournalRepository(target).brewCurve(saved.id))!;
        expect(restored.source, 'meticulous');
        expect(restored.curve.weight, weight.weight);
        expect(restored.curve.portal!.samples, portal.samples);
        expect(restored.curve.portal!.offsetMs, -500);
      },
    );
  }
}

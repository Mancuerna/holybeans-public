import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/preferences/scale_settings.dart';
import 'package:holybeans/data/services/ble_scale.dart';
import 'package:holybeans/data/services/scale.dart';
import 'package:holybeans/domain/bookoo_protocol.dart';
import 'package:holybeans/ui/brews/brew_devices.dart';
import 'package:holybeans/ui/brews/brew_draft.dart';
import 'package:holybeans/ui/brews/brew_timer.dart';
import 'package:universal_ble/universal_ble.dart';

import 'helpers/bookoo_dose_packet.dart';
import 'helpers/fake_scale_ble_platform.dart';
import 'helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Ultra reconnects after losing its link while enabling weight notifications', () async {
    final database = memoryDatabase();
    final platform = _BookooPlatform(notify: true, fail: false);
    UniversalBle.setInstance(platform);
    final scale = BleScale(ScaleSettings(database));
    addTearDown(() async {
      await scale.disconnect();
      scale.dispose();
      await database.close();
    });
    await scale.pair(const FoundDevice(id: 'BOOKOO-TEST', name: 'BOOKOO_SC_U'));
    platform.lose('BOOKOO-TEST');
    await Future<void>.delayed(Duration.zero);

    platform.loseOnWeightSubscription = true;
    await scale.connect();
    expect(scale.connected, isFalse);
    expect(scale.status, DeviceStatus.idle);
    expect(scale.activeScaleId, isNull);

    platform.loseOnWeightSubscription = false;
    await scale.connect(automatic: true);
    expect(scale.activeScaleId, 'BOOKOO-TEST');
    final doses = <double>[];
    final subscription = scale.doses.listen(doses.add);
    addTearDown(subscription.cancel);
    platform.updateCharacteristicValue(
      'BOOKOO-TEST',
      BookooUuids.command,
      Uint8List.fromList(bookooDosePacket(1800)),
      null,
    );
    await Future<void>.delayed(Duration.zero);
    expect(doses, [18]);
  });

  for (final options in [
    (notify: true, fail: false),
    (notify: false, fail: false),
    (notify: true, fail: true),
  ]) {
    test(
      'a BLE dose preserves live readings with command channel $options',
      () async {
        final database = memoryDatabase();
        final platform = _BookooPlatform(
          notify: options.notify,
          fail: options.fail,
        );
        UniversalBle.setInstance(platform);
        final scale = BleScale(ScaleSettings(database));
        await scale.pair(
          const FoundDevice(id: 'BOOKOO-TEST', name: 'BOOKOO_SC_U'),
        );
        expect(scale.connected, isTrue);
        expect(
          platform.subscriptions.contains((
            BookooUuids.service,
            BookooUuids.command,
          )),
          options.notify,
        );
        final draft = BrewDraft();
        final timer = BrewTimer(
          minutes: draft.durationMinutes,
          seconds: draft.durationSeconds,
        );
        var measurements = 0;
        final devices = BrewDevices(
          draft: draft,
          timer: timer,
          isEspresso: () => false,
          scale: scale,
          onMeasurement: () => measurements++,
        );
        final readings = <ScaleReading>[];
        final subscription = scale.readings.listen(readings.add);
        addTearDown(() async {
          await subscription.cancel();
          devices.dispose();
          timer.dispose();
          draft.dispose();
          await scale.disconnect();
          scale.dispose();
          await database.close();
        });

        final doseChannel = options.notify && !options.fail
            ? BookooUuids.command
            : BookooUuids.weight;
        Future<void> emit(List<int> bytes, {bool weight = false}) async {
          platform.updateCharacteristicValue(
            'BOOKOO-TEST',
            weight ? BookooUuids.weight : doseChannel,
            Uint8List.fromList(bytes),
            null,
          );
          await Future<void>.delayed(Duration.zero);
        }

        // A dose is usable even before the first live weight notification.
        await emit(bookooDosePacket(1820));
        expect(draft.dose.text, '18.2');
        expect(scale.reading, isNull);
        expect(readings, isEmpty);

        final weight = [
          3,
          0x0B,
          0,
          0x13,
          0x88,
          1,
          0x2B,
          0,
          0x0E,
          0x10,
          0x2B,
          0,
          0,
          80,
          0,
          0,
          0,
          0,
          0,
        ];
        await emit([...weight, bookooChecksum(weight)], weight: true);
        final live = scale.reading;
        expect(live!.grams, 36);
        expect(live.timerMs, 5000);
        final writes = platform.writes.length;
        await emit(bookooDosePacket(2000));
        expect(draft.dose.text, '20');
        expect(identical(scale.reading, live), isTrue);
        expect(readings, hasLength(1));
        expect(platform.writes, hasLength(writes));

        final corrupt = bookooDosePacket(2100)..[19] ^= 1;
        await emit(corrupt);
        expect(draft.dose.text, '20');
        expect(readings, hasLength(1));

        await scale.disconnect();
        await emit(bookooDosePacket(2200));
        expect(draft.dose.text, '20');
        final previousMeasurements = measurements;
        await scale.connect();
        expect(scale.connected, isTrue);
        await emit(bookooDosePacket(2300));
        expect(draft.dose.text, '23');
        expect(measurements, previousMeasurements + 1);
      },
    );
  }
}

class _BookooPlatform extends FakeScaleBlePlatform {
  _BookooPlatform({required this.notify, required this.fail});

  final bool notify;
  final bool fail;
  bool loseOnWeightSubscription = false;

  @override
  Future<List<BleService>> discoverServices(
    String deviceId,
    bool withDescriptors,
  ) async => [
    BleService(BookooUuids.service, [
      BleCharacteristic(BookooUuids.weight, [
        CharacteristicProperty.notify,
      ], []),
      BleCharacteristic(BookooUuids.command, [
        CharacteristicProperty.write,
        if (notify) CharacteristicProperty.notify,
      ], []),
    ]),
  ];

  @override
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) async {
    await super.setNotifiable(
      deviceId,
      service,
      characteristic,
      bleInputProperty,
    );
    if (characteristic == BookooUuids.weight && loseOnWeightSubscription) {
      lose(deviceId);
    }
    if (characteristic == BookooUuids.command && fail) {
      throw StateError('Dose notifications unavailable');
    }
  }
}

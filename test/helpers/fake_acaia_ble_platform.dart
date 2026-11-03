import 'dart:async';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

import 'fake_scale_ble_platform.dart';

// Independent peripheral framing; never calls the production encoder/parser.
class FakeAcaiaBlePlatform extends FakeScaleBlePlatform {
  FakeAcaiaBlePlatform({this.classic = false, this.pearl = false});
  final bool pearl;
  Duration settingsDelay = Duration.zero;
  bool sendSettings = true;
  bool sendWeights = true;
  bool settingsSent = false;
  bool settingsAfterSubscription = false;
  bool identified = false;
  bool notificationsRequested = false;
  final notificationRequest = Completer<void>();
  bool ignoreAcknowledgedHandshake = false;
  bool requiresAndroidWakeUp = false;
  bool failWakeUp = false;
  bool failMtu = false;
  final mtuRequests = <(String, int)>[];
  bool awake = false;
  final wakeUps = <List<int>>[];
  final wakeUpProperties = <BleOutputProperty>[];
  final writeProperties = <BleOutputProperty>[];
  final bool classic;
  bool respond = true;
  bool failControl = false;
  bool subscribed = false;
  @override
  String get id => 'ACAIA-TEST';
  @override
  String get name => classic
      ? 'ACAIA PEARL'
      : pearl
      ? 'PEARL-TEST'
      : 'LUNAR-TEST';
  @override
  String get service => classic
      ? '00001820-0000-1000-8000-00805f9b34fb'
      : '49535343-fe7d-4ae5-8fa9-9fafd205e455';
  @override
  String get characteristic => classic
      ? '00002a80-0000-1000-8000-00805f9b34fb'
      : '49535343-1e4d-4bd9-ba61-23c647249616';
  String get commandCharacteristic =>
      classic ? characteristic : '49535343-8841-43f4-a8d4-ecbe34729bb3';
  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) async {
    mtuRequests.add((deviceId, expectedMtu));
    if (failMtu) throw StateError('MTU request failed');
    return expectedMtu;
  }

  @override
  Future<List<BleService>> discoverServices(
    String deviceId,
    bool withDescriptors,
  ) async => [
    BleService(service, [
      BleCharacteristic(characteristic, [
        CharacteristicProperty.notify,
        if (classic) CharacteristicProperty.write,
      ], []),
      if (!classic)
        BleCharacteristic(commandCharacteristic, [
          CharacteristicProperty.writeWithoutResponse,
          if (pearl) CharacteristicProperty.write,
        ], []),
    ]),
  ];
  @override
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty property,
  ) async {
    subscribed = true;
    identified = false;
    notificationsRequested = false;
    settingsSent = false;
    awake = false;
    await super.setNotifiable(deviceId, service, characteristic, property);
  }

  void reply(int command, List<int> body) {
    var a = 0;
    var b = 0;
    for (var i = 0; i < body.length; i++) {
      if (i.isEven) {
        a += body[i];
      } else {
        b += body[i];
      }
    }
    updateCharacteristicValue(
      id,
      characteristic,
      Uint8List.fromList([239, 221, command, ...body, a & 255, b & 255]),
      null,
    );
  }

  void button(int code) => reply(12, [3, 8, code]);
  @override
  void emit(double weight, {double flow = 0}) {
    grams = weight;
    final raw = (weight.abs() * 10).round();
    reply(12, [
      12,
      5,
      raw & 255,
      (raw >> 8) & 255,
      0,
      0,
      1,
      weight < 0 ? 2 : 0,
      7,
      seconds ~/ 60,
      seconds % 60,
      0,
    ]);
  }

  void loseConnection() => updateConnection(id, false);
  @override
  Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty property,
  ) async {
    if (!subscribed ||
        service != this.service ||
        characteristic != commandCharacteristic) {
      throw StateError('Wrong Acaia channel/order');
    }
    if (value.length == 2 && value[0] == 0 && value[1] == 1) {
      if (classic) throw StateError('Unexpected classic wake-up');
      wakeUps.add(value.toList());
      wakeUpProperties.add(property);
      if (failWakeUp) throw StateError('Wake-up failed');
      awake = true;
      return;
    }
    writes.add(value.toList());
    writeProperties.add(property);
    if (value.length > 20) {
      throw StateError('Peripheral rejects long writes');
    }
    if (value.length < 3) throw StateError('Invalid raw frame');
    if (requiresAndroidWakeUp && !classic && !awake) return;
    final command = value[2];
    if (![0, 4, 6, 11, 12, 13].contains(command)) {
      throw StateError('Forbidden command');
    }
    if (failControl && (command == 4 || command == 13)) {
      throw StateError('Control failed');
    }
    if (!respond) return;
    // Some firmware may acknowledge a GATT request without accepting the
    // Acaia handshake. Reproduce the captured silence, not a radio failure.
    if (ignoreAcknowledgedHandshake &&
        (command == 11 || command == 12) &&
        property == BleOutputProperty.withResponse) {
      return;
    }
    if (command == 11) identified = true;
    if (command == 12) {
      if (!identified) throw StateError('Subscription before identification');
      notificationsRequested = true;
      if (!notificationRequest.isCompleted) notificationRequest.complete();
      if (settingsSent && sendWeights) emit(grams);
    }
    if (sendSettings && command == (settingsAfterSubscription ? 12 : 11)) {
      Future<void>.delayed(settingsDelay, () {
        if (pearl) {
          // Actual Pearl 1.0.014 notification, without device identifiers.
          updateCharacteristicValue(
            id,
            this.characteristic,
            Uint8List.fromList([
              0xef,
              0xdd,
              8,
              9,
              0x49,
              2,
              1,
              1,
              0,
              0,
              1,
              1,
              0x0d,
              0x4b,
            ]),
            null,
          );
        } else {
          reply(8, [9, 64, 2, 2, 1, 0, 1, 1, 0]);
        }
        settingsSent = true;
        if (notificationsRequested && sendWeights) emit(grams);
      });
    }
    if (command == 0 && sendWeights) emit(grams);
    if (command == 4) {
      tareCount++;
      emit(0);
    }
    if (command == 13) {
      if (value[4] == 1) seconds = 0;
      button(switch (value[4]) {
        0 => 8,
        1 => 9,
        _ => 10,
      });
      emit(grams);
    }
  }
}

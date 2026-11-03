import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/services/paired_device_file.dart';
import 'package:holybeans/data/services/pressure_sensor.dart';
import 'package:holybeans/domain/bookoo_pressure_protocol.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/settings/pressure_sensor_section.dart';
import 'package:patrol/patrol.dart';
import 'package:universal_ble/universal_ble.dart';

import '../../test/helpers/fake_pressure_ble_platform.dart';

/// Checks pairing and pressure display with a simulated BOOKOO monitor.
Future<void> checkBookooPressure(PatrolIntegrationTester $) async {
  final platform = FakePressureBlePlatform();
  UniversalBle.setInstance(platform);
  final directory = await Directory.systemTemp.createTemp('bookoo-patrol-');
  final sensor = BlePressureSensor(
    PairedDeviceFile(File('${directory.path}/sensor.json')),
  );
  try {
    await $.pumpWidgetAndSettle(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SafeArea(
            child: ListView(children: [PressureSensorSection(sensor: sensor)]),
          ),
        ),
      ),
    );
    expect(find.textContaining('BOOKOO Espresso Monitor'), findsOneWidget);
    expect(find.textContaining('Pressensor'), findsNothing);
    expect(
      find.textContaining('starts and stops transmission'),
      findsOneWidget,
    );
    await $.tap(find.byKey(const ValueKey('sensor-find')));
    await $.waitUntilVisible(find.text('BOOKOO_EM-TEST'));
    await $.tap(find.text('Connect'));
    expect(platform.writes.single.bytes, bookooStartPressure);
    platform.updateCharacteristicValue(
      'BOOKOO-TEST',
      BookooPressureUuids.pressure,
      Uint8List.fromList([2, 27, 0, 0, 3, 142, 85, 0, 0, 0]),
      null,
    );
    await $.pumpAndSettle();
    await $.waitUntilVisible(find.text('9.1 bar'));
    await $.takeNativeScreenshot('bookoo-pressure-settings');
    await $.tap(find.byKey(const ValueKey('sensor-forget')));
    expect(sensor.name, isNull);
    expect(platform.writes.last.bytes, bookooStopPressure);
    expect(platform.events.take(3), [
      'connect:BOOKOO-TEST',
      'subscribe:BOOKOO-TEST',
      'start:BOOKOO-TEST',
    ]);
    expect(platform.events.skip(3), [
      'stop:BOOKOO-TEST',
      'disconnect:BOOKOO-TEST',
    ]);
    await $.waitUntilVisible(find.byKey(const ValueKey('sensor-find')));
  } finally {
    await $.pumpWidgetAndSettle(const SizedBox.shrink());
    await sensor.disconnect();
    sensor.dispose();
    await directory.delete(recursive: true);
  }
}

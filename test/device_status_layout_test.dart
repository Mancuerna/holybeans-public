import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/services/scale.dart';
import 'package:holybeans/ui/scale/scale_compact.dart';

import 'helpers/fake_pressure_sensor.dart';
import 'helpers/fake_scale.dart';
import 'helpers/ui_test_support.dart';

void main() {
  for (final locale in ['es', 'en']) {
    for (final textScale in [1.0, 2.0]) {
      for (final pressure in [false, true]) {
        testWidgets(
          '${pressure ? 'pressure' : 'scale'} status keeps fields still '
          'at 320px, $locale, text scale $textScale',
          (tester) async {
            tester.view.physicalSize = const Size(320, 800);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final scale = FakeScale(name: 'ACAIA PEARL');
            final sensor = FakePressureSensor(name: 'BOOKOO EM');
            addTearDown(scale.dispose);
            addTearDown(sensor.dispose);
            await tester.pumpWidget(
              localizedApp(
                locale: Locale(locale),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(textScale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        if (pressure)
                          PressureStatusRow(sensor: sensor)
                        else
                          ScaleStatusRow(scale: scale),
                        const TextField(key: ValueKey('next-field')),
                      ],
                    ),
                  ),
                ),
              ),
            );
            final field = find.byKey(const ValueKey('next-field'));
            final initialPosition = tester.getTopLeft(field);
            for (final status in [
              DeviceStatus.connecting,
              DeviceStatus.failed,
              DeviceStatus.idle,
              DeviceStatus.failed,
            ]) {
              scale
                ..status = status
                ..notifyListeners();
              sensor
                ..status = status
                ..notifyListeners();
              await tester.pump();
              expect(tester.takeException(), isNull);
              expect(
                tester.getTopLeft(field),
                initialPosition,
                reason: '$status must not move the next field',
              );
            }
            final statusText = find.byKey(const ValueKey('device-status'));
            final message = tester.widget<Text>(statusText).data!;
            await tester.longPress(statusText);
            await tester.pump(const Duration(milliseconds: 200));
            expect(find.text(message), findsNWidgets(2));
            expect(tester.getTopLeft(field), initialPosition);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}

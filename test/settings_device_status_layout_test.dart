import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/preferences/share_template_settings.dart';
import 'package:holybeans/data/services/scale.dart';
import 'package:holybeans/ui/core/app_theme.dart';
import 'package:holybeans/ui/settings/settings_page.dart';

import 'helpers/fake_pressure_sensor.dart';
import 'helpers/fake_refractometer.dart';
import 'helpers/fake_scale.dart';
import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  for (final locale in ['es', 'en']) {
    for (final textScale in [1.0, 2.0]) {
      for (final device in ['scale', 'pressure', 'refractometer']) {
        testWidgets(
          'settings $device stays still at 320px, $locale, text $textScale',
          (tester) async {
            tester.view.physicalSize = const Size(320, 900);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final db = memoryDatabase();
            final scale = FakeScale(name: 'ACAIA PEARL');
            final pressure = FakePressureSensor(name: 'BOOKOO EM');
            final refractometer = FakeRefractometer(name: 'DiFluid R2');
            addTearDown(db.close);
            addTearDown(scale.dispose);
            addTearDown(pressure.dispose);
            addTearDown(refractometer.dispose);
            await tester.pumpWidget(
              localizedApp(
                theme: AppTheme.light(),
                locale: Locale(locale),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(textScale)),
                  child: child!,
                ),
                home: SettingsPage(
                  locale: Locale(locale),
                  onLocaleChanged: (_) {},
                  onExportBackup: () async {},
                  onExportCsv: () {},
                  onImportBackup: () async {},
                  parameterSettings: BrewParameterSettings(db),
                  templateSettings: ShareTemplateSettings(db),
                  scale: device == 'scale' ? scale : null,
                  pressureSensor: device == 'pressure' ? pressure : null,
                  refractometer: device == 'refractometer'
                      ? refractometer
                      : null,
                ),
              ),
            );
            await tester.pumpAndSettle();
            final tile = find.byKey(ValueKey('settings-$device'));
            await tester.scrollUntilVisible(tile, 200);
            await tester.pumpAndSettle();
            final initialRect = tester.getRect(tile);
            for (final status in [
              DeviceStatus.connecting,
              DeviceStatus.failed,
              DeviceStatus.bluetoothOff,
              DeviceStatus.denied,
              DeviceStatus.idle,
              DeviceStatus.failed,
            ]) {
              scale
                ..status = status
                ..notifyListeners();
              pressure
                ..status = status
                ..notifyListeners();
              refractometer
                ..status = status
                ..notifyListeners();
              await tester.pump();
              expect(tester.takeException(), isNull);
              expect(
                tester.getRect(tile),
                initialRect,
                reason: '$status must not move the settings below the device',
              );
            }
            final tooltip = find.descendant(
              of: tile,
              matching: find.byType(Tooltip),
            );
            final message = tester.widget<Tooltip>(tooltip).message!;
            await tester.longPress(tooltip);
            await tester.pump(const Duration(milliseconds: 200));
            expect(find.text(message), findsNWidgets(2));
            expect(tester.getRect(tile), initialRect);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  }
}

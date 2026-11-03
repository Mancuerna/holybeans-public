import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/services/paired_device.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/core/device_toasts.dart';

import 'helpers/fake_refractometer.dart';
import 'helpers/fake_scale.dart';

void main() {
  test('only connecting and disconnecting are changes', () {
    final watch = DeviceLinkWatch();
    expect(
      [
        DeviceStatus.idle,
        DeviceStatus.connecting,
        DeviceStatus.failed, // a device that is off: no notice
        DeviceStatus.connecting,
        DeviceStatus.connected,
        DeviceStatus.connected,
        DeviceStatus.idle,
        DeviceStatus.bluetoothOff,
      ].map(watch.add),
      [null, null, null, null, true, null, false, null],
    );
  });

  testWidgets('a device connecting or going away is said, and the notice '
      'goes away by itself', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final scale = FakeScale(name: 'BOOKOO_SC_U');
    final refractometer = FakeRefractometer(name: 'R2 Extract');
    addTearDown(scale.dispose);
    addTearDown(refractometer.dispose);
    await tester.pumpWidget(
      HolyBeansApp(
        database: database,
        initialLocale: const Locale('en'),
        scale: scale,
        refractometer: refractometer,
      ),
    );
    await tester.pump();
    // The fakes connect at once, before the app is drawn; real devices take
    // a few seconds. Connecting again is a change like that one.
    expect(find.byKey(const ValueKey('device-toast')), findsNothing);
    await refractometer.disconnect();
    await refractometer.connect();
    await tester.pump();
    expect(find.text('Refractometer connected'), findsOneWidget);
    await tester.pump(DeviceToasts.shownFor);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('device-toast')), findsNothing);

    await scale.disconnect();
    await tester.pump();
    expect(find.text('Scale disconnected'), findsOneWidget);
    await tester.pump(DeviceToasts.shownFor);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('the notice shows over an open sheet and never takes a tap', (
    tester,
  ) async {
    final scale = FakeScale(name: 'BOOKOO_SC_U');
    addTearDown(scale.dispose);
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) =>
            DeviceToasts(devices: {DeviceKind.scale: scale}, child: child!),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => SizedBox.expand(
                  child: TextButton(
                    onPressed: () => taps++,
                    child: const Text('Sheet'),
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await scale.connect();
    await tester.pump();
    final toast = find.byKey(const ValueKey('device-toast'));
    expect(find.text('Scale connected'), findsOneWidget);
    await tester.tapAt(tester.getCenter(toast));
    expect(taps, 1, reason: 'the tap reaches the sheet under the notice');
    await tester.pump(DeviceToasts.shownFor);
    await tester.pumpAndSettle();
  });

  for (final reduced in [false, true]) {
    testWidgets('notice transition respects reduced motion: $reduced', (
      tester,
    ) async {
      final scale = FakeScale(name: 'BOOKOO_SC_U');
      addTearDown(scale.dispose);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: DeviceToasts(
              devices: {DeviceKind.scale: scale},
              child: child!,
            ),
          ),
          home: const Scaffold(),
        ),
      );
      expect(
        tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher)).duration,
        reduced ? Duration.zero : const Duration(milliseconds: 200),
      );
    });
  }

  testWidgets('a device switched on again reconnects by itself while the '
      'app is open, but not one the user disconnected', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final scale = FakeScale(name: 'BOOKOO_SC_U');
    addTearDown(scale.dispose);
    await tester.pumpWidget(
      HolyBeansApp(
        database: database,
        initialLocale: const Locale('en'),
        scale: scale,
      ),
    );
    await tester.pump();
    expect(scale.connected, isTrue);

    scale.lose();
    await tester.pump();
    expect(find.text('Scale disconnected'), findsOneWidget);
    await tester.pump(const Duration(seconds: 8));
    expect(scale.connected, isTrue, reason: 'switched on again');
    expect(find.text('Scale connected'), findsOneWidget);

    await scale.disconnect();
    await tester.pump(const Duration(seconds: 20));
    expect(scale.connected, isFalse, reason: 'the user disconnected it');
    await scale.connect();
    expect(scale.connected, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}

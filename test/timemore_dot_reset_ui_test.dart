import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/preferences/scale_settings.dart';
import 'package:holybeans/data/services/ble_scale.dart';
import 'package:holybeans/data/services/scale.dart';
import 'package:holybeans/domain/scale_recording.dart';
import 'package:holybeans/ui/brews/brew_devices.dart';
import 'package:holybeans/ui/brews/brew_draft.dart';
import 'package:holybeans/ui/brews/brew_scale_reset_button.dart';
import 'package:holybeans/ui/brews/brew_timer.dart';
import 'package:holybeans/ui/scale/scale_compact.dart';
import 'package:universal_ble/universal_ble.dart';

import 'helpers/fake_dot_ble_platform.dart';
import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  for (final failure in ['missing ACK', 'missing zero', 'link loss']) {
    testWidgets('Dot reset recovers through Connect after $failure', (
      tester,
    ) async {
      final db = memoryDatabase();
      final platform = FakeDotBlePlatform();
      UniversalBle.setInstance(platform);
      final events = <String>[];
      final scale = BleScale(
        ScaleSettings(db),
        trace: (event, data) => events.add('$event: $data'),
      );
      Future<void> settleUntil(bool Function() done) async {
        // Database and stream cancellation also complete outside the widget's
        // fake clock. Yield to them while continuing to drain BLE callbacks.
        for (var i = 0; i < 100 && !done(); i++) {
          await tester.pump(const Duration(milliseconds: 10));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
        expect(done(), isTrue, reason: events.join('\n'));
        await tester.pumpAndSettle();
      }

      final draft = BrewDraft();
      late BrewDevices devices;
      final timer = BrewTimer(
        minutes: draft.durationMinutes,
        seconds: draft.durationSeconds,
        onStart: (seconds) => devices.timerStarted(seconds),
        onStop: () => devices.timerStopped(),
        onReset: () => devices.timerReset(),
      );
      final pairing = scale.pair(
        FoundDevice(id: platform.id, name: platform.name),
      );
      await settleUntil(() => scale.rememberedScales.isNotEmpty);
      expect(scale.rememberedScales, hasLength(1));
      await pairing;
      devices = BrewDevices(
        draft: draft,
        timer: timer,
        isEspresso: () => false,
        scale: scale,
      );
      // Flush the automatic reset on entering the form.
      final initialReset = scale.send(ScaleCommand.resetTimer);
      await tester.pump();
      expect(await initialReset, isTrue);
      addTearDown(() async {
        timer.dispose();
        devices.dispose();
        draft.dispose();
        await scale.disconnect();
        scale.dispose();
        await db.close();
      });
      await tester.pumpWidget(
        localizedApp(
          locale: const Locale('en'),
          home: Scaffold(
            body: ListenableBuilder(
              listenable: devices.scale!,
              builder: (context, _) => ScaleStatusRow(
                scale: scale,
                busy: devices.scale!.resetting,
                resetAction: BrewScaleResetButton(
                  session: devices.scale!,
                  timer: timer,
                ),
              ),
            ),
          ),
        ),
      );
      timer.settle(45);
      platform.seconds = 45;
      platform.emit(36.2);
      await tester.pumpAndSettle();
      platform.writes.clear();
      platform.acknowledge = failure != 'missing ACK';
      platform.applyReset = false;
      final reset = find.byKey(const ValueKey('scale-reset'));
      await tester.tap(reset);
      await tester.pump();
      expect(devices.scale!.resetting, isTrue);
      expect(timer.canStart, isFalse);
      if (failure == 'link loss') platform.lose(platform.id);
      await tester.pump(const Duration(seconds: 4));
      await settleUntil(() => !scale.connected && !devices.scale!.resetting);
      expect(scale.connected, isFalse, reason: events.join('\n'));
      expect(devices.scale!.resetting, isFalse);
      expect(timer.running, isFalse);
      expect(platform.tareCount, 0);
      final connect = find.byKey(const ValueKey('scale-connect'));
      expect(connect, findsOneWidget);

      platform.acknowledge = true;
      platform.applyReset = true;
      await tester.tap(connect);
      await settleUntil(() => scale.connected);
      expect(scale.connected, isTrue);
      platform.emit(36.2);
      await tester.pumpAndSettle();
      // Reconnecting must not replay the failed reset or its pending tare.
      expect(platform.writes.where((p) => p[2] == 3), hasLength(1));
      expect(platform.events.where((e) => e == 'bond'), hasLength(1));
      expect(reset, findsOneWidget);
      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(scale.connected, isTrue);
      expect(timer.elapsedSeconds, 0);
      expect(platform.seconds, 0);
      expect(platform.tareCount, 1);
      expect(find.text('0.0 g'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

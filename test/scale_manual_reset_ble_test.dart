import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/preferences/scale_settings.dart';
import 'package:holybeans/data/services/ble_scale.dart';
import 'package:holybeans/data/services/scale.dart';
import 'package:holybeans/domain/scale_recording.dart';
import 'package:holybeans/ui/brews/brew_scale_session.dart';
import 'package:holybeans/ui/brews/brew_timer.dart';
import 'package:universal_ble/universal_ble.dart';

import 'helpers/fake_acaia_ble_platform.dart';
import 'helpers/fake_dot_ble_platform.dart';
import 'helpers/fake_scale_ble_platform.dart';
import 'helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final family in [
    'bookoo-ultra',
    'bookoo-mini',
    'microbalance',
    'microbalance-ti',
    'microbalance-alternate',
    'acaia',
    'acaia-classic',
    'dot',
  ]) {
    for (final running in [false, true]) {
      test(
        '$family manual reset while running=$running leaves weight and time at zero',
        () async {
          final bookoo = family.startsWith('bookoo');
          final acaia = family.startsWith('acaia');
          final platform = acaia
              ? FakeAcaiaBlePlatform(classic: family == 'acaia-classic')
              : family == 'dot'
              ? FakeDotBlePlatform()
              : FakeScaleBlePlatform(
                  ti: family == 'microbalance-ti',
                  alternate: family == 'microbalance-alternate',
                );
          UniversalBle.setInstance(platform);
          final db = memoryDatabase();
          final scale = BleScale(ScaleSettings(db));
          final minutes = TextEditingController();
          final seconds = TextEditingController();
          BrewScaleSession? session;
          BrewTimer? timer;
          try {
            await scale.pair(
              FoundDevice(
                id: bookoo ? 'BOOKOO-TEST' : platform.id,
                name: bookoo
                    ? (family == 'bookoo-mini' ? 'BOOKOO_SC_M' : 'BOOKOO_SC_U')
                    : platform.name,
              ),
            );
            expect(scale.connected, isTrue);
            final brew = session = BrewScaleSession(scale);
            timer = BrewTimer(
              minutes: minutes,
              seconds: seconds,
              onStart: brew.timerStarted,
              onStop: brew.timerStopped,
              onReset: brew.timerReset,
            );
            // Flush the initial dial reset before simulating a previous result.
            await scale.send(ScaleCommand.resetTimer);
            platform.state = running ? 10 : 11;
            platform.seconds = 45;
            platform.grams = 36.2;
            platform.writes.clear();
            expect(await brew.resetWeightAndTimer(timer.reset), isTrue);
            expect(timer.running, isFalse);
            expect(timer.elapsedSeconds, 0);
            expect(brew.recording, isFalse);
            if (bookoo) {
              expect(platform.writes, [
                [3, 10, 6, 0, 0, 15],
                [3, 10, 1, 0, 0, 8],
              ]);
            } else {
              expect(platform.seconds, 0);
              expect(platform.grams, 0);
              expect(platform.tareCount, 1);
              if (family == 'dot') {
                expect(
                  platform.writes.map(
                    (frame) => [
                      frame[3],
                      ...frame.sublist(6, frame.length - 2),
                    ],
                  ),
                  [
                    [2, 3],
                    [13],
                  ],
                );
                expect(scale.connected, isTrue);
              } else if (acaia) {
                final controls = platform.writes.where(
                  (frame) => [4, 13].contains(frame[2]),
                );
                expect(controls.map((frame) => frame[2]), [13, 13, 4]);
                expect(controls.take(2).map((frame) => frame[4]), [2, 1]);
              } else {
                expect(platform.state, 5);
              }
            }
          } finally {
            timer?.dispose();
            session?.dispose();
            minutes.dispose();
            seconds.dispose();
            await scale.disconnect();
            scale.dispose();
            await db.close();
          }
        },
      );
    }
  }
}

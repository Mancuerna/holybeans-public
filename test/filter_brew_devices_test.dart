import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/ui/brews/brew_devices.dart';
import 'package:holybeans/ui/brews/brew_draft.dart';
import 'package:holybeans/ui/brews/brew_timer.dart';

import 'helpers/fake_scale.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<void> checkStop({
    required bool espresso,
    required bool measured,
    String target = '300',
  }) async {
    final draft = BrewDraft();
    draft.water.text = target;
    draft.beverage.text = '40';
    final scale = FakeScale(name: 'BOOKOO_SC_U', connected: true);
    late final BrewDevices devices;
    final timer = BrewTimer(
      minutes: draft.durationMinutes,
      seconds: draft.durationSeconds,
      onStart: (seconds) => devices.timerStarted(seconds),
      onStop: () => devices.timerStopped(),
      onReset: () => devices.timerReset(),
    );
    devices = BrewDevices(
      draft: draft,
      timer: timer,
      isEspresso: () => espresso,
      scale: scale,
    );
    try {
      timer.toggle();
      if (measured) {
        for (final grams in [0.0, 281.0, -120.0]) {
          scale.emit(grams);
          await Future<void>.delayed(const Duration(milliseconds: 120));
        }
      }
      timer.stop();
      expect(draft.water.text, espresso || !measured ? target : '281');
      expect(draft.beverage.text, '40');
      if (!espresso) {
        expect(devices.filterWaterTarget, target.isEmpty ? isNull : 300);
        timer.toggle();
        timer.stop();
        expect(devices.filterWaterTarget, target.isEmpty ? isNull : 300);
        timer.reset();
        draft.water.text = '320';
        expect(devices.filterWaterTarget, 320);
      }
    } finally {
      timer.dispose();
      devices.dispose();
      draft.dispose();
      scale.dispose();
    }
  }

  test(
    'filter stop overwrites planned water, keeps the target and survives lifting',
    () => checkStop(espresso: false, measured: true),
  );
  test(
    'without recorded water Stop leaves the planned water untouched',
    () => checkStop(espresso: false, measured: false),
  );
  test(
    'an unspecified target is not invented from the final measurement',
    () => checkStop(espresso: false, measured: true, target: ''),
  );
  test(
    'espresso keeps its typed water and yield',
    () => checkStop(espresso: true, measured: true),
  );
}

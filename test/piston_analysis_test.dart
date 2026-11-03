import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/meticulous/piston_analysis.dart';

Map<String, dynamic> sample({
  String? status = 'retracting',
  double current = 1.2,
  double speed = -10,
  double drive = -100,
  double position = 45,
  double pressure = 0,
}) => {
  'status': status,
  'shot': {'pressure': pressure},
  'sensors': {
    'motor_current': current,
    'motor_speed': speed,
    'motor_power': drive,
    'motor_position': position,
  },
};
Map<String, dynamic> shot(List<Object?> data) => {
  'id': 'shot',
  'time': 1000,
  'data': data,
};
void main() {
  test(
    'historical selection preserves medians and ignores pre-shot retraction',
    () {
      final result = analyzePiston(
        shot([
          sample(status: 'click_to_start'),
          for (var i = 0; i < 10; i++) sample(current: 9),
          sample(status: 'Extraction'),
          for (final c in [1.0, 1.1, 1.2, 1.3, 1.4, 9.0]) sample(current: c),
        ]),
      );
      expect(result.current, 1.25);
      expect(result.speed, 10);
      expect(result.samples, 6);
    },
  );
  test(
    'requires observed extraction context and five finite signed samples',
    () {
      for (final preceding in [
        null,
        '',
        'unknown',
        'idle',
        'click_to_start',
        'home',
        'finished',
      ]) {
        expect(
          analyzePiston(
            shot([
              sample(status: preceding),
              for (var i = 0; i < 5; i++) sample(),
            ]),
          ).usable,
          false,
        );
      }
      for (final bad in [
        sample(speed: 10),
        sample(drive: 100),
        sample(position: 34.99),
        sample(position: 55.01),
        sample(pressure: .1),
        sample(pressure: -.1),
        sample(current: double.nan),
        sample(speed: double.infinity),
      ]) {
        expect(
          analyzePiston(
            shot([
              sample(status: 'Extraction'),
              for (var i = 0; i < 5; i++) bad,
            ]),
          ).usable,
          false,
        );
      }
      expect(
        analyzePiston(
          shot([
            sample(status: 'Extraction'),
            for (var i = 0; i < 4; i++) sample(),
          ]),
        ).usable,
        false,
      );
      expect(
        analyzePiston(
          shot([
            sample(status: 'Extraction'),
            sample(status: null),
            for (var i = 0; i < 5; i++) sample(),
          ]),
        ).usable,
        false,
      );
    },
  );
  test('includes exact position and signed speed/drive bounds; missing values are not zero', () {
    for (final position in [35.0, 55.0]) {
      final result = analyzePiston(
        shot([
          {'status': 'Extraction'},
          for (var i = 0; i < 5; i++)
            sample(
              position: position,
              speed: -8,
              drive: -99,
              pressure: .099,
              current: -1,
            ),
        ]),
      );
      expect(result.current, 1);
      expect(result.speed, 8);
    }
    final missing = sample();
    (missing['shot'] as Map).clear();
    expect(
      analyzePiston(
        shot([
          sample(status: 'Extraction'),
          for (var i = 0; i < 5; i++) missing,
        ]),
      ).usable,
      false,
    );
  });
  test(
    'smoothing resets at maintenance and trend does not depend on view range',
    () {
      final start = DateTime(2026).millisecondsSinceEpoch;
      final readings = [
        for (var i = 0; i < 20; i++)
          PistonReading(
            shotId: '$i',
            timeMs: start + i * Duration.millisecondsPerDay,
            samples: 5,
            current: i < 10 ? 2 : 1 + (i - 10) * .01,
            speed: 10,
          ),
      ];
      final services = [
        PistonService(id: 's', timeMs: readings[10].timeMs, kind: 'grease'),
      ];
      final series = pistonSeries(readings, services);
      expect(series[9].value, 2);
      expect(series[10].value, 1);
      final trend = pistonTrend(readings, services);
      expect(trend.monthly, closeTo(30 / 1.035, .001));
      expect(trend.change, greaterThan(0));
      expect(
        pistonTrend(readings, [
          PistonService(
            id: 'after',
            timeMs: readings.last.timeMs + 1,
            kind: 'clean',
          ),
        ]).monthly,
        isNull,
      );
      expect(pistonTrend(readings.take(2).toList(), []).change, isNull);
    },
  );
}

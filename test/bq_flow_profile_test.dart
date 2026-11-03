import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/beanconqueror/bq_flow_profile.dart';
import 'package:holybeans/domain/shot_curve.dart';

String clock(int ms) {
  final time = Duration(milliseconds: ms);
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.inHours % 24)}:${two(time.inMinutes % 60)}:'
      '${two(time.inSeconds % 60)}.'
      '${(time.inMilliseconds % 1000).toString().padLeft(3, '0')}';
}

void main() {
  test('a machine shot keeps weight, flow and pressure over time', () {
    // As BeanConqueror stores a Meticulous shot: clock times from
    // midnight and no brew time.
    final profile = {
      'weight': [
        for (final (ms, grams) in [(0, 0.0), (500, 0.4), (1000, 1.6)])
          {'timestamp': clock(ms), 'brew_time': '', 'actual_weight': grams},
      ],
      'realtimeFlow': [
        for (final (ms, flow) in [(0, 0.0), (480, 0.8), (1010, 2.4)])
          {'timestamp': clock(ms), 'brew_time': '', 'flow_value': flow},
      ],
      'pressureFlow': [
        for (final (ms, bar) in [(0, 1.0), (520, 6.5), (990, 9.0)])
          {'timestamp': clock(ms), 'brew_time': '', 'actual_pressure': bar},
      ],
    };
    final curve = bqFlowCurve(profile)!;
    expect(curve.timesMs, [0, 500, 1000]);
    expect(curve.weight, [0, 0.4, 1.6]);
    expect(curve.flow, [0, 0.8, 2.4], reason: 'nearest flow sample');
    expect(curve.pressure, [1, 6.5, 9]);
    expect(
      curve.series,
      CurveSeries.values.toSet().toList()
        ..sort((a, b) => a.index.compareTo(b.index)),
    );
  });

  test('a scale brew has no pressure and may cross midnight', () {
    const start = 23 * 3600000 + 59 * 60000 + 59000; // 23:59:59
    final profile = {
      'weight': [
        for (final (offset, grams) in [(0, 0.0), (600, 12.0), (1200, 30.5)])
          {
            'timestamp': clock(start + offset),
            'brew_time': '${offset ~/ 1000}.${offset % 1000 ~/ 100}',
            'actual_weight': grams,
          },
      ],
      'realtimeFlow': <Object>[],
      'pressureFlow': [
        {'timestamp': clock(start), 'actual_pressure': 0},
      ],
    };
    final curve = bqFlowCurve(profile)!;
    expect(curve.timesMs, [0, 600, 1200]);
    expect(curve.weight.last, 30.5);
    expect(curve.pressure, isEmpty, reason: 'all zero');
    expect(curve.flow, isEmpty);
  });

  test('profiles without enough weight samples give no curve', () {
    expect(bqFlowCurve(null), isNull);
    expect(bqFlowCurve({'weight': <Object>[]}), isNull);
    expect(
      bqFlowCurve({
        'weight': [
          {'timestamp': 'not a time', 'actual_weight': 3},
          {'timestamp': '00:00:01.000', 'actual_weight': 4},
        ],
      }),
      isNull,
    );
  });
}

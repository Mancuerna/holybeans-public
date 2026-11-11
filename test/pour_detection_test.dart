import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/brew_pours.dart';
import 'package:holybeans/domain/pour_detection.dart';
import 'package:holybeans/domain/shot_curve.dart';

/// Builds a scale curve sampled every 100 ms from steps: `pour(seconds,
/// grams)` adds water steadily, `wait(seconds)` keeps it, `swirl(seconds)`
/// shakes the weight and lets it settle back.
class _CurveBuilder {
  final _times = <int>[];
  final _weight = <double>[];
  var _ms = 0;
  var _grams = 0.0;

  void _sample(double grams) {
    _times.add(_ms);
    _weight.add(grams);
    _ms += 100;
  }

  void wait(int seconds) {
    for (var i = 0; i < seconds * 10; i++) {
      _sample(_grams);
    }
  }

  void pour(int seconds, double grams) {
    final steps = seconds * 10;
    for (var i = 1; i <= steps; i++) {
      _sample(_grams + grams * i / steps);
    }
    _grams += grams;
  }

  /// The weight jumps up and down by up to [swing] grams, then settles.
  void swirl(int seconds, {double swing = 80}) {
    for (var i = 0; i < seconds * 10; i++) {
      _sample(_grams + (i.isEven ? swing : -swing) * (1 - i / (seconds * 10)));
    }
  }

  ShotCurve get curve =>
      ShotCurve(timesMs: _times, flow: const [], weight: _weight);
}

void main() {
  group('five equal pours with long rests', () {
    final builder = _CurveBuilder()..wait(2);
    for (var i = 0; i < 5; i++) {
      builder
        ..pour(6, 50)
        ..wait(25);
    }
    for (final (blooms, pours, expected) in <(int?, int?, (int, int)?)>[
      (null, null, (3, 2)),
      (null, 3, (2, 3)),
      (null, 5, (0, 5)),
      (0, null, (0, 5)),
      (0, 5, (0, 5)),
      (2, 3, (2, 3)),
      (0, 3, null),
      (2, 4, null),
      (null, 6, null),
      (null, 1, null),
      (null, 0, null),
      (-1, null, null),
      (4, null, null),
      (null, -1, null),
      (null, 11, null),
    ]) {
      test('counts $blooms + $pours give $expected', () {
        final found = brewPoursFromCurve(
          builder.curve,
          doseGrams: 15,
          bloomCount: blooms,
          pourCount: pours,
        );
        if (expected == null) {
          expect(found, isNull);
          return;
        }
        expect((found!.bloomCount, found.pourCount), expected);
        expect(found.phases, hasLength(5));
        expect(found.phases.map((p) => p.waterGrams), List.filled(5, 50));
        expect(found.phases.map((p) => p.durationSeconds), List.filled(5, 6));
        expect(found.phases.map((p) => (p.kind, p.number)), [
          for (var i = 1; i <= expected.$1; i++) (BrewPourKind.bloom, i),
          for (var i = 1; i <= expected.$2; i++) (BrewPourKind.pour, i),
        ]);
      });
    }
    test('an explicit bloom count larger than detection is left alone', () {
      final short = _CurveBuilder()
        ..wait(2)
        ..pour(6, 50)
        ..wait(25);
      expect(brewPoursFromCurve(short.curve, bloomCount: 2), isNull);
      final onlyBloom = brewPoursFromCurve(short.curve, pourCount: 0)!;
      expect((onlyBloom.bloomCount, onlyBloom.pourCount), (1, 0));
    });
  });

  test('two blooms and two pours, with a swirl that settles back', () {
    final brew = _CurveBuilder()
      ..wait(2)
      ..pour(6, 50)
      ..wait(25)
      ..pour(6, 50)
      ..wait(22)
      ..pour(10, 90)
      ..wait(20)
      ..pour(8, 90)
      ..swirl(3)
      ..wait(30);
    final pours = detectPours(brew.curve);
    expect(pours.map((pour) => pour.grams.round()), [50, 50, 90, 90]);
    expect(pours.first.startMs, closeTo(2000, 300));
    expect(pours.first.endMs, closeTo(8000, 300));

    final brewPours = brewPoursFromCurve(brew.curve, doseGrams: 16)!;
    expect((brewPours.bloomCount, brewPours.pourCount), (2, 2));
    final first = brewPours.phases.first;
    expect(first.kind, BrewPourKind.bloom);
    expect(first.waterGrams, 50);
    expect(first.durationSeconds, 6);
    expect(first.restSeconds, 25);
    final last = brewPours.phases.last;
    expect(
      (last.kind, last.number, last.waterGrams),
      (BrewPourKind.pour, 2, 90),
    );
    expect(last.restSeconds, isNull, reason: 'only blooms rest');
  });

  test('a pour that stutters for a moment is still one pour', () {
    final brew = _CurveBuilder()
      ..wait(2)
      ..pour(4, 30)
      ..wait(1)
      ..pour(4, 30)
      ..wait(10);
    expect(detectPours(brew.curve).map((pour) => pour.grams.round()), [60]);
  });

  test('the blooms given by hand win over the guess', () {
    final brew = _CurveBuilder()
      ..wait(2)
      ..pour(6, 50)
      ..wait(25)
      ..pour(6, 50)
      ..wait(22)
      ..pour(10, 150)
      ..wait(10);
    expect(brewPoursFromCurve(brew.curve, doseGrams: 16)!.bloomCount, 2);
    final oneBloom = brewPoursFromCurve(
      brew.curve,
      doseGrams: 16,
      bloomCount: 1,
    )!;
    expect((oneBloom.bloomCount, oneBloom.pourCount), (1, 2));
    // Without the dose, a bloom is a small share of the water.
    expect(brewPoursFromCurve(brew.curve)!.bloomCount, 2);
  });

  test('a curve that starts while pouring, and a carafe lifted at the end', () {
    final brew = _CurveBuilder()
      ..pour(5, 40)
      ..wait(20)
      ..pour(8, 160)
      ..wait(10);
    final lifted = _CurveBuilder()
      ..wait(2)
      ..pour(5, 40)
      ..wait(20)
      ..pour(8, 160)
      ..wait(10)
      ..pour(1, -200)
      ..wait(10);
    for (final curve in [brew.curve, lifted.curve]) {
      expect(detectPours(curve).map((pour) => pour.grams.round()), [40, 160]);
    }
  });

  test('nothing to record: no pours, or more than a brew holds', () {
    expect(brewPoursFromCurve((_CurveBuilder()..wait(30)).curve), isNull);
    final pulses = _CurveBuilder()..wait(2);
    for (var i = 0; i < 13; i++) {
      pulses
        ..pour(3, 20)
        ..wait(8);
    }
    expect(detectPours(pulses.curve), hasLength(13));
    expect(
      brewPoursFromCurve(pulses.curve, bloomCount: 1),
      isNull,
      reason: 'twelve pours after the bloom',
    );
  });

  test('a large dose\'s first pour after a wait is not a third bloom', () {
    // A tester's free pour: 30 g of coffee, blooms of 59.5 and 63.6 g, then
    // 129.4 g with an 18 s wait before the last pour. Under five times the
    // dose and followed by a long rest, it used to count as a bloom.
    DetectedPour step(int start, int end, double grams) =>
        DetectedPour(startMs: start * 1000, endMs: end * 1000, grams: grams);
    final pours = [
      step(0, 10, 59.5),
      step(32, 46, 63.6),
      step(62, 72, 129.4),
      step(90, 110, 203.1),
    ];
    final found = brewPoursOf(pours, doseGrams: 30)!;
    expect((found.bloomCount, found.pourCount), (2, 2));
    // Blooms of a similar size still count, up to three of them.
    final similar = [
      step(0, 8, 50.2),
      step(30, 38, 49.7),
      step(57, 65, 52.0),
      step(85, 100, 150),
    ];
    expect(brewPoursOf(similar, doseGrams: 16)!.bloomCount, 3);
  });
}

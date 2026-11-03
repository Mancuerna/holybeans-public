import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/filter_brew_progress.dart';
import 'package:holybeans/domain/shot_curve.dart';

void main() {
  test('ratios and water remaining follow recorded water and the target', () {
    final progress = FilterBrewProgress(
      pouredGrams: 281,
      doseGrams: 18,
      targetWaterGrams: 300,
    );
    expect(progress.currentRatio, closeTo(15.611, 0.001));
    expect(progress.targetRatio, closeTo(16.667, 0.001));
    expect(progress.remainingGrams, 19);
    expect(progress.excessGrams, 0);
  });

  test('excess water does not become negative remaining water', () {
    final progress = FilterBrewProgress(
      pouredGrams: 310,
      doseGrams: 20,
      targetWaterGrams: 300,
    );
    expect(progress.remainingGrams, 0);
    expect(progress.excessGrams, 10);
    expect(progress.currentRatio, 15.5);
    expect(progress.targetRatio, 15);
  });

  test('missing or invalid dose, target and measurements stay unknown', () {
    final progress = FilterBrewProgress(
      pouredGrams: double.nan,
      doseGrams: 0,
      targetWaterGrams: double.infinity,
    );
    expect(progress.pouredGrams, isNull);
    expect(progress.currentRatio, isNull);
    expect(progress.targetRatio, isNull);
    expect(progress.remainingGrams, isNull);
    expect(FilterBrewProgress(targetWaterGrams: 300).remainingGrams, 300);
  });

  test('lifting the dripper keeps the maximum valid water recorded', () {
    final curve = ShotCurve(
      timesMs: const [0, 100, 200, 300],
      flow: const [],
      weight: const [0, 281, -120, double.nan],
    );
    expect(recordedWaterGrams(curve), 281);
    expect(recordedWaterGrams(null), isNull);
  });
}

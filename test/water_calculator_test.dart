import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/water_adjustment.dart';
import 'package:holybeans/domain/water_chemistry.dart';
import 'package:holybeans/domain/water_presets.dart';

void main() {
  test('calcium hydrate changes mass while preserving every ion and GH', () {
    final anhydrous = saltContribution(
      WaterSalt.calciumChloride,
      CalciumForm.anhydrous,
      .1,
    );
    final dihydrate = saltContribution(
      WaterSalt.calciumChloride,
      CalciumForm.dihydrate,
      .1 * 147.02 / 110.99,
    );
    for (final ion in WaterIon.values) {
      expect(dihydrate[ion], closeTo(anhydrous[ion]!, 1e-9));
    }
    expect(dihydrate.gh, closeTo(90.1764, .001));
  });

  test(
    'Epsom example independently reproduces 80 GH and sodium buffer 40 KH',
    () {
      final water = waterFromSalts(
        {WaterSalt.epsom: .197004803, WaterSalt.sodiumBicarbonate: .067149647},
        1,
        CalciumForm.anhydrous,
      );
      expect(water.gh, closeTo(80, .00001));
      expect(water.kh, closeTo(40, .00001));
      expect(water[WaterIon.calcium], 0);
      expect(water[WaterIon.magnesium], closeTo(19.427, .002));
      expect(water[WaterIon.bicarbonate], closeTo(48.77, .01));
      expect(water.mineralSum, isNotNull);
    },
  );

  test(
    'each salt preserves electrical charge and excludes crystallisation water',
    () {
      for (final salt in WaterSalt.values) {
        for (final calcium in CalciumForm.values) {
          final w = saltContribution(salt, calcium, 1);
          final positive =
              2 * w[WaterIon.calcium]! / 40.078 +
              2 * w[WaterIon.magnesium]! / 24.305 +
              w[WaterIon.sodium]! / 22.989769 +
              w[WaterIon.potassium]! / 39.0983;
          final negative =
              w[WaterIon.chloride]! / 35.45 +
              2 * w[WaterIon.sulfate]! / 96.063 +
              w[WaterIon.bicarbonate]! / bicarbonateMass;
          expect(positive, closeTo(negative, 1e-9));
          expect(w.mineralSum, lessThanOrEqualTo(1000.02));
        }
      }
    },
  );

  test('presets scale linearly and calcium choice preserves the target', () {
    for (final preset in WaterPreset.values) {
      final one = preset.gramsPerLitre(CalciumForm.anhydrous);
      final five = one.map((s, g) => MapEntry(s, g * 5));
      final water = waterFromSalts(five, 5, CalciumForm.anhydrous);
      final hydrated = waterFromSalts(
        preset.gramsPerLitre(CalciumForm.dihydrate),
        1,
        CalciumForm.dihydrate,
      );
      for (final ion in WaterIon.values) {
        expect(water[ion], closeTo(preset.composition[ion]!, 1e-9));
        expect(hydrated[ion], closeTo(water[ion]!, 1e-9));
      }
    }
    expect(WaterPreset.baristaHustle.composition.gh, closeTo(80, 1e-9));
    expect(WaterPreset.baristaHustle.composition.kh, closeTo(40, 1e-9));
    expect(
      WaterPreset.raoPerger.gramsPerLitre(
        CalciumForm.anhydrous,
      )[WaterSalt.calciumChloride],
      .03,
    );
  });

  test('mineral water reaches GH/KH with nonnegative additions and retains calcium', () {
    final base = WaterComposition(
      ions: {
        WaterIon.calcium: 10,
        WaterIon.magnesium: 5,
        WaterIon.bicarbonate: 30,
      },
    );
    final grams = adjustWater(
      base: base,
      target: WaterPreset.baristaHustle.composition,
      litres: 1,
      calcium: CalciumForm.dihydrate,
    );
    final result = base.add(waterFromSalts(grams, 1, CalciumForm.dihydrate));
    expect(grams.values.every((g) => g >= 0), isTrue);
    expect(result.gh, closeTo(80, 1e-7));
    expect(result.kh, closeTo(40, 1e-7));
    expect(result[WaterIon.calcium], 10);
    expect(result[WaterIon.sodium], isNull);
    expect(result.mineralSum, isNull);
  });

  test(
    'an already matching water needs no salts and high KH cannot decrease',
    () {
      final target = WaterPreset.raoPerger.composition;
      final zero = adjustWater(
        base: target,
        target: target,
        litres: 1,
        calcium: CalciumForm.anhydrous,
      );
      expect(zero.values.every((g) => g == 0), isTrue);
      final base = WaterComposition(
        ions: {for (final ion in WaterIon.values) ion: 0},
        measuredGh: 10,
        measuredKh: 150,
      );
      final grams = adjustWater(
        base: base,
        target: target,
        litres: 2,
        calcium: CalciumForm.anhydrous,
      );
      expect(grams[WaterSalt.sodiumBicarbonate], 0);
      expect(grams[WaterSalt.potassiumBicarbonate], 0);
      final result = base.add(waterFromSalts(grams, 2, CalciumForm.anhydrous));
      expect(result.kh, 150);
      expect(result.gh, closeTo(target.gh!, 1e-7));
    },
  );

  test(
    'an exactly attainable full profile is recovered from a diluted copy',
    () {
      final target = WaterPreset.raoPerger.composition;
      final base = WaterComposition(
        ions: target.ions.map((ion, v) => MapEntry(ion, v! * .25)),
      );
      final grams = adjustWater(
        base: base,
        target: target,
        litres: 5,
        calcium: CalciumForm.dihydrate,
      );
      final result = base.add(waterFromSalts(grams, 5, CalciumForm.dihydrate));
      for (final ion in WaterIon.values) {
        expect(result[ion], closeTo(target[ion]!, .0001));
      }
      final ref = WaterPreset.raoPerger.gramsPerLitre(CalciumForm.dihydrate);
      for (final salt in WaterSalt.values) {
        expect(grams[salt], closeTo(ref[salt]! * 3.75, .00001));
      }
    },
  );

  test('restricted sources reproduce the hand-calculated bottle example', () {
    final base = WaterComposition(
      ions: {
        WaterIon.calcium: 10,
        WaterIon.magnesium: 5,
        WaterIon.bicarbonate: 30,
      },
    );
    final grams = adjustWater(
      base: base,
      target: WaterPreset.baristaHustle.composition,
      litres: 1,
      calcium: CalciumForm.dihydrate,
      allowed: {WaterSalt.epsom, WaterSalt.sodiumBicarbonate},
    );
    expect(grams[WaterSalt.epsom], closeTo(.0848, .0001));
    expect(grams[WaterSalt.sodiumBicarbonate], closeTo(.02584, .0001));
    expect(grams[WaterSalt.calciumChloride], 0);
  });

  test(
    'random bottle compositions preserve GH/KH deficits and volume scaling',
    () {
      final random = Random(70);
      for (var n = 0; n < 80; n++) {
        final base = WaterComposition(
          ions: {
            for (final ion in WaterIon.values) ion: random.nextDouble() * 100,
          },
        );
        final target = WaterPreset.values[n % 3].composition;
        final grams = adjustWater(
          base: base,
          target: target,
          litres: 1,
          calcium: CalciumForm.dihydrate,
        );
        final five = adjustWater(
          base: base,
          target: target,
          litres: 5,
          calcium: CalciumForm.dihydrate,
        );
        for (final salt in WaterSalt.values) {
          expect(grams[salt]!.isFinite && grams[salt]! >= 0, isTrue);
          expect(five[salt], closeTo(grams[salt]! * 5, 1e-9));
        }
        final result = base.add(
          waterFromSalts(grams, 1, CalciumForm.dihydrate),
        );
        expect(result.gh, closeTo(max(base.gh!, target.gh!), .00001));
        expect(result.kh, closeTo(max(base.kh!, target.kh!), .00001));
      }
    },
  );

  test(
    'versioned recipe round trip preserves unknowns, targets, form and doses',
    () {
      final recipe = WaterRecipe(
        litres: 3,
        calcium: CalciumForm.dihydrate,
        mode: WaterCalculationMode.preset,
        base: WaterComposition(
          ions: {
            WaterIon.calcium: 10,
            WaterIon.magnesium: 5,
            WaterIon.bicarbonate: 30,
          },
        ),
        target: WaterPreset.raoPerger.composition,
        grams: {WaterSalt.epsom: .123},
        presetId: WaterPreset.raoPerger.name,
      );
      final decoded = WaterRecipe.fromJson(recipe.toJson());
      expect(decoded.toJson(), recipe.toJson());
      expect(decoded.result[WaterIon.sodium], isNull);
      for (final invalid in ['{}', '{"version":2}', 'not json']) {
        expect(() => WaterRecipe.fromJson(invalid), throwsFormatException);
      }
    },
  );

  test('invalid masses, volumes and missing base hardness are rejected', () {
    for (final value in [-1.0, double.nan, double.infinity]) {
      expect(
        () => saltContribution(WaterSalt.epsom, CalciumForm.anhydrous, value),
        throwsArgumentError,
      );
    }
    for (final volume in [0.0, -1.0, double.infinity]) {
      expect(
        () => waterFromSalts({}, volume, CalciumForm.anhydrous),
        throwsArgumentError,
      );
    }
    expect(
      () => adjustWater(
        base: WaterComposition(),
        target: WaterPreset.hendon.composition,
        litres: 1,
        calcium: CalciumForm.anhydrous,
      ),
      throwsArgumentError,
    );
  });
}

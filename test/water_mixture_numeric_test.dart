import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/water_adjustment.dart';
import 'package:holybeans/domain/water_chemistry.dart';
import 'package:holybeans/domain/water_presets.dart';

// Independent reference values from direct stoichiometry, not production
// helpers: 40/M(CaCO3) mmol/L of each divalent ion, 80/M(CaCO3) of NaHCO3.
// M(CaCO3)=100.0869, Ca=40.078, Mg=24.305; hydrate masses in docs/DATA.md.
void main() {
  for (final (form, calciumGrams) in [
    (CalciumForm.anhydrous, .044357453373),
    (CalciumForm.dihydrate, .058756940219),
  ]) {
    for (final (magnesiumSalt, magnesiumGrams, chloride, sulfate) in [
      (WaterSalt.epsom, .098502401413, 28.335376557771, 38.391837493218),
      (WaterSalt.magnesiumChloride, .081249394276, 56.670753115543, 0.0),
    ]) {
      test(
        'numeric reference: $form + $magnesiumSalt, 80/40, half calcium',
        () {
          final target = customWaterTarget(
            80,
            40,
            magnesiumSalt,
            WaterSalt.sodiumBicarbonate,
            form,
            calciumGhFraction: .5,
          );
          final grams = adjustWaterMixture(
            base: WaterComposition.distilled(),
            target: target,
            litres: 1,
            calcium: form,
            magnesiumSource: magnesiumSalt,
            khSource: WaterSalt.sodiumBicarbonate,
          );
          expect(
            grams[WaterSalt.calciumChloride],
            closeTo(calciumGrams, 1e-12),
          );
          expect(grams[magnesiumSalt], closeTo(magnesiumGrams, 1e-12));
          expect(
            grams[WaterSalt.sodiumBicarbonate],
            closeTo(.067149646957, 1e-12),
          );
          final actual = waterFromSalts(grams, 1, form);
          for (final (ion, expected) in [
            (WaterIon.calcium, 16.017280982826),
            (WaterIon.magnesium, 9.713558917301),
            (WaterIon.chloride, chloride),
            (WaterIon.sulfate, sulfate),
            (WaterIon.sodium, 18.375846589314),
            (WaterIon.bicarbonate, 48.771057950641),
            (WaterIon.potassium, 0.0),
          ]) {
            expect(actual[ion], closeTo(expected, 1e-9), reason: ion.name);
          }
          expect(actual.gh, closeTo(80, 1e-9));
          expect(actual.kh, closeTo(40, 1e-9));
        },
      );
    }
  }
  test(
    'numeric reference: subtract starting Ca5 Mg2 KH10, scale to 5 litres',
    () {
      final base = WaterComposition(
        ions: {
          ...WaterComposition.distilled().ions,
          WaterIon.calcium: 5,
          WaterIon.magnesium: 2,
          WaterIon.bicarbonate: 12.192764487660224,
        },
      );
      final target = customWaterTarget(
        80,
        40,
        WaterSalt.epsom,
        WaterSalt.sodiumBicarbonate,
        CalciumForm.dihydrate,
        calciumGhFraction: .5,
      );
      final grams = adjustWaterMixture(
        base: base,
        target: target,
        litres: 5,
        calcium: CalciumForm.dihydrate,
        magnesiumSource: WaterSalt.epsom,
        khSource: WaterSalt.sodiumBicarbonate,
      );
      expect(
        grams[WaterSalt.calciumChloride],
        closeTo(.040415206599507645 * 5, 1e-12),
      );
      expect(grams[WaterSalt.epsom], closeTo(.07822097783777594 * 5, 1e-12));
      expect(
        grams[WaterSalt.sodiumBicarbonate],
        closeTo(.05036223521759591 * 5, 1e-12),
      );
      final result = base.add(waterFromSalts(grams, 5, CalciumForm.dihydrate));
      expect(result[WaterIon.calcium], closeTo(16.017280982826, 1e-9));
      expect(result[WaterIon.magnesium], closeTo(9.713558917301, 1e-9));
      expect(result.gh, closeTo(80, 1e-9));
      expect(result.kh, closeTo(40, 1e-9));
    },
  );
}

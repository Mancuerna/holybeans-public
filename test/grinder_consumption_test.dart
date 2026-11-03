import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/grinder_consumption.dart';

ConsumptionDose dose(
  double? grams, {
  String? id,
  String? name,
  bool preGround = false,
  int time = 0,
}) => (
  grinderId: id,
  grinderName: name,
  isPreGround: preGround,
  grams: grams,
  brewedAtMs: time,
);

void main() {
  test('IDs preserve renamed grinders and separate equal names', () {
    final groups = consumptionByGrinder([
      dose(15, id: 'a', name: 'Old'),
      dose(20, id: 'b', name: 'New'),
      dose(18, id: 'a', name: 'New', time: 1),
      dose(null, id: 'a', name: 'New', time: 2),
    ]);
    expect(groups.map((g) => (g.name, g.grams, g.brewCount, g.doseCount)), [
      ('New', 33.0, 3, 2),
      ('New', 20.0, 1, 1),
    ]);
  });
  test(
    'legacy names, pre-ground and unknown are separate and preserve mass',
    () {
      final groups = consumptionByGrinder([
        dose(15, name: 'Legacy'),
        dose(18, name: ' Legacy '),
        dose(20, preGround: true, id: 'ignored', name: 'Legacy'),
        dose(10),
      ]);
      expect(groups.map((g) => (g.source, g.grams)), [
        (ConsumptionSource.grinder, 33.0),
        (ConsumptionSource.preGround, 20.0),
        (ConsumptionSource.unknown, 10.0),
      ]);
      expect(groups.fold(0.0, (sum, g) => sum + g.grams), 63);
    },
  );
  test('missing or invalid doses are not invented or counted as known', () {
    final groups = consumptionByGrinder([
      dose(null),
      dose(double.nan),
      dose(double.infinity),
      dose(-1),
      dose(0),
    ]);
    expect(groups.single.grams, 0);
    expect(groups.single.brewCount, 5);
    expect(groups.single.doseCount, 0);
    expect(consumptionByGrinder([]), isEmpty);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/bean_roaster_groups.dart';
import 'package:holybeans/domain/freshness.dart';

GroupedBean bean(
  String id,
  String roaster, {
  double? grams,
  FreshnessPhase? phase,
}) => (id: id, roaster: roaster, grams: grams, phase: phase);

void main() {
  test('groups case and spaces, preserves accents and input coffee order', () {
    final groups = groupBeansByRoaster([
      bean('z', '  Big   Sur ', grams: 100, phase: FreshnessPhase.prime),
      bean('a', 'BIG SUR', grams: 200, phase: FreshnessPhase.prime),
      bean('b', 'Bíg Sur', grams: 50),
      bean('c', 'Alpha'),
      bean('d', ' '),
      bean('e', ''),
    ]);
    expect(groups.map((g) => g.key), ['alpha', 'big sur', 'bíg sur', '']);
    expect(groups[1].name, 'Big Sur');
    expect(groups[1].beans.map((b) => b.id), ['z', 'a']);
    expect(groups[1].knownGrams, 300);
    expect(groups[1].hasUnknownStock, isFalse);
    expect(groups[1].phases, {FreshnessPhase.prime: 2});
    expect(groups.last.beans, hasLength(2));
  });

  test('partial stock stays explicitly unknown; no invented phase', () {
    final group = groupBeansByRoaster([
      bean('a', 'R', grams: 125, phase: FreshnessPhase.aging),
      bean('b', 'R'),
      bean('c', 'R', grams: 0),
    ]).single;
    expect(group.knownGrams, 125);
    expect(group.hasUnknownStock, isTrue);
    expect(group.phases, {FreshnessPhase.aging: 1});
    expect(groupBeansByRoaster([]), isEmpty);
  });
}

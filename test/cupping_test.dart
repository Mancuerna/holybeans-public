import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/cupping.dart';

void main() {
  test('dose follows the SCA proportion until water is edited', () {
    final d = CuppingDraft()..updateDose(8.25);
    expect(d.water, 150);
    d.waterEdited = true;
    d.water = 140;
    d.updateDose(11);
    expect(d.suggestedCapacity, 200);
    expect(d.water, 140);
  });
  test(
    'round trip preserves explicit none and shared choices independently',
    () {
      final d = CuppingDraft()
        ..grinderId = 'g'
        ..waterProfileId = 'w'
        ..grindSetting = '25';
      d.cups[1]
        ..commonGrinder = false
        ..commonWater = false;
      final restored = CuppingDraft.fromJson(d.toJson());
      expect(restored.grinderFor(restored.cups[0]), 'g');
      expect(restored.waterFor(restored.cups[0]), 'w');
      expect(restored.grinderFor(restored.cups[1]), null);
      expect(restored.waterFor(restored.cups[1]), null);
      restored.grinderId = 'new';
      expect(restored.grinderFor(restored.cups[1]), null);
      expect(restored.settingFor(restored.cups[0]), '25');
    },
  );
  test('zero is a valid overall rating; a missing intensity is incomplete', () {
    final d = CuppingDraft();
    for (final c in d.cups) {
      c.coffeeId = 'c';
      c.rating = 0;
      c.scores = [1, 2, 3, 4, 5];
    }
    expect(d.ready, true);
    expect(d.scoredCount, 12);
    d.cups[0].scores[2] = null;
    expect(d.ready, false);
    expect(d.scoredCount, 11);
  });
  test('the clock survives resume and tasting defaults to 10 minutes', () {
    final d = CuppingDraft()
      ..startedAtMs = 1000
      ..brokenAtMs = 241000
      ..phase = CuppingPhase.cooling;
    final restored = CuppingDraft.fromJson(d.toJson());
    expect(restored.elapsedAt(721000), 720);
    expect(restored.tastingSeconds - restored.elapsedAt(241000), 360);
    expect(restored.elapsedAt(0), 0);
  });
  test('skipped scores count as answered and survive a draft round trip', () {
    final d = CuppingDraft();
    for (final cup in d.cups) {
      cup.notEvaluated = List.filled(6, true);
    }
    expect(d.scoringComplete, true);
    expect(d.scoredCount, 12);
    final restored = CuppingDraft.fromJson(d.toJson());
    expect(restored.cups.first.complete, true);
    expect(restored.cups.first.rating, null);
    expect(restored.cups.first.scores, everyElement(isNull));
    restored.cups.first.notEvaluated[2] = false;
    expect(restored.scoringComplete, false);
  });
  test(
    'paused time is excluded and a reset keeps the first pour timestamp',
    () {
      final d = CuppingDraft()
        ..startedAtMs = 1000
        ..timerStartedAtMs = 1000
        ..phase = CuppingPhase.infusion
        ..pausedAtMs = 121000;
      expect(d.elapsedAt(301000), 120);
      d.pausedTotalMs = 180000;
      d.pausedAtMs = null;
      expect(d.elapsedAt(301000), 120);
      d.timerStartedAtMs = 301000;
      d.pausedTotalMs = 0;
      expect(CuppingDraft.fromJson(d.toJson()).elapsedAt(301000), 0);
      expect(d.startedAtMs, 1000);
      expect(parseCuppingDuration('05:30'), 330);
      expect(parseCuppingDuration('5:60'), null);
    },
  );
  for (final mutate in <void Function(Map<String, dynamic>)>[
    (m) => m['version'] = 2,
    (m) => m['dose'] = 0,
    (m) => m['cups'] = <Object?>[],
    (m) =>
        (m['cups'] as List).addAll(List.filled(5, (m['cups'] as List).first)),
    (m) => m['phase'] = 'tasting',
    (m) => m['tastingAtMs'] = 50,
    (m) => (m['cups'][0] as Map)['rating'] = 7.3,
    (m) => (m['cups'][0] as Map)['scores'] = [0, 1, 2, 3, 4],
    (m) => (m['cups'][0] as Map)['scores'] = [1, 2],
    (m) => (m['cups'][0] as Map)['notEvaluated'] = [true],
    (m) {
      (m['cups'][0] as Map)['notEvaluated'] = [
        true,
        false,
        false,
        false,
        false,
        false,
      ];
      (m['cups'][0] as Map)['rating'] = 5;
    },
  ]) {
    test('invalid draft is rejected (${mutate.hashCode})', () {
      final map = jsonDecode(CuppingDraft().toJson()) as Map<String, dynamic>;
      mutate(map);
      expect(
        () => CuppingDraft.fromJson(jsonEncode(map)),
        throwsFormatException,
      );
    });
  }
}

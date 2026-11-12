import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/extraction_profile.dart';
import 'package:holybeans/domain/flow_guide.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/ui/profiles/profile_editor_model.dart';

void main() {
  test('linear flow integrates exactly and never extrapolates', () {
    final p = ExtractionProfile(
      id: 'p',
      name: 'Ramp',
      durationMs: 10000,
      flow: [
        (elapsedMs: 0, value: 0, breakBefore: false),
        (elapsedMs: 10000, value: 4, breakBefore: false),
      ],
    );
    expect(p.targetAt(p.flow, 5000), 2);
    expect(p.weightAt(5000), 5);
    expect(p.predictedGrams, 20);
    expect(p.targetAt(p.flow, -1), isNull);
    expect(p.targetAt(p.flow, 10001), isNull);
    expect(p.weightAt(10001), isNull);
    expect(ExtractionProfile.decode(p.encode()).encode(), p.encode());
  });
  test('pressure-only and missing cup readings do not invent yield', () {
    final example = ExtractionProfile.example('p', 'Pressure');
    final pressure = example.copyWith(
      flow: [],
      primary: 'pressure',
      targetGrams: 36,
    );
    expect(pressure.predictedGrams, isNull);
    final gap = example.copyWith(
      flow: [
        (elapsedMs: 0, value: 1, breakBefore: false),
        (elapsedMs: 1000, value: 1, breakBefore: false),
        (elapsedMs: 30000, value: 1, breakBefore: true),
      ],
    );
    expect(gap.targetAt(gap.flow, 1000), 1);
    expect(gap.targetAt(gap.flow, 2000), isNull);
    expect(gap.predictedGrams, isNull);
    expect(
      ExtractionProfile.decode(gap.encode()).flow.last.breakBefore,
      isTrue,
    );
  });
  test('imports demo V5 and rejects corrupt or future files', () {
    final demo = {
      'format': 'holybeans-profile-designer-demo',
      'version': 3,
      'name': 'Demo',
      'durationSeconds': 30,
      'doseGrams': 18,
      'temperatureCelsius': 93,
      'flowPoints': [
        {'tSeconds': 0, 'flowGs': 1},
        {'tSeconds': 30, 'flowGs': 1},
      ],
      'pressurePoints': [
        {'tSeconds': 0, 'pressureBar': 0},
        {'tSeconds': 30, 'pressureBar': 9},
      ],
    };
    expect(ExtractionProfile.decode(jsonEncode(demo)).predictedGrams, 30);
    for (final mutation in [
      {'version': 99},
      {'flowPoints': <Object>[]},
      {'durationSeconds': -1},
      {
        'pressurePoints': [
          {'tSeconds': 0, 'pressureBar': -1},
          {'tSeconds': 30, 'pressureBar': 9},
        ],
      },
    ]) {
      expect(
        () => ExtractionProfile.decode(jsonEncode({...demo, ...mutation})),
        throwsFormatException,
      );
    }
    final p = ExtractionProfile.example('p', 'p');
    expect(
      () => ExtractionProfile.decode(jsonEncode({...p.toJson(), 'version': 2})),
      throwsFormatException,
    );
    expect(
      () => p.copyWith(flow: [...p.flow, p.flow.last]),
      throwsFormatException,
    );
    expect(() => p.copyWith(doseGrams: double.nan), throwsFormatException);
    expect(() => p.copyWith(flow: [], pressure: []), throwsFormatException);
  });
  test('shot conversion preserves timer origin, gaps and source', () {
    final curve = ShotCurve(
      timesMs: [0, 500, 1000, 1500, 4000, 4500, 5000],
      weight: [0, 1, 2, 3, 6, 7, 8],
      flow: [],
    );
    final original = FlowGuide.fromCurve(curve)!;
    final p = ExtractionProfile.fromShot(id: 's', name: 'Saved', curve: curve);
    expect(p.flow.first.elapsedMs, original.points.first.elapsedMs);
    expect(
      p.flow.where((p) => p.breakBefore).length,
      original.points.where((p) => p.breakBefore).length,
    );
    expect(p.targetAt(p.flow, 3000), isNull);
    expect(p.predictedGrams, isNull);
    expect(curve.weight, [0, 1, 2, 3, 6, 7, 8]);
  });
  test('editor undo, redo, channels and explicit duration scaling', () {
    final original = ExtractionProfile.example('p', 'Example');
    final m = ProfileEditorModel(original);
    addTearDown(m.dispose);
    m.scaleDuration(60000);
    expect(m.profile.predictedGrams, original.predictedGrams! * 2);
    m.undo();
    expect(m.profile.encode(), original.encode());
    m.redo();
    expect(m.profile.durationMs, 60000);
    m.setChannels({'pressure'});
    expect(m.profile.flow, isEmpty);
    expect(m.active, 'pressure');
    m.setChannels({});
    expect(m.profile.pressure, isNotEmpty);
    m.setChannels({'flow', 'pressure'});
    m.select('flow', 1);
    m.add();
    expect(m.points.length, 6);
    m.remove(m.selected);
    expect(m.points.length, 5);
    final before = m.profile.encode();
    m.beginDrag();
    m.move(1, 14000, 1, dragging: true);
    m.move(1, 14000, 2, dragging: true);
    m.endDrag();
    m.undo();
    expect(m.profile.encode(), before);
  });
}

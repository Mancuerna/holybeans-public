import 'dart:convert';
import 'dart:math' as math;

import 'package:holybeans/domain/flow_guide.dart';
import 'package:holybeans/domain/pressure_guide.dart';
import 'package:holybeans/domain/shot_curve.dart';

class ExtractionProfile {
  ExtractionProfile({
    required this.id,
    required this.name,
    required this.durationMs,
    this.doseGrams = 18,
    this.temperatureC = 93,
    this.targetGrams,
    this.notes = '',
    this.primary = 'flow',
    List<GuidePoint> flow = const [],
    List<GuidePoint> pressure = const [],
  }) : flow = List.unmodifiable(flow),
       pressure = List.unmodifiable(pressure) {
    validate();
  }

  final String id;
  final String name;
  final String notes;
  final String primary;
  final int durationMs;
  final double doseGrams;
  final double temperatureC;
  final double? targetGrams;
  final List<GuidePoint> flow;
  final List<GuidePoint> pressure;

  void validate() {
    if (id.isEmpty ||
        id.length > 200 ||
        name.trim().isEmpty ||
        name.length > 80 ||
        notes.length > 1200 ||
        durationMs < 1000 ||
        durationMs > 600000 ||
        !doseGrams.isFinite ||
        doseGrams <= 0 ||
        doseGrams > 100 ||
        !temperatureC.isFinite ||
        temperatureC < 0 ||
        temperatureC > 110 ||
        targetGrams != null &&
            (!targetGrams!.isFinite ||
                targetGrams! <= 0 ||
                targetGrams! > 2000) ||
        flow.isEmpty && pressure.isEmpty ||
        !['flow', 'pressure'].contains(primary) ||
        (primary == 'flow' ? flow : pressure).isEmpty) {
      throw const FormatException('Invalid extraction profile');
    }
    for (final points in [flow, pressure]) {
      if (points.isEmpty) continue;
      if (points.length < 2 || points.length > 2000) {
        throw const FormatException('Invalid profile point count');
      }
      for (var i = 0; i < points.length; i++) {
        final p = points[i];
        if (p.elapsedMs < 0 ||
            p.elapsedMs > durationMs ||
            !p.value.isFinite ||
            p.value < 0 ||
            p.value > 30 ||
            i > 0 && p.elapsedMs <= points[i - 1].elapsedMs) {
          throw const FormatException('Invalid profile point');
        }
      }
    }
  }

  double? targetAt(List<GuidePoint> points, int ms) {
    if (points.isEmpty ||
        ms < points.first.elapsedMs ||
        ms > points.last.elapsedMs) {
      return null;
    }
    for (var i = 0; i < points.length; i++) {
      final b = points[i];
      if (b.elapsedMs == ms) return b.value;
      if (b.elapsedMs > ms) {
        if (b.breakBefore) return null;
        final a = points[i - 1];
        return a.value +
            (b.value - a.value) *
                (ms - a.elapsedMs) /
                (b.elapsedMs - a.elapsedMs);
      }
    }
    return null;
  }

  double? weightAt(int ms) {
    if (flow.isEmpty ||
        flow.first.elapsedMs != 0 ||
        ms < 0 ||
        ms > flow.last.elapsedMs) {
      return null;
    }
    var total = 0.0;
    for (var i = 1; i < flow.length; i++) {
      final a = flow[i - 1];
      final b = flow[i];
      if (ms <= a.elapsedMs) break;
      if (b.breakBefore) return null;
      final end = math.min(ms, b.elapsedMs);
      total +=
          (end - a.elapsedMs) / 1000 * (a.value + targetAt(flow, end)!) / 2;
      if (end == ms) break;
    }
    return total;
  }

  double? get predictedGrams => weightAt(durationMs);

  ExtractionProfile copyWith({
    String? id,
    String? name,
    int? durationMs,
    double? doseGrams,
    double? temperatureC,
    double? targetGrams,
    String? notes,
    String? primary,
    List<GuidePoint>? flow,
    List<GuidePoint>? pressure,
  }) => ExtractionProfile(
    id: id ?? this.id,
    name: name ?? this.name,
    durationMs: durationMs ?? this.durationMs,
    doseGrams: doseGrams ?? this.doseGrams,
    temperatureC: temperatureC ?? this.temperatureC,
    targetGrams: targetGrams ?? this.targetGrams,
    notes: notes ?? this.notes,
    primary: primary ?? this.primary,
    flow: flow ?? this.flow,
    pressure: pressure ?? this.pressure,
  );

  Map<String, dynamic> toJson() => {
    'format': 'holybeans-extraction-profile',
    'version': 1,
    'id': id,
    'name': name,
    'durationMs': durationMs,
    'doseGrams': doseGrams,
    'temperatureC': temperatureC,
    'targetGrams': targetGrams,
    'notes': notes,
    'primary': primary,
    for (final entry in {'flow': flow, 'pressure': pressure}.entries)
      entry.key: [
        for (final p in entry.value)
          {'ms': p.elapsedMs, 'value': p.value, 'breakBefore': p.breakBefore},
      ],
  };
  String encode() => jsonEncode(toJson());

  static ExtractionProfile decode(String source) {
    if (utf8.encode(source).length > 512 * 1024) {
      throw const FormatException('Profile too large');
    }
    try {
      final j = jsonDecode(source) as Map<String, dynamic>;
      if (j['format'] == 'holybeans-profile-designer-demo') return _demo(j);
      if (j['format'] != 'holybeans-extraction-profile' || j['version'] != 1) {
        throw const FormatException('Unsupported profile format');
      }
      List<GuidePoint> points(String key) => [
        for (final p in j[key] as List)
          (
            elapsedMs: p['ms'] as int,
            value: (p['value'] as num).toDouble(),
            breakBefore: p['breakBefore'] as bool? ?? false,
          ),
      ];
      return ExtractionProfile(
        id: j['id'] as String,
        name: j['name'] as String,
        durationMs: j['durationMs'] as int,
        doseGrams: (j['doseGrams'] as num).toDouble(),
        temperatureC: (j['temperatureC'] as num).toDouble(),
        targetGrams: (j['targetGrams'] as num?)?.toDouble(),
        notes: j['notes'] as String? ?? '',
        primary: j['primary'] as String,
        flow: points('flow'),
        pressure: points('pressure'),
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Invalid profile file');
    }
  }

  static ExtractionProfile _demo(Map<String, dynamic> j) {
    if (![2, 3].contains(j['version'])) {
      throw const FormatException('Unsupported demo version');
    }
    List<GuidePoint> points(String key, String value) => [
      for (final p in j[key] as List)
        (
          elapsedMs: ((p['tSeconds'] as num) * 1000).round(),
          value: (p[value] as num).toDouble(),
          breakBefore: false,
        ),
    ];
    return ExtractionProfile(
      id: 'imported-demo',
      name: j['name'] as String,
      durationMs: ((j['durationSeconds'] as num) * 1000).round(),
      doseGrams: (j['doseGrams'] as num).toDouble(),
      temperatureC: (j['temperatureCelsius'] as num? ?? 93).toDouble(),
      notes: j['notes'] as String? ?? '',
      flow: points('flowPoints', 'flowGs'),
      pressure: points('pressurePoints', 'pressureBar'),
    );
  }

  static ExtractionProfile fromShot({
    required String id,
    required String name,
    required ShotCurve curve,
    double? doseGrams,
    double? temperatureC,
    double? targetGrams,
  }) {
    final flow = FlowGuide.fromCurve(curve)?.points ?? <GuidePoint>[];
    final pressure = PressureGuide.fromCurve(curve);
    final bars = <GuidePoint>[
      if (pressure != null)
        for (var i = 0; i < pressure.timesMs.length; i++)
          (
            elapsedMs: pressure.timesMs[i],
            value: pressure.bars[i],
            breakBefore: false,
          ),
    ];
    return ExtractionProfile(
      id: id,
      name: name,
      durationMs: curve.timesMs.last,
      doseGrams: doseGrams ?? 18,
      temperatureC: temperatureC ?? 93,
      targetGrams: targetGrams,
      primary: flow.isNotEmpty ? 'flow' : 'pressure',
      flow: simplify(flow, .04),
      pressure: simplify(bars, .04),
    );
  }

  static List<GuidePoint> simplify(List<GuidePoint> points, double tolerance) {
    if (points.length <= 2) return points;
    final keep = <int>{0, points.length - 1};
    for (var i = 1; i < points.length; i++) {
      if (points[i].breakBefore) keep.addAll([i - 1, i]);
    }
    final boundaries = keep.toList()..sort();
    final pending = <(int, int)>[
      for (var i = 1; i < boundaries.length; i++)
        (boundaries[i - 1], boundaries[i]),
    ];
    while (pending.isNotEmpty) {
      final (start, end) = pending.removeLast();
      if (end - start < 2) continue;
      final a = points[start];
      final b = points[end];
      var largest = tolerance;
      var chosen = -1;
      for (var i = start + 1; i < end; i++) {
        final expected =
            a.value +
            (b.value - a.value) *
                (points[i].elapsedMs - a.elapsedMs) /
                (b.elapsedMs - a.elapsedMs);
        final error = (points[i].value - expected).abs();
        if (error > largest) {
          largest = error;
          chosen = i;
        }
      }
      if (chosen >= 0) {
        keep.add(chosen);
        pending.addAll([(start, chosen), (chosen, end)]);
      }
    }
    return [for (final i in keep.toList()..sort()) points[i]];
  }

  static ExtractionProfile example(String id, String name) => ExtractionProfile(
    id: id,
    name: name,
    durationMs: 30000,
    flow: [
      for (final (t, v) in [
        (0, 0.0),
        (7000, 0.0),
        (11000, 2.0),
        (26000, 2.0),
        (30000, 0.0),
      ])
        (elapsedMs: t, value: v, breakBefore: false),
    ],
    pressure: [
      for (final (t, v) in [
        (0, 0.0),
        (7000, 2.0),
        (11000, 9.0),
        (24000, 7.0),
        (30000, 0.0),
      ])
        (elapsedMs: t, value: v, breakBefore: false),
    ],
  );
}

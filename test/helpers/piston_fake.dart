import 'package:holybeans/data/services/piston_history_client.dart';
import 'package:holybeans/domain/meticulous/piston_analysis.dart';

class FakePistonSource implements PistonHistorySource {
  FakePistonSource(
    this.rows, {
    this.machine = 'machine',
    this.failAfter,
    this.offline = false,
  });
  final List<PistonReading> rows;
  final String machine;
  final int? failAfter;
  final bool offline;
  final starts = <int?>[];
  final fetched = <String>[];
  bool closed = false;
  @override
  Future<String> serial() async {
    if (offline) throw StateError('Offline');
    return machine;
  }

  @override
  Future<List<PistonShotIndex>> index({int? sinceMs, int limit = 128}) async {
    starts.add(sinceMs);
    final sorted =
        rows.where((r) => sinceMs == null || r.timeMs >= sinceMs).toList()
          ..sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return sorted
        .take(limit)
        .map((r) => (id: r.shotId, timeMs: r.timeMs))
        .toList();
  }

  @override
  Future<List<PistonReading>> readings(List<String> ids) async {
    if (failAfter != null && fetched.length >= failAfter!) {
      throw StateError('Interrupted');
    }
    fetched.addAll(ids);
    return rows.where((r) => ids.contains(r.shotId)).toList();
  }

  @override
  void close() {
    closed = true;
  }
}

List<PistonReading> pistonFixture({int count = 280}) => [
  for (var i = 0; i < count; i++)
    PistonReading(
      shotId: 'shot-$i',
      timeMs:
          DateTime(2026).millisecondsSinceEpoch +
          i * Duration.millisecondsPerDay,
      samples: 6,
      current: 1 + (i % 50) * .012,
      speed: 10 - (i % 50) * .005,
    ),
];

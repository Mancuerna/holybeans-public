import 'package:holybeans/data/repositories/piston_repository.dart';
import 'package:holybeans/domain/meticulous/piston_analysis.dart';

typedef PistonRange = ({
  List<PistonPoint> points,
  PistonTrend trend,
  int total,
});

/// Analysis shared by progress updates and range changes for one snapshot.
class PistonViewData {
  PistonViewData(this.snapshot);

  final PistonSnapshot snapshot;
  late final currentSeries = pistonSeries(snapshot.readings, snapshot.services);
  late final speedSeries = pistonSeries(
    snapshot.readings,
    snapshot.services,
    speed: true,
  );
  (int, bool)? _selection;
  late PistonRange _range;

  PistonRange range(int since, bool speed) {
    final selection = (since, speed);
    if (_selection == selection) return _range;
    final series = speed ? speedSeries : currentSeries;
    final points = series.where((p) => p.timeMs >= since).toList();
    _range = (
      points: points,
      trend: pistonTrend(points, snapshot.services),
      total: snapshot.readings.where((r) => r.timeMs >= since).length,
    );
    _selection = selection;
    return _range;
  }
}

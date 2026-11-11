import 'package:holybeans/data/repositories/piston_repository.dart';
import 'package:holybeans/domain/meticulous/piston_analysis.dart';

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
  late final trend = pistonTrend(snapshot.readings, snapshot.services);
  late final usable = snapshot.readings
      .where((reading) => reading.usable)
      .toList();

  List<PistonPoint> series(bool speed) => speed ? speedSeries : currentSeries;
}

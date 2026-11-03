import 'package:holybeans/data/services/paired_device.dart';
import 'package:holybeans/domain/scale_recording.dart';

export 'package:holybeans/data/services/paired_device.dart';

/// A Bluetooth scale as the app sees it: the weight it reads and the few
/// commands it accepts (several readings a second while connected).
abstract interface class Scale implements PairedDevice {
  List<FoundDevice> get rememberedScales;
  String? get activeScaleId;
  Future<void> forgetScale(String id);

  /// Last reading while connected.
  ScaleReading? get reading;

  /// Readings as they arrive.
  Stream<ScaleReading> get readings;

  // Newly saved coffee doses in grams, where supported; no cached replay.
  Stream<double> get doses;

  /// Asks the scale to [command]; false when it is not connected or the
  /// write failed.
  Future<bool> send(ScaleCommand command);
}

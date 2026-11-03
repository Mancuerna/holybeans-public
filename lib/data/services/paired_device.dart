import 'package:flutter/foundation.dart';

/// Where the connection with a Bluetooth device stands.
enum DeviceStatus {
  idle,
  searching,
  connecting,
  connected,

  /// The last connection attempt failed (device off, out of range or held
  /// by another phone).
  failed,
  bluetoothOff,

  /// Android did not grant the Bluetooth permission.
  denied,
}

/// A device seen while searching.
class FoundDevice {
  const FoundDevice({required this.id, required this.name});

  final String id;
  final String name;
}

/// A Bluetooth device the user finds, pairs and the app reconnects to.
/// Listeners hear every change, readings included.
abstract interface class PairedDevice implements Listenable {
  DeviceStatus get status;

  /// Name of the remembered device, or null when none is paired.
  String? get name;

  /// Devices found by the current or last search.
  List<FoundDevice> get found;

  /// Whether a search has run, to tell "none found" from "not searched".
  bool get hasSearched;

  bool get connected;

  /// Looks for devices nearby for a few seconds.
  Future<void> search();
  Future<void> stopSearch();

  /// Connects to [device] and remembers it.
  Future<void> pair(FoundDevice device);

  /// Connects to the remembered device, unless already connected. An
  /// [automatic] attempt, the app reconnecting by itself, is skipped after
  /// the user disconnected the device, until they connect it again.
  Future<void> connect({bool automatic = false});
  Future<void> disconnect();

  /// Disconnects and forgets the remembered device.
  Future<void> forget();
}

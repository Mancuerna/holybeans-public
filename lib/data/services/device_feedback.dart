import 'package:flutter/services.dart';

/// Beeps, screen wake while brewing and the Bluetooth settings. The Android side lives
/// in MainActivity; elsewhere (tests, other platforms) calls do nothing.
class DeviceFeedback {
  const DeviceFeedback();

  static const _channel = MethodChannel('holybeans/device');

  /// A short beep for a countdown, or a long one when a step starts.
  Future<void> beep({bool long = false}) => _call('beep', {'long': long});

  /// The "faaah" played when Brazil is picked as an origin (easter egg);
  /// silent when the phone is on silent or vibrate (also with Do Not
  /// Disturb, which Samsung reports as not ringing).
  Future<void> faaah() => _call('faaah', const {});

  /// How many screens asked to keep the display on; the brew form and the
  /// pour assistant can overlap.
  static int _screenOnHolders = 0;

  /// Keeps the screen from turning off while [on]. Calls are counted: the
  /// screen may turn off again only when every holder has let go.
  Future<void> keepScreenOn(bool on) async {
    final before = _screenOnHolders;
    _screenOnHolders = on
        ? _screenOnHolders + 1
        : (_screenOnHolders - 1).clamp(0, 1 << 30);
    if ((before == 0) != (_screenOnHolders == 0)) {
      await _call('keepScreenOn', {'on': _screenOnHolders > 0});
    }
  }

  /// The home screen widget's coffee and recipe; null clears it.
  Future<void> updateWidget({String? title, String? recipe}) =>
      _call('updateWidget', {'title': ?title, 'recipe': ?recipe});

  /// Labels of the launcher shortcuts, the widget and the ongoing notice's
  /// channel, in the app's language rather than the phone's.
  Future<void> setSurfaceLabels(Map<String, String> labels) =>
      _call('setSurfaceLabels', labels);

  /// Opens the phone's Bluetooth settings, for a device that needs it on.
  Future<void> openBluetoothSettings() =>
      _call('openBluetoothSettings', const {});

  /// The installed version as "0.5.12 (133)", or null off Android.
  Future<String?> appVersion() async {
    try {
      return await _channel.invokeMethod<String>('appVersion');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<void> _call(String method, Map<String, Object> arguments) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // No device behind the channel.
    } on PlatformException {
      // A beep that fails must not stop the brew.
    }
  }
}

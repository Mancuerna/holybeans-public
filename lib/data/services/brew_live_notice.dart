import 'package:flutter/services.dart';

/// The brew in progress as an ongoing Android notification.
///
/// Its clock and pours can be read from the lock screen. On Android 16 and
/// later it can be a progress-style Live Update; on Android 8 through 15 it
/// uses a chronometer and a progress bar. The Android side is LiveUpdateBridge.
/// On Android 7, on other platforms or without permission to notify, calls
/// do nothing.
class BrewLiveNotice {
  const BrewLiveNotice();

  static const _channel = MethodChannel('holybeans/live-update');

  /// A running timer started at [startedAt], counting up.
  Future<void> showTimer({
    required String title,
    required String text,
    required DateTime startedAt,
  }) => _call('show', {
    'title': title,
    'text': text,
    'startedAtMs': startedAt.millisecondsSinceEpoch,
  });

  /// A planned brew: [segments] are the grams of each step (bloom and
  /// pours), [poured] the grams so far.
  Future<void> showPours({
    required String title,
    required String text,
    required DateTime startedAt,
    required List<int> segments,
    required int poured,
  }) => _call('show', {
    'title': title,
    'text': text,
    'startedAtMs': startedAt.millisecondsSinceEpoch,
    'segments': segments,
    'progress': poured,
  });

  Future<void> clear() => _call('clear', const {});

  Future<void> _call(String method, Map<String, Object> arguments) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // No Android behind the channel (tests, other platforms).
    } on PlatformException {
      // A notice that fails must not stop the brew.
    }
  }
}

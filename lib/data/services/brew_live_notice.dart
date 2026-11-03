import 'package:flutter/services.dart';

/// The brew in progress as an ongoing notification, so its clock (and, in
/// the pour assistant, its pours) can be read from the lock screen with the
/// hands busy. On Android 16 it is a progress-style Live Update; before, an
/// ongoing notification with a chronometer and a progress bar. The Android
/// side is LiveUpdateBridge; elsewhere, or without permission to notify,
/// calls do nothing.
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

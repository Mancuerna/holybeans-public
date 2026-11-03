import 'dart:async';

import 'package:flutter/widgets.dart';

/// Seconds in [minutes] and [seconds], or null when both are empty or zero.
int? durationSecondsOf(
  TextEditingController minutes,
  TextEditingController seconds,
) {
  final minutesText = minutes.text.trim();
  final secondsText = seconds.text.trim();
  if (minutesText.isEmpty && secondsText.isEmpty) return null;
  final value =
      (int.tryParse(minutesText) ?? 0) * 60 + (int.tryParse(secondsText) ?? 0);
  return value == 0 ? null : value;
}

bool isValidBrewDurationPart(String? value, {int? maximum}) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return true;
  final parsed = RegExp(r'^\d+$').hasMatch(text) ? int.tryParse(text) : null;
  return parsed != null && (maximum == null || parsed <= maximum);
}

/// Owns the extraction clock for the lifetime of a brew form.
/// Scrolling may dispose its controls without stopping the clock.
class BrewTimer extends ChangeNotifier {
  BrewTimer({
    required this.minutes,
    required this.seconds,
    this.onStart,
    this.onStop,
    this.onReset,
  }) {
    minutes.addListener(_refresh);
    seconds.addListener(_refresh);
  }

  final TextEditingController minutes;
  final TextEditingController seconds;
  final ValueChanged<int>? onStart;
  final VoidCallback? onStop;
  final VoidCallback? onReset;
  Timer? _ticker;
  int _baseSeconds = 0;
  bool _writing = false;

  bool Function()? allowStart;
  bool Function()? restartOnStart;
  VoidCallback? onValidateStart;
  bool get canStart => allowStart?.call() ?? true;

  bool get running => _ticker != null;
  bool get hasValidDuration =>
      isValidBrewDurationPart(minutes.text) &&
      isValidBrewDurationPart(seconds.text, maximum: 59);
  int get elapsedSeconds => durationSecondsOf(minutes, seconds) ?? 0;

  void _refresh() {
    if (!_writing) notifyListeners();
  }

  void toggle() {
    if (running) {
      stop();
      return;
    }
    if (!canStart) return;
    onValidateStart?.call();
    if (!hasValidDuration) return;
    _baseSeconds = (restartOnStart?.call() ?? false) ? 0 : elapsedSeconds;
    _write(_baseSeconds);
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (timer) => _write(_baseSeconds + timer.tick),
    );
    onStart?.call(_baseSeconds);
    notifyListeners();
  }

  void stop() {
    if (!running) return;
    _ticker!.cancel();
    _ticker = null;
    onStop?.call();
    notifyListeners();
  }

  /// Sets a stopped timer to [total] seconds, for an end that was only
  /// clear after it happened.
  void settle(int total) {
    if (running) return;
    _write(total);
  }

  void reset() {
    _ticker?.cancel();
    _ticker = null;
    _writing = true;
    minutes.clear();
    seconds.clear();
    _writing = false;
    onReset?.call();
    notifyListeners();
  }

  void _write(int total) {
    _writing = true;
    minutes.text = '${total ~/ 60}';
    seconds.text = (total % 60).toString().padLeft(2, '0');
    _writing = false;
    notifyListeners();
  }

  @override
  void dispose() {
    if (running) {
      _ticker!.cancel();
      onStop?.call();
    }
    minutes.removeListener(_refresh);
    seconds.removeListener(_refresh);
    super.dispose();
  }
}

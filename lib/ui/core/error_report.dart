import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Leaves a trace of an error the app recovered from, such as a save that
/// failed and was answered with a message.
///
/// Writes one line to the device log (`adb logcat`, also in release) with
/// the error and where it was thrown, and the whole error with its [stack]
/// to the debugging tools. Without this, a `catch` that shows "could not
/// save" would lose why.
void reportError(Object error, StackTrace stack) {
  final where = stack.toString().split('\n').firstOrNull?.trim() ?? '';
  debugPrint('HolyBeans recovered from: $error ($where)');
  developer.log(
    'Recovered from an error',
    name: 'holybeans',
    error: error,
    stackTrace: stack,
  );
}

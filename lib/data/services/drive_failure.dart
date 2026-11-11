import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Distinguishes recoverable Drive failure sources while retaining the cause.
enum DriveFailureKind { timeout, storage, invalidData, platform, unexpected }

class DriveFailure {
  const DriveFailure(this.kind, this.cause, this.stack);
  factory DriveFailure.from(Object cause, StackTrace stack) => DriveFailure(
    switch (cause) {
      TimeoutException() => DriveFailureKind.timeout,
      FileSystemException() => DriveFailureKind.storage,
      FormatException() => DriveFailureKind.invalidData,
      PlatformException() => DriveFailureKind.platform,
      _ => DriveFailureKind.unexpected,
    },
    cause,
    stack,
  );
  final DriveFailureKind kind;
  final Object cause;
  final StackTrace stack;
}

import 'dart:async';

import 'package:flutter/services.dart';

/// Text that reaches HolyBeans from outside, through the
/// "holybeans/incoming" channel of MainActivity: a `.holybeans` file opened
/// from a chat, text shared to the app or a `holybeans://bean` link. Also
/// scans a QR code with Google's scanner screen.
///
/// Without Android behind the channel (tests, other platforms) nothing
/// arrives and scanning returns null.
class IncomingShares {
  IncomingShares({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('holybeans/incoming') {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'arrived' && call.arguments is String) {
        _arrivals.add(call.arguments as String);
      }
    });
  }

  final MethodChannel _channel;
  final _arrivals = StreamController<String>.broadcast();

  /// Texts that arrive while the app is open.
  Stream<String> get arrivals => _arrivals.stream;

  /// The text the app was opened with, once; null when none.
  Future<String?> takeLaunch() async {
    try {
      return await _channel.invokeMethod<String>('take');
    } on MissingPluginException {
      return null;
    }
  }

  /// The text of a scanned QR code; null when cancelled. Throws
  /// [QrScanFailed] when the scanner cannot start, such as without Play
  /// services.
  Future<String?> scanQr() async {
    try {
      return await _channel.invokeMethod<String>('scan');
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      if (error.code == 'scan_failed') throw QrScanFailed(error.message);
      rethrow;
    }
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    unawaited(_arrivals.close());
  }
}

/// Google's QR scanner could not start.
class QrScanFailed implements Exception {
  const QrScanFailed(this.reason);

  /// What the scanner said, for the error report.
  final String? reason;

  @override
  String toString() => 'QrScanFailed: $reason';
}

import 'dart:async';
import 'dart:isolate';

import 'package:holybeans/data/repositories/history_query.dart';

/// A search page reuses one isolate across note batches, then releases it.
/// This avoids one isolate startup per batch when a query has no matches.
class HistoryMatcher {
  Isolate? _worker;
  ReceivePort? _port;
  StreamIterator<dynamic>? _responses;
  SendPort? _requests;

  Future<List<int>> match(HistoryRequest request) async {
    if (const bool.fromEnvironment('dart.library.js_interop')) {
      await null;
      return selectHistory(request);
    }
    if (_requests == null) {
      final port = _port = ReceivePort();
      final responses = _responses = StreamIterator<dynamic>(port);
      _worker = await Isolate.spawn(
        _run,
        port.sendPort,
        onError: port.sendPort,
        debugName: 'history-page-search',
      );
      if (!await responses.moveNext() || responses.current is! SendPort) {
        throw StateError('Search worker did not start');
      }
      _requests = responses.current as SendPort;
    }
    _requests!.send(request);
    if (!await _responses!.moveNext()) {
      throw StateError('Search worker stopped');
    }
    final result = _responses!.current;
    if (result is! List<int>) throw StateError('Search worker failed: $result');
    return result;
  }

  static void _run(SendPort output) {
    final input = ReceivePort();
    output.send(input.sendPort);
    input.listen((dynamic request) {
      try {
        output.send(selectHistory(request as HistoryRequest));
      } catch (error, stack) {
        output.send('$error\n$stack');
      }
    });
  }

  Future<void> dispose() async {
    _worker?.kill(priority: Isolate.immediate);
    _port?.close();
    await _responses?.cancel();
  }
}

import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:holybeans/domain/curve_accumulator.dart';
import 'package:holybeans/domain/prepared_curve.dart';

/// One worker per visible chart; requests are coalesced by CurveViewModel.
class CurveWorker {
  Isolate? _isolate;
  ReceivePort? _messages;
  Future<SendPort>? _ready;
  Completer<PreparedCurve>? _active;
  bool _closed = false;

  Future<SendPort> _start() async {
    final ready = Completer<SendPort>();
    final messages = _messages = ReceivePort();
    messages.listen((dynamic message) {
      if (message is SendPort) {
        if (!ready.isCompleted) ready.complete(message);
      } else if (message is PreparedCurve) {
        _active?.complete(message);
        _active = null;
      } else {
        final error = StateError('Curve worker failed: $message');
        if (!ready.isCompleted) ready.completeError(error);
        _active?.completeError(error);
        _active = null;
      }
    });
    _isolate = await Isolate.spawn(
      _work,
      messages.sendPort,
      onError: messages.sendPort,
      debugName: 'extraction-curve',
    );
    if (_closed) {
      _isolate?.kill(priority: Isolate.immediate);
      messages.close();
      throw StateError('Curve worker closed');
    }
    return ready.future;
  }

  Future<PreparedCurve> prepare(CurveRequest request) async {
    if (_closed) throw StateError('Curve worker closed');
    if (kIsWeb) return compute(prepareCurve, request);
    final send = await (_ready ??= _start());
    if (_closed) throw StateError('Curve worker closed');
    final result = _active = Completer<PreparedCurve>();
    send.send(request);
    return result.future;
  }

  static void _work(SendPort replies) {
    final input = ReceivePort();
    final accumulator = CurveAccumulator();
    replies.send(input.sendPort);
    input.listen((dynamic request) {
      try {
        replies.send(accumulator.prepare(request as CurveRequest));
      } catch (error, stack) {
        replies.send('$error\n$stack');
      }
    });
  }

  void dispose() {
    _closed = true;
    _isolate?.kill(priority: Isolate.immediate);
    _messages?.close();
    _active?.completeError(StateError('Curve worker closed'));
    _active = null;
  }
}

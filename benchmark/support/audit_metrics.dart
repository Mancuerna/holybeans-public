import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

typedef AuditRecord = void Function(Map<String, Object?> record);

Map<String, Object> distribution(List<double> samples) {
  final sorted = [...samples]..sort();
  double percentile(double p) => sorted[max(0, (p * sorted.length).ceil() - 1)];
  return {
    'samples': samples,
    'count': samples.length,
    'medianMs': percentile(0.5),
    'p95Ms': percentile(0.95),
    'minMs': sorted.first,
    'maxMs': sorted.last,
  };
}

Future<Map<String, Object>> measure(
  FutureOr<void> Function() action, {
  int warmups = 2,
  int repetitions = 9,
  AuditMemory? memory,
}) async {
  for (var i = 0; i < warmups; i++) {
    await action();
  }
  // Synchronous CPU warmups otherwise leave GC notifications queued until the
  // measured loop ends. Drain that queue before taking the initial counter.
  await Future<void>.delayed(const Duration(milliseconds: 20));
  final samples = <double>[];
  final gcBefore = memory?.gcEvents;
  final cpuBefore = processCpuTicks();
  for (var i = 0; i < repetitions; i++) {
    final watch = Stopwatch()..start();
    await action();
    watch.stop();
    samples.add(watch.elapsedMicroseconds / 1000);
  }
  final cpuAfter = processCpuTicks();
  // Give asynchronous service events time to arrive outside timed samples.
  await Future<void>.delayed(const Duration(milliseconds: 10));
  return {
    ...distribution(samples),
    if (gcBefore != null) 'mainIsolateGcEvents': memory!.gcEvents - gcBefore,
    if (cpuBefore != null && cpuAfter != null)
      'processCpuTicks': cpuAfter - cpuBefore,
  };
}

int? processCpuTicks() {
  if (!Platform.isLinux && !Platform.isAndroid) return null;
  final stat = File('/proc/self/stat').readAsStringSync();
  final fields = stat.substring(stat.lastIndexOf(')') + 2).split(' ');
  // Linux proc(5): fields 14 and 15 are user and system CPU clock ticks.
  return int.parse(fields[11]) + int.parse(fields[12]);
}

// A minimal local VM-service client avoids adding a production dependency.
// GC is requested only at memory checkpoints, outside timed operations.
class AuditMemory {
  AuditMemory._(this.socket, this.isolateId) {
    subscription = socket.listen((event) {
      final message = jsonDecode(event as String) as Map<String, dynamic>;
      if (message['method'] == 'streamNotify') {
        final params = message['params'] as Map<String, dynamic>;
        final event = params['event'] as Map<String, dynamic>;
        if (params['streamId'] == 'GC' &&
            (event['isolate'] as Map<String, dynamic>?)?['id'] == isolateId) {
          gcEvents++;
        }
        return;
      }
      final completer = pending.remove(message['id']);
      if (completer == null) return;
      if (message['error'] != null) {
        completer.completeError(StateError('${message['error']}'));
      } else {
        completer.complete(message['result'] as Map<String, dynamic>);
      }
    });
  }

  final WebSocket socket;
  final String isolateId;
  late final StreamSubscription<dynamic> subscription;
  final pending = <String, Completer<Map<String, dynamic>>>{};
  int nextId = 0;
  int gcEvents = 0;

  static Future<AuditMemory?> connect() async {
    final info = await developer.Service.getInfo();
    final uri = info.serverWebSocketUri;
    final isolateId = developer.Service.getIsolateId(Isolate.current);
    if (uri == null || isolateId == null) return null;
    final memory = AuditMemory._(
      await WebSocket.connect(uri.toString()),
      isolateId,
    );
    await memory.call('streamListen', {'streamId': 'GC'});
    return memory;
  }

  Future<Map<String, dynamic>> call(
    String method,
    Map<String, Object> params,
  ) async {
    final id = '${nextId++}';
    final completer = Completer<Map<String, dynamic>>();
    pending[id] = completer;
    socket.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      }),
    );
    try {
      return await completer.future.timeout(const Duration(seconds: 20));
    } finally {
      pending.remove(id);
    }
  }

  Future<Map<String, Object?>> snapshot() async {
    final allocation = await call('getAllocationProfile', {
      'isolateId': isolateId,
      'gc': true,
    });
    return {
      'rssBytes': ProcessInfo.currentRss,
      'mainIsolateAfterGc': allocation['memoryUsage'],
    };
  }

  Future<void> close() async {
    await subscription.cancel();
    await socket.close();
  }
}

Future<Map<String, Object?>> memorySnapshot(AuditMemory? memory) async =>
    memory == null
    ? {'rssBytes': ProcessInfo.currentRss, 'mainIsolateAfterGc': null}
    : memory.snapshot();

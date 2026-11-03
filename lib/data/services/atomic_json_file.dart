import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

/// Serializes changes to a local JSON file across store instances in one isolate.
///
/// Failed writes keep the previous file and do not block later operations.
class AtomicJsonFile {
  AtomicJsonFile(this.file);

  final File file;
  static final _pending = <String, Future<void>>{};

  Future<T> _exclusive<T>(Future<T> Function() action) async {
    final key = path.normalize(file.absolute.path);
    final previous = _pending[key];
    final completed = Completer<void>();
    _pending[key] = completed.future;
    try {
      await previous;
      return await action();
    } finally {
      completed.complete();
      if (identical(_pending[key], completed.future)) {
        unawaited(_pending.remove(key));
      }
    }
  }

  // Atomic rename lets readers use the last complete file without waiting
  // for a pending write. Callers await write() when they need the new value.
  Future<Object?> read() async {
    if (!file.existsSync()) return null;
    return jsonDecode(await file.readAsString());
  }

  Future<void> write(Object? value) {
    // Capture the caller's value before it can change while waiting.
    final source = jsonEncode(value);
    return _exclusive(() async {
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(source, flush: true);
      await temporary.rename(file.path);
    });
  }

  Future<void> delete() => _exclusive(() async {
    if (file.existsSync()) await file.delete();
  });
}

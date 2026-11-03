import 'dart:async';

import 'package:holybeans/data/services/photo_store.dart';
import 'package:path/path.dart' as path;

abstract final class JournalLock {
  static final _pendingWork = <String, Future<void>>{};

  /// Serializes journal reads and photo replacement for the same folder.
  static Future<T> withJournalLock<T>(
    PhotoStore? photos,
    Future<T> Function() action,
  ) async {
    if (photos == null) return action();
    final key = path.normalize(photos.directory.absolute.path);
    final previous = _pendingWork[key];
    final completed = Completer<void>();
    _pendingWork[key] = completed.future;
    try {
      await previous;
      return await action();
    } finally {
      completed.complete();
      if (identical(_pendingWork[key], completed.future)) {
        unawaited(_pendingWork.remove(key));
      }
    }
  }
}

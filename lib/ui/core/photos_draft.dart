import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/ui/core/error_report.dart';

/// Owns photos until the form is saved or discarded, including late picks.
class PhotosDraft extends ChangeNotifier {
  PhotosDraft(this.store, [List<String> saved = const []])
    : original = List.unmodifiable(saved),
      _current = List.unmodifiable(saved);

  final PhotoStore? store;

  /// Optional reference-aware cleanup for photos shared by journal records.
  Future<void> Function(String name)? deletePhoto;
  final List<String> original;
  List<String> _current;
  List<String> get current => _current;
  final Set<String> _added = {};
  bool _committed = false;
  bool _disposed = false;
  bool _saving = false;
  bool _picking = false;
  bool get picking => _picking;

  bool get locked => _saving || _committed || _disposed;

  void beginSave() {
    if (picking || locked) throw StateError('Photo draft is busy');
    _saving = true;
    notifyListeners();
  }

  void endSave() {
    _saving = false;
    if (_disposed) {
      _discardAdded();
    } else {
      notifyListeners();
    }
  }

  bool get changed =>
      current.length != original.length ||
      current.indexed.any((entry) => original[entry.$1] != entry.$2);

  void set(List<String> names) {
    if (locked) return;
    _added.addAll(names.where((name) => !original.contains(name)));
    _current = List.unmodifiable(names);
    notifyListeners();
  }

  /// Serializes selections and appends to the current list after awaiting.
  Future<bool> pick(Future<String?> Function() select, {int limit = 8}) async {
    if (locked || picking || current.length >= limit) {
      return false;
    }
    _picking = true;
    notifyListeners();
    try {
      final name = await select();
      if (name == null) return false;
      if (_disposed || _committed || current.length >= limit) {
        await _delete(name);
        return false;
      }
      set([...current, name]);
      return true;
    } finally {
      _picking = false;
      if (!_disposed) notifyListeners();
    }
  }

  // Persistence has succeeded. Cleanup must not turn it into a failed save.
  Future<void> commit() async {
    if (picking) throw StateError('Photo selection is still pending');
    _committed = true;
    for (final name in {...original, ..._added}) {
      if (!current.contains(name)) await _delete(name);
    }
  }

  Future<void> _delete(String name) async {
    try {
      final remove = deletePhoto;
      if (remove != null) {
        await remove(name);
      } else {
        await store?.delete(name);
      }
    } catch (error, stack) {
      reportError(error, stack);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (!_saving) _discardAdded();
    super.dispose();
  }

  void _discardAdded() {
    if (!_committed) {
      for (final name in _added) {
        unawaited(_delete(name));
      }
    }
  }
}

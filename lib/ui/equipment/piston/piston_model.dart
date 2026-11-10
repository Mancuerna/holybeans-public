import 'package:flutter/foundation.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/repositories/piston_repository.dart';
import 'package:holybeans/data/services/piston_history_client.dart';
import 'package:holybeans/domain/meticulous/piston_analysis.dart';

class PistonModel extends ChangeNotifier {
  PistonModel(this.repository, this.methodId, this.address);
  final PistonRepository repository;
  final String methodId;
  final String address;
  PistonSnapshot data = const PistonSnapshot();
  bool loading = true;
  bool busy = false;
  bool failed = false;
  bool loadFailed = false;
  int processed = 0;
  bool _disposed = false;
  bool _cancelled = false;
  PistonHistorySource? _source;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> open() async {
    try {
      data = await repository.load(methodId);
      loadFailed = false;
    } on Object catch (error, stack) {
      reportError(error, stack);
      loadFailed = true;
    }
    loading = false;
    _notify();
    if (!_disposed && !loadFailed && data.serial != null) await refresh();
  }

  Future<void> refresh() async {
    if (busy || _disposed) return;
    busy = true;
    failed = false;
    processed = 0;
    _cancelled = false;
    _notify();
    try {
      _source = connectPistonHistory(address);
      await repository.sync(
        methodId,
        _source!,
        cancelled: () => _cancelled || _disposed,
        onProgress: (count) {
          processed = count;
          _notify();
        },
      );
    } on Object catch (error, stack) {
      if (!_cancelled && !_disposed) {
        reportError(error, stack);
        failed = true;
      }
    } finally {
      _source?.close();
      _source = null;
      if (!_disposed) {
        try {
          data = await repository.load(methodId);
          loadFailed = false;
        } on Object catch (error, stack) {
          reportError(error, stack);
          loadFailed = true;
        }
        busy = false;
        _notify();
      }
    }
  }

  void cancel() {
    _cancelled = true;
    _source?.close();
  }

  Future<bool> save(PistonService service) async {
    try {
      await repository.saveService(data.serial!, service);
      data = await repository.load(methodId);
      _notify();
      return true;
    } on Object catch (error, stack) {
      reportError(error, stack);
      return false;
    }
  }

  Future<bool> delete(PistonService service) async {
    try {
      await repository.deleteService(data.serial!, service.id);
      data = await repository.load(methodId);
      _notify();
      return true;
    } on Object catch (error, stack) {
      reportError(error, stack);
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    super.dispose();
  }
}

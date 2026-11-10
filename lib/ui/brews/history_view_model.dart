import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/history_query.dart';
import 'package:holybeans/data/repositories/journal_data.dart';

/// Search work is independent of rendering. Only one worker runs at a time;
/// typing and journal changes replace its pending request, never its result.
class HistoryViewModel extends ChangeNotifier {
  HistoryViewModel({Future<List<int>> Function(HistoryRequest)? search})
    : _search = search ?? _inBackground;

  final Future<List<int>> Function(HistoryRequest) _search;
  HistoryRequest? _request;
  HistoryRequest? _pending;
  bool _running = false;
  bool _disposed = false;
  bool busy = false;
  Object? error;
  List<Brew> visible = const [];
  List<Coffee> coffeeOptions = const [];
  List<String> methods = const [];
  bool _large = false;

  int get length => visible.length;
  Brew? brewAt(int index) =>
      index < 0 || index >= visible.length ? null : visible[index];

  static Future<List<int>> _inBackground(HistoryRequest request) =>
      compute(selectHistory, request, debugLabel: 'history-search');

  void update(JournalData data, HistoryQuery query) {
    if (_disposed) return;
    final previous = _request;
    final sameBrews = identical(previous?.brews, data.brews);
    final sameCoffees = identical(previous?.coffees, data.coffees);
    if (sameBrews && sameCoffees && previous?.query == query) return;
    if (!sameCoffees) {
      coffeeOptions = data.coffees.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    if (!sameBrews) {
      methods = {...data.brews.map((brew) => brew.methodName)}.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      _large =
          data.brews.length > 200 ||
          data.brews.fold<int>(
                0,
                (sum, brew) => sum + (brew.notes?.length ?? 0),
              ) >
              65536;
    }
    final request = (brews: data.brews, coffees: data.coffees, query: query);
    _request = request;
    error = null;
    if (query.text.isEmpty || !_large) {
      _pending = null;
      busy = false;
      visible = [for (final i in selectHistory(request)) data.brews[i]];
      notifyListeners();
    } else {
      busy = true;
      visible = const [];
      _pending = request;
      notifyListeners();
      if (!_running) unawaited(_drain());
    }
  }

  Future<void> _drain() async {
    _running = true;
    try {
      while (!_disposed && _pending != null) {
        final request = _pending!;
        _pending = null;
        try {
          final indices = await _search(request);
          if (_disposed || _request != request) continue;
          visible = [for (final i in indices) request.brews[i]];
          busy = false;
          notifyListeners();
        } catch (failure, stack) {
          reportError(failure, stack);
          if (_disposed || _request != request) continue;
          error = failure;
          busy = false;
          notifyListeners();
        }
      }
    } finally {
      _running = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _pending = null;
    _request = null;
    super.dispose();
  }
}

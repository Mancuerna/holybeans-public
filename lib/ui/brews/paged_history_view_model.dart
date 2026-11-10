import 'dart:async';

import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/history_pages.dart';
import 'package:holybeans/data/repositories/history_query.dart';
import 'package:holybeans/data/repositories/journal_data.dart';
import 'package:holybeans/data/repositories/journal_read_queries.dart';
import 'package:holybeans/ui/brews/history_view_model.dart';

/// Keeps at most six pages of previews. Cursors are small and allow evicted
/// pages to be fetched again without retaining every visited brew.
class PagedHistoryViewModel extends HistoryViewModel {
  PagedHistoryViewModel(JournalReadQueries reads)
    : pages = HistoryPages(reads) {
    _subscription = reads.watchRevision().listen(
      (_) => _reset(),
      onError: (Object failure, StackTrace stack) {
        reportError(failure, stack);
        error = failure;
        busy = false;
        notifyListeners();
      },
    );
  }
  final HistoryPages pages;
  late final StreamSubscription<int> _subscription;
  final _cache = <int, List<Brew>>{};
  final _cursors = <HistoryCursor?>[null];
  final _queue = <int>{};
  List<Coffee> _coffees = const [];
  HistoryQuery? _query;
  int _length = 0;
  int? _revision;
  int _generation = 0;
  bool _more = false;
  bool _draining = false;
  bool _closed = false;
  (int, int)? _fetching;

  void retry() => _reset();

  @override
  int get length => _length + (_more ? 1 : 0);
  int get cachedRows => _cache.values.fold(0, (sum, rows) => sum + rows.length);

  @override
  Brew? brewAt(int index) {
    if (index < 0) return null;
    final page = index ~/ HistoryPages.pageSize;
    final rows = _cache.remove(page);
    if (rows != null) _cache[page] = rows;
    if (rows == null) _enqueue(page);
    if (index >= _length - 10 && _more) _enqueue(_cursors.length - 1);
    final offset = index % HistoryPages.pageSize;
    return rows != null && offset < rows.length ? rows[offset] : null;
  }

  @override
  void update(JournalData data, HistoryQuery query) {
    if (_closed) return;
    final changed = _query != query || !identical(_coffees, data.coffees);
    _query = query;
    if (!identical(_coffees, data.coffees)) {
      _coffees = data.coffees;
      coffeeOptions = _coffees.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    if (changed) _reset();
  }

  void _reset() {
    if (_closed || _query == null) return;
    _generation++;
    _cache.clear();
    _queue.clear();
    _cursors
      ..clear()
      ..add(null);
    _length = 0;
    _revision = null;
    _more = false;
    busy = true;
    error = null;
    notifyListeners();
    final generation = _generation;
    unawaited(
      pages
          .methods()
          .then((value) {
            if (_closed || generation != _generation) return;
            methods = value;
            notifyListeners();
          })
          .catchError(reportError),
    );
    _enqueue(0);
  }

  void _enqueue(int page) {
    if (_closed ||
        error != null ||
        page < 0 ||
        page >= _cursors.length ||
        _cache.containsKey(page) ||
        _fetching == (_generation, page)) {
      return;
    }
    _queue.add(page);
    if (!_draining) {
      _draining = true;
      scheduleMicrotask(_drain);
    }
  }

  Future<void> _drain() async {
    try {
      while (!_closed && _queue.isNotEmpty) {
        final page = _queue.first;
        _queue.remove(page);
        final generation = _generation;
        _fetching = (generation, page);
        try {
          final result = await pages.page(
            _query!,
            _coffees,
            after: _cursors[page],
            expectedRevision: _revision,
            cancelled: () => _closed || generation != _generation,
          );
          if (_closed || generation != _generation) continue;
          _revision = result.revision;
          _cache[page] = result.rows;
          while (_cache.length > 6) {
            _cache.remove(_cache.keys.first);
          }
          final end = page * HistoryPages.pageSize + result.rows.length;
          if (end >= _length) {
            _length = end;
            _more = result.more;
            if (result.more && _cursors.length == page + 1) {
              _cursors.add(result.next);
            }
          }
          busy = false;
          error = null;
          notifyListeners();
        } on StaleHistoryPage {
          if (!_closed && generation == _generation) _reset();
        } catch (failure, stack) {
          if (_closed || generation != _generation) continue;
          reportError(failure, stack);
          busy = false;
          error = failure;
          notifyListeners();
        }
      }
    } finally {
      _fetching = null;
      _draining = false;
    }
  }

  @override
  void dispose() {
    _closed = true;
    _queue.clear();
    _cache.clear();
    unawaited(_subscription.cancel());
    super.dispose();
  }
}

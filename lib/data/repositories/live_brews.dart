import 'dart:async';

import 'package:drift/drift.dart';
import 'package:holybeans/data/database/app_database.dart';

/// Screens share one snapshot. Closing the last subscriber releases its rows,
/// including notes, and cancels the database subscription.
class LiveBrewStore {
  LiveBrewStore(this.database);
  final AppDatabase database;
  _BrewSession? _session;

  Stream<List<Brew>> watch({required bool includeArchived}) =>
      Stream.multi((sink) {
        final session = _session ??= _BrewSession(database);
        session.add(sink, includeArchived);
        sink.onCancel = () async {
          session.listeners.remove(sink);
          if (session.listeners.isNotEmpty) return;
          if (identical(_session, session)) _session = null;
          await session.close();
        };
      }, isBroadcast: true);
}

class _BrewListener {
  _BrewListener(this.archived);
  final bool archived;
  int? revision;
}

class _BrewSession {
  _BrewSession(this.database);
  final AppDatabase database;
  final listeners = <MultiStreamController<List<Brew>>, _BrewListener>{};
  final _rows = <String, Brew>{};
  // Cancelled by close(), when the last subscriber goes away.
  StreamSubscription<List<QueryRow>>? _subscription;
  int? _revision;
  List<Brew> _all = const [];
  List<Brew> _active = const [];
  bool _closed = false;
  bool _running = false;
  bool _dirty = false;

  Selectable<QueryRow> get _changes => database.customSelect(
    'SELECT coalesce(max(revision), 0) AS revision FROM temp.brew_changes',
    readsFrom: {database.brews},
  );

  void add(MultiStreamController<List<Brew>> sink, bool archived) {
    listeners[sink] = _BrewListener(archived);
    if (_subscription == null) {
      _subscription = _changes.watch().listen(
        (_) => unawaited(_refresh()),
        onError: _error,
        onDone: () {
          for (final sink in listeners.keys.toList()) {
            sink.close();
          }
        },
      );
    } else {
      // Validate the revision before replaying. A new listener immediately
      // after a write must not receive the old cached rows as its first event.
      unawaited(_refresh());
    }
  }

  void _error(Object error, StackTrace stack) {
    if (_closed) return;
    for (final sink in listeners.keys.toList()) {
      sink.addError(error, stack);
    }
  }

  Future<void> _refresh() async {
    _dirty = true;
    if (_running || _closed) return;
    _running = true;
    try {
      while (_dirty && !_closed) {
        _dirty = false;
        // The watermark and its rows belong to the same SQLite snapshot.
        final update = await database.transaction(() async {
          final current = (await _changes.getSingle()).read<int>('revision');
          if (_revision == current) return (current, <Brew>[], <String>[]);
          if (_revision == null) {
            return (
              current,
              await database.select(database.brews).get(),
              <String>[],
            );
          }
          final changed = await database
              .customSelect(
                'SELECT c.brew_id AS changed_id, b.* FROM temp.brew_changes c '
                'LEFT JOIN brews b ON b.id = c.brew_id WHERE c.revision > ?',
                variables: [Variable(_revision)],
              )
              .get();
          final updated = <Brew>[];
          final removed = <String>[];
          for (final row in changed) {
            if (row.data['id'] == null) {
              removed.add(row.read<String>('changed_id'));
            } else {
              updated.add(database.brews.map(row.data));
            }
          }
          return (current, updated, removed);
        });
        if (_closed) return;
        final (revision, updated, removed) = update;
        if (revision != _revision) {
          for (final id in removed) {
            _rows.remove(id);
          }
          for (final row in updated) {
            _rows[row.id] = row;
          }
          _revision = revision;
          _all = List.unmodifiable(_rows.values.toList()..sort(compareBrews));
          _active = List.unmodifiable(
            _all.where((row) => row.archivedAtMs == null),
          );
        }
        for (final entry in listeners.entries.toList()) {
          if (entry.value.revision == _revision) continue;
          entry.value.revision = _revision;
          entry.key.add(entry.value.archived ? _all : _active);
        }
      }
    } catch (error, stack) {
      _error(error, stack);
    } finally {
      _running = false;
    }
  }

  Future<void> close() async {
    _closed = true;
    _rows.clear();
    _all = _active = const [];
    await _subscription?.cancel();
    _subscription = null;
  }
}

int compareBrews(Brew a, Brew b) {
  final date = b.brewedAtMs.compareTo(a.brewedAtMs);
  if (date != 0) return date;
  final created = b.createdAtMs.compareTo(a.createdAtMs);
  if (created != 0) return created;
  // SQLite BINARY orders valid UTF-8 by code point, whereas String.compareTo
  // orders UTF-16 units. Imported IDs need not be ASCII UUIDs.
  final first = a.id.runes.iterator;
  final second = b.id.runes.iterator;
  while (first.moveNext()) {
    if (!second.moveNext()) return 1;
    final order = first.current.compareTo(second.current);
    if (order != 0) return order;
  }
  return second.moveNext() ? -1 : 0;
}

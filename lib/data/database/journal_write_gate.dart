import 'dart:async';

import 'package:drift/drift.dart';

class JournalReadOnlyException implements Exception {
  const JournalReadOnlyException();
  @override
  String toString() => 'Journal restoration is in progress';
}

/// Protects journal writers, including imports. Local preferences serialize with
/// restoration under a separate lock. Read-only transactions remain available.
class JournalWriteGate extends QueryInterceptor {
  bool writable = true;
  final Object _authorization = Object();
  final Map<TransactionExecutor, TransactionExecutor?> _parents = {};
  final Set<TransactionExecutor> _written = {};
  final Object _preferencesOwner = Object();
  Future<void>? _preferencesTail;

  @override
  TransactionExecutor beginTransaction(QueryExecutor parent) {
    final transaction = parent.beginTransaction();
    _parents[transaction] = parent is TransactionExecutor ? parent : null;
    return transaction;
  }

  Future<T> restoring<T>(Future<T> Function() action) =>
      runZoned(action, zoneValues: {_authorization: true});

  /// Local preferences remain writable offline. Serialize them with the
  /// read-and-reinject part of restoration so neither side loses an update.
  Future<T> withPreferencesLock<T>(Future<T> Function() action) async {
    if (Zone.current[_preferencesOwner] == true) return restoring(action);
    final previous = _preferencesTail;
    final completed = Completer<void>();
    _preferencesTail = completed.future;
    try {
      await previous;
      return await runZoned(
        () => restoring(action),
        zoneValues: {_preferencesOwner: true},
      );
    } finally {
      completed.complete();
      if (identical(_preferencesTail, completed.future)) {
        _preferencesTail = null;
      }
    }
  }

  void checkWriteAllowed() {
    if (!writable && Zone.current[_authorization] != true) {
      throw const JournalReadOnlyException();
    }
  }

  void _check(QueryExecutor executor) {
    checkWriteAllowed();
    TransactionExecutor? transaction = executor is TransactionExecutor
        ? executor
        : null;
    while (transaction != null) {
      _written.add(transaction);
      transaction = _parents[transaction];
    }
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    // Drift also uses runSelect for INSERT/UPDATE/DELETE ... RETURNING.
    // Current read queries start with SELECT; schema checks use these read-only
    // PRAGMAs. Unknown statement forms fail closed while verification is pending.
    final sql = statement.trimLeft();
    final readOnly =
        RegExp(r'^SELECT\b', caseSensitive: false).hasMatch(sql) ||
        RegExp(
          r'^PRAGMA\s+(foreign_key_check|integrity_check|user_version)\s*;?\s*$',
          caseSensitive: false,
        ).hasMatch(sql);
    if (!readOnly) _check(executor);
    return executor.runSelect(statement, args);
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _check(executor);
    return executor.runInsert(statement, args);
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _check(executor);
    return executor.runUpdate(statement, args);
  }

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _check(executor);
    return executor.runDelete(statement, args);
  }

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _check(executor);
    return executor.runCustom(statement, args);
  }

  @override
  Future<void> runBatched(
    QueryExecutor executor,
    BatchedStatements statements,
  ) {
    _check(executor);
    return executor.runBatched(statements);
  }

  @override
  Future<void> commitTransaction(TransactionExecutor inner) {
    _parents.remove(inner);
    if (_written.remove(inner) &&
        !writable &&
        Zone.current[_authorization] != true) {
      throw const JournalReadOnlyException();
    }
    return inner.send();
  }

  @override
  Future<void> rollbackTransaction(TransactionExecutor inner) {
    _parents.remove(inner);
    _written.remove(inner);
    return inner.rollback();
  }
}

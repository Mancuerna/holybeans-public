import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/history_query.dart';
import 'package:holybeans/data/repositories/journal_read_queries.dart';

typedef HistoryCursor = ({int brewed, int created, String id});
typedef HistoryPage = ({
  List<Brew> rows,
  HistoryCursor? next,
  bool more,
  int revision,
});

class StaleHistoryPage implements Exception {}

class HistoryPages {
  HistoryPages(this.reads);
  final JournalReadQueries reads;
  static const pageSize = 50;

  Future<List<String>> methods() async => [
    for (final row
        in await reads.database
            .customSelect(
              'SELECT DISTINCT method_name FROM brews ORDER BY lower(method_name)',
            )
            .get())
      row.read<String>('method_name'),
  ];

  Future<HistoryPage> page(
    HistoryQuery query,
    List<Coffee> coffees, {
    HistoryCursor? after,
    int? expectedRevision,
    bool Function()? cancelled,
  }) async {
    final database = reads.database;
    final revision = await reads.revision();
    if (expectedRevision != null && expectedRevision != revision) {
      throw StaleHistoryPage();
    }
    final result = <Brew>[];
    var cursor = after;
    while (true) {
      if (cancelled?.call() ?? false) throw StaleHistoryPage();
      final conditions = <String>[];
      final variables = <Variable>[];
      void where(String expression, Object value) {
        conditions.add(expression);
        variables.add(switch (value) {
          final String value => Variable(value),
          final int value => Variable(value),
          final double value => Variable(value),
          _ => throw ArgumentError.value(value),
        });
      }

      if (!query.archived) conditions.add('b.archived_at_ms IS NULL');
      if (query.coffeeId != null) where('b.coffee_id = ?', query.coffeeId!);
      if (query.methodId != null) {
        conditions.add(
          '(b.method_id = ? OR (b.method_id IS NULL AND b.method_name = ?))',
        );
        variables.addAll([
          Variable(query.methodId),
          Variable(query.methodName),
        ]);
      } else if (query.methodName != null) {
        where('b.method_name = ?', query.methodName!);
      }
      if (query.startMs != null) where('b.brewed_at_ms >= ?', query.startMs!);
      if (query.endMs != null) where('b.brewed_at_ms < ?', query.endMs!);
      if (query.minimumRating != null) {
        where('b.rating >= ?', query.minimumRating!);
      }
      if (cursor != null) {
        conditions.add(
          '(b.brewed_at_ms ${query.ascending ? '>' : '<'} ? OR '
          '(b.brewed_at_ms = ? AND (b.created_at_ms < ? OR '
          '(b.created_at_ms = ? AND b.id > ?))))',
        );
        variables.addAll([
          Variable(cursor.brewed),
          Variable(cursor.brewed),
          Variable(cursor.created),
          Variable(cursor.created),
          Variable(cursor.id),
        ]);
      }
      final batch = await database
          .customSelect(
            'SELECT ${brewPreviewColumns(database, notes: query.text.isNotEmpty)} FROM brews b '
            '${conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}'} '
            'ORDER BY b.brewed_at_ms ${query.ascending ? 'ASC' : 'DESC'}, b.created_at_ms DESC, b.id ASC LIMIT 64',
            variables: variables,
          )
          .get();
      final rows = batch
          .map((row) => database.brews.map(row.data))
          .toList(growable: false);
      final request = (brews: rows, coffees: coffees, query: query);
      // Small bounded batches finish faster than starting an isolate. Long
      // notes and metadata stay off the UI thread even in a small journal.
      final textSize =
          rows.fold<int>(
            0,
            (sum, brew) =>
                sum +
                (brew.notes?.length ?? 0) +
                brew.methodName.length +
                (brew.grinderName?.length ?? 0),
          ) +
          coffees.fold<int>(
            0,
            (sum, coffee) => sum + coffee.name.length + coffee.roaster.length,
          );
      final matches = query.text.isEmpty
          ? [for (var i = 0; i < rows.length; i++) i]
          : textSize <= 16384
          ? _matchingIndices(request)
          : await compute(
              _matchingIndices,
              request,
              debugLabel: 'history-page-search',
            );
      final matching = matches.toSet();
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        if (matching.contains(i)) {
          if (result.length == pageSize) {
            if (await reads.revision() != revision) throw StaleHistoryPage();
            return (
              rows: List<Brew>.unmodifiable(result),
              next: cursor,
              more: true,
              revision: revision,
            );
          }
          result.add(row.copyWith(notes: const Value(null)));
        }
        cursor = (brewed: row.brewedAtMs, created: row.createdAtMs, id: row.id);
      }
      if (await reads.revision() != revision) throw StaleHistoryPage();
      if (rows.length < 64) {
        return (
          rows: List<Brew>.unmodifiable(result),
          next: cursor,
          more: false,
          revision: revision,
        );
      }
    }
  }

  static List<int> _matchingIndices(HistoryRequest request) =>
      selectHistory(request);
}

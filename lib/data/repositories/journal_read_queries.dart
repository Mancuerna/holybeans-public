import 'package:drift/drift.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/brew_overview.dart';

/// Exclude unbounded detail text before SQLite transfers a row to the UI.
String brewPreviewColumns(
  AppDatabase database, {
  String alias = 'b',
  bool notes = false,
}) => database.brews.$columns
    .map((column) {
      final name = column.$name;
      return (name == 'notes' && !notes) || name == 'pour_phases_json'
          ? 'NULL AS "$name"'
          : '$alias."$name"';
    })
    .join(', ');

class JournalReadQueries {
  JournalReadQueries(this.database);
  final AppDatabase database;

  Stream<int> watchRevision() => database
      .customSelect(
        'SELECT coalesce(max(revision), 0) AS revision FROM temp.brew_changes',
        readsFrom: {database.brews},
      )
      .watchSingle()
      .map((row) => row.read<int>('revision'))
      .distinct();

  Future<int> revision() async =>
      (await database
              .customSelect(
                'SELECT coalesce(max(revision), 0) AS revision FROM temp.brew_changes',
              )
              .getSingle())
          .read<int>('revision');

  Stream<BrewOverview> watchOverview() async* {
    BrewOverview? previous;
    int? lastRevision;
    await for (final _ in watchRevision()) {
      final result = await database.transaction(() async {
        final current = await revision();
        if (previous != null && current == lastRevision) {
          return (summary: previous, revision: current);
        }
        return (
          summary: await overview(
            previous: previous,
            sinceRevision: lastRevision,
          ),
          revision: current,
        );
      });
      if (identical(previous, result.summary)) continue;
      previous = result.summary;
      lastRevision = result.revision;
      yield result.summary;
    }
  }

  Future<BrewOverview> overview({
    DateTime? now,
    BrewOverview? previous,
    int? sinceRevision,
  }) => database.transaction(() async {
    final changed = previous == null || sinceRevision == null
        ? null
        : {
            for (final row
                in await database
                    .customSelect(
                      'SELECT coffee_id FROM temp.brew_coffee_changes WHERE revision > ?',
                      variables: [Variable(sinceRevision)],
                    )
                    .get())
              row.read<String>('coffee_id'),
          };
    // Revision is an internal integer. Keep the dirty-ID selection in SQLite
    // rather than generating a parameter for every coffee in a bulk restore.
    String affected(String column) => changed == null
        ? '1'
        : '$column IN (SELECT coffee_id FROM temp.brew_coffee_changes WHERE revision > $sinceRevision)';
    Map<String, T> retained<T>(Map<String, T>? values) => {
      if (changed != null && values != null)
        for (final entry in values.entries)
          if (!changed.contains(entry.key)) entry.key: entry.value,
    };
    List<Brew> previews(List<QueryRow> rows, List<Brew>? old) =>
        [
          if (changed != null && old != null)
            ...old.where((brew) => !changed.contains(brew.coffeeId)),
          ...rows.map((row) => database.brews.map(row.data)),
        ]..sort((a, b) {
          final date = b.brewedAtMs.compareTo(a.brewedAtMs);
          if (date != 0) return date;
          final created = b.createdAtMs.compareTo(a.createdAtMs);
          return created != 0 ? created : a.id.compareTo(b.id);
        });
    final groups = await database.customSelect('''
      SELECT coffee_id, count(*) AS n,
        sum(CASE WHEN rating BETWEEN 0 AND 10 THEN 1 ELSE 0 END) AS rated,
        coalesce(sum(CASE WHEN rating BETWEEN 0 AND 10 THEN rating ELSE 0 END), 0.0) AS total,
        max(brewed_at_ms) AS last_ms, min(created_at_ms) AS first_ms FROM brews WHERE ${affected('coffee_id')} GROUP BY coffee_id
    ''').get();
    final recentRows = await database
        .customSelect(
          'SELECT coffee_id, brewed_at_ms, count(*) AS n FROM brews WHERE brewed_at_ms >= ? AND ${affected('coffee_id')} GROUP BY coffee_id, brewed_at_ms',
          variables: [
            Variable(
              (now ?? DateTime.now())
                  .subtract(const Duration(days: 7))
                  .millisecondsSinceEpoch,
            ),
          ],
        )
        .get();
    final years = await database.customSelect('''
      SELECT coffee_id, min(brewed_at_ms) AS at_ms FROM brews WHERE ${affected('coffee_id')}
      GROUP BY coffee_id, strftime('%Y', brewed_at_ms / 1000, 'unixepoch', 'localtime')
    ''').get();
    // The covering coffee/date index makes these bounded lookups independent
    // of the number or size of historical notes.
    final recent = await database.customSelect('''
      SELECT ${brewPreviewColumns(database)} FROM coffees c CROSS JOIN brews b
      WHERE b.id IN (
        SELECT id FROM brews recent WHERE recent.coffee_id = c.id
        ORDER BY brewed_at_ms DESC, created_at_ms DESC, id ASC LIMIT 3
      ) AND ${affected('c.id')} ORDER BY b.brewed_at_ms DESC, b.created_at_ms DESC, b.id ASC
    ''').get();
    final seeds = await database.customSelect('''
      SELECT ${brewPreviewColumns(database)} FROM coffees c JOIN brews b ON b.id = (
        SELECT id FROM brews WHERE coffee_id = c.id AND archived_at_ms IS NULL
        ORDER BY is_favorite DESC, brewed_at_ms DESC, created_at_ms DESC, id ASC LIMIT 1
      ) WHERE ${affected('c.id')}
    ''').get();
    final latest = await database.customSelect('''
      SELECT ${brewPreviewColumns(database)} FROM coffees c CROSS JOIN brews b
      WHERE b.id = (SELECT id FROM brews WHERE coffee_id = c.id AND archived_at_ms IS NULL
        ORDER BY brewed_at_ms DESC, created_at_ms DESC, id ASC LIMIT 1)
      AND ${affected('c.id')} ORDER BY b.brewed_at_ms DESC, b.created_at_ms DESC, b.id ASC
    ''').get();
    final doses = await database.customSelect('''
      SELECT coffee_id, dose_grams FROM (
        SELECT coffee_id, dose_grams,
          row_number() OVER (PARTITION BY coffee_id ORDER BY brewed_at_ms DESC, created_at_ms DESC, id ASC) AS position
        FROM brews WHERE dose_grams IS NOT NULL AND ${affected('coffee_id')}
      ) WHERE position <= 5
    ''').get();
    final doseGroups = <String, List<double>>{};
    for (final row in doses) {
      (doseGroups[row.read<String>('coffee_id')] ??= []).add(
        row.read<double>('dose_grams'),
      );
    }
    final byCoffee = retained(previous?.byCoffee)
      ..addAll({
        for (final row in groups)
          row.read<String>('coffee_id'): (
            count: row.read<int>('n'),
            rated: row.read<int>('rated'),
            ratingSum: row.read<double>('total'),
            lastMs: row.read<int>('last_ms'),
            firstCreatedMs: row.read<int>('first_ms'),
          ),
      });
    final yearsByCoffee = retained(previous?.yearsByCoffee);
    for (final row in years) {
      (yearsByCoffee[row.read<String>('coffee_id')] ??= []).add(
        row.read<int>('at_ms'),
      );
    }
    final datesByCoffee = retained(previous?.recentDatesByCoffee);
    for (final row in recentRows) {
      (datesByCoffee[row.read<String>('coffee_id')] ??= {})[row.read<int>(
        'brewed_at_ms',
      )] = row.read<int>(
        'n',
      );
    }
    final recentDates = <int, int>{};
    final cutoff = (now ?? DateTime.now())
        .subtract(const Duration(days: 7))
        .millisecondsSinceEpoch;
    for (final dates in datesByCoffee.values) {
      for (final entry in dates.entries) {
        if (entry.key >= cutoff) {
          recentDates.update(
            entry.key,
            (count) => count + entry.value,
            ifAbsent: () => entry.value,
          );
        }
      }
    }
    final yearDates = <int, int>{};
    for (final dates in yearsByCoffee.values) {
      for (final date in dates) {
        final year = DateTime.fromMillisecondsSinceEpoch(date).year;
        if (!yearDates.containsKey(year) || date < yearDates[year]!) {
          yearDates[year] = date;
        }
      }
    }
    int? firstCreated;
    for (final totals in byCoffee.values) {
      if (firstCreated == null || totals.firstCreatedMs < firstCreated) {
        firstCreated = totals.firstCreatedMs;
      }
    }
    return BrewOverview(
      byCoffee: Map.unmodifiable(byCoffee),
      previews: List.unmodifiable(previews(recent, previous?.previews)),
      latestActive: List.unmodifiable(previews(latest, previous?.latestActive)),
      seeds: Map.unmodifiable(
        retained(previous?.seeds)..addAll({
          for (final row in seeds)
            row.read<String>('coffee_id'): database.brews.map(row.data),
        }),
      ),
      doses: Map.unmodifiable(
        retained(previous?.doses)..addAll({
          for (final entry in doseGroups.entries)
            entry.key: _median(entry.value),
        }),
      ),
      weekCount: recentDates.values.fold(0, (sum, n) => sum + n),
      recentDates: Map.unmodifiable(recentDates),
      firstCreatedMs: firstCreated,
      yearDates: List.unmodifiable(yearDates.values),
      yearsByCoffee: Map.unmodifiable({
        for (final entry in yearsByCoffee.entries)
          entry.key: List<int>.unmodifiable(entry.value),
      }),
      recentDatesByCoffee: Map.unmodifiable({
        for (final entry in datesByCoffee.entries)
          entry.key: Map<int, int>.unmodifiable(entry.value),
      }),
    );
  });

  static double _median(List<double> values) {
    values.sort();
    final middle = values.length ~/ 2;
    return values.length.isOdd
        ? values[middle]
        : (values[middle - 1] + values[middle]) / 2;
  }

  /// Analytics load only while requested and never transfer long notes.
  Stream<List<Brew>> watchAnalytics({bool ratedOnly = false}) => database
      .customSelect(
        'SELECT ${brewPreviewColumns(database)} FROM brews b ${ratedOnly ? 'WHERE b.rating IS NOT NULL' : ''} ORDER BY b.brewed_at_ms DESC, b.created_at_ms DESC, b.id ASC',
        readsFrom: {database.brews},
      )
      .watch()
      .map(
        (rows) => rows
            .map((row) => database.brews.map(row.data))
            .toList(growable: false),
      );

  Future<List<Brew>> analytics() => watchAnalytics().first;
}

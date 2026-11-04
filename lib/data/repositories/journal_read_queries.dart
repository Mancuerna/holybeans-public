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
      .map((row) => row.read<int>('revision'));

  Future<int> revision() async =>
      (await database
              .customSelect(
                'SELECT coalesce(max(revision), 0) AS revision FROM temp.brew_changes',
              )
              .getSingle())
          .read<int>('revision');

  Stream<BrewOverview> watchOverview() =>
      watchRevision().asyncMap((_) => overview());

  Future<BrewOverview> overview({
    DateTime? now,
  }) => database.transaction(() async {
    final groups = await database.customSelect('''
      SELECT coffee_id, count(*) AS n,
        sum(CASE WHEN rating BETWEEN 0 AND 10 THEN 1 ELSE 0 END) AS rated,
        coalesce(sum(CASE WHEN rating BETWEEN 0 AND 10 THEN rating ELSE 0 END), 0.0) AS total,
        max(brewed_at_ms) AS last_ms FROM brews GROUP BY coffee_id
    ''').get();
    final global = await database
        .customSelect(
          '''
      SELECT min(created_at_ms) AS first_ms,
        coalesce(sum(CASE WHEN brewed_at_ms >= ? THEN 1 ELSE 0 END), 0) AS week
      FROM brews
    ''',
          variables: [
            Variable(
              (now ?? DateTime.now())
                  .subtract(const Duration(days: 7))
                  .millisecondsSinceEpoch,
            ),
          ],
        )
        .getSingle();
    final recentDates = await database
        .customSelect(
          'SELECT brewed_at_ms, count(*) AS n FROM brews WHERE brewed_at_ms >= ? GROUP BY brewed_at_ms',
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
      SELECT min(brewed_at_ms) AS at_ms FROM brews
      GROUP BY strftime('%Y', brewed_at_ms / 1000, 'unixepoch', 'localtime')
    ''').get();
    // The covering coffee/date index makes these bounded lookups independent
    // of the number or size of historical notes.
    final recent = await database.customSelect('''
      SELECT ${brewPreviewColumns(database)} FROM coffees c CROSS JOIN brews b
      WHERE b.id IN (
        SELECT id FROM brews recent WHERE recent.coffee_id = c.id
        ORDER BY brewed_at_ms DESC, created_at_ms DESC, id ASC LIMIT 3
      ) ORDER BY b.brewed_at_ms DESC, b.created_at_ms DESC, b.id ASC
    ''').get();
    final seeds = await database.customSelect('''
      SELECT ${brewPreviewColumns(database)} FROM coffees c JOIN brews b ON b.id = (
        SELECT id FROM brews WHERE coffee_id = c.id AND archived_at_ms IS NULL
        ORDER BY is_favorite DESC, brewed_at_ms DESC, created_at_ms DESC, id ASC LIMIT 1
      )
    ''').get();
    final latest = await database.customSelect('''
      SELECT ${brewPreviewColumns(database)} FROM coffees c CROSS JOIN brews b
      WHERE b.id = (SELECT id FROM brews WHERE coffee_id = c.id AND archived_at_ms IS NULL
        ORDER BY brewed_at_ms DESC, created_at_ms DESC, id ASC LIMIT 1)
      ORDER BY b.brewed_at_ms DESC, b.created_at_ms DESC, b.id ASC
    ''').get();
    final doses = await database.customSelect('''
      SELECT coffee_id, dose_grams FROM (
        SELECT coffee_id, dose_grams,
          row_number() OVER (PARTITION BY coffee_id ORDER BY brewed_at_ms DESC, created_at_ms DESC, id ASC) AS position
        FROM brews WHERE dose_grams IS NOT NULL
      ) WHERE position <= 5
    ''').get();
    final doseGroups = <String, List<double>>{};
    for (final row in doses) {
      (doseGroups[row.read<String>('coffee_id')] ??= []).add(
        row.read<double>('dose_grams'),
      );
    }
    return BrewOverview(
      byCoffee: Map.unmodifiable({
        for (final row in groups)
          row.read<String>('coffee_id'): (
            count: row.read<int>('n'),
            rated: row.read<int>('rated'),
            ratingSum: row.read<double>('total'),
            lastMs: row.read<int>('last_ms'),
          ),
      }),
      previews: List.unmodifiable(
        recent.map((row) => database.brews.map(row.data)),
      ),
      latestActive: List.unmodifiable(
        latest.map((row) => database.brews.map(row.data)),
      ),
      seeds: Map.unmodifiable({
        for (final row in seeds)
          row.read<String>('coffee_id'): database.brews.map(row.data),
      }),
      doses: Map.unmodifiable({
        for (final entry in doseGroups.entries) entry.key: _median(entry.value),
      }),
      weekCount: global.read<int>('week'),
      recentDates: Map.unmodifiable({
        for (final row in recentDates)
          row.read<int>('brewed_at_ms'): row.read<int>('n'),
      }),
      firstCreatedMs: global.readNullable<int>('first_ms'),
      yearDates: List.unmodifiable(years.map((row) => row.read<int>('at_ms'))),
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

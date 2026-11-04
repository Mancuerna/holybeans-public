import 'package:drift/drift.dart';
import 'package:holybeans/data/repositories/journal_read_queries.dart';
import 'package:holybeans/domain/grinder_consumption.dart';

typedef MethodUse = ({int count, double? rating, int? lastMs});
typedef EquipmentOverview = ({
  Map<String, MethodUse> methods,
  Map<String, GrinderUse> grinders,
});

extension EquipmentReads on JournalReadQueries {
  Stream<Map<String, int>> watchRecipientUses() => database
      .customSelect(
        'SELECT recipient_id, count(*) AS n FROM brews WHERE recipient_id IS NOT NULL GROUP BY recipient_id',
        readsFrom: {database.brews},
      )
      .watch()
      .map(
        (rows) => {
          for (final row in rows)
            row.read<String>('recipient_id'): row.read<int>('n'),
        },
      );

  Stream<EquipmentOverview> watchEquipment() => watchRevision().asyncMap(
    (_) => database.transaction(() async {
      final methods = await database.customSelect('''
      SELECT method_id, count(*) AS n, max(brewed_at_ms) AS last_ms,
        avg(rating) AS rating
      FROM brews WHERE method_id IS NOT NULL GROUP BY method_id
    ''').get();
      final rows = await database.customSelect('''
      SELECT grinder_id, method_name, trim(grind_setting) AS setting,
        count(*) AS n, max(brewed_at_ms) AS last_ms
      FROM brews WHERE grinder_id IS NOT NULL
      GROUP BY grinder_id, method_name, trim(grind_setting)
      ORDER BY last_ms DESC, method_name, setting
    ''').get();
      final byGrinder = <String, List<QueryRow>>{};
      for (final row in rows) {
        (byGrinder[row.read<String>('grinder_id')] ??= []).add(row);
      }
      return (
        methods: {
          for (final row in methods)
            row.read<String>('method_id'): (
              count: row.read<int>('n'),
              rating: row.readNullable<double>('rating'),
              lastMs: row.read<int>('last_ms'),
            ),
        },
        grinders: {
          for (final entry in byGrinder.entries)
            entry.key: _grinder(entry.value),
        },
      );
    }),
  );
}

GrinderUse _grinder(List<QueryRow> rows) {
  final methodCounts = <String, int>{};
  final best = <String, ({String setting, int count, int last})>{};
  var count = 0;
  int? last;
  for (final row in rows) {
    final method = row.read<String>('method_name');
    final n = row.read<int>('n');
    final at = row.read<int>('last_ms');
    count += n;
    if (last == null || at > last) last = at;
    methodCounts[method] = (methodCounts[method] ?? 0) + n;
    final setting = row.readNullable<String>('setting');
    if (setting == null || setting.isEmpty) continue;
    final previous = best[method];
    if (previous == null ||
        n > previous.count ||
        (n == previous.count && at > previous.last)) {
      best[method] = (setting: setting, count: n, last: at);
    }
  }
  final methods = best.keys.toList()
    ..sort((a, b) => methodCounts[b]!.compareTo(methodCounts[a]!));
  return (
    brewCount: count,
    lastBrewedAtMs: last,
    usualSettings: [
      for (final method in methods)
        (method: method, setting: best[method]!.setting),
    ],
  );
}

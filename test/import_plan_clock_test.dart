import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/beanconqueror/bq_import_plan.dart';

void main() {
  test('missing import dates use the supplied time and retain known dates', () {
    final now = DateTime.utc(2024, 2, 3, 4, 5);
    final known = DateTime.utc(2023, 6, 7);
    final export = BqExport(
      beans: [
        {
          'name': 'Missing date',
          'config': {'uuid': 'missing'},
          'finished': true,
        },
        {
          'name': 'Known date',
          'config': {
            'uuid': 'known',
            'unix_timestamp': known.millisecondsSinceEpoch ~/ 1000,
          },
          'finished': true,
        },
      ],
    );
    final plan = planBeanconquerorImport(export, const BqJournal(), now: now);
    final [missing, dated] = plan.coffees;
    expect(missing.createdAtMs, now.millisecondsSinceEpoch);
    expect(missing.archivedAtMs, now.millisecondsSinceEpoch);
    expect(dated.createdAtMs, known.millisecondsSinceEpoch);
    expect(dated.archivedAtMs, known.millisecondsSinceEpoch);
  });
}

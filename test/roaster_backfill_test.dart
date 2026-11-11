import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';

import 'helpers/test_database.dart';

void main() {
  for (final narrow in [false, true]) {
    test('roaster migration preserves names and links with narrow=$narrow', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      if (narrow) {
        // Prove the migration needs no columns beyond its historical inputs.
        // A later generated Coffee row must not become a migration dependency.
        await db.customStatement('PRAGMA foreign_keys = OFF');
        await db.customStatement('DROP TABLE coffees');
        await db.customStatement(
          'CREATE TABLE coffees (id TEXT PRIMARY KEY, roaster TEXT NOT NULL)',
        );
        await db.customStatement('PRAGMA foreign_keys = ON');
      }
      const names = [
        ' Roast  Lab ',
        'Roast Lab',
        'ROAST LAB',
        'Zulu',
        'ZULU',
        '  ',
        'Café\tSur',
      ];
      for (var index = 0; index < names.length; index++) {
        await db.customStatement(
          narrow ? 'INSERT INTO coffees (id, roaster) VALUES (?, ?)' : "INSERT INTO coffees (id, roaster, name, created_at_ms, updated_at_ms) VALUES (?, ?, 'Coffee', 1, 1)",
          ['$index', names[index]],
        );
      }
      Future<List<Map<String, Object?>>> rows(String sql) async => [
        for (final row in await db.customSelect(sql).get()) row.data,
      ];
      final before = await rows('SELECT * FROM coffees ORDER BY id');
      await db.backfillRoastersFrom34();
      final roasters = await rows(
        'SELECT id, name, name_key FROM roasters ORDER BY name_key',
      );
      expect(
        {for (final r in roasters) r['name_key']: r['id']},
        {
          'roast lab': 'a3c9d587-d5a2-5d6f-9922-278bd59183e1',
          'zulu': '57f61962-7323-5fca-a11d-85a902e957bb',
          'café sur': 'b3ee19f7-1ff4-59c4-b5ca-203517e50818',
        },
      );
      expect(
        {for (final r in roasters) r['name_key']: r['name']},
        {'roast lab': 'Roast Lab', 'zulu': 'ZULU', 'café sur': 'Café Sur'},
      );
      final links = await rows(
        'SELECT c.coffee_id, r.name_key FROM coffee_roaster_links c JOIN roasters r ON c.roaster_id = r.id ORDER BY c.coffee_id',
      );
      expect(links, [
        for (final id in ['0', '1', '2'])
          {'coffee_id': id, 'name_key': 'roast lab'},
        for (final id in ['3', '4']) {'coffee_id': id, 'name_key': 'zulu'},
        {'coffee_id': '6', 'name_key': 'café sur'},
      ]);
      expect(await rows('SELECT * FROM coffees ORDER BY id'), before);
      // Re-running must preserve identities and avoid duplicate links.
      await db.backfillRoastersFrom34();
      expect(
        await rows('SELECT id, name, name_key FROM roasters ORDER BY name_key'),
        roasters,
      );
      expect(
        await rows(
          'SELECT c.coffee_id, r.name_key FROM coffee_roaster_links c JOIN roasters r ON c.roaster_id = r.id ORDER BY c.coffee_id',
        ),
        links,
      );
      expect(await rows('PRAGMA foreign_key_check'), isEmpty);
    });
  }
}

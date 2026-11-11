import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/brew_csv.dart';

import 'helpers/test_database.dart';

void main() {
  for (final (value, encoded) in [
    ('=1+1', "'=1+1"),
    ('+1+1', "'+1+1"),
    ('-1+1', "'-1+1"),
    ('@SUM(A1)', "'@SUM(A1)"),
    ('\t=1+1', "'\t=1+1"),
    ('\r=1+1', '"\'\r=1+1"'),
    ('=SUM(1, "2")', '"\'=SUM(1, ""2"")"'),
  ]) {
    test(
      'neutralises spreadsheet prefix ${value.codeUnitAt(0)} (${value.length} chars)',
      () {
        final at = DateTime(2026, 1, 2, 3, 4).millisecondsSinceEpoch;
        final csv = brewsCsv(
          coffees: [
            Coffee(
              id: 'coffee',
              name: value,
              roaster: value,
              roastLevel: value,
              isFavorite: false,
              isDecaf: false,
              createdAtMs: at,
              updatedAtMs: at,
            ),
          ],
          brews: [
            Brew(
              id: 'brew',
              coffeeId: 'coffee',
              methodName: value,
              profileName: value,
              grinderName: value,
              grindSetting: value,
              waterProfileName: value,
              notes: value,
              doseGrams: 18,
              waterGrams: 288,
              temperatureC: -5,
              isPreGround: false,
              recipientIsPortafilter: false,
              isFavorite: false,
              brewedAtMs: at,
              createdAtMs: at,
              updatedAtMs: at,
            ),
          ],
          lots: const [],
        );
        final expected = List.filled(35, '');
        expected[0] = '2026-01-02 03:04';
        for (final index in [1, 2, 3, 4, 5, 6, 7, 29, 30]) {
          expected[index] = encoded;
        }
        expected[9] = '18';
        expected[10] = '288';
        expected[13] = '-5';
        expect(
          csv.substring(csv.indexOf('\r\n') + 2),
          '${expected.join(',')}\r\n',
        );
      },
    );
  }

  test('brews export as CSV for spreadsheets', () async {
    final database = memoryDatabase();
    addTearDown(database.close);
    final repository = JournalRepository(database);
    final coffeeId = await repository.createCoffee(
      name: 'Kenya, "AA"',
      roaster: 'Roaster',
      roastLevel: 'light',
      initialGrams: 250,
      paidPriceCents: 1500,
    );
    await repository.createBrew(
      coffeeId: coffeeId,
      methodName: 'V60',
      doseGrams: 18,
      waterGrams: 288,
      beverageGrams: 250,
      tdsPercent: 1.35,
      rating: 7.5,
      notes: 'Juicy\nbright',
      brewedAt: DateTime(2026, 9, 29, 8, 5),
    );
    final older = await repository.createBrew(
      coffeeId: coffeeId,
      methodName: 'Espresso',
      doseGrams: 17.5,
      brewedAt: DateTime(2026, 9, 28, 7, 30),
    );
    await repository.setBrewArchived(older, archived: true);

    final csv = brewsCsv(
      brews: await database.select(database.brews).get(),
      coffees: await database.select(database.coffees).get(),
      lots: await database.select(database.coffeeLots).get(),
    );
    expect(csv, startsWith('﻿brewed_at,coffee,roaster,'));
    final lines = csv.substring(1).split('\r\n');
    // Rows end in CRLF; the line break inside the quoted notes is a bare LF.
    expect(lines.first.split(',').length, 35);
    expect(
      lines[1],
      startsWith(
        '2026-09-28 07:30,"Kenya, ""AA""",Roaster,light,Espresso,,,,,17.5,',
      ),
    );
    expect(lines[1], endsWith(',1.05,,,yes,,,'));
    expect(
      lines[2],
      startsWith(
        '2026-09-29 08:05,"Kenya, ""AA""",Roaster,light,V60,,,,,18,288,250,',
      ),
    );
    expect(lines[2], contains(',1.35,18.75,7.5,'));
    expect(lines[2], endsWith(',1.08,,"Juicy\nbright",,,,'));
    expect(lines, hasLength(4));
    expect(lines.last, isEmpty);
  });
}

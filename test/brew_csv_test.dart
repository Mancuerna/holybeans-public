import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/brew_csv.dart';

void main() {
  test('brews export as CSV for spreadsheets', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
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

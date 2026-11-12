import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/domain/brew_input.dart';
import 'package:holybeans/domain/extraction_profile.dart';

import 'helpers/test_database.dart';

void main() {
  test(
    'library and immutable brew snapshot survive edits, deletion and backup',
    () async {
      final db = memoryDatabase();
      final restored = memoryDatabase();
      addTearDown(db.close);
      addTearDown(restored.close);
      final repo = JournalRepository(db);
      final library = repo.extractionProfiles;
      final p = ExtractionProfile.example('profile', 'Original');
      await library.save(p);
      await library.favorite(p.id, true);
      await library.used(p.id);
      await library.save(p.copyWith(notes: 'Updated'));
      final row = (await library.watch().first).single;
      expect(row.isFavorite, isTrue);
      expect(row.lastUsedAtMs, isNotNull);
      final coffee = await repo.createCoffee(
        name: 'Coffee',
        roaster: 'Test',
        initialGrams: 250,
      );
      await repo.saveBrewWithOutcome(
        BrewInput(
          coffeeId: coffee,
          methodName: 'Espresso',
          extractionProfileJson: p.encode(),
          doseGrams: 18,
        ),
      );
      final brew = (await db.select(db.brews).get()).single;
      await library.save(p.copyWith(name: 'Changed'));
      expect(
        (await db.select(db.brews).getSingle()).extractionProfileJson,
        p.encode(),
      );
      final source = await JournalBackup(db).exportJson();
      await JournalBackup(restored).restoreJson(source);
      expect(
        (await restored.select(restored.extractionProfiles).getSingle())
            .isFavorite,
        isTrue,
      );
      expect(
        (await restored.select(restored.brews).getSingle())
            .extractionProfileJson,
        p.encode(),
      );
      await library.delete(p.id);
      expect(await library.watch().first, isEmpty);
      expect((await db.select(db.brews).getSingle()).id, brew.id);
      expect(
        (await db.select(db.brews).getSingle()).extractionProfileJson,
        p.encode(),
      );
      await repo.saveBrewWithOutcome(
        BrewInput(coffeeId: coffee, methodName: 'Espresso', doseGrams: 18),
        id: brew.id,
      );
      expect(
        (await db.select(db.brews).getSingle()).extractionProfileJson,
        p.encode(),
      );
      await repo.saveBrewWithOutcome(
        BrewInput(
          coffeeId: coffee,
          methodName: 'Espresso',
          doseGrams: 18,
          replaceExtractionProfile: true,
        ),
        id: brew.id,
      );
      expect(
        (await db.select(db.brews).getSingle()).extractionProfileJson,
        isNull,
      );
    },
  );
  test(
    'invalid restored profile rolls back and old backups have an empty library',
    () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final repo = JournalRepository(db);
      await repo.extractionProfiles.save(
        ExtractionProfile.example('p', 'Keep'),
      );
      final backup = JournalBackup(db);
      final source = await backup.exportJson();
      final bad = jsonDecode(source) as Map<String, dynamic>;
      (bad['data']['extractionProfiles'] as List).first['dataJson'] = '{}';
      await expectLater(
        backup.restoreJson(jsonEncode(bad)),
        throwsFormatException,
      );
      expect((await repo.extractionProfiles.watch().first).single.id, 'p');
      final legacy = jsonDecode(source) as Map<String, dynamic>;
      legacy['version'] = 36;
      (legacy['data'] as Map).remove('extractionProfiles');
      await backup.restoreJson(jsonEncode(legacy));
      expect(await repo.extractionProfiles.watch().first, isEmpty);
    },
  );
}

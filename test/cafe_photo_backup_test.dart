import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/cafe_repository.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/data/services/journal_restore.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/domain/cafe_journal.dart';

void main() {
  test('cafe-only photo is exported and restored with the journal', () async {
    final dir = await Directory.systemTemp.createTemp('cafe-photo-backup-');
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final store = PhotoStore(Directory('${dir.path}/photos'));
    try {
      final bytes = Uint8List.fromList([255, 216, 255, 1, 2, 3, 255, 217]);
      final name = await store.add(bytes);
      await CafeRepository(db).save(
        CafeDrinkInput(
          cafe: const CafeInput(name: 'Cafe'),
          drinkType: 'V60',
          drankAt: DateTime(2026),
          photos: [name],
        ),
      );
      final backup = JournalBackup(db);
      final archive = await backup.exportArchive(store);
      expect(JournalBackup.readArchive(archive).$2[name], bytes);
      await store.delete(name);
      await backup.restoreArchive(archive, store);
      expect(await store.file(name).readAsBytes(), bytes);
      expect((await CafeRepository(db).read()).photos.single.fileName, name);
      expect(JournalBackup.inspectArchive(archive).cafeDrinks, 1);
      final home = JournalRepository(db);
      final coffee = await home.createCoffee(
        name: 'Existing bag',
        roaster: 'Roaster',
      );
      await home.setCoffeePhotos(coffee, [name]);
      final cafes = CafeRepository(db);
      await cafes.delete((await cafes.read()).drinks.single.id);
      await cafes.deletePhotoIfUnused(store, name);
      expect(await store.file(name).readAsBytes(), bytes);
      await home.setCoffeePhotos(coffee, []);
      await cafes.deletePhotoIfUnused(store, name);
      expect(store.file(name).existsSync(), isFalse);
    } finally {
      await db.close();
      await dir.delete(recursive: true);
    }
  });
}

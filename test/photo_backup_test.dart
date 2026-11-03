import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/data/services/journal_restore.dart';
import 'package:holybeans/data/services/photo_store.dart';

void main() {
  late Directory temp;
  late AppDatabase database;
  late JournalRepository repository;
  late PhotoStore photos;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('holybeans-photos');
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = JournalRepository(database);
    photos = PhotoStore(Directory('${temp.path}/photos'));
  });

  tearDown(() async {
    await database.close();
    await temp.delete(recursive: true);
  });

  final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 1, 2, 3, 0xFF, 0xD9]);

  test('photo store names files and rejects paths', () async {
    final name = await photos.add(jpeg);
    expect(PhotoStore.isValidName(name), isTrue);
    expect(await photos.file(name).readAsBytes(), jpeg);
    expect(PhotoStore.isValidName('../evil.jpg'), isFalse);
    expect(PhotoStore.isValidName('photo.png'), isFalse);
    expect(() => photos.file('../x.jpg'), throwsArgumentError);
    await photos.delete(name);
    expect(photos.file(name).existsSync(), isFalse);
  });

  test('editing a brew keeps its photos, in order', () async {
    final coffeeId = await repository.createCoffee(
      name: 'Photo coffee',
      roaster: 'Test roaster',
    );
    final brewId = await repository.createBrew(
      coffeeId: coffeeId,
      methodName: 'V60',
      doseGrams: 18,
    );
    final name = await photos.add(jpeg);
    final second = await photos.add(jpeg);
    await repository.setBrewPhotos(brewId, [second, name]);
    await repository.saveBrew(
      id: brewId,
      coffeeId: coffeeId,
      methodName: 'V60',
      doseGrams: 20,
    );
    final brew = await database.select(database.brews).getSingle();
    expect(brew.doseGrams, 20);
    expect(await repository.brewPhotos(brewId), [second, name]);
    expect(
      () => repository.setBrewPhotos(brewId, [name, name]),
      throwsArgumentError,
    );
    expect(
      () => repository.setBrewPhotos(brewId, ['../x.jpg']),
      throwsArgumentError,
    );
  });

  test('ZIP backups round-trip photos and ignore unsafe entries', () async {
    final coffeeId = await repository.createCoffee(
      name: 'Photo coffee',
      roaster: 'Test roaster',
    );
    final bagPhoto = await photos.add(jpeg);
    final backPhoto = await photos.add(jpeg);
    await repository.setCoffeePhotos(coffeeId, [bagPhoto, backPhoto]);
    final orphan = await photos.add(Uint8List.fromList([9, 9, 9]));

    final zip = await JournalBackup(database).exportArchive(photos);
    final archive = ZipDecoder().decodeBytes(zip);
    expect(archive.find(JournalBackup.archiveJournal), isNotNull);
    expect(archive.find('photos/$bagPhoto'), isNotNull);
    expect(archive.find('photos/$backPhoto'), isNotNull);
    // Unreferenced photos are not exported.
    expect(archive.find('photos/$orphan'), isNull);
    expect(JournalBackup.inspectArchive(zip).coffees, 1);

    // A tampered archive with a path-like entry is restored without it.
    final tampered = Archive();
    for (final file in archive) {
      tampered.add(ArchiveFile.bytes(file.name, file.readBytes()!));
    }
    tampered.add(ArchiveFile.bytes('photos/../escape.jpg', jpeg));
    final target = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(target.close);
    final targetPhotos = PhotoStore(Directory('${temp.path}/restored'));
    await JournalBackup(target)
        .restoreArchive(ZipEncoder().encodeBytes(tampered), targetPhotos);

    final restored = await target.select(target.coffees).getSingle();
    expect(await JournalRepository(target).coffeePhotos(restored.id), [
      bagPhoto,
      backPhoto,
    ]);
    expect(await targetPhotos.file(bagPhoto).readAsBytes(), jpeg);
    expect((await targetPhotos.readAll()).keys.toSet(), {bagPhoto, backPhoto});
    expect(File('${temp.path}/escape.jpg').existsSync(), isFalse);
  });

  test('plain JSON backups restore without photo references', () async {
    final coffeeId = await repository.createCoffee(
      name: 'Photo coffee',
      roaster: 'Test roaster',
    );
    await repository.setCoffeePhotos(coffeeId, [await photos.add(jpeg)]);
    final source = await JournalBackup(database).exportJson();
    final target = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(target.close);
    await JournalBackup(target).restoreJson(source);
    expect(await target.select(target.coffeePhotos).get(), isEmpty);

    final bad = jsonDecode(source) as Map<String, dynamic>;
    ((bad['data'] as Map<String, dynamic>)['coffeePhotos'] as List)
            .single['fileName'] =
        '../../etc/passwd';
    await expectLater(
      JournalBackup(target).restoreJson(jsonEncode(bad)),
      throwsFormatException,
    );
  });

  test('a v15 backup brings its single photo as the cover', () async {
    final coffeeId = await repository.createCoffee(
      name: 'Old photo coffee',
      roaster: 'Test roaster',
    );
    final name = await photos.add(jpeg);
    await repository.setCoffeePhotos(coffeeId, [name]);
    final backup = jsonDecode(
      await JournalBackup(database).exportJson(),
    ) as Map<String, dynamic>;
    final data = backup['data'] as Map<String, dynamic>;
    backup['version'] = 15;
    for (final key in ['coffeePhotos', 'brewPhotos', 'vessels']) {
      data.remove(key);
    }
    final coffee = (data['coffees'] as List).single as Map<String, dynamic>;
    coffee
      ..remove('isDecaf')
      ..remove('shopUrl')
      ..['photoFile'] = name;

    final target = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(target.close);
    await JournalBackup(target)
        .restoreJson(jsonEncode(backup), availablePhotos: {name});
    expect(await JournalRepository(target).coffeePhotos(coffeeId), [name]);
    final restored = await target.select(target.coffees).getSingle();
    expect(restored.isDecaf, isFalse);
  });
}

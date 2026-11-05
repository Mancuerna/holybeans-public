import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/preferences/coffee_maze_settings.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory directory;
  late File file;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('coffee-maze-');
    file = File(path.join(directory.path, 'record.json'));
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'a record survives reopening and cannot be lowered by overlapping saves',
    () async {
      final first = CoffeeMazeSettings(file);
      final second = CoffeeMazeSettings(file);
      expect(await first.readBest(), 0);
      await Future.wait([
        first.saveBest(1200),
        second.saveBest(50),
        first.saveBest(900),
      ]);
      expect(await CoffeeMazeSettings(file).readBest(), 1200);
    },
  );

  test('invalid preferences recover on the next record', () async {
    for (final source in [
      'broken json',
      '{"best":-5}',
      '{"best":"100"}',
      '[]',
    ]) {
      await file.writeAsString(source);
      final settings = CoffeeMazeSettings(file);
      expect(await settings.readBest(), 0);
      await settings.saveBest(250);
      expect(await settings.readBest(), 250);
    }
  });

  test(
    'a failed write preserves the record and does not block later saves',
    () async {
      final settings = CoffeeMazeSettings(file);
      await settings.saveBest(100);
      final obstacle = Directory(path.join(directory.path, 'record.json.tmp'));
      await obstacle.create();
      await expectLater(
        settings.saveBest(200),
        throwsA(isA<FileSystemException>()),
      );
      expect(await settings.readBest(), 100);
      await obstacle.delete();
      await settings.saveBest(300);
      expect(await settings.readBest(), 300);
    },
  );
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/data/services/journal_restore.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/domain/brew_input.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as path;

// Synthetic export/restore experiment. Timings are observations, not pass/fail
// thresholds, and are never presented as Android or Drive throughput.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  for (final fixture in [
    (name: 'small', coffees: 5, brews: 50, photos: 2),
    (name: 'medium', coffees: 50, brews: 500, photos: 10),
    (name: 'large', coffees: 250, brews: 2500, photos: 40),
  ]) {
    test('synthetic ${fixture.name} journal retains inventory, curves and photos', () async {
      final directory = await Directory.systemTemp.createTemp('drive-export-');
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      final target = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async {
        await database.close();
        await target.close();
        await directory.delete(recursive: true);
      });
      final repository = JournalRepository(database);
      final photos = PhotoStore(Directory(path.join(directory.path, 'source')));
      final targetPhotos = PhotoStore(
        Directory(path.join(directory.path, 'target')),
      );
      final coffeeIds = <String>[];
      final lotIds = <String>[];
      final brewIds = <String>[];
      await database.transaction(() async {
        for (var index = 0; index < fixture.coffees; index++) {
          final id = await repository.createCoffee(
            name: 'Synthetic coffee $index',
            roaster: 'Laboratory roaster ${index % 5}',
            country: 'Colombia',
            initialGrams: 1000,
            roastDate: '2026-10-01',
            notes: 'Generated fixture; no personal journal content.',
          );
          coffeeIds.add(id);
          lotIds.add((await repository.coffeeLots(id)).single.id);
        }
        for (var index = 0; index < fixture.brews; index++) {
          final coffee = index % coffeeIds.length;
          final brew = await repository.saveBrewWithOutcome(
            BrewInput(
              coffeeId: coffeeIds[coffee],
              lotId: lotIds[coffee],
              methodName: index.isEven ? 'Espresso' : 'V60',
              doseGrams: 18,
              beverageGrams: index.isEven ? 36 : 270,
              waterGrams: index.isEven ? null : 300,
              timeSeconds: index.isEven ? 30 : 180,
              brewedAt: DateTime.utc(2026).add(Duration(hours: index)),
              notes: 'Generated preparation $index',
            ),
            curve: index.isEven ? _curve(index) : null,
          );
          brewIds.add(brew.id);
        }
      });
      for (var index = 0; index < fixture.photos; index++) {
        final name = await photos.add(_jpeg(index));
        await repository.setBrewPhotos(brewIds[index], [name]);
      }
      final backup = JournalBackup(database);
      final watch = Stopwatch()..start();
      final source = await backup.exportJson();
      final exportMs = watch.elapsedMilliseconds;
      final photoBytes = await backup.referencedPhotos(photos);
      watch.reset();
      final archive = JournalBackup.encodeArchive(source, photoBytes);
      final zipMs = watch.elapsedMilliseconds;
      watch.reset();
      final compressedJson = gzip.encode(utf8.encode(source));
      final gzipMs = watch.elapsedMilliseconds;
      final manualExportSamples = <Map<String, num>>[];
      for (var sample = 0; sample < 3; sample++) {
        final (manualArchive, timing) = await _measureEventLoop(
          () => backup.exportArchive(photos),
        );
        manualExportSamples.add(timing);
        final (manualSource, manualPhotos) = JournalBackup.readArchive(
          manualArchive,
        );
        expect(
          (jsonDecode(manualSource) as Map<String, dynamic>)['data'],
          (jsonDecode(source) as Map<String, dynamic>)['data'],
        );
        expect(manualPhotos, photoBytes);
      }
      final (readSource, readPhotos) = JournalBackup.readArchive(archive);
      expect(jsonDecode(readSource), jsonDecode(source));
      expect(readPhotos, photoBytes);
      watch.reset();
      final (_, restoreSample) = await _measureEventLoop(
        () => JournalBackup(target).restoreArchive(archive, targetPhotos),
      );
      final restoreMs = watch.elapsedMilliseconds;
      final original = jsonDecode(source) as Map<String, dynamic>;
      final restored = jsonDecode(
        await JournalBackup(target).exportJson(),
      ) as Map<String, dynamic>;
      expect(restored['data'], original['data']);
      expect(await targetPhotos.readAll(), photoBytes);
      expect((await target.select(target.brews).get()).length, fixture.brews);
      expect(
        (await target.select(target.coffeeLots).get()).map(
          (lot) => lot.remainingGrams,
        ),
        everyElement(820),
      );
      // One more saved brew references no new photo: existing photo bytes are
      // reusable even though the complete journal snapshot changes.
      await repository.createBrew(
        coffeeId: coffeeIds.first,
        lotId: lotIds.first,
        methodName: 'V60',
        doseGrams: 18,
        waterGrams: 300,
      );
      final next = await backup.exportJson();
      final nextPhotos = await backup.referencedPhotos(photos);
      expect(nextPhotos, photoBytes);
      final nextZip = JournalBackup.encodeArchive(next, nextPhotos);
      final nextCompressedJson = gzip.encode(utf8.encode(next));
      stdout.writeln(
        'DRIVE_EXPORT_BENCHMARK ${jsonEncode({'fixture': fixture.name, 'environment': 'host Flutter test; in-memory SQLite', 'coffees': fixture.coffees, 'brews': fixture.brews, 'curves': fixture.brews ~/ 2, 'curveSamples': 301, 'photos': fixture.photos, 'photoWidth': 640, 'photoHeight': 480, 'jpegQuality': 85, 'jsonBytes': utf8.encode(source).length, 'gzipJsonBytes': compressedJson.length, 'photoBytes': photoBytes.values.fold<int>(0, (sum, bytes) => sum + bytes.length), 'zipBytes': archive.length, 'exportMs': exportMs, 'zipMs': zipMs, 'gzipMs': gzipMs, 'restoreMs': restoreMs, 'restoreSample': restoreSample, 'manualExportSamples': manualExportSamples, 'nextZipBytes': nextZip.length, 'nextGzipJsonBytes': nextCompressedJson.length, 'nextNewPhotoBytes': 0, 'allCollectionsAndPhotosEqual': true})}',
      );
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}

Future<(T, Map<String, num>)> _measureEventLoop<T>(
  Future<T> Function() action,
) async {
  final watch = Stopwatch()..start();
  var lastTick = 0;
  var maximumGap = 0;
  var ticks = 0;
  void recordGap() {
    final now = watch.elapsedMicroseconds;
    maximumGap = max(maximumGap, now - lastTick);
    lastTick = now;
  }

  final heartbeat = Timer.periodic(const Duration(milliseconds: 2), (_) {
    ticks++;
    recordGap();
  });
  try {
    final result = await action();
    final elapsed = watch.elapsedMicroseconds;
    recordGap();
    return (
      result,
      {
        'elapsedMs': elapsed / 1000,
        'maxEventLoopGapMs': maximumGap / 1000,
        'timerTicks': ticks,
      },
    );
  } finally {
    heartbeat.cancel();
    watch.stop();
  }
}

ShotCurve _curve(int seed) {
  final random = Random(seed);
  double precise(double value) => (value * 100).round() / 100;
  return ShotCurve(
    timesMs: [for (var tick = 0; tick <= 300; tick++) tick * 100],
    pressure: [
      for (var tick = 0; tick <= 300; tick++)
        precise(min(9, tick / 8) + random.nextDouble() * 0.2),
    ],
    flow: [
      for (var tick = 0; tick <= 300; tick++)
        tick < 50 ? 0 : precise(1.3 + random.nextDouble() * 0.3),
    ],
    weight: [
      for (var tick = 0; tick <= 300; tick++)
        precise(max(0, (tick - 50) * 0.144)),
    ],
  );
}

Uint8List _jpeg(int seed) {
  final random = Random(seed);
  final pixels = image.Image(width: 640, height: 480);
  for (final pixel in pixels) {
    pixel.setRgb(random.nextInt(256), random.nextInt(256), random.nextInt(256));
  }
  return Uint8List.fromList(image.encodeJpg(pixels, quality: 85));
}

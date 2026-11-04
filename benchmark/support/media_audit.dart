import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/journal_backup.dart';
import 'package:holybeans/data/services/journal_restore.dart';
import 'package:holybeans/data/services/photo_resizer.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;

import 'audit_metrics.dart';
import 'journal_fixture.dart';

Future<void> runMediaAudit(AuditRecord record, {AuditMemory? memory}) async {
  // Image generation is outside all timings and runs off the UI isolate.
  final inputs = await compute(_photos, 0);
  record({
    'operation': 'photo_inputs',
    'dimensions': ['1600x1200', '4000x3000'],
    'bytes': inputs.map((bytes) => bytes.length).toList(),
    'pattern': 'deterministic gradient; not camera-image throughput',
  });
  for (var i = 0; i < inputs.length; i++) {
    late Uint8List output;
    final metric = await measure(
      () async {
        output = await shrinkPhoto(inputs[i]);
      },
      warmups: 1,
      repetitions: 5,
      memory: memory,
    );
    final decoded = img.decodeJpg(output)!;
    expect(decoded.width, 1600);
    expect(decoded.height, 1200);
    record({
      'operation': 'photo_resize_$i',
      ...metric,
      'outputBytes': output.length,
      ...await memorySnapshot(memory),
    });
  }
  final batch = [
    for (var i = 0; i < 8; i++) MapEntry('$i', inputs[i % inputs.length]),
  ];
  final resized = <String, Uint8List>{};
  final parallel = await measure(
    () async {
      resized.clear();
      await shrinkEach(batch, (key, value) async => resized[key] = value);
      expect(resized.length, 8);
    },
    warmups: 1,
    repetitions: 3,
    memory: memory,
  );
  record({
    'operation': 'photo_resize_batch_8',
    ...parallel,
    'concurrency': photosInParallel,
    ...await memorySnapshot(memory),
  });

  final source = await AuditDatabase.open();
  final target = await AuditDatabase.open();
  try {
    await const JournalFixture(1000, 2048).seed(source.database);
    final photos = PhotoStore(
      Directory(path.join(source.directory.path, 'photos')),
    );
    final targetPhotos = PhotoStore(
      Directory(path.join(target.directory.path, 'photos')),
    );
    final repo = JournalRepository(source.database);
    for (var i = 0; i < 8; i++) {
      await repo.setBrewPhotos('audit-brew-$i', [
        await photos.add(resized['$i']!),
      ]);
    }
    final backup = JournalBackup(source.database);
    late String json;
    record({
      'operation': 'device_backup_export_1000',
      ...await measure(
        () async => json = await backup.exportJson(),
        repetitions: 5,
        memory: memory,
      ),
    });
    final photoBytes = await backup.referencedPhotos(photos);
    late Uint8List archive;
    record({
      'operation': 'device_backup_zip_1000',
      ...await measure(
        () => archive = JournalBackup.encodeArchive(json, photoBytes),
        repetitions: 5,
        memory: memory,
      ),
    });
    final (readJson, readPhotos) = JournalBackup.readArchive(archive);
    expect(jsonDecode(readJson), jsonDecode(json));
    expect(readPhotos, photoBytes);
    final restore = JournalRestore(
      JournalBackup(target.database),
      targetPhotos,
    );
    record({
      'operation': 'device_backup_restore_1000',
      ...await measure(
        () => restore.replace(readJson, readPhotos),
        warmups: 1,
        repetitions: 3,
        memory: memory,
      ),
      'archiveBytes': archive.length,
      ...await memorySnapshot(memory),
    });
    final restored = jsonDecode(
      await JournalBackup(target.database).exportJson(),
    ) as Map<String, dynamic>;
    expect(
      restored['data'],
      (jsonDecode(json) as Map<String, dynamic>)['data'],
    );
    expect(await targetPhotos.readAll(), photoBytes);
    record({'operation': 'device_backup_round_trip', 'equal': true});
  } finally {
    await source.close();
    await target.close();
  }
}

List<Uint8List> _photos(int seed) => [
  for (final (width, height) in [(1600, 1200), (4000, 3000)])
    _jpeg(width, height),
];

Uint8List _jpeg(int width, int height) {
  final image = img.Image(width: width, height: height);
  for (final pixel in image) {
    pixel.setRgb(pixel.x % 256, pixel.y % 256, (pixel.x + pixel.y) % 256);
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

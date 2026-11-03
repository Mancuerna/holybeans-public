import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/services/photo_resizer.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Times how BeanConqueror photos are prepared on the phone: the Dart
/// decoder used up to October 2026, one at a time as the import did, against
/// [shrinkPhoto] alone and [shrinkEach] as the import uses it now.
///
/// Reads the JPEG files pushed to `files/bench` in the test package's
/// external folder (`adb push`), repeated [rounds] times, and writes the
/// times to `files/bench/result.json`. Run it as a profile build
/// (docs/PATROL.md).
Future<void> runPhotoBenchmark({int rounds = 8}) async {
  final folder = Directory(
    '${(await getExternalStorageDirectory())!.path}/bench',
  )..createSync(recursive: true);
  // Patrol clears the package's data before running, so the photos are
  // pushed while the test waits, followed by an empty `ready` file.
  final ready = File('${folder.path}/ready');
  for (var i = 0; i < 300 && !ready.existsSync(); i++) {
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  expect(ready.existsSync(), isTrue, reason: 'push the photos and `ready`');
  final sources = [
    for (final file in folder.listSync().whereType<File>())
      if (file.path.toLowerCase().endsWith('.jpg')) file,
  ]..sort((a, b) => a.path.compareTo(b.path));
  expect(sources, isNotEmpty, reason: 'push JPEG files to ${folder.path}');
  final originals = [for (final file in sources) file.readAsBytesSync()];
  final photos = [
    for (var round = 0; round < rounds; round++)
      for (final (i, bytes) in originals.indexed) MapEntry('$round-$i', bytes),
  ];

  // One of each first, so neither pays for starting up.
  await compute(_legacyShrink, originals.first);
  await shrinkPhoto(originals.first);

  // Results are measured after the clocks stop.
  final legacyOut = <String, Uint8List>{};
  final legacy = Stopwatch()..start();
  for (final MapEntry(:key, :value) in photos) {
    legacyOut[key] = await compute(_legacyShrink, value);
  }
  legacy.stop();

  final singleOut = <String, Uint8List>{};
  final single = Stopwatch()..start();
  for (final MapEntry(:key, :value) in photos) {
    singleOut[key] = await shrinkPhoto(value);
  }
  single.stop();

  final parallelOut = <String, Uint8List>{};
  final parallel = Stopwatch()..start();
  await shrinkEach(photos, (name, bytes) async => parallelOut[name] = bytes);
  parallel.stop();

  Map<String, (int, int)> sizes(Map<String, Uint8List> out) => {
    for (final MapEntry(:key, :value) in out.entries) key: _size(value),
  };
  final legacySizes = sizes(legacyOut);
  expect(sizes(singleOut), legacySizes, reason: 'same size and orientation');
  expect(sizes(parallelOut), legacySizes);
  int kilobytes(Map<String, Uint8List> out) =>
      out.values.fold(0, (sum, bytes) => sum + bytes.length) ~/ 1024;
  final count = photos.length;
  final result = {
    'device': Platform.operatingSystemVersion,
    'photos': count,
    'sources': {
      for (final (i, file) in sources.indexed)
        file.uri.pathSegments.last: {
          'bytes': originals[i].length,
          'shrunk': legacySizes['0-$i'].toString(),
        },
    },
    'legacyMs': legacy.elapsedMilliseconds,
    'nativeOneByOneMs': single.elapsedMilliseconds,
    'nativeParallelMs': parallel.elapsedMilliseconds,
    'parallel': photosInParallel,
    'legacyOutputKB': kilobytes(legacyOut),
    'nativeOutputKB': kilobytes(singleOut),
    'legacyPerPhotoMs': legacy.elapsedMilliseconds / count,
    'nativeOneByOnePerPhotoMs': single.elapsedMilliseconds / count,
    'nativeParallelPerPhotoMs': parallel.elapsedMilliseconds / count,
  };
  final json = const JsonEncoder.withIndent('  ').convert(result);
  File('${folder.path}/result.json').writeAsStringSync(json);
  debugPrint('PHOTO_BENCHMARK $json');
}

(int, int) _size(Uint8List jpeg) {
  final decoded = img.decodeJpg(jpeg)!;
  return (decoded.width, decoded.height);
}

/// `shrinkPhoto` as it was before October 2026, for comparison.
Uint8List _legacyShrink(Uint8List bytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } on Object {
    decoded = null;
  }
  if (decoded == null) return bytes;
  var image = img.bakeOrientation(decoded);
  final longest = image.width > image.height ? image.width : image.height;
  if (longest > photoMaxPixels) {
    image = image.width >= image.height
        ? img.copyResize(image, width: photoMaxPixels)
        : img.copyResize(image, height: photoMaxPixels);
  }
  return img.encodeJpg(image, quality: 82);
}

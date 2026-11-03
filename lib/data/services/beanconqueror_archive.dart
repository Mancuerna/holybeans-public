import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:holybeans/domain/beanconqueror/bq_flow_profile.dart';
import 'package:holybeans/domain/beanconqueror/bq_import_plan.dart';
import 'package:holybeans/domain/beanconqueror/bq_values.dart';
import 'package:holybeans/domain/shot_curve.dart';

/// The file is not a BeanConqueror export HolyBeans can read.
class BqArchiveException implements Exception {
  const BqArchiveException(this.reason);

  final String reason;

  @override
  String toString() => 'BqArchiveException: $reason';
}

/// Reads the `Beanconqueror.zip` that BeanConqueror's Export writes: the
/// main `Beanconqueror.json` plus, for long collections, numbered chunks
/// (`Beanconqueror_Brews_1.json`…) that continue it. A bare
/// `Beanconqueror.json` is read too, and so is a ZIP of the whole export
/// folder: the export (or its `Beanconqueror.zip`) with the `brews` folder
/// of flow profiles and any photos, which are read one at a time.
abstract final class BeanconquerorArchive {
  static const mainFile = 'Beanconqueror.json';
  static const _innerZip = 'Beanconqueror.zip';

  /// Chunked collections and the name their chunk files use.
  static const _chunked = {
    'BREWS': 'Brews',
    'BEANS': 'Beans',
    'BARISTAMODE_BREWS': 'Baristamode',
  };

  /// Exports with this much uncompressed JSON are refused.
  static const _maxJsonBytes = 200 * 1024 * 1024;

  /// A flow profile or photo larger than this is left out.
  static const _maxFileBytes = 30 * 1024 * 1024;

  static BqExport read(Uint8List bytes) {
    final Map<String, dynamic> data;
    if (_looksZip(bytes)) {
      data = _fromZip(_decode(bytes));
    } else {
      data = _json(bytes, mainFile);
    }
    return _export(data);
  }

  /// Names of the files a ZIP carries besides the export (flow profiles,
  /// photos), as the export refers to them; empty for a bare JSON.
  static Set<String> extraFileNames(Uint8List bytes) {
    if (!_looksZip(bytes)) return const {};
    return {
      for (final file in _decode(bytes).files)
        if (file.isFile && !isExportFile(file.name)) bqFileName(file.name),
    };
  }

  /// The flow profiles of [request] (ZIP bytes and the names wanted), as
  /// curves. They are decoded one at a time, so hundreds of them fit in
  /// memory; one that does not read is left out, like a missing one.
  static Map<String, ShotCurve> curves(
    (Uint8List bytes, Set<String> names) request,
  ) {
    final (bytes, names) = request;
    final curves = <String, ShotCurve>{};
    for (final (name, file) in _wanted(bytes, names)) {
      try {
        final curve = bqFlowCurve(jsonDecode(utf8.decode(file.readBytes()!)));
        if (curve != null) curves[name] = curve;
      } on Object {
        // Damaged or not a profile.
      } finally {
        // The archive keeps what it decompressed; let it go.
        file.clear();
      }
    }
    return curves;
  }

  /// Flow profiles already read, by name, as curves; one that does not
  /// read is left out. For files read one by one from a folder.
  static Map<String, ShotCurve> curvesFromFiles(
    List<(String name, Uint8List bytes)> files,
  ) {
    final curves = <String, ShotCurve>{};
    for (final (name, bytes) in files) {
      try {
        final curve = bqFlowCurve(jsonDecode(utf8.decode(bytes)));
        if (curve != null) curves[name] = curve;
      } on Object {
        // Damaged or not a profile.
      }
    }
    return curves;
  }

  /// The files of [request] (ZIP bytes and the names wanted), such as
  /// photos.
  static Map<String, Uint8List> files(
    (Uint8List bytes, Set<String> names) request,
  ) {
    final (bytes, names) = request;
    final found = <String, Uint8List>{};
    for (final (name, file) in _wanted(bytes, names)) {
      if (file.readBytes() case final content?) found[name] = content;
      file.clear();
    }
    return found;
  }

  static Iterable<(String, ArchiveFile)> _wanted(
    Uint8List bytes,
    Set<String> names,
  ) sync* {
    if (!_looksZip(bytes)) return;
    final seen = <String>{};
    for (final file in _decode(bytes).files) {
      if (!file.isFile || file.size > _maxFileBytes) continue;
      final name = bqFileName(file.name);
      if (names.contains(name) && seen.add(name)) yield (name, file);
    }
  }

  static bool _looksZip(Uint8List bytes) =>
      bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B; // "PK"

  static Archive _decode(Uint8List bytes) {
    try {
      return ZipDecoder().decodeBytes(bytes);
    } on Object {
      throw const BqArchiveException('Not a ZIP file');
    }
  }

  /// Whether [path] is part of the export itself rather than a curve or
  /// photo it refers to.
  static bool isExportFile(String path) {
    final name = bqFileName(path);
    return name == mainFile ||
        name == _innerZip ||
        RegExp(r'^Beanconqueror_\w+_\d+\.json$').hasMatch(name);
  }

  /// The archive entry called [name], at the top or in a folder.
  static ArchiveFile? _find(Archive archive, String name) {
    for (final file in archive.files) {
      if (file.isFile && bqFileName(file.name) == name) return file;
    }
    return null;
  }

  static Map<String, dynamic> _fromZip(Archive archive) {
    final main = _find(archive, mainFile);
    if (main == null) {
      // A ZIP of the export folder holds the export's own ZIP.
      final inner = _find(archive, _innerZip)?.readBytes();
      if (inner == null) {
        throw const BqArchiveException('No $mainFile in the ZIP');
      }
      return _fromZip(_decode(inner));
    }
    final total = archive.files
        .where((file) => isExportFile(file.name))
        .fold<int>(0, (sum, file) => sum + file.size);
    if (total > _maxJsonBytes) {
      throw const BqArchiveException('Export too large');
    }
    final data = _json(main.readBytes(), mainFile);
    for (final MapEntry(key: collection, value: fileName) in _chunked.entries) {
      // Chunk 0 lives in the main file; the rest follow from 1.
      for (var index = 1; ; index++) {
        final chunk = _find(archive, 'Beanconqueror_${fileName}_$index.json');
        if (chunk == null) break;
        final rows = jsonDecode(utf8.decode(chunk.readBytes() ?? const []));
        if (rows is! List) {
          throw BqArchiveException('Chunk ${chunk.name} is not a list');
        }
        final existing = data[collection];
        data[collection] = [if (existing is List) ...existing, ...rows];
      }
    }
    return data;
  }

  static Map<String, dynamic> _json(List<int>? bytes, String name) {
    if (bytes == null) throw BqArchiveException('Cannot read $name');
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on Object {
      throw BqArchiveException('$name is not JSON');
    }
    if (decoded is! Map<String, dynamic>) {
      throw BqArchiveException('$name is not an object');
    }
    return decoded;
  }

  static BqExport _export(Map<String, dynamic> data) {
    // Every export carries its settings and version.
    if (!data.containsKey('SETTINGS') && !data.containsKey('VERSION')) {
      throw const BqArchiveException('Not a BeanConqueror export');
    }
    List<BqObject> rows(String key) {
      final value = data[key];
      if (value == null) return const [];
      if (value is! List) throw BqArchiveException('$key is not a list');
      return value.whereType<BqObject>().toList();
    }

    final settings = switch (data['SETTINGS']) {
      [final BqObject first, ...] => first,
      final BqObject single => single,
      _ => const <String, dynamic>{},
    };
    return BqExport(
      beans: rows('BEANS'),
      brews: rows('BREWS'),
      mills: rows('MILL'),
      preparations: rows('PREPARATION'),
      waters: rows('WATER'),
      settings: settings,
    );
  }
}

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:holybeans/data/services/beanconqueror_archive.dart';
import 'package:holybeans/data/services/export_folder.dart';
import 'package:holybeans/domain/beanconqueror/bq_values.dart';
import 'package:holybeans/domain/shot_curve.dart';

/// Reports how many of the curves wanted have been read.
typedef BqProgress = void Function(int done, int total);

/// The curves and photos an import can take besides the export itself,
/// by the file names the export refers to.
abstract interface class BqExtraFiles {
  Set<String> get names;

  /// The flow profiles named [wanted], as curves; one that does not read is
  /// left out, like a missing one.
  Future<Map<String, ShotCurve>> curves(
    Set<String> wanted, {
    BqProgress? onProgress,
  });

  /// The raw files named [wanted], such as photos.
  Future<Map<String, Uint8List>> files(Set<String> wanted);
}

/// A ZIP of the whole export folder, read lazily in another isolate.
class ZipExtraFiles implements BqExtraFiles {
  const ZipExtraFiles(this.bytes, this.names);

  final Uint8List bytes;

  @override
  final Set<String> names;

  /// The curves and photos in [bytes], or null when it carries none.
  static Future<ZipExtraFiles?> of(Uint8List bytes) async {
    final names = await compute(BeanconquerorArchive.extraFileNames, bytes);
    return names.isEmpty ? null : ZipExtraFiles(bytes, names);
  }

  @override
  Future<Map<String, ShotCurve>> curves(
    Set<String> wanted, {
    BqProgress? onProgress,
  }) async {
    final found = await compute(BeanconquerorArchive.curves, (bytes, wanted));
    onProgress?.call(wanted.length, wanted.length);
    return found;
  }

  @override
  Future<Map<String, Uint8List>> files(Set<String> wanted) =>
      compute(BeanconquerorArchive.files, (bytes, wanted));
}

/// The export folder itself ("Full export to directory"): its files are
/// read one by one and decoded a small batch at a time in another isolate,
/// so hundreds of curves never sit in memory together.
class FolderExtraFiles implements BqExtraFiles {
  FolderExtraFiles(this.folder, Iterable<FolderFile> files)
    : _byName = {
        for (final file in files)
          if (!BeanconquerorArchive.isExportFile(file.path))
            bqFileName(file.path): file,
      };

  final ExportFolder folder;
  final Map<String, FolderFile> _byName;

  /// Curves decoded per trip to the other isolate.
  static const _batch = 25;

  // Built once: the import screen asks for every curve and photo on each
  // frame, and an export folder can hold thousands of files.
  @override
  late final Set<String> names = _byName.keys.toSet();

  /// The export in [files]: its `Beanconqueror.zip`, or the JSON files it
  /// holds when they were unpacked, as one ZIP for
  /// [BeanconquerorArchive.read]; null when the folder has no export.
  static Future<Uint8List?> exportOf(
    ExportFolder folder,
    List<FolderFile> files,
  ) async {
    // The shallowest copy, in case the export folder sits inside another.
    final byDepth = [...files]
      ..sort(
        (a, b) => '/'
            .allMatches(a.path)
            .length
            .compareTo('/'.allMatches(b.path).length),
      );
    for (final file in byDepth) {
      if (bqFileName(file.path) == 'Beanconqueror.zip') {
        return folder.read(file);
      }
    }
    final parts = [
      for (final file in byDepth)
        if (BeanconquerorArchive.isExportFile(file.path)) file,
    ];
    if (!parts.any((file) => bqFileName(file.path) == 'Beanconqueror.json')) {
      return null;
    }
    final archive = Archive();
    for (final file in parts) {
      archive.add(
        ArchiveFile.bytes(bqFileName(file.path), await folder.read(file)),
      );
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  @override
  Future<Map<String, ShotCurve>> curves(
    Set<String> wanted, {
    BqProgress? onProgress,
  }) async {
    final names = [
      for (final name in wanted)
        if (_byName.containsKey(name)) name,
    ]..sort();
    final curves = <String, ShotCurve>{};
    for (var start = 0; start < names.length; start += _batch) {
      final batch = <(String, Uint8List)>[];
      for (final name in names.skip(start).take(_batch)) {
        try {
          batch.add((name, await folder.read(_byName[name]!)));
        } on Object {
          // Unreadable: left out, like a missing one.
        }
      }
      curves.addAll(await compute(BeanconquerorArchive.curvesFromFiles, batch));
      onProgress?.call((start + _batch).clamp(0, names.length), names.length);
    }
    return curves;
  }

  @override
  Future<Map<String, Uint8List>> files(Set<String> wanted) async {
    final found = <String, Uint8List>{};
    for (final name in wanted) {
      final file = _byName[name];
      if (file == null) continue;
      try {
        found[name] = await folder.read(file);
      } on Object {
        // Unreadable: left out.
      }
    }
    return found;
  }
}

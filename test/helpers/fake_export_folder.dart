import 'dart:typed_data';

import 'package:holybeans/data/services/export_folder.dart';

/// An export folder in memory: [files] by path; [reads] counts each read.
class FakeExportFolder implements ExportFolder {
  FakeExportFolder(this.files, {this.picked = 'content://export'});

  final Map<String, List<int>> files;

  /// What the picker returns; null as if cancelled.
  final String? picked;
  final reads = <String>[];

  @override
  Future<String?> pick() async => picked;

  @override
  Future<List<FolderFile>> list(String uri) async => [
    for (final MapEntry(key: path, value: bytes) in files.entries)
      FolderFile(path: path, uri: 'content://$path', size: bytes.length),
  ];

  @override
  Future<Uint8List> read(FolderFile file) async {
    reads.add(file.path);
    return Uint8List.fromList(files[file.path]!);
  }
}

import 'package:flutter/services.dart';

/// A file inside a picked folder, by its path from that folder.
class FolderFile {
  const FolderFile({required this.path, required this.uri, this.size = 0});

  /// Such as `brews/<uuid>_flow_profile.json`.
  final String path;

  /// What [ExportFolder.read] reads it by.
  final String uri;
  final int size;
}

/// Another app's export folder, picked by the user and only read: its files
/// are listed first and read one at a time, so a folder of hundreds never
/// sits in memory at once.
abstract interface class ExportFolder {
  /// Opens the system folder picker; null when cancelled.
  Future<String?> pick();

  /// Every file in the folder [uri] and its subfolders.
  Future<List<FolderFile>> list(String uri);

  Future<Uint8List> read(FolderFile file);
}

/// [ExportFolder] backed by MainActivity's "holybeans/import-folder"
/// channel (Android's storage access framework, read access only).
class AndroidExportFolder implements ExportFolder {
  const AndroidExportFolder();

  static const _channel = MethodChannel('holybeans/import-folder');

  @override
  Future<String?> pick() => _channel.invokeMethod<String>('pick');

  @override
  Future<List<FolderFile>> list(String uri) async => [
    for (final entry
        in await _channel.invokeListMethod<Map<Object?, Object?>>('list', {
              'uri': uri,
            }) ??
            const <Map<Object?, Object?>>[])
      FolderFile(
        path: entry['path']! as String,
        uri: entry['uri']! as String,
        size: (entry['size'] as int?) ?? 0,
      ),
  ];

  @override
  Future<Uint8List> read(FolderFile file) async =>
      (await _channel.invokeMethod<Uint8List>('read', {'uri': file.uri}))!;
}

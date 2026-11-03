import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Keeps bag and brew photos as JPEG files in one app-private folder. The
/// database only stores each photo's file name.
class PhotoStore {
  PhotoStore(this.directory);

  final Directory directory;

  static Future<PhotoStore> open() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(path.join(support.path, 'photos'));
    await directory.create(recursive: true);
    return PhotoStore(directory);
  }

  static final _validName = RegExp(r'^[0-9a-f-]{36}\.jpg$');

  /// Whether [name] is a file name this store could have produced; anything
  /// else (paths, other extensions) is rejected, including from backups.
  static bool isValidName(String name) => _validName.hasMatch(name);

  File file(String name) {
    if (!isValidName(name)) throw ArgumentError.value(name, 'name');
    return File(path.join(directory.path, name));
  }

  /// Copies the picked image into the store and returns its new name.
  Future<String> add(Uint8List bytes) async {
    final name = '${const Uuid().v4()}.jpg';
    await directory.create(recursive: true);
    await file(name).writeAsBytes(bytes, flush: true);
    return name;
  }

  Future<void> delete(String? name) async {
    if (name == null || !isValidName(name)) return;
    final target = file(name);
    if (target.existsSync()) await target.delete();
  }

  /// Names of the stored photos, without reading them.
  Future<Set<String>> names() async {
    if (!directory.existsSync()) return {};
    return {
      await for (final entry in directory.list())
        if (entry is File && isValidName(path.basename(entry.path)))
          path.basename(entry.path),
    };
  }

  /// Every stored photo, by name.
  Future<Map<String, Uint8List>> readAll() async {
    final photos = <String, Uint8List>{};
    if (!directory.existsSync()) return photos;
    await for (final entry in directory.list()) {
      final name = path.basename(entry.path);
      if (entry is File && isValidName(name)) {
        photos[name] = await entry.readAsBytes();
      }
    }
    return photos;
  }

  /// Writes and flushes replacement files without touching current photos.
  Future<void> stageReplacement(
    Directory staged,
    Map<String, Uint8List> photos,
  ) async {
    await staged.create(recursive: true);
    final target = PhotoStore(staged);
    for (final entry in photos.entries) {
      await target.file(entry.key).writeAsBytes(entry.value, flush: true);
    }
  }

  /// Promotes a prepared folder after the coordinator has kept the original.
  Future<void> promoteReplacement(Directory staged) =>
      staged.rename(directory.path);
}

import 'dart:io';

import 'package:holybeans/data/services/atomic_json_file.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class CoffeeMazeSettings {
  CoffeeMazeSettings(File file) : _json = AtomicJsonFile(file);

  final AtomicJsonFile _json;
  static Future<void> _pending = Future<void>.value();

  static Future<CoffeeMazeSettings> open() async {
    final directory = await getApplicationSupportDirectory();
    return CoffeeMazeSettings(
      File(path.join(directory.path, 'coffee_maze.json')),
    );
  }

  Future<int> readBest() async {
    try {
      final value = await _json.read();
      if (value is Map && value['best'] is int) {
        final best = value['best'] as int;
        if (best >= 0) return best;
      }
    } on FormatException {
      // A damaged game preference must not prevent another round.
    }
    return 0;
  }

  Future<void> saveBest(int score) {
    final result = _pending.then((_) async {
      final previous = await readBest();
      if (score > previous) await _json.write({'best': score});
    });
    // Serialize read/modify/write even when the screen is reopened immediately.
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}

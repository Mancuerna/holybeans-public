import 'dart:io';

import 'package:holybeans/data/services/atomic_json_file.dart';
import 'package:holybeans/domain/label_printer_profile.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class LabelOutputPreferences {
  LabelOutputPreferences(File file) : _json = AtomicJsonFile(file);

  final AtomicJsonFile _json;
  LabelPrinterModel? model;
  final _papers = <LabelPrinterModel, LabelPaper>{};

  static Future<LabelOutputPreferences> open() async {
    final directory = await getApplicationSupportDirectory();
    final preferences = LabelOutputPreferences(
      File(path.join(directory.path, 'label_output.json')),
    );
    await preferences.load();
    return preferences;
  }

  LabelPaper paperFor(LabelPrinterModel model) =>
      _papers[model] ?? model.defaultPaper;

  Future<void> load() async {
    model = null;
    _papers.clear();
    try {
      final value = await _json.read();
      if (value is! Map) return;
      final papers = value['papers'];
      for (final candidate in LabelPrinterModel.values) {
        if (candidate.name == value['model']) model = candidate;
        final saved = papers is Map ? papers[candidate.name] : null;
        if (saved is! Map) continue;
        for (final paper in candidate.papers) {
          if (paper.widthMm == saved['widthMm'] &&
              paper.lengthMm == saved['lengthMm']) {
            _papers[candidate] = paper;
            break;
          }
        }
      }
    } on FormatException {
      // A damaged local preference must not prevent opening the editor.
    } on FileSystemException {
      // Defaults remain usable when the preference cannot be read.
    }
  }

  Future<void> remember(LabelPaper paper) async {
    if (!paper.model.papers.contains(paper)) {
      throw const FormatException('Unsupported label paper');
    }
    model = paper.model;
    _papers[paper.model] = paper;
    await _json.write({
      'model': model!.name,
      'papers': {
        for (final entry in _papers.entries)
          entry.key.name: {
            'widthMm': entry.value.widthMm,
            'lengthMm': entry.value.lengthMm,
          },
      },
    });
  }
}

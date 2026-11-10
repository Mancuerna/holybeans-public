import 'dart:async';

import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/services/label_printer.dart';

/// Attempts every printer cleanup action, reporting failures independently.
Future<void> closeLabelPrinters(Iterable<LabelPrinter> printers) async {
  for (final printer in printers) {
    for (final cleanup in <FutureOr<void> Function()>[
      printer.stopSearch,
      printer.disconnect,
      printer.dispose,
    ]) {
      try {
        await cleanup();
      } catch (error, stack) {
        reportError(error, stack);
      }
    }
  }
}

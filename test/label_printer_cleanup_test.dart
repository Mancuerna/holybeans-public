import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/services/label_printer_cleanup.dart';
import 'package:holybeans/data/services/paired_device.dart';

import 'helpers/fake_label_printer.dart';

class _CleanupPrinter extends FakeLabelPrinter {
  _CleanupPrinter(this.id, this.calls, {this.failure}) {
    status = DeviceStatus.connected;
  }

  final String id;
  final List<String> calls;
  final String? failure;
  bool disposed = false;

  void _record(String action) {
    calls.add('$id.$action');
    if (action == failure) throw StateError('$id.$action failed');
  }

  @override
  Future<void> stopSearch() async => _record('stopSearch');

  @override
  Future<void> disconnect() async {
    _record('disconnect');
    await super.disconnect();
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
    _record('dispose');
  }
}

void main() {
  for (final failure in [null, 'stopSearch', 'disconnect', 'dispose']) {
    test(
      'closes every printer after ${failure ?? 'successful cleanup'}',
      () async {
        final reports = <String>[];
        final previousDebugPrint = debugPrint;
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null) reports.add(message);
        };
        addTearDown(() => debugPrint = previousDebugPrint);
        final calls = <String>[];
        final first = _CleanupPrinter('first', calls, failure: failure);
        final second = _CleanupPrinter('second', calls);

        await closeLabelPrinters([first, second]);

        expect(calls, [
          'first.stopSearch',
          'first.disconnect',
          'first.dispose',
          'second.stopSearch',
          'second.disconnect',
          'second.dispose',
        ]);
        expect(first.disposed, isTrue);
        expect(second.disposed, isTrue);
        expect(second.connected, isFalse);
        expect(first.jobs + second.jobs, 0);
        if (failure == null) {
          expect(reports, isEmpty);
        } else {
          expect(reports, hasLength(1));
          expect(reports.single, contains('first.$failure failed'));
        }
      },
    );
  }
}

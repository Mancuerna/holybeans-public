import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/services/paired_device.dart';
import 'package:holybeans/ui/labels/label_printer_controls.dart';

import 'helpers/fake_label_printer.dart';
import 'helpers/ui_test_support.dart';

void main() {
  for (final language in ['es', 'en']) {
    testWidgets(
      'copies failed connection report without printing ($language)',
      (tester) async {
        final printer = FakeLabelPrinter();
        addTearDown(printer.dispose);
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await tester.pumpWidget(
          localizedApp(
            locale: Locale(language),
            home: Scaffold(body: LabelPrinterControls(printer: printer)),
          ),
        );
        await tester.pumpAndSettle();
        final button = find.byKey(
          const ValueKey('label-printer-copy-diagnostics'),
        );
        expect(button, findsNothing);
        printer.diagnosticReport = 'Selected: B1 Pro\nrequest: 165\ntimeout';
        printer.status = DeviceStatus.failed;
        await printer.stopSearch();
        // The real printer notifies on its failed connection state.
        await printer.search();
        await tester.pumpAndSettle();
        expect(button, findsOneWidget);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(copied, printer.diagnosticReport);
        expect(printer.jobs, 0);
      },
    );
  }
}

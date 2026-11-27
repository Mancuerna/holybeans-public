import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> tapShareControl(WidgetTester tester, String key) async {
  final control = find.byKey(ValueKey(key));
  await tester.ensureVisible(control);
  await tester.tap(control);
  await tester.pumpAndSettle();
}

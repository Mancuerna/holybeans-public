import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/journal_audit.dart';
import 'support/journal_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final fixture in auditFixtures) {
    test('journal access ${fixture.name}', () async {
      await runJournalAudit(fixture, (record) {
        stdout.writeln(
          'JOURNAL_AUDIT ${jsonEncode({'environment': 'host Flutter test; file-backed background SQLite', ...record})}',
        );
      });
    }, timeout: const Timeout(Duration(minutes: 20)));
  }
}
